#!/bin/bash
# error_analysis.sh - 错误分析脚本

BUILD_DIR=$1
cd $BUILD_DIR

echo "=== 固件构建错误分析报告 ===" > error_analysis.log

# 首先检查构建结果
echo "=== 构建结果摘要 ===" >> error_analysis.log
if [ -d "bin/targets" ]; then
    FIRMWARE_COUNT=$(find bin/targets -name "*.bin" -o -name "*.img" -o -name "*.trx" 2>/dev/null | wc -l)
    if [ $FIRMWARE_COUNT -gt 0 ]; then
        echo "✅ 构建状态: 成功" >> error_analysis.log
        echo "✅ 生成的固件文件: $FIRMWARE_COUNT" >> error_analysis.log
        find bin/targets -name "*.bin" -o -name "*.img" -o -name "*.trx" 2>/dev/null | head -10 >> error_analysis.log
    else
        echo "❌ 构建状态: 失败 - 无固件生成" >> error_analysis.log
    fi
else
    echo "❌ 构建状态: 失败 - 无目标目录" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 关键错误检查放在前面
echo "=== 关键错误检查 ===" >> error_analysis.log
if grep -q "Error [0-9]" build.log 2>/dev/null; then
    echo "❌ 发现编译错误:" >> error_analysis.log
    grep "Error [0-9]" build.log | head -5 >> error_analysis.log
else
    echo "✅ 未发现关键编译错误" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 检查 package/install 错误
if grep -q "package/install.*Error 255" build.log 2>/dev/null; then
    echo "❌ 关键错误: 软件包安装失败 (Error 255)" >> error_analysis.log
    echo "💡 建议解决方案:" >> error_analysis.log
    echo "  1. 检查软件包依赖关系" >> error_analysis.log
    echo "  2. 清理并重新编译: make clean && make dirclean" >> error_analysis.log
    echo "  3. 检查磁盘空间是否充足" >> error_analysis.log
    echo "  4. 尝试单线程编译: make -j1 V=s" >> error_analysis.log
    echo "" >> error_analysis.log
fi

# 错误原因分析和建议
echo "=== 错误原因分析和建议 ===" >> error_analysis.log

# 检查其他常见错误
if grep -q "No such file or directory" build.log 2>/dev/null; then
    echo "⚠️  文件缺失错误" >> error_analysis.log
    echo "💡 可能原因: 源码不完整或下载失败" >> error_analysis.log
    echo "" >> error_analysis.log
fi

if grep -q "Broken pipe" build.log 2>/dev/null; then
    echo "⚠️  管道错误" >> error_analysis.log
    echo "💡 这是并行编译的正常现象，不影响最终结果" >> error_analysis.log
    echo "" >> error_analysis.log
fi

# 下面是详细的错误分类（放在后面）
echo "=== 详细错误分类 ===" >> error_analysis.log
echo "开始收集和分析错误日志..." >> error_analysis.log

echo "1. 严重错误 (Failed):" >> error_analysis.log
grep -i "failed" build.log | head -10 >> error_analysis.log 2>/dev/null || echo "无严重错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "2. 编译错误 (error:):" >> error_analysis.log
grep "error:" build.log | head -10 >> error_analysis.log 2>/dev/null || echo "无编译错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "3. 退出错误 (error 1/error 2):" >> error_analysis.log
grep -E "error [12]" build.log | head -5 >> error_analysis.log 2>/dev/null || echo "无退出错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "4. 文件缺失错误:" >> error_analysis.log
grep -i "no such file or directory" build.log | head -5 >> error_analysis.log 2>/dev/null || echo "无文件缺失错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "5. 管道错误:" >> error_analysis.log
grep -i "broken pipe" build.log | head -5 >> error_analysis.log 2>/dev/null || echo "无管道错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "6. 缺失依赖错误:" >> error_analysis.log
grep -i "missing" build.log | head -5 >> error_analysis.log 2>/dev/null || echo "无缺失依赖错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "错误分析完成" >> error_analysis.log

# 创建错误摘要
echo "=== 错误摘要 ===" > error_summary.log
echo "构建状态: $(grep "构建状态" error_analysis.log | head -1)" >> error_summary.log
echo "关键错误: $(grep "关键错误检查" error_analysis.log -A 2 | tail -1)" >> error_summary.log
echo "" >> error_summary.log
echo "详细报告请查看 error_analysis.log" >> error_summary.log

# 在终端显示关键信息
echo "=== 构建结果 ==="
tail -n 20 error_analysis.log | head -n 15
