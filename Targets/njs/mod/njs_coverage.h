#ifndef _NJS_COVERAGE_H
#define _NJS_COVERAGE_H

#include <stdint.h>
#include <njs.h>
#include <setjmp.h>

// 既存の定義を削除し、njs_fuzzilli.cと共有する定義を使用
#ifndef SHM_SIZE
#define SHM_SIZE 0x100000
#endif

#ifndef MAX_EDGES
#define MAX_EDGES ((SHM_SIZE - 4) * 8)
#endif

#define MEMORY_LEAK_THRESHOLD (1024 * 1024)  // 1MB

// 共有メモリのデータ構造
struct shmem_data {
    uint32_t num_edges;
    uint8_t edges[];
};

// グローバル変数の宣言
extern jmp_buf crash_jmp_buf;
extern struct shmem_data* __shmem;
extern uint32_t *__edges_start, *__edges_stop;

// グローバル関数の宣言
size_t getCurrentMemoryUsage(void);
void __sanitizer_cov_reset_edgeguards(void);
void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop);
void __sanitizer_cov_trace_pc_guard(uint32_t *guard);

// メモリ使用量取得関数
size_t getCurrentMemoryUsage(void);

// カバレッジ関連の関数宣言
void __sanitizer_cov_reset_edgeguards(void);
void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop);
void __sanitizer_cov_trace_pc_guard(uint32_t *guard);
void print_coverage_stats(void);

// テストケース生成関数の宣言
void generate_test_cases(void);
void generate_memory_fuzzing_test_cases(void);

// メモリチェック関連の関数宣言
void check_memory_state(void);

// ヒープ検証関連の関数宣言
void monitor_heap_operations(void);
void detect_heap_corruption(void);

#ifdef __cplusplus
extern "C" {
#endif

// 外部インターフェース関数
njs_int_t njs_coverage_init(njs_vm_t *vm);
void njs_coverage_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif /* _NJS_COVERAGE_H */