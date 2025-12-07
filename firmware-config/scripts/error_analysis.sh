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
echo "子目标: $SUBTARGET" >> error_analysis.log
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
    echo "=== C库配置状态 ===" >> error_analysis.log
    if grep -q "CONFIG_USE_MUSL=y" .config; then
        echo "✅ C库: musl (现代OpenWrt默认使用)" >> error_analysis.log
        echo "💡 注意: musl是轻量级C库，适用于嵌入式系统" >> error_analysis.log
    elif grep -q "CONFIG_USE_GLIBC=y" .config; then
        echo "✅ C库: glibc (功能完整的C库)" >> error_analysis.log
        echo "💡 注意: glibc功能更完整，但体积较大" >> error_analysis.log
    elif grep -q "CONFIG_USE_UCLIBC=y" .config; then
        echo "✅ C库: uclibc (旧版OpenWrt使用)" >> error_analysis.log
        echo "💡 注意: uclibc是较旧的C库，现代OpenWrt已转向musl" >> error_analysis.log
    else
        echo "⚠️  C库: 未明确指定" >> error_analysis.log
    fi
    
    echo "" >> error_analysis.log
    echo "=== 关键USB配置状态 ===" >> error_analysis.log
    USB_CONFIGS=(
        "kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-storage"
        "kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3"
        "kmod-usb-xhci-hcd" "kmod-usb-ehci" "kmod-usb-ohci"
        "kmod-usb-storage-uas" "kmod-usb-storage-extras"
        "kmod-scsi-core" "kmod-scsi-generic"
        "kmod-usb-uhci" "kmod-usb2-pci" "kmod-usb-ohci-pci"
        "kmod-usb-xhci-pci" "kmod-usb-xhci-mtk" "kmod-usb-xhci-plat-hcd"
    )
    
    for config in "${USB_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
            echo "✅ $config: 已启用" >> error_analysis.log
        else
            echo "❌ $config: 未启用" >> error_analysis.log
            # 解释原因
            case $config in
                "kmod-usb-xhci-hcd")
                    echo "     说明: USB 3.0扩展主机控制器接口驱动" >> error_analysis.log
                    echo "     影响: 禁用后USB 3.0端口可能无法工作或降速为USB 2.0" >> error_analysis.log
                    echo "     建议: 如果设备有USB 3.0端口，必须启用" >> error_analysis.log
                    ;;
                "kmod-phy-qcom-dwc3")
                    echo "     说明: 高通平台USB 3.0物理层驱动" >> error_analysis.log
                    echo "     影响: 仅适用于高通平台（如IPQ40xx），禁用可能影响USB 3.0功能" >> error_analysis.log
                    echo "     建议: 如果是高通平台且需要USB 3.0，必须启用" >> error_analysis.log
                    ;;
                "kmod-usb-dwc3")
                    echo "     说明: USB 3.0主机控制器核心驱动" >> error_analysis.log
                    echo "     影响: 禁用后USB 3.0功能可能无法使用" >> error_analysis.log
                    echo "     建议: 如果需要USB 3.0支持，必须启用" >> error_analysis.log
                    ;;
                "kmod-usb-dwc3-qcom")
                    echo "     说明: 高通平台专用USB 3.0控制器驱动" >> error_analysis.log
                    echo "     影响: 仅适用于高通平台，禁用可能影响USB 3.0控制器工作" >> error_analysis.log
                    echo "     建议: 如果是高通平台，必须启用" >> error_analysis.log
                    ;;
                "kmod-usb-ehci")
                    echo "     说明: USB 2.0增强主机控制器接口驱动" >> error_analysis.log
                    echo "     影响: 禁用后USB 2.0高速设备可能无法正常工作" >> error_analysis.log
                    echo "     建议: 建议启用，除非明确知道不需要USB 2.0高速支持" >> error_analysis.log
                    ;;
                "kmod-usb-ohci")
                    echo "     说明: USB 1.1开放主机控制器接口驱动" >> error_analysis.log
                    echo "     影响: 禁用后USB 1.1低速设备可能无法正常工作" >> error_analysis.log
                    echo "     建议: 建议启用，兼容老设备" >> error_analysis.log
                    ;;
                "kmod-usb-storage-uas")
                    echo "     说明: USB Attached SCSI协议支持，用于高速USB存储设备" >> error_analysis.log
                    echo "     影响: 禁用后高速USB 3.0存储设备可能无法发挥全部性能" >> error_analysis.log
                    echo "     建议: 如果有USB 3.0存储设备，建议启用" >> error_analysis.log
                    ;;
                "kmod-scsi-core")
                    echo "     说明: SCSI核心驱动，用于硬盘和U盘支持" >> error_analysis.log
                    echo "     影响: 禁用后可能导致部分存储设备无法识别" >> error_analysis.log
                    echo "     建议: 必须启用" >> error_analysis.log
                    ;;
                "kmod-usb-xhci-mtk")
                    echo "     说明: 雷凌平台USB 3.0控制器驱动" >> error_analysis.log
                    echo "     影响: 仅适用于雷凌平台（如MT76xx），禁用可能影响USB 3.0功能" >> error_analysis.log
                    echo "     建议: 如果是雷凌平台，建议启用" >> error_analysis.log
                    ;;
            esac
        fi
    done
    
    # 平台专用驱动检查
    echo "" >> error_analysis.log
    echo "=== 平台专用USB驱动状态 ===" >> error_analysis.log
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "🔧 高通IPQ40xx平台专用驱动:" >> error_analysis.log
        QCOM_CONFIGS=("kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3-of-simple")
        for config in "${QCOM_CONFIGS[@]}"; do
            if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
                echo "✅ $config: 已启用" >> error_analysis.log
            else
                echo "❌ $config: 未启用（高通平台建议启用）" >> error_analysis.log
            fi
        done
    elif [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; }; then
        echo "🔧 雷凌MT76xx平台专用驱动:" >> error_analysis.log
        MTK_CONFIGS=("kmod-usb-ohci-pci" "kmod-usb2-pci" "kmod-usb-xhci-mtk")
        for config in "${MTK_CONFIGS[@]}"; do
            if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
                echo "✅ $config: 已启用" >> error_analysis.log
            else
                echo "❌ $config: 未启用（雷凌平台建议启用）" >> error_analysis.log
            fi
        done
    fi
    
    echo "" >> error_analysis.log
    echo "=== 文件系统支持状态 ===" >> error_analysis.log
    FS_CONFIGS=("kmod-fs-ext4" "kmod-fs-vfat" "kmod-fs-exfat" "kmod-fs-ntfs3" "kmod-nls-utf8" "kmod-nls-cp437" "kmod-nls-iso8859-1" "kmod-nls-cp936")
    for config in "${FS_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
            echo "✅ $config: 已启用" >> error_analysis.log
        else
            echo "❌ $config: 未启用" >> error_analysis.log
        fi
    done
    
    echo "" >> error_analysis.log
    echo "=== USB配置总结 ===" >> error_analysis.log
    local total_usb_configs=0
    local enabled_usb_configs=0
    
    for config in "${USB_CONFIGS[@]}"; do
        total_usb_configs=$((total_usb_configs + 1))
        if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
            enabled_usb_configs=$((enabled_usb_configs + 1))
        fi
    done
    
    echo "USB驱动总数: $total_usb_configs" >> error_analysis.log
    echo "已启用: $enabled_usb_configs" >> error_analysis.log
    echo "未启用: $((total_usb_configs - enabled_usb_configs))" >> error_analysis.log
    
    if [ $enabled_usb_configs -eq $total_usb_configs ]; then
        echo "🎉 所有关键USB驱动都已启用！" >> error_analysis.log
    elif [ $enabled_usb_configs -ge $((total_usb_configs * 8 / 10)) ]; then
        echo "⚠️  大部分USB驱动已启用，但仍有部分未启用" >> error_analysis.log
    else
        echo "❌ 大量USB驱动未启用，USB功能可能受限" >> error_analysis.log
    fi
    
    echo "" >> error_analysis.log
    echo "=== 工具链配置状态 ===" >> error_analysis.log
    TOOLCHAIN_CONFIGS=(
        "gcc" "binutils" "libc" "libgcc" "musl" "glibc"
    )
    
    for config in "${TOOLCHAIN_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}" .config; then
            echo "✅ $config: 已配置" >> error_analysis.log
        else
            echo "⚠️  $config: 未配置" >> error_analysis.log
        fi
    done
    
    # 显示前5个被禁用的插件
    echo "" >> error_analysis.log
    echo "=== 前5个被禁用的插件 ===" >> error_analysis.log
    grep "^# CONFIG_PACKAGE_.* is not set$" .config | head -5 | while read line; do
        pkg_name=$(echo $line | sed 's/# CONFIG_PACKAGE_//;s/ is not set//')
        echo "❌ $pkg_name" >> error_analysis.log
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
    "C库相关错误:|musl|glibc|uclibc|libc"
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

echo "=== C库依赖问题分析 ===" >> error_analysis.log
echo "💡 关于'警告: 未找到关键依赖: uclibc'的说明:" >> error_analysis.log
echo "" >> error_analysis.log
echo "1. 📚 OpenWrt C库历史:" >> error_analysis.log
echo "   - uClibc: 旧版OpenWrt使用的轻量级C库" >> error_analysis.log
echo "   - musl: 现代OpenWrt默认使用的C库（21.02+）" >> error_analysis.log
echo "   - glibc: 完整功能的C库，体积较大" >> error_analysis.log
echo "" >> error_analysis.log
echo "2. 🔧 修复方法:" >> error_analysis.log
echo "   - 检查配置文件中的C库设置:" >> error_analysis.log
echo "     grep 'CONFIG_USE_' .config" >> error_analysis.log
echo "   - 对于OpenWrt 21.02/23.05，应该使用musl" >> error_analysis.log
echo "   - 如果确实需要uclibc，需要特殊配置" >> error_analysis.log
echo "" >> error_analysis.log
echo "3. ✅ 正确的检查方法:" >> error_analysis.log
echo "   - 不应该检查'uclibc'，而应该检查'musl'" >> error_analysis.log
echo "   - 脚本已修复，不再将uclibc作为关键依赖" >> error_analysis.log
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

echo "❌ C库相关错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - 错误的C库配置（uclibc/musl/glibc混用）" >> error_analysis.log
echo "   - C库文件缺失或损坏" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查配置文件中的C库设置" >> error_analysis.log
echo "   - 确保使用正确的C库（现代OpenWrt用musl）" >> error_analysis.log
echo "   - 重新下载C库依赖" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ USB相关错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - USB驱动配置不完整" >> error_analysis.log
echo "   - 缺少平台专用USB驱动" >> error_analysis.log
echo "   - USB 3.0驱动未启用" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 确保启用所有核心USB驱动: kmod-usb-core, kmod-usb2, kmod-usb3" >> error_analysis.log
echo "   - 确保启用USB 3.0驱动: kmod-usb-xhci-hcd, kmod-usb-dwc3" >> error_analysis.log
echo "   - 根据平台启用专用驱动: IPQ40xx->高通驱动, MT76xx->雷凌驱动" >> error_analysis.log
echo "   - 确保启用存储支持: kmod-usb-storage, kmod-scsi-core" >> error_analysis.log
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
echo "8. 🔌 检查USB插件: 确保所有关键USB驱动已启用（当前配置已强制启用）" >> error_analysis.log
echo "9. 🖥️ 检查平台专用驱动: 根据您的设备平台（高通/雷凌）启用相应驱动" >> error_analysis.log
echo "10. 💾 检查文件系统支持: 确保NTFS3, ext4, vfat等文件系统驱动已启用" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 针对USB问题的特殊修复方案 ===" >> error_analysis.log
echo "如果USB功能仍然有问题，请尝试以下步骤:" >> error_analysis.log
echo "" >> error_analysis.log
echo "1. 🔍 检查USB配置状态:" >> error_analysis.log
echo "   grep 'CONFIG_PACKAGE_kmod-usb' .config | grep '=y'" >> error_analysis.log
echo "" >> error_analysis.log
echo "2. 🔧 手动添加缺失的USB驱动（如果发现缺失）:" >> error_analysis.log
echo "   对于高通IPQ40xx平台:" >> error_analysis.log
echo "   echo 'CONFIG_PACKAGE_kmod-usb-dwc3=y' >> .config" >> error_analysis.log
echo "   echo 'CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y' >> .config" >> error_analysis.log
echo "   echo 'CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y' >> .config" >> error_analysis.log
echo "" >> error_analysis.log
echo "   对于雷凌MT76xx平台:" >> error_analysis.log
echo "   echo 'CONFIG_PACKAGE_kmod-usb-ohci-pci=y' >> .config" >> error_analysis.log
echo "   echo 'CONFIG_PACKAGE_kmod-usb2-pci=y' >> .config" >> error_analysis.log
echo "   echo 'CONFIG_PACKAGE_kmod-usb-xhci-mtk=y' >> .config" >> error_analysis.log
echo "" >> error_analysis.log
echo "3. 🛠️ 重新应用配置:" >> error_analysis.log
echo "   make defconfig" >> error_analysis.log
echo "" >> error_analysis.log
echo "4. 🔄 重新编译:" >> error_analysis.log
echo "   make -j$(nproc) V=s" >> error_analysis.log
echo "" >> error_analysis.log

echo "错误分析完成 - 查看 error_analysis.log 获取详细信息" >> error_analysis.log

cat error_analysis.log

if [ ! -d "bin/targets" ]; then
    exit 1
fi
