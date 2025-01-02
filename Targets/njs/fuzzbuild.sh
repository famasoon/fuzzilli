#!/bin/bash
set -e

cd njs/
# メモリ関連のサニタイザを追加
SANITIZER_FLAGS="-g -fsanitize=address,undefined,leak -fsanitize-coverage=trace-pc-guard"
MEMORY_FLAGS="-fno-omit-frame-pointer -fno-optimize-sibling-calls"
DEBUG_FLAGS="-DDEBUG -DNJS_DEBUG_MEMORY=1 -DNJS_DEBUG_LEVEL=2"

./configure --cc=clang --cc-opt="$SANITIZER_FLAGS $MEMORY_FLAGS $DEBUG_FLAGS"
make njs_fuzzilli

LLVM_PROFILE_FILE="njs.profraw" ./build/njs_fuzzilli test.js
llvm-profdata merge -sparse njs.profraw -o njs.profdata
llvm-cov show ./build/njs_fuzzilli -instr-profile=njs.profdata > coverage_report.txt