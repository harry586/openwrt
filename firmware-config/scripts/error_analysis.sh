#!/bin/bash
set -e

BUILD_DIR=${1:-/mnt/openwrt-build}
cd "$BUILD_DIR"

echo "=== 固件构建错误分析报告 ===" > error_analysis.log
echo "生成时间: $(date)" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 构建环境信息 ===" >> error_analysis.log
echo "构建目录: $BUILD_DIR" >> error_analysis.log
echo "设备: $DEVICE" >> error_analysis.log
echo "目标平台: $TARGET" >> error_analysis.log
echo "版本分支: $SELECTED_BRANCH" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 系统资源状态 ===" >> error_analysis.log
echo "磁盘空间:" >> error_analysis.log
df -h >> error_analysis.log
echo "" >> error_analysis.log
echo "内存使用:" >> error_analysis.log
free -h >> error_analysis.log
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

echo "=== 配置状态检查 ===" >> error_analysis.log
if [ -f ".config" ]; then
    echo "✅ 配置文件存在" >> error_analysis.log
    echo "启用的包数量: $(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)" >> error_analysis.log
    echo "禁用的包数量: $(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "=== 关键USB配置状态 ===" >> error_analysis.log
    USB_CONFIGS=(
        "kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-storage"
        "kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3"
        "kmod-usb-xhci-hcd" "kmod-usb-ehci" "kmod-usb-ohci"
    )
    
    for config in "${USB_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
            echo "✅ $config: 已启用" >> error_analysis.log
        else
            echo "❌ $config: 未启用" >> error_analysis.log
        fi
    done
    
    echo "" >> error_analysis.log
    echo "=== 工具链配置状态 ===" >> error_analysis.log
    TOOLCHAIN_CONFIGS=(
        "gcc" "binutils" "libc" "libgcc" "uclibc" "musl" "glibc"
    )
    
    for config in "${TOOLCHAIN_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}" .config; then
            echo "✅ $config: 已配置" >> error_analysis.log
        else
            echo "⚠️  $config: 未配置" >> error_analysis.log
        fi
    done
else
    echo "❌ 配置文件不存在" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "=== 关键错误检查 ===" >> error_analysis.log
if [ -f "build.log" ]; then
    echo "检查日志文件: build.log" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ 发现编译错误:" >> error_analysis.log
    grep -E "Error [0-9]|error:" build.log | head -15 >> error_analysis.log || echo "无关键编译错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ Makefile执行错误:" >> error_analysis.log
    grep -E "make.*Error|Makefile.*failed" build.log | head -10 >> error_analysis.log || echo "无Makefile错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ 依赖错误:" >> error_analysis.log
    grep -E "depends on|missing dependencies" build.log | head -10 >> error_analysis.log || echo "无依赖错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ 文件缺失错误:" >> error_analysis.log
    grep -E "No such file|file not found|cannot find" build.log | head -10 >> error_analysis.log || echo "无文件缺失错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ 内存相关错误:" >> error_analysis.log
    grep -E "out of memory|Killed process|oom" build.log | head -5 >> error_analysis.log || echo "无内存错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ 工具链相关错误:" >> error_analysis.log
    grep -E "toolchain|compiler|linker|gcc|binutils" build.log -i | head -10 >> error_analysis.log || echo "无工具链错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "⚠️ 被忽略的错误:" >> error_analysis.log
    grep "Error.*ignored" build.log >> error_analysis.log || echo "无被忽略错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "ℹ️ 管道错误 (通常是正常现象):" >> error_analysis.log
    grep "Broken pipe" build.log | head -3 >> error_analysis.log || echo "无管道错误" >> error_analysis.log
else
    echo "未找到构建日志文件 build.log" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "=== 详细错误分类 ===" >> error_analysis.log
echo "开始收集和分析错误日志..." >> error_analysis.log
echo "使用日志文件: build.log" >> error_analysis.log
echo "" >> error_analysis.log

ERROR_CATEGORIES=(
    "严重错误 (Failed):|failed|FAILED"
    "编译错误 (error:):|error:"
    "退出错误 (error 1/error 2):|error [12]|Error [12]"
    "文件缺失错误:|No such file|file not found|cannot find"
    "依赖错误:|depends on|missing dependencies"
    "配置错误:|configuration error|config error"
    "语法错误:|syntax error"
    "类型错误:|type error"
    "未定义引用:|undefined reference"
    "内存错误:|out of memory|Killed process|oom"
    "权限错误:|Permission denied|operation not permitted"
    "网络错误:|Connection refused|timeout|Network is unreachable"
    "哈希校验错误:|Hash mismatch|Bad hash"
    "管道错误:|Broken pipe"
    "工具链错误:|toolchain|compiler|gcc|binutils|ld"
)

for category in "${ERROR_CATEGORIES[@]}"; do
    IFS='|' read -r category_name patterns <<< "$category"
    echo "=== $category_name ===" >> error_analysis.log
    pattern_array=($patterns)
    grep_cmd="grep -i"
    for pattern in "${pattern_array[@]}"; do
        grep_cmd+=" -e \"$pattern\""
    done
    grep_cmd+=" build.log | head -5"
    eval $grep_cmd >> error_analysis.log || echo "无相关错误" >> error_analysis.log
    echo "" >> error_analysis.log
done

echo "=== 工具链状态检查 ===" >> error_analysis.log
if [ -d "staging_dir" ]; then
    echo "✅ 工具链目录存在" >> error_analysis.log
    echo "工具链位置: staging_dir" >> error_analysis.log
    
    COMPONENTS=("toolchain" "bin" "lib" "include")
    for comp in "${COMPONENTS[@]}"; do
        find staging_dir -name "*$comp*" -type d 2>/dev/null | head -3 >> error_analysis.log || true
    done
    
    if command -v find > /dev/null 2>&1; then
        COMPILERS=$(find staging_dir -name "*gcc*" -o -name "*g++*" 2>/dev/null | head -5)
        if [ -n "$COMPILERS" ]; then
            echo "✅ 编译器文件:" >> error_analysis.log
            echo "$COMPILERS" >> error_analysis.log
        else
            echo "⚠️  未找到编译器文件" >> error_analysis.log
        fi
    fi
else
    echo "❌ 工具链目录不存在" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "=== 错误原因分析和建议 ===" >> error_analysis.log

echo "❌ 文件缺失错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - 源码不完整或下载失败" >> error_analysis.log
echo "   - 依赖包未正确下载" >> error_analysis.log
echo "   - 网络连接问题导致下载中断" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 重新运行工作流" >> error_analysis.log
echo "   - 检查网络连接" >> error_analysis.log
echo "   - 清理缓存重新编译" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ 依赖错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - 包依赖关系配置错误" >> error_analysis.log
echo "   - 版本不兼容" >> error_analysis.log
echo "   - 缺少必要的依赖包" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查包依赖配置" >> error_analysis.log
echo "   - 更新 feeds" >> error_analysis.log
echo "   - 手动安装缺失依赖" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ 内存错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - 系统内存不足" >> error_analysis.log
echo "   - 并行编译任务过多" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 减少并行编译任务数 (make -j2)" >> error_analysis.log
echo "   - 增加交换空间" >> error_analysis.log
echo "   - 使用更高内存的构建环境" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ 配置错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - .config 文件配置冲突" >> error_analysis.log
echo "   - 不兼容的选项组合" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查 .config 文件中的冲突选项" >> error_analysis.log
echo "   - 运行 'make defconfig' 修复配置" >> error_analysis.log
echo "   - 重新生成配置" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ 编译错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - 代码语法错误" >> error_analysis.log
echo "   - 头文件缺失" >> error_analysis.log
echo "   - 编译器版本不兼容" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查代码语法" >> error_analysis.log
echo "   - 安装缺失的开发包" >> error_analysis.log
echo "   - 使用兼容的编译器版本" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ 工具链错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - 工具链未正确安装" >> error_analysis.log
echo "   - 编译器路径配置错误" >> error_analysis.log
echo "   - 缺少必要的编译工具" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查工具链配置" >> error_analysis.log
echo "   - 重新安装工具链" >> error_analysis.log
echo "   - 使用预编译的工具链" >> error_analysis.log
echo "" >> error_analysis.log

echo "ℹ️ 管道错误" >> error_analysis.log
echo "💡 说明:" >> error_analysis.log
echo "   - 这是并行编译的正常现象，通常不影响最终结果" >> error_analysis.log
echo "   - 由于编译进程间通信导致，可以忽略" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 快速修复建议 ===" >> error_analysis.log
echo "1. 🔄 重新运行工作流" >> error_analysis.log
echo "2. 🧹 清理构建目录重新开始" >> error_analysis.log
echo "3. 📦 更新所有 feeds: ./scripts/feeds update -a && ./scripts/feeds install -a" >> error_analysis.log
echo "4. ⚙️ 检查配置冲突: make defconfig" >> error_analysis.log
echo "5. 🐛 减少并行任务: make -j2 V=s" >> error_analysis.log
echo "6. 🌐 检查网络连接和代理设置" >> error_analysis.log
echo "7. 🔧 检查工具链: 确保 staging_dir/toolchain-* 目录存在且完整" >> error_analysis.log
echo "" >> error_analysis.log

echo "错误分析完成 - 查看 error_analysis.log 获取详细信息" >> error_analysis.log

cat error_analysis.log

if [ ! -d "bin/targets" ]; then
    exit 1
fi
