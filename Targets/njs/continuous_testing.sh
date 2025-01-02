#!/bin/bash
while true; do
    ./build/njs_fuzzilli fuzz
    sleep 1
    # カバレッジレポートの生成
    ./generate_coverage_report.sh
done 