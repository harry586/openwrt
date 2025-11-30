#!/bin/bash
set -e

BUILD_DIR=${1:-/mnt/openwrt-build}
cd "$BUILD_DIR"

echo "=== 固件构建错误分析报告 ===" > error_analysis.log
echo "生成时间: $(date)" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 构建环境信息 ===" >> error_analysis.log
echo "构建目录: $BUILD_DIR" >> error_analysis.log
if [ -f "build_env.sh" ]; then
    source build_env.sh
    echo "设备: $DEVICE" >> error_analysis.log
    echo "目标平台: $TARGET" >> error_analysis.log
    echo "版本分支: $SELECTED_BRANCH" >> error_analysis.log
    echo "配置模式: $CONFIG_MODE" >> error_analysis.log
fi
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
    
    # 检查关键配置
    echo "" >> error_analysis.log
    echo "=== 关键配置状态 ===" >> error_analysis.log
    KEY_CONFIGS=(
        "luci-app-filetransfer" "luci-app-turboacc" "kmod-usb-core"
        "kmod-usb-storage" "kmod-usb2" "kmod-usb3" "block-mount"
    )
    
    for config in "${KEY_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
            echo "✅ $config: 已启用" >> error_analysis.log
        else
            echo "❌ $config: 未启用" >> error_analysis.log
        fi
    done
else
    echo "❌ 配置文件不存在" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "=== 自定义文件处理状态 ===" >> error_analysis.log
if [ -f "custom_files_log/custom_files.log" ]; then
    cat custom_files_log/custom_files.log >> error_analysis.log
else
    echo "ℹ️ 未找到自定义文件处理日志" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "=== 关键错误检查 ===" >> error_analysis.log
if [ -f "build.log" ]; then
    echo "检查日志文件: build.log" >> error_analysis.log
    
    # 编译错误
    echo "" >> error_analysis.log
    echo "❌ 发现编译错误:" >> error_analysis.log
    grep -E "Error [0-9]|error:" build.log | head -15 >> error_analysis.log || echo "无关键编译错误" >> error_analysis.log
    
    # Makefile错误
    echo "" >> error_analysis.log
    echo "❌ Makefile执行错误:" >> error_analysis.log
    grep -E "make.*Error|Makefile.*failed" build.log | head -10 >> error_analysis.log || echo "无Makefile错误" >> error_analysis.log
    
    # 依赖错误
    echo "" >> error_analysis.log
    echo "❌ 依赖错误:" >> error_analysis.log
    grep -E "depends on|missing dependencies" build.log | head -10 >> error_analysis.log || echo "无依赖错误" >> error_analysis.log
    
    # 文件缺失错误
    echo "" >> error_analysis.log
    echo "❌ 文件缺失错误:" >> error_analysis.log
    grep -E "No such file|file not found|cannot find" build.log | head -10 >> error_analysis.log || echo "无文件缺失错误" >> error_analysis.log
    
    # 内存错误
    echo "" >> error_analysis.log
    echo "❌ 内存相关错误:" >> error_analysis.log
    grep -E "out of memory|Killed process|oom" build.log | head -5 >> error_analysis.log || echo "无内存错误" >> error_analysis.log
    
    # 被忽略的错误
    echo "" >> error_analysis.log
    echo "⚠️ 被忽略的错误:" >> error_analysis.log
    grep "Error.*ignored" build.log >> error_analysis.log || echo "无被忽略错误" >> error_analysis.log
    
    # 管道错误（通常是正常现象）
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

echo "=== 构建流程检查 ===" >> error_analysis.log
echo "检查各步骤完成情况:" >> error_analysis.log

# 检查关键文件是否存在
CHECK_FILES=(
    "feeds.conf.default:Feeds配置"
    ".config:主配置文件" 
    "build.log:构建日志"
    "bin/targets/:固件输出目录"
)

for check in "${CHECK_FILES[@]}"; do
    IFS=':' read -r file desc <<< "$check"
    if [ -e "$file" ]; then
        echo "✅ $desc: 存在" >> error_analysis.log
    else
        echo "❌ $desc: 缺失" >> error_analysis.log
    fi
done
echo "" >> error_analysis.log

echo "=== 插件启用状态 ===" >> error_analysis.log
if [ -f ".config" ]; then
    echo "✅ 已启用的插件列表:" >> error_analysis.log
    grep "^CONFIG_PACKAGE_luci-app-.*=y$" .config | sed 's/CONFIG_PACKAGE_//;s/=y//' | while read plugin; do
        echo "  ✅ $plugin" >> error_analysis.log
    done
    
    echo "" >> error_analysis.log
    echo "❌ 已禁用的插件列表:" >> error_analysis.log
    grep "^# CONFIG_PACKAGE_luci-app-.* is not set$" .config | sed 's/# CONFIG_PACKAGE_//;s/ is not set//' | while read plugin; do
        echo "  ❌ $plugin" >> error_analysis.log
    done
else
    echo "❌ 配置文件不存在，无法检查插件状态" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "=== 错误原因分析和建议 ===" >> error_analysis.log

# 文件缺失错误
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

# 依赖错误
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

# 配置错误
echo "❌ 配置错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - .config 文件配置冲突" >> error_analysis.log
echo "   - 不兼容的选项组合" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查 .config 文件中的冲突选项" >> error_analysis.log
echo "   - 运行 'make defconfig' 修复配置" >> error_analysis.log
echo "   - 重新生成配置" >> error_analysis.log
echo "" >> error_analysis.log

# 编译错误
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

echo "=== 快速修复建议 ===" >> error_analysis.log
echo "1. 🔄 重新运行工作流" >> error_analysis.log
echo "2. 🧹 清理构建目录重新开始" >> error_analysis.log
echo "3. 📦 更新所有 feeds: ./scripts/feeds update -a && ./scripts/feeds install -a" >> error_analysis.log
echo "4. ⚙️ 检查配置冲突: make defconfig" >> error_analysis.log
echo "5. 🐛 减少并行任务: make -j2 V=s" >> error_analysis.log
echo "6. 🌐 检查网络连接和代理设置" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 下一步操作 ===" >> error_analysis.log
if [ -d "bin/targets" ]; then
    echo "🎉 构建成功！可以下载固件文件进行刷机。" >> error_analysis.log
    echo "固件位置: bin/targets/" >> error_analysis.log
else
    echo "🔧 构建失败，请根据上面的错误分析进行修复。" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "错误分析完成 - 查看 error_analysis.log 获取详细信息" >> error_analysis.log

# 输出到控制台
cat error_analysis.log

# 如果构建失败，以错误状态退出
if [ ! -d "bin/targets" ]; then
    exit 1
fi
