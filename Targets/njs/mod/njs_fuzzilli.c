#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <setjmp.h>
#include <errno.h>
#include <njs.h>
#include <njs_main.h>
#include <njs_value.h>
#include <njs_object.h>
#include <njs_string.h>
#include "njs_coverage.h"

// グローバル変数の定義
jmp_buf crash_jmp_buf;
struct shmem_data* __shmem;
uint32_t *__edges_start, *__edges_stop;

#define SHM_SIZE 0x100000
#define MAX_EDGES ((SHM_SIZE - 4) * 8)
#define MEMORY_LEAK_THRESHOLD (1024 * 1024)  // 1MB

// メモリ使用量取得関数の実装
size_t getCurrentMemoryUsage(void) {
    size_t vm_size = 0;
    FILE *status = fopen("/proc/self/status", "r");
    if (status) {
        char line[128];
        while (fgets(line, sizeof(line), status)) {
            if (strncmp(line, "VmSize:", 7) == 0) {
                sscanf(line, "VmSize: %lu", &vm_size);
                break;
            }
        }
        fclose(status);
    }
    return vm_size;
}

// テストケース実行用のヘルパー関数
static void execute_test(njs_vm_t *vm, const char *test_case) {
    njs_int_t ret;
    njs_opaque_value_t result;  // njs_value_tの代わりにnjs_opaque_value_tを使用
    u_char *start = (u_char *)test_case;
    u_char *end = start + strlen(test_case);
    
    ret = njs_vm_compile(vm, &start, end);
    if (ret != NJS_OK) {
        printf("[TEST] Compilation failed: %s\n", test_case);
        return;
    }

    ret = njs_vm_start(vm, njs_value_arg(&result));
    if (ret != NJS_OK) {
        printf("[TEST] Execution failed: %s\n", test_case);
    }
}

// メインのファジング関数
static void run_fuzzing_tests(njs_vm_t *vm) {
    // RIP制御を試みるテストケース
    const char *rip_control_tests[] = {
        // スタックバッファオーバーフロー
        "(() => { let a = new Array(1000000).fill('A'); a.toString(); })();",
        
        // ヒープオーバーフロー
        "(() => { let b = new ArrayBuffer(0xffffffff); })();",
        
        // 型混乱による制御フロー操作
        "(() => { let o = {}; o.__proto__ = new Uint8Array(8); })();",
        
        // JITコンパイラの最適化を悪用
        "for(let i=0; i<1000000; i++) { eval('(' + i + ')'); }",
        
        NULL
    };

    // メモリ破壊テストケース
    const char *memory_corruption_tests[] = {
        // 大量のメモリ確保と解放
        "let arrays = []; for(let i=0; i<1000; i++) { arrays.push(new ArrayBuffer(1024*1024)); }",
        
        // ガベージコレクタの誤動作を誘発
        "let obj = {}; for(let i=0; i<1000; i++) { obj = {prev: obj}; }",
        
        // TypedArrayの境界チェックバイパス
        "let buf = new ArrayBuffer(8); let view = new DataView(buf); view.setInt64(0, 0x4141414141414141);",
        
        NULL
    };

    // テストケースの実行
    for (const char **test = rip_control_tests; *test != NULL; test++) {
        execute_test(vm, *test);
    }

    for (const char **test = memory_corruption_tests; *test != NULL; test++) {
        execute_test(vm, *test);
    }
}

int main(int argc, char* argv[]) {
    njs_vm_t *vm;
    njs_vm_opt_t vm_options;
    
    // VMの初期化
    memset(&vm_options, 0, sizeof(njs_vm_opt_t));
    vm = njs_vm_create(&vm_options);
    if (vm == NULL) {
        fprintf(stderr, "Failed to create VM\n");
        return 1;
    }

    // メモリリークチェック
    size_t initial_memory = getCurrentMemoryUsage();
    
    // クラッシュハンドリング
    if (setjmp(crash_jmp_buf) == 0) {
        // テァジングテストの実行
        run_fuzzing_tests(vm);
    } else {
        fprintf(stderr, "Crash detected during test execution\n");
    }

    // メモリリークの検出
    size_t final_memory = getCurrentMemoryUsage();
    if (final_memory - initial_memory > MEMORY_LEAK_THRESHOLD) {
        fprintf(stderr, "Memory leak detected: %lu KB\n", 
                (final_memory - initial_memory));
    }

    // クリーンアップ
    njs_vm_destroy(vm);
    return 0;
}

// サニタイザー関数の実装
__attribute__((visibility("default")))
void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
    uint32_t index = *guard;
    if (!index) return;
    __shmem->edges[index / 8] |= 1 << (index % 8);
    *guard = 0;
}

__attribute__((visibility("default")))
void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop) {
    if (start == stop || *start) return;

    if (__edges_start != NULL || __edges_stop != NULL) {
        fprintf(stderr, "Coverage instrumentation is only supported for a single module\n");
        _exit(-1);
    }

    __edges_start = start;
    __edges_stop = stop;

    const char* shm_key = getenv("SHM_ID");
    if (!shm_key) {
        puts("[COV] no shared memory bitmap available, skipping");
        __shmem = (struct shmem_data*) malloc(SHM_SIZE);
    } else {
        int fd = shm_open(shm_key, O_RDWR, S_IRUSR | S_IWUSR);
        if (fd <= -1) {
            fprintf(stderr, "Failed to open shared memory region: %s\n", strerror(errno));
            _exit(-1);
        }

        __shmem = (struct shmem_data*) mmap(0, SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (__shmem == MAP_FAILED) {
            fprintf(stderr, "Failed to mmap shared memory region\n");
            _exit(-1);
        }
    }

    __sanitizer_cov_reset_edgeguards();
    __shmem->num_edges = stop - start;
    printf("[COV] edge counters initialized. Shared memory: %s with %u edges\n", shm_key, __shmem->num_edges);
}

__attribute__((visibility("default")))
void __sanitizer_cov_reset_edgeguards(void) {
    uint64_t N = 0;
    for (uint32_t *x = __edges_start; x < __edges_stop && N < MAX_EDGES; x++)
        *x = ++N;
}

