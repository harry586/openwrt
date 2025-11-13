#!/bin/bash
# error_analysis.sh - 错误分析脚本

set -e

BUILD_DIR=${1:-/mnt/openwrt-build}

echo "=== 错误分析开始 ===" > error_analysis.log
echo "分析时间: $(date)" >> error_analysis.log
echo "构建目录: $BUILD_DIR" >> error_analysis.log
echo "" >> error_analysis.log

cd "$BUILD_DIR"

if [ ! -f "build_detailed.log" ]; then
    echo "❌ 错误: 找不到构建日志文件 build_detailed.log" >> error_analysis.log
    exit 1
fi

# 1. 检查严重错误
echo "1. 严重错误检查..." >> error_analysis.log
if grep -q "Error [0-9]" build_detailed.log; then
    echo "❌ 发现编译错误:" >> error_analysis.log
    grep "Error [0-9]" build_detailed.log | head -10 >> error_analysis.log
else
    echo "✅ 未发现严重编译错误" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 2. 检查make错误
echo "2. Makefile错误检查..." >> error_analysis.log
if grep -q "make.*Error" build_detailed.log; then
    echo "⚠️ 发现Makefile执行错误:" >> error_analysis.log
    grep "make.*Error" build_detailed.log | head -10 >> error_analysis.log
else
    echo "✅ 未发现Makefile执行错误" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 3. 检查文件缺失错误
echo "3. 文件缺失错误检查..." >> error_analysis.log
if grep -q "No such file" build_detailed.log || grep -q "file not found" build_detailed.log; then
    echo "❌ 发现文件缺失错误:" >> error_analysis.log
    grep -E "No such file|file not found" build_detailed.log | head -10 >> error_analysis.log
else
    echo "✅ 未发现文件缺失错误" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 4. 检查依赖错误
echo "4. 依赖关系错误检查..." >> error_analysis.log
if grep -q "depends on" build_detailed.log; then
    echo "❌ 发现依赖关系错误:" >> error_analysis.log
    grep "depends on" build_detailed.log | head -10 >> error_analysis.log
else
    echo "✅ 未发现依赖关系错误" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 5. 检查空间错误
echo "5. 磁盘空间检查..." >> error_analysis.log
if grep -q "No space left" build_detailed.log; then
    echo "❌ 发现磁盘空间不足错误" >> error_analysis.log
    grep "No space left" build_detailed.log >> error_analysis.log
else
    echo "✅ 未发现磁盘空间错误" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 6. 检查设备配置错误
echo "6. 设备配置检查..." >> error_analysis.log
if grep -q "Device.*not found" build_detailed.log || grep -q "unknown device" build_detailed.log; then
    echo "❌ 发现设备配置错误:" >> error_analysis.log
    grep -E "Device.*not found|unknown device" build_detailed.log >> error_analysis.log
else
    echo "✅ 未发现设备配置错误" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 7. 检查被忽略的错误
echo "7. 被忽略的错误检查..." >> error_analysis.log
if grep -q "Error.*ignored" build_detailed.log; then
    echo "⚠️ 发现被忽略的错误:" >> error_analysis.log
    grep "Error.*ignored" build_detailed.log >> error_analysis.log
else
    echo "✅ 未发现被忽略的错误" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 8. 检查警告
echo "8. 警告信息统计..." >> error_analysis.log
WARNING_COUNT=$(grep -c "warning:" build_detailed.log || true)
if [ "$WARNING_COUNT" -gt 0 ]; then
    echo "⚠️ 发现 $WARNING_COUNT 个警告" >> error_analysis.log
    echo "前10个警告:" >> error_analysis.log
    grep "warning:" build_detailed.log | head -10 >> error_analysis.log
else
    echo "✅ 未发现警告" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 9. 构建结果总结
echo "=== 构建结果总结 ===" >> error_analysis.log
if [ -d "bin/targets" ]; then
    echo "✅ 构建状态: 成功" >> error_analysis.log
    echo "生成的固件文件:" >> error_analysis.log
    find bin/targets -name "*.bin" -o -name "*.img" -o -name "*.trx" 2>/dev/null | sort >> error_analysis.log
    
    # 检查目标设备固件
    if find bin/targets -name "*asus_rt-ac42u*" 2>/dev/null | grep -q .; then
        echo "✅ 找到正确的 ASUS RT-AC42U 固件" >> error_analysis.log
    elif find bin/targets -name "*ac42u*" 2>/dev/null | grep -q .; then
        echo "✅ 找到 AC42U 相关固件" >> error_analysis.log
    else
        echo "⚠️ 未找到目标设备固件" >> error_analysis.log
    fi
else
    echo "❌ 构建状态: 失败" >> error_analysis.log
    echo "bin/targets 目录不存在" >> error_analysis.log
fi
echo "" >> error_analysis.log

# 10. 建议和修复措施
echo "=== 建议和修复措施 ===" >> error_analysis.log
if grep -q "No such file" error_analysis.log; then
    echo "💡 文件缺失建议: 检查源码完整性或重新下载依赖" >> error_analysis.log
fi

if grep -q "depends on" error_analysis.log; then
    echo "💡 依赖错误建议: 检查包依赖关系，确保所有依赖包已正确安装" >> error_analysis.log
fi

if grep -q "No space left" error_analysis.log; then
    echo "💡 空间不足建议: 清理磁盘空间或增加构建目录的空间" >> error_analysis.log
fi

if grep -q "Device.*not found" error_analysis.log; then
    echo "💡 设备配置建议: 检查设备名称是否正确，验证设备在源码中的支持" >> error_analysis.log
fi

echo "" >> error_analysis.log
echo "错误分析完成" >> error_analysis.log

# 在控制台输出摘要
echo "=== 错误分析摘要 ==="
grep -E "✅|❌|⚠️" error_analysis.log | head -20
