#!/bin/bash
# error_analysis.sh - 错误分析脚本

BUILD_DIR=$1
cd $BUILD_DIR

echo "=== 固件构建错误分析报告 ===" > error_analysis.log

# 首先检查构建结果
echo "=== 构建结果摘要 ===" >> error_analysis.log

# 检查多个可能的固件位置
if [ -d "bin/targets" ]; then
    FIRMWARE_COUNT=$(find bin/targets -name "*.bin" -o -name "*.img" -o -name "*.trx" 2>/dev/null | wc -l)
    if [ $FIRMWARE_COUNT -gt 0 ]; then
        echo "✅ 构建状态: 成功" >> error_analysis.log
        echo "✅ 生成的固件文件: $FIRMWARE_COUNT" >> error_analysis.log
        find bin/targets -name "*.bin" -o -name "*.img" -o -name "*.trx" 2>/dev/null | head -10 >> error_analysis.log
    else
        echo "❌ 构建状态: 部分成功 - 编译完成但无固件生成" >> error_analysis.log
    fi
elif [ -d "bin" ]; then
    FIRMWARE_COUNT=$(find bin -name "*.bin" -o -name "*.img" -o -name "*.trx" 2>/dev/null | wc -l)
    if [ $FIRMWARE_COUNT -gt 0 ]; then
        echo "✅ 构建状态: 成功" >> error_analysis.log
        echo "✅ 生成的固件文件: $FIRMWARE_COUNT" >> error_analysis.log
        find bin -name "*.bin" -o -name "*.img" -o -name "*.trx" 2>/dev/null | head -10 >> error_analysis.log
    else
        echo "❌ 构建状态: 失败 - 编译完成但无固件生成" >> error_analysis.log
    fi
else
    echo "❌ 构建状态: 失败 - 编译未完成" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 关键错误检查放在前面
echo "=== 关键错误检查 ===" >> error_analysis.log

# 检查所有可能的日志文件
LOG_FILES="build.log build_detailed.log"
FOUND_ERRORS=0

for LOG_FILE in $LOG_FILES; do
    if [ -f "$LOG_FILE" ]; then
        echo "检查日志文件: $LOG_FILE" >> error_analysis.log
        
        # 检查编译错误
        if grep -q "Error [0-9]" "$LOG_FILE" 2>/dev/null; then
            echo "❌ 发现编译错误:" >> error_analysis.log
            grep "Error [0-9]" "$LOG_FILE" | head -10 >> error_analysis.log
            FOUND_ERRORS=1
        fi
        
        # 检查特定错误模式
        if grep -q "cp: cannot create.*No such file or directory" "$LOG_FILE" 2>/dev/null; then
            echo "❌ 关键错误: 文件创建失败" >> error_analysis.log
            grep "cp: cannot create.*No such file or directory" "$LOG_FILE" | head -5 >> error_analysis.log
            FOUND_ERRORS=1
        fi
        
        # 检查内核构建错误
        if grep -q "target/linux failed to build" "$LOG_FILE" 2>/dev/null; then
            echo "❌ 关键错误: Linux内核构建失败" >> error_analysis.log
            grep -A 5 -B 5 "target/linux failed to build" "$LOG_FILE" >> error_analysis.log
            FOUND_ERRORS=1
        fi
        
        # 检查makefile错误
        if grep -q "Makefile.*Error" "$LOG_FILE" 2>/dev/null; then
            echo "❌ Makefile执行错误:" >> error_analysis.log
            grep "Makefile.*Error" "$LOG_FILE" | head -5 >> error_analysis.log
            FOUND_ERRORS=1
        fi
    fi
done

if [ $FOUND_ERRORS -eq 0 ]; then
    echo "✅ 未发现关键编译错误" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 错误原因分析和建议
echo "=== 错误原因分析和建议 ===" >> error_analysis.log

# 检查文件创建错误
if grep -q "cp: cannot create.*No such file or directory" build_detailed.log 2>/dev/null; then
    echo "❌ 关键错误: 文件系统权限或空间问题" >> error_analysis.log
    echo "💡 可能原因:" >> error_analysis.log
    echo "  1. 磁盘空间不足" >> error_analysis.log
    echo "  2. 文件系统权限问题" >> error_analysis.log  
    echo "  3. 内核配置错误导致init文件无法创建" >> error_analysis.log
    echo "💡 解决方案:" >> error_analysis.log
    echo "  1. 检查磁盘空间: df -h" >> error_analysis.log
    echo "  2. 清理构建目录: make clean" >> error_analysis.log
    echo "  3. 检查目标设备配置是否正确" >> error_analysis.log
    echo "  4. 尝试使用不同的内核版本" >> error_analysis.log
    echo "" >> error_analysis.log
fi

# 检查内核构建错误
if grep -q "target/linux failed to build" build_detailed.log 2>/dev/null; then
    echo "❌ 关键错误: Linux内核编译失败" >> error_analysis.log
    echo "💡 可能原因:" >> error_analysis.log
    echo "  1. 内核配置冲突" >> error_analysis.log
    echo "  2. 工具链问题" >> error_analysis.log
    echo "  3. 设备树配置错误" >> error_analysis.log
    echo "💡 解决方案:" >> error_analysis.log
    echo "  1. 清理内核构建: make target/linux/clean" >> error_analysis.log
    echo "  2. 检查内核配置: make kernel_menuconfig" >> error_analysis.log
    echo "  3. 验证设备支持" >> error_analysis.log
    echo "" >> error_analysis.log
fi

# 检查其他常见错误
if grep -q "No such file or directory" build_detailed.log 2>/dev/null; then
    echo "⚠️  文件缺失错误" >> error_analysis.log
    echo "💡 可能原因: 源码不完整或下载失败" >> error_analysis.log
    echo "" >> error_analysis.log
fi

if grep -q "Broken pipe" build_detailed.log 2>/dev/null; then
    echo "⚠️  管道错误 (正常现象)" >> error_analysis.log
    echo "💡 这是并行编译的正常现象，不影响最终结果" >> error_analysis.log
    echo "" >> error_analysis.log
fi

# 下面是详细的错误分类（放在后面）
echo "=== 详细错误分类 ===" >> error_analysis.log
echo "开始收集和分析错误日志..." >> error_analysis.log

if [ -f "build_detailed.log" ]; then
    LOG_FILE="build_detailed.log"
else
    LOG_FILE="build.log"
fi

echo "使用日志文件: $LOG_FILE" >> error_analysis.log
echo "" >> error_analysis.log

echo "1. 严重错误 (Failed):" >> error_analysis.log
grep -i "failed" "$LOG_FILE" | head -10 2>/dev/null || echo "无严重错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "2. 编译错误 (error:):" >> error_analysis.log
grep "error:" "$LOG_FILE" | head -10 2>/dev/null || echo "无编译错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "3. 退出错误 (error 1/error 2):" >> error_analysis.log
grep -E "error [12]" "$LOG_FILE" | head -5 2>/dev/null || echo "无退出错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "4. 文件缺失错误:" >> error_analysis.log
grep -i "no such file or directory" "$LOG_FILE" | head -5 2>/dev/null || echo "无文件缺失错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "5. 管道错误:" >> error_analysis.log
grep -i "broken pipe" "$LOG_FILE" | head -5 2>/dev/null || echo "无管道错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "6. 缺失依赖错误:" >> error_analysis.log
grep -i "missing" "$LOG_FILE" | head -5 2>/dev/null || echo "无缺失依赖错误" >> error_analysis.log
echo "" >> error_analysis.log

echo "错误分析完成" >> error_analysis.log

# 创建错误摘要
echo "=== 错误摘要 ===" > error_summary.log
echo "构建状态: $(grep "构建状态" error_analysis.log | head -1)" >> error_summary.log
echo "关键错误: $(grep "关键错误:" error_analysis.log | head -1)" >> error_summary.log
echo "" >> error_summary.log
echo "详细报告请查看 error_analysis.log" >> error_summary.log

# 在终端显示关键信息
echo "=== 构建结果 ==="
grep -A 5 "构建结果摘要" error_analysis.log
echo ""
echo "=== 关键错误 ==="
grep -A 3 "关键错误检查" error_analysis.log
echo ""
echo "=== 解决方案 ==="
grep -A 5 "错误原因分析和建议" error_analysis.log
