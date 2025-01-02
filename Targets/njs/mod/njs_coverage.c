#include "njs_coverage.h"
#include <stdio.h>
#include <njs.h>
#include <string.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/shm.h>
#include <fcntl.h>
#include <errno.h>

// グローバル変数の定義
jmp_buf crash_jmp_buf;

// ランダムな文字列生成用のヘルパー関数
static char* generate_random_string(size_t length) {
    static const char charset[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?";
    char* str = malloc(length + 1);
    for (size_t i = 0; i < length; i++) {
        str[i] = charset[rand() % (sizeof(charset) - 1)];
    }
    str[length] = '\0';
    return str;
}

// テストケース実行用の拡張ヘルパー関数
static void execute_test_with_timeout(njs_vm_t *vm, const char *test_case, int timeout_ms) {
    njs_int_t ret;
    njs_value_t result;
    clock_t start = clock();
    
    // タイムアウト付きで実行
    while ((clock() - start) * 1000 / CLOCKS_PER_SEC < timeout_ms) {
        ret = njs_vm_compile(vm, &result, (u_char *)test_case, strlen(test_case));
        if (ret != NJS_OK) {
            printf("[TEST] Compilation failed: %s\n", test_case);
            return;
        }

        ret = njs_vm_start(vm, &result);
        if (ret != NJS_OK) {
            printf("[TEST] Execution failed: %s\n", test_case);
            break;
        }
    }
}

// RIP制御の試行を含む敵対的なテストケース
static const char *control_flow_attacks[] = {
    // 関数ポインタの破壊を試みる
    "(() => {"
    "    let buf = new ArrayBuffer(8);"
    "    let view = new DataView(buf);"
    "    view.setBigUint64(0, 0x4141414141414141n);" // 任意のアドレス
    "    let fn = Function.prototype.call;"
    "    Object.defineProperty(Function.prototype, 'call', {"
    "        get: () => {"
    "            return new Proxy(fn, {"
    "                apply: (target, thisArg, args) => {"
    "                    thisArg.__proto__ = view;"
    "                    return target.apply(thisArg, args);"
    "                }"
    "            });"
    "        }"
    "    });"
    "})();",

    // vtableの破壊を試みる
    "(() => {"
    "    let spray = [];"
    "    for(let i = 0; i < 1000; i++) {"
    "        let buf = new ArrayBuffer(16);"
    "        let view = new DataView(buf);"
    "        view.setBigUint64(0, 0x4242424242424242n);" // vtableアドレス
    "        view.setBigUint64(8, 0x4343434343434343n);" // 関数ポインタ
    "        spray.push(view);"
    "    }"
    "    Object.prototype[Symbol.toPrimitive] = function() {"
    "        spray.length = 0;"
    "        gc();"
    "        return 1;"
    "    };"
    "})();",

    // JITスプレーを試みる
    "(() => {"
    "    function jitSpray() {"
    "        'use strict';"
    "        let x = 0x90909090; // NOPスレッド"
    "        let y = 0x41414141; // シェルコードのアドレス"
    "        for(let i = 0; i < 10000; i++) {"
    "            x = x + y | 0;"
    "            y = y + x | 0;"
    "        }"
    "        return x + y;"
    "    }"
    "    for(let i = 0; i < 1000; i++) jitSpray();"
    "})();",

    // スタック上のリターンアドレスの破壊を試みる
    "(() => {"
    "    let buf = new ArrayBuffer(1024);"
    "    let view = new DataView(buf);"
    "    for(let i = 0; i < buf.byteLength; i += 8) {"
    "        view.setBigUint64(i, 0x4444444444444444n);" // リターンアドレス
    "    }"
    "    function recursiveCall(depth) {"
    "        if(depth <= 0) return;"
    "        let arr = new Uint8Array(buf);"
    "        recursiveCall(depth - 1);"
    "    }"
    "    try {"
    "        recursiveCall(100);"
    "    } catch(e) {}"
    "})();",

    // 型混乱を利用したコード実行を試みる
    "(() => {"
    "    let conversion = {"
    "        [Symbol.toPrimitive]: function(hint) {"
    "            if(hint === 'number') {"
    "                return 0x4545454545454545;" // 任意のアドレス
    "            }"
    "            return '';"
    "        }"
    "    };"
    "    function trigger(obj) {"
    "        return obj | 0;"
    "    }"
    "    for(let i = 0; i < 1000; i++) {"
    "        trigger(conversion);"
    "    }"
    "})();",

    NULL
};

void generate_test_cases(void) {
    njs_vm_t *vm;
    njs_vm_opt_t vm_options;
    
    srand(time(NULL));
    memset(&vm_options, 0, sizeof(njs_vm_opt_t));
    vm = njs_vm_create(&vm_options);
    
    if (vm == NULL) {
        fprintf(stderr, "Failed to create VM\n");
        return;
    }

    // 敵対的なテストケース
    const char *aggressive_tests[] = {
        // プロトタイプ汚染攻撃
        "Object.prototype.__proto__ = null; "
        "Object.prototype.toString = function() { throw new Error('Prototype pollution'); };",

        // 深いネストによるスタック枯渇
        "var obj = {}; "
        "for(var i = 0; i < 100000; i++) { obj = {next: obj}; } "
        "JSON.stringify(obj);",

        // メモリ枯渇攻撃
        "var arrays = []; "
        "while(true) { "
        "   arrays.push(new Array(1000000).fill('x'.repeat(1000))); "
        "}",

        // 無限ループによるCPU枯渇
        "for(;;) { Math.random(); }",

        // 正規表現DoS
        "var evil = '(a+)+b'; "
        "var str = 'a'.repeat(100) + 'b'; "
        "new RegExp(evil).test(str);",

        // JSONパース攻撃
        "JSON.parse('[' + '1,'.repeat(1000000) + '1]')",

        // 巨大な文字列操作
        "var s = 'a'.repeat(1000000); "
        "while(true) { s += s; }",

        NULL
    };

    // 動的に生成される敵対的なテストケース
    char test_buffer[4096];
    for (int i = 0; i < 100; i++) {
        // ランダムな深いネストのオブジェクト生成
        snprintf(test_buffer, sizeof(test_buffer),
            "var obj = {}; "
            "var current = obj; "
            "for(var i = 0; i < %d; i++) { "
            "   current = current.next = {value: '%s'}; "
            "} "
            "JSON.stringify(obj);",
            rand() % 10000,
            generate_random_string(rand() % 100));
        execute_test_with_timeout(vm, test_buffer, 1000);  // 1秒タイムアウト

        // ランダムな正規表現DoS
        char* random_pattern = generate_random_string(rand() % 20);
        snprintf(test_buffer, sizeof(test_buffer),
            "var pattern = '(%s+)+%s'; "
            "var str = '%s'.repeat(%d); "
            "new RegExp(pattern).test(str);",
            random_pattern,
            generate_random_string(1),
            random_pattern,
            rand() % 1000);
        free(random_pattern);
        execute_test_with_timeout(vm, test_buffer, 1000);
    }

    // 既存のテストケースを実行
    for (const char **test = aggressive_tests; *test != NULL; test++) {
        execute_test_with_timeout(vm, *test, 2000);  // 2秒タイムアウト
    }

    // 制御フロー攻撃のテストケースを実行
    printf("\n[*] Executing control flow attack test cases...\n");
    for (const char **test = control_flow_attacks; *test != NULL; test++) {
        execute_test_with_timeout(vm, *test, 3000);  // 3秒タイムアウト
    }

    // ROP攻撃のシミュレーション
    char rop_buffer[8192];
    for (int i = 0; i < 100; i++) {
        snprintf(rop_buffer, sizeof(rop_buffer),
            "(() => {"
            "    let gadgets = [];"
            "    for(let i = 0; i < 100; i++) {"
            "        let buf = new ArrayBuffer(8);"
            "        let view = new DataView(buf);"
            "        view.setBigUint64(0, BigInt('0x%016llx'));" // ランダムなガジェットアドレス
            "        gadgets.push(view);"
            "    }"
            "    function triggerROP() {"
            "        let tmp = [];"
            "        for(let g of gadgets) {"
            "            tmp.push(g);"
            "            gc();"
            "        }"
            "    }"
            "    triggerROP();"
            "})();",
            (unsigned long long)(rand() * rand()));
        execute_test_with_timeout(vm, rop_buffer, 1000);
    }

    njs_vm_destroy(vm);
}

void generate_memory_fuzzing_test_cases(void) {
    njs_vm_t *vm;
    njs_vm_opt_t vm_options;
    
    memset(&vm_options, 0, sizeof(njs_vm_opt_t));
    vm = njs_vm_create(&vm_options);
    
    if (vm == NULL) {
        fprintf(stderr, "Failed to create VM\n");
        return;
    }

    // メモリ破壊を狙った敵対的なテストケース
    const char *memory_attacks[] = {
        // ヒープスプレー攻撃
        "var spray = []; "
        "for(var i = 0; i < 10000; i++) { "
        "   spray.push(new ArrayBuffer(1024).fill(0x41414141)); "
        "} "
        "for(var i = 0; i < spray.length; i++) { "
        "   spray[i] = undefined; "
        "} "
        "gc();",

        // メモリフラグメンテーション誘発
        "var fragments = []; "
        "for(var i = 0; i < 1000; i++) { "
        "   if (i % 2 === 0) { "
        "       fragments.push(new ArrayBuffer(1024 * 1024)); "
        "   } "
        "} "
        "for(var i = 0; i < fragments.length; i += 2) { "
        "   fragments[i] = undefined; "
        "} "
        "gc();",

        // TypedArrayの境界値攻撃
        "var buffer = new ArrayBuffer(16); "
        "var view = new Uint32Array(buffer); "
        "view[4] = 0xFFFFFFFF;",  // 境界外アクセス

        // 巨大なArrayBufferの確保と解放の繰り返し
        "for(var i = 0; i < 100; i++) { "
        "   var buf = new ArrayBuffer(1024 * 1024 * 100); "
        "   buf = undefined; "
        "   gc(); "
        "}",

        NULL
    };

    for (const char **test = memory_attacks; *test != NULL; test++) {
        execute_test_with_timeout(vm, *test, 5000);  // 5秒タイムアウト
    }

    // クリーンアップ
    njs_vm_destroy(vm);
}

// メモリリーク検出の強化
void check_memory_state(void) {
    static size_t last_vm_size = 0;
    static size_t last_rss = 0;
    
    printf("\n=== Memory Status ===\n");
    FILE *status = fopen("/proc/self/status", "r");
    if (status) {
        char line[128];
        size_t current_vm_size = 0;
        size_t current_rss = 0;
        
        while (fgets(line, sizeof(line), status)) {
            if (strncmp(line, "VmSize:", 7) == 0) {
                sscanf(line, "VmSize: %lu", &current_vm_size);
            } else if (strncmp(line, "VmRSS:", 6) == 0) {
                sscanf(line, "VmRSS: %lu", &current_rss);
            }
        }
        
        // メモリ使用量の変化を検出
        if (last_vm_size > 0) {
            long vm_diff = current_vm_size - last_vm_size;
            long rss_diff = current_rss - last_rss;
            
            printf("Memory changes since last check:\n");
            printf("VmSize: %+ld KB\n", vm_diff);
            printf("VmRSS: %+ld KB\n", rss_diff);
            
            if (vm_diff > 1024 || rss_diff > 1024) {
                printf("WARNING: Significant memory increase detected!\n");
            }
        }
        
        last_vm_size = current_vm_size;
        last_rss = current_rss;
        fclose(status);
    }
    printf("==================\n\n");
}

// メモリ破壊検出の強化
static void enhanced_memory_check(const void* ptr, size_t size) {
    // 既存のチェックに加えて、RIP制御の可能性をチェック
    void* return_address;
    #if defined(__x86_64__)
    asm volatile("movq 8(%%rbp), %0" : "=r"(return_address));
    #endif
    
    // リターンアドレスが実行可能領域外を指していないかチェック
    if ((uintptr_t)return_address < 0x400000 || 
        (uintptr_t)return_address > 0x7fffffffffff) {
        fprintf(stderr, "WARNING: Suspicious return address detected: %p\n", return_address);
    }
    
    // スタックカナリアのチェック
    uintptr_t* stack_chk = (uintptr_t*)__builtin_frame_address(0) - 1;
    if (*stack_chk != *(uintptr_t*)__builtin_frame_address(1)) {
        fprintf(stderr, "WARNING: Stack canary corruption detected\n");
    }
}

// getCurrentMemoryUsage関数をstatic修飾子を外して公開
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

// サニタイザー関数をグローバルに公開
void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
    uint32_t index = *guard;
    if (!index) return;
    __shmem->edges[index / 8] |= 1 << (index % 8);
    *guard = 0;
}

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

void __sanitizer_cov_reset_edgeguards(void) {
    uint64_t N = 0;
    for (uint32_t *x = __edges_start; x < __edges_stop && N < MAX_EDGES; x++)
        *x = ++N;
} 