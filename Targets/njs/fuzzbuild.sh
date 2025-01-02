#!/bin/bash
set -e

cd njs/
./configure --cc=clang --cc-opt="-g -fsanitize-coverage=trace-pc-guard -fprofile-instr-generate -fcoverage-mapping"
make njs_fuzzilli

LLVM_PROFILE_FILE="njs.profraw" ./build/njs_fuzzilli test.js
llvm-profdata merge -sparse njs.profraw -o njs.profdata
llvm-cov show ./build/njs_fuzzilli -instr-profile=njs.profdata > coverage_report.txt