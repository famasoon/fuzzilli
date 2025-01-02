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

static njs_int_t njs_fuzzilli_func(njs_vm_t *vm, njs_value_t *args,
    njs_uint_t nargs, njs_index_t unused, njs_value_t *retval);

static njs_int_t njs_fuzzilli_init(njs_vm_t *vm);

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


    value = njs_lvalue_arg(&lvalue, args, nargs, 1);

    ret = njs_value_to_string(vm, value, value);
    if(njs_slow_path(ret != NJS_OK)) { return ret; }

    (void) njs_string_trim(value, &string, NJS_TRIM_START);

    char *str = (char *)string.start;
    str[string.length] = 0x00;

        if (!strcmp(str, "FUZZILLI_CRASH")) {
        // fetch arg
        ret = njs_value_to_uint32(vm, njs_arg(args, nargs, 2), &num);
        if(njs_slow_path(ret != NJS_OK)) { return ret; }

        // execute action
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
        // fetch arg
        value2 = njs_lvalue_arg(&lvalue2, args, nargs, 2);
        value2->type = NJS_STRING;
        ret = njs_value_to_string(vm, value2, value2);
        if(njs_slow_path(ret != NJS_OK)) { return ret; }
        (void) njs_string_trim(value2, &string2, NJS_TRIM_START);

        char* print_str = (char*)string2.start;
        print_str[string2.length] = 0x00;

        // execute action
        FILE* fzliout = fdopen(REPRL_DWFD, "w");
        if (!fzliout) {
            fprintf(stderr, "Fuzzer output channel not available, printing to stdout instead\n");
            fzliout = stdout;
        }

        if (print_str) {
            fprintf(fzliout, "%s\n", print_str);
        }
        fflush(fzliout);
    } else if (!strcmp(str, "FUZZILLI_TEST_OBJECT")) {
        // オブジェクト操作のテスト
        njs_value_t obj;
        njs_object_value_init(&obj);
        
        // プロパティの設定
        njs_value_t prop;
        njs_string_value_init(&prop, (u_char*)"test", 4);
        njs_object_prop_set(vm, &obj, "prop", &prop);
        
        // メソッドの呼び出し
        njs_function_call(vm, njs_function(&obj), &obj, NULL, 0);
    } else if (!strcmp(str, "FUZZILLI_TEST_PROTOTYPE")) {
        njs_value_t proto, obj;
        njs_object_value_init(&proto);
        njs_object_value_init(&obj);
        
        njs_object_prototype_set(vm, &obj, &proto);
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



struct shmem_data* __shmem;
uint32_t *__edges_start, *__edges_stop;


void __sanitizer_cov_reset_edgeguards() {
    uint64_t N = 0;
    for (uint32_t *x = __edges_start; x < __edges_stop && N < MAX_EDGES; x++)
        *x = ++N;
}

void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop) {
    // Avoid duplicate initialization
    if (start == stop || *start)
        return;

    if (__edges_start != NULL || __edges_stop != NULL) {
        fprintf(stderr, "Coverage instrumentation is only supported for a single module\n");
        _exit(-1);
    }

    __edges_start = start;
    __edges_stop = stop;

    // Map the shared memory region
    const char* shm_key = getenv("SHM_ID");
    if (!shm_key) {
        puts("[COV] no shared memory bitmap available, skipping");
        __shmem = (struct shmem_data*) malloc(SHM_SIZE);
    } else {
        int fd = shm_open(shm_key, O_RDWR, S_IREAD | S_IWRITE);
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

void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
    uint32_t index = *guard;
    if (!index) return;
    
    // エッジカウンターの記録
    index = (index & EDGE_COUNTER_MASK);
    __shmem->edges[index / 8] |= 1 << (index % 8);
    
    // ヒットカウントの記録
    ((struct coverage_data*)__shmem)->hit_count[index]++;
    
    *guard = 0;
}