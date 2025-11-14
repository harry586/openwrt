#!/bin/bash
set -e

BUILD_DIR=${1:-/mnt/openwrt-build}
cd "$BUILD_DIR"

echo "=== 错误分析报告 ===" > error_analysis.log
echo "生成时间: $(date)" >> error_analysis.log

if [ -f "build_detailed.log" ]; then
    # 检查错误类型
    echo "1. 编译错误:" >> error_analysis.log
    grep "Error" build_detailed.log | head -10 >> error_analysis.log || echo "无编译错误" >> error_analysis.log
    
    echo "2. 警告:" >> error_analysis.log
    grep "warning:" build_detailed.log | head -5 >> error_analysis.log || echo "无警告" >> error_analysis.log
    
    echo "3. 被忽略的错误:" >> error_analysis.log
    grep "Error.*ignored" build_detailed.log >> error_analysis.log || echo "无被忽略错误" >> error_analysis.log
fi

# 构建状态
if [ -d "bin/targets" ]; then
    echo "构建状态: 成功" >> error_analysis.log
    echo "固件文件:" >> error_analysis.log
    find bin/targets -name "*.bin" >> error_analysis.log
else
    echo "构建状态: 失败" >> error_analysis.log
fi

cat error_analysis.log
