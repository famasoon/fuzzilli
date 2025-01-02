#include <njs.h>
#include <njs_assert.h>
#include <njs_string.h>
#include <assert.h>
#include <stdio.h>
#include <njs_main.h>

#include <stdlib.h>
#include <sys/mman.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include "njs_coverage.h"
#include <sys/types.h>

#define MAX_MEMORY_ADDRESS ((uintptr_t)1 << 47)  // 128TB - 一般的な64ビットシステムの制限

// 前方宣言
static void enhanced_memory_check(const void* ptr, size_t size);
static int is_valid_heap_address(const void* ptr);
static void watch_memory_access(void* ptr, size_t size);
static void check_memory_access(void* ptr);
static void check_memory_corruption(const void* ptr, size_t size);
static njs_int_t njs_fuzzilli_func(njs_vm_t *vm, njs_value_t *args,
    njs_uint_t nargs, njs_index_t unused, njs_value_t *retval);
static njs_int_t njs_fuzzilli_init(njs_vm_t *vm);

// メモリアクセス監視の強化
#define MEMORY_WATCH_SIZE 1024
static struct {
    void* addresses[MEMORY_WATCH_SIZE];
    size_t sizes[MEMORY_WATCH_SIZE];
    int count;
} memory_watch;

// 関数の実装
static void watch_memory_access(void* ptr, size_t size) {
    if (memory_watch.count < MEMORY_WATCH_SIZE) {
        memory_watch.addresses[memory_watch.count] = ptr;
        memory_watch.sizes[memory_watch.count] = size;
        memory_watch.count++;
    }
}

static void check_memory_access(void* ptr) {
    for (int i = 0; i < memory_watch.count; i++) {
        if (ptr >= memory_watch.addresses[i] && 
            ptr < (void*)((char*)memory_watch.addresses[i] + memory_watch.sizes[i])) {
            fprintf(stderr, "Suspicious memory access detected at %p\n", ptr);
            break;
        }
    }
}

static int is_valid_heap_address(const void* ptr) {
    if (ptr == NULL) {
        return 0;
    }
    
    if ((uintptr_t)ptr % sizeof(void*) != 0) {
        return 0;
    }
    
    return 1;
}

static njs_external_t  njs_ext_fuzzilli[] = {
    {
        .flags = NJS_EXTERN_PROPERTY | NJS_EXTERN_SYMBOL,
        .name.symbol = NJS_SYMBOL_TO_STRING_TAG,
        .u.property = {
            .value = "fuzzilli",
        }
    },

    {
        .flags = NJS_EXTERN_METHOD,
        .name.string = njs_str("testing"),
        .writable = 1,
        .configurable = 1,
        .enumerable = 1,
        .u.method = {
            .native = njs_fuzzilli_func,
        }
    },
};

njs_module_t  njs_fuzzilli_module = {
    .name = njs_str("fuzzilli"),
    .preinit = NULL,
    .init = njs_fuzzilli_init,
};

#define REPRL_DWFD 103

static void check_memory_corruption(const void* ptr, size_t size) {
    if (ptr == NULL) {
        fprintf(stderr, "Null pointer access detected\n");
        return;
    }
    
    if ((uintptr_t)ptr + size > MAX_MEMORY_ADDRESS) {
        fprintf(stderr, "Memory boundary violation detected\n");
        return;
    }
    
    if (!is_valid_heap_address(ptr)) {
        fprintf(stderr, "Invalid heap access detected\n");
        return;
    }
    
    void* stack_var;
    if (ptr >= (void*)&stack_var - 1024*1024 && 
        ptr <= (void*)&stack_var + 1024*1024) {
        fprintf(stderr, "Potential stack memory access violation\n");
        return;
    }

    watch_memory_access((void*)ptr, size);
    check_memory_access((void*)ptr);
    enhanced_memory_check(ptr, size);
}

static void enhanced_memory_check(const void* ptr, size_t size) {
    void* return_address;
    #if defined(__x86_64__)
    asm volatile("movq 8(%%rbp), %0" : "=r"(return_address));
    #endif
    
    if ((uintptr_t)return_address < 0x400000 || 
        (uintptr_t)return_address > 0x7fffffffffff) {
        fprintf(stderr, "WARNING: Suspicious return address detected: %p\n", return_address);
    }
    
    void* frame_base = __builtin_frame_address(0);
    if (frame_base == NULL) {
        fprintf(stderr, "WARNING: Invalid frame pointer detected\n");
        return;
    }

    void* stack_var;
    if ((uintptr_t)frame_base < (uintptr_t)&stack_var - 1024*1024 || 
        (uintptr_t)frame_base > (uintptr_t)&stack_var + 1024*1024) {
        fprintf(stderr, "WARNING: Stack frame corruption detected\n");
    }

    uintptr_t* current_frame = (uintptr_t*)frame_base;
    if (*current_frame == 0 || *current_frame == (uintptr_t)-1) {
        fprintf(stderr, "WARNING: Suspicious stack frame value detected\n");
    }
}

static njs_int_t
njs_fuzzilli_func(njs_vm_t *vm, njs_value_t *args, njs_uint_t nargs,
    njs_index_t unused, njs_value_t *retval)
{
    uint32_t     num;
    njs_int_t    ret;
    njs_value_t        *value, lvalue;
    njs_value_t        *value2, lvalue2;
    njs_string_prop_t string;
    njs_string_prop_t string2;
    double       number_value;

    value = njs_lvalue_arg(&lvalue, args, nargs, 1);

    ret = njs_value_to_string(vm, value, value);
    if(njs_slow_path(ret != NJS_OK)) { return ret; }

    (void) njs_string_trim(value, &string, NJS_TRIM_START);

    char *str = (char *)string.start;
    str[string.length] = 0x00;

    if (!strcmp(str, "FUZZILLI_CRASH")) {
        ret = njs_value_to_uint32(vm, njs_arg(args, nargs, 2), &num);
        if(njs_slow_path(ret != NJS_OK)) { return ret; }

        switch (num) {
        case 0:
            *((int*)0x41414141) = 0x1337;
            break;
        case 1:
            assert(0);
            break;
        default:
            assert(0);
            break;
        }
    } else if (!strcmp(str, "FUZZILLI_PRINT") && nargs > 1) {
        value2 = njs_lvalue_arg(&lvalue2, args, nargs, 2);
        value2->type = NJS_STRING;
        ret = njs_value_to_string(vm, value2, value2);
        if(njs_slow_path(ret != NJS_OK)) { return ret; }
        (void) njs_string_trim(value2, &string2, NJS_TRIM_START);

        char* print_str = (char*)string2.start;
        print_str[string2.length] = 0x00;

        FILE* fzliout = fdopen(REPRL_DWFD, "w");
        if (!fzliout) {
            fprintf(stderr, "Fuzzer output channel not available, printing to stdout instead\n");
            fzliout = stdout;
        }

        if (print_str) {
            fprintf(fzliout, "%s\n", print_str);
        }
        fflush(fzliout);
    } else if (!strcmp(str, "FUZZILLI_MEMORY_CHECK")) {
        njs_value_t *ptr_value = njs_arg(args, nargs, 2);
        njs_value_t *size_value = njs_arg(args, nargs, 3);
        void *ptr;
        size_t size;

        if (njs_value_is_number(ptr_value)) {
            ret = njs_value_to_number(vm, ptr_value, &number_value);
            if (ret != NJS_OK) return ret;
            ptr = (void*)(uintptr_t)number_value;
        } else {
            return NJS_ERROR;
        }

        ret = njs_value_to_number(vm, size_value, &number_value);
        if (ret != NJS_OK) return ret;
        size = (size_t)number_value;

        check_memory_corruption(ptr, size);
    }

    return NJS_OK;
}

static njs_int_t
njs_fuzzilli_init(njs_vm_t *vm)
{
    njs_int_t           ret, proto_id;
    njs_str_t           name = njs_str("fuzzer");
    njs_str_t           fuzzer_func  = njs_str("fuzzer.testing");
    njs_str_t           builtin_name = njs_str("fuzzilli");
    njs_opaque_value_t  value;
    njs_opaque_value_t  method;

    proto_id = njs_vm_external_prototype(vm, njs_ext_fuzzilli,
                                         njs_nitems(njs_ext_fuzzilli));
    if (njs_slow_path(proto_id < 0)) {
        return NJS_ERROR;
    }

    ret = njs_vm_external_create(vm, njs_value_arg(&value), proto_id, NULL, 1);
    if (njs_slow_path(ret != NJS_OK)) {
        return NJS_ERROR;
    }

    ret = njs_vm_bind(vm, &name, njs_value_arg(&value), 1);
    if (njs_slow_path(ret != NJS_OK)) {
        return NJS_ERROR;
    }

    ret = njs_vm_value(vm, &fuzzer_func, njs_value_arg(&method));
    if (njs_slow_path(ret != NJS_OK)) {
        return NJS_ERROR;
    }

    ret = njs_vm_bind(vm, &builtin_name, njs_value_arg(&method), 0);
    if (njs_slow_path(ret != NJS_OK)) {
        return NJS_ERROR;
    }

    return NJS_OK;
}