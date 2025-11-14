#!/bin/bash
set -e

BUILD_DIR=${1:-/mnt/openwrt-build}
cd "$BUILD_DIR"

echo "=== 固件构建错误分析报告 ===" > error_analysis.log
echo "生成时间: $(date)" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 构建结果摘要 ===" >> error_analysis.log
if [ -d "bin/targets" ]; then
    echo "✅ 构建状态: 成功" >> error_analysis.log
    echo "✅ 生成的固件文件: $(find bin/targets -name '*.bin' -o -name '*.img' | wc -l)" >> error_analysis.log
    find bin/targets -name "*.bin" -o -name "*.img" | head -5 >> error_analysis.log
else
    echo "❌ 构建状态: 失败" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "=== 关键错误检查 ===" >> error_analysis.log
if [ -f "build_detailed.log" ]; then
    echo "检查日志文件: build_detailed.log" >> error_analysis.log
    
    # 编译错误
    echo "❌ 发现编译错误:" >> error_analysis.log
    grep -E "Error [0-9]|error:" build_detailed.log | head -10 >> error_analysis.log || echo "无关键编译错误" >> error_analysis.log
    
    # Makefile错误
    echo "" >> error_analysis.log
    echo "❌ Makefile执行错误:" >> error_analysis.log
    grep "make.*Error" build_detailed.log | head -10 >> error_analysis.log || echo "无Makefile错误" >> error_analysis.log
    
    # 被忽略的错误
    echo "" >> error_analysis.log
    echo "⚠️ 被忽略的错误:" >> error_analysis.log
    grep "Error.*ignored" build_detailed.log >> error_analysis.log || echo "无被忽略错误" >> error_analysis.log
    
    # 文件缺失错误
    echo "" >> error_analysis.log
    echo "❌ 文件缺失错误:" >> error_analysis.log
    grep -E "No such file|file not found" build_detailed.log | head -5 >> error_analysis.log || echo "无文件缺失错误" >> error_analysis.log
else
    echo "未找到构建日志文件" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "=== 错误原因分析和建议 ===" >> error_analysis.log
echo "⚠️  文件缺失错误" >> error_analysis.log
echo "💡 可能原因: 源码不完整或下载失败" >> error_analysis.log
echo "" >> error_analysis.log
echo "⚠️  管道错误" >> error_analysis.log
echo "💡 这是并行编译的正常现象，不影响最终结果" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 详细错误分类 ===" >> error_analysis.log
echo "开始收集和分析错误日志..." >> error_analysis.log
echo "使用日志文件: build_detailed.log" >> error_analysis.log
echo "" >> error_analysis.log

echo "1. 严重错误 (Failed):" >> error_analysis.log
grep -i "failed" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
echo "" >> error_analysis.log

echo "2. 编译错误 (error:):" >> error_analysis.log
grep "error:" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
echo "" >> error_analysis.log

echo "3. 退出错误 (error 1/error 2):" >> error_analysis.log
grep -E "error 1|error 2" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
echo "" >> error_analysis.log

echo "4. 文件缺失错误:" >> error_analysis.log
grep -E "No such file|file not found" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
echo "" >> error_analysis.log

echo "5. 管道错误:" >> error_analysis.log
grep "Broken pipe" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
echo "" >> error_analysis.log

echo "6. 缺失依赖错误:" >> error_analysis.log
grep "depends on" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
echo "" >> error_analysis.log

echo "错误分析完成" >> error_analysis.log

# 输出到控制台
cat error_analysis.log
