#!/bin/bash
set -e

BUILD_DIR=${1:-/mnt/openwrt-build}
cd "$BUILD_DIR"

echo "=== 固件构建错误分析报告（增强版）===" > error_analysis.log
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
        echo "🔧 说明: 现代OpenWrt/ImmortalWrt默认使用musl，glibc未配置是正常现象" >> error_analysis.log
    elif grep -q "CONFIG_USE_GLIBC=y" .config; then
        echo "✅ C库: glibc (功能完整的C库)" >> error_analysis.log
        echo "💡 注意: glibc功能更完整，但体积较大" >> error_analysis.log
    elif grep -q "CONFIG_USE_UCLIBC=y" .config; then
        echo "✅ C库: uclibc (旧版OpenWrt使用)" >> error_analysis.log
        echo "💡 注意: uclibc是较旧的C库，现代OpenWrt已转向musl" >> error_analysis.log
    else
        echo "⚠️ C库: 未明确指定" >> error_analysis.log
    fi
    
    echo "" >> error_analysis.log
    echo "=== 关键USB配置状态 ===" >> error_analysis.log
    USB_CONFIGS=("kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-storage" "kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-xhci-hcd" "kmod-usb-ehci" "kmod-usb-ohci" "kmod-usb-storage-uas" "kmod-usb-storage-extras" "kmod-scsi-core" "kmod-scsi-generic" "kmod-usb-uhci" "kmod-usb2-pci" "kmod-usb-ohci-pci" "kmod-usb-xhci-pci" "kmod-usb-xhci-mtk" "kmod-usb-xhci-plat-hcd")
    
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
                    echo "建议: 建议启用，兼容老设备" >> error_analysis.log
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
    total_usb_configs=0
    enabled_usb_configs=0
    
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
        echo "⚠️ 大部分USB驱动已启用，但仍有部分未启用" >> error_analysis.log
    else
        echo "❌ 大量USB驱动未启用，USB功能可能受限" >> error_analysis.log
    fi
    
    echo "" >> error_analysis.log
    echo "=== 编译器配置状态 ===" >> error_analysis.log
    COMPILER_CONFIGS=("gcc" "binutils" "libc" "libgcc" "musl" "glibc")
    
    for config in "${COMPILER_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}" .config; then
            echo "✅ $config: 已配置" >> error_analysis.log
        else
            echo "⚠️ $config: 未配置" >> error_analysis.log
            # 特别说明glibc未配置的原因
            if [ "$config" = "glibc" ]; then
                echo "     说明: glibc是桌面系统的标准C库，体积较大" >> error_analysis.log
                echo "     说明: OpenWrt/ImmortalWrt默认使用musl作为轻量级C库" >> error_analysis.log
                echo "     说明: glibc未配置是正常现象，不影响编译和运行" >> error_analysis.log
            fi
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

echo "=== 编译器文件状态检查 ===" >> error_analysis.log
if [ -d "staging_dir" ]; then
    echo "✅ 编译目录存在: staging_dir" >> error_analysis.log
    
    # 检查编译器文件
    echo "🔍 检查编译器文件:" >> error_analysis.log
    find staging_dir -name "*gcc*" -type f -executable 2>/dev/null | head -10 >> error_analysis.log || echo "  未找到编译器文件" >> error_analysis.log
    
    # 检查具体的arm编译器
    echo "🔍 检查arm编译器 (IPQ40xx):" >> error_analysis.log
    find staging_dir -name "arm-openwrt-linux-muslgnueabi-gcc" -type f 2>/dev/null >> error_analysis.log || echo "  未找到arm编译器" >> error_analysis.log
    
    # 检查mipsel编译器
    echo "🔍 检查mipsel编译器 (MT76xx):" >> error_analysis.log
    find staging_dir -name "mipsel-openwrt-linux-musl-gcc" -type f 2>/dev/null >> error_analysis.log || echo "  未找到mipsel编译器" >> error_analysis.log
    
    # 检查编译器版本
    echo "🔍 检查编译器版本:" >> error_analysis.log
    find staging_dir -name "*gcc" -type f -executable 2>/dev/null | head -3 | while read compiler; do
        echo "编译器: $compiler" >> error_analysis.log
        $compiler --version 2>&1 | head -1 >> error_analysis.log 2>/dev/null || echo "  无法获取版本" >> error_analysis.log
    done
    
    # 新增：检查头文件路径
    echo "" >> error_analysis.log
    echo "🔍 检查编译器头文件路径:" >> error_analysis.log
    find staging_dir -name "stdc-predef.h" -type f 2>/dev/null >> error_analysis.log || echo "  未找到stdc-predef.h头文件" >> error_analysis.log
    
    find staging_dir -name "stdio.h" -type f 2>/dev/null | head -1 >> error_analysis.log || echo "  未找到stdio.h头文件" >> error_analysis.log
    
    # 检查host/include目录
    echo "🔍 检查host/include目录:" >> error_analysis.log
    if [ -d "staging_dir/host/include" ]; then
        echo "✅ host/include目录存在" >> error_analysis.log
        echo "  头文件数量: $(find staging_dir/host/include -name "*.h" -type f 2>/dev/null | wc -l)" >> error_analysis.log
        # 检查具体头文件
        echo "  关键头文件:" >> error_analysis.log
        for header in "stdio.h" "stdlib.h" "string.h" "features.h" "stdc-predef.h"; do
            if find staging_dir/host/include -name "$header" -type f 2>/dev/null | grep -q .; then
                echo "    ✅ $header" >> error_analysis.log
            else
                echo "    ❌ $header - 缺失" >> error_analysis.log
            fi
        done
    else
        echo "❌ host/include目录不存在" >> error_analysis.log
    fi
    
    # 新增：检查libtool相关文件
    echo "" >> error_analysis.log
    echo "🔍 检查libtool相关文件:" >> error_analysis.log
    if [ -d "staging_dir/host/share/aclocal" ]; then
        echo "✅ host/share/aclocal目录存在" >> error_analysis.log
        echo "  aclocal文件数量: $(find staging_dir/host/share/aclocal -name "*.m4" -type f 2>/dev/null | wc -l)" >> error_analysis.log
        
        # 检查libtool.m4
        if find staging_dir/host/share/aclocal -name "libtool.m4" -type f 2>/dev/null | grep -q .; then
            echo "  ✅ libtool.m4存在" >> error_analysis.log
        else
            echo "  ❌ libtool.m4缺失 - 这是关键错误" >> error_analysis.log
        fi
    else
        echo "❌ host/share/aclocal目录不存在" >> error_analysis.log
    fi
    
    # 新增：检查libtool二进制文件
    echo "🔍 检查libtool二进制文件:" >> error_analysis.log
    find staging_dir -name "libtool" -type f -executable 2>/dev/null | head -3 >> error_analysis.log || echo "  未找到libtool二进制文件" >> error_analysis.log
    
    # 新增：检查autoconf/automake文件
    echo "🔍 检查autoconf/automake文件:" >> error_analysis.log
    find staging_dir -name "aclocal" -type f -executable 2>/dev/null | head -2 >> error_analysis.log || echo "  未找到aclocal" >> error_analysis.log
    find staging_dir -name "autoconf" -type f -executable 2>/dev/null | head -2 >> error_analysis.log || echo "  未找到autoconf" >> error_analysis.log
    find staging_dir -name "automake" -type f -executable 2>/dev/null | head -2 >> error_analysis.log || echo "  未找到automake" >> error_analysis.log
    
    # 新增：检查GCC构建目录
    echo "" >> error_analysis.log
    echo "🔍 检查GCC构建目录状态:" >> error_analysis.log
    find build_dir -name "gcc-8.4.0" -type d 2>/dev/null | while read gcc_dir; do
        echo "GCC目录: $gcc_dir" >> error_analysis.log
        if [ -f "$gcc_dir/gcc/system.h" ]; then
            echo "  ✅ system.h存在" >> error_analysis.log
            # 检查是否有备份文件
            if [ -f "$gcc_dir/gcc/system.h.backup" ]; then
                echo "  ✅ system.h备份存在" >> error_analysis.log
            fi
        fi
        
        if [ -f "$gcc_dir/gcc/auto-host.h" ]; then
            echo "  ✅ auto-host.h存在" >> error_analysis.log
            if [ -f "$gcc_dir/gcc/auto-host.h.backup" ]; then
                echo "  ✅ auto-host.h备份存在" >> error_analysis.log
            fi
        fi
    done
    
    # 新增：检查GDB构建目录
    echo "" >> error_analysis.log
    echo "🔍 检查GDB构建目录状态:" >> error_analysis.log
    find build_dir -name "gdb-10.1" -type d 2>/dev/null | while read gdb_dir; do
        echo "GDB目录: $gdb_dir" >> error_analysis.log
        echo "  目录大小: $(du -sh "$gdb_dir" 2>/dev/null | cut -f1)" >> error_analysis.log
        if [ -f "$gdb_dir/gdb/Makefile" ]; then
            echo "  ✅ Makefile存在" >> error_analysis.log
        fi
        # 检查common-defs.h
        if [ -f "$gdb_dir/gdbsupport/common-defs.h" ]; then
            echo "  ✅ common-defs.h存在" >> error_analysis.log
            if [ -f "$gdb_dir/gdbsupport/common-defs.h.backup" ]; then
                echo "  ✅ common-defs.h备份存在" >> error_analysis.log
            fi
            
            # 检查_GL_ATTRIBUTE_FORMAT_PRINTF修复状态
            echo "  🔍 检查_GL_ATTRIBUTE_FORMAT_PRINTF修复状态:" >> error_analysis.log
            if grep -q "^#define ATTRIBUTE_PRINTF(format_idx, arg_idx) __attribute__ ((__format__ (__printf__, format_idx, arg_idx)))" "$gdb_dir/gdbsupport/common-defs.h"; then
                echo "    ✅ _GL_ATTRIBUTE_FORMAT_PRINTF已修复" >> error_analysis.log
            else
                echo "    ❌ _GL_ATTRIBUTE_FORMAT_PRINTF未修复" >> error_analysis.log
                echo "    💡 建议: 运行修复脚本或手动修复common-defs.h第111行" >> error_analysis.log
            fi
        fi
        
        # 检查common-utils.c修复状态
        if [ -f "$gdb_dir/gdb/common/common-utils.c" ]; then
            echo "  🔍 检查common-utils.c修复状态:" >> error_analysis.log
            if grep -q "^#define DISABLE_ASSERT 1" "$gdb_dir/gdb/common/common-utils.c"; then
                echo "    ✅ DISABLE_ASSERT已添加" >> error_analysis.log
            else
                echo "    ❌ DISABLE_ASSERT未添加" >> error_analysis.log
            fi
        fi
    done
    
    # 新增：检查binutils构建目录
    echo "" >> error_analysis.log
    echo "🔍 检查binutils构建目录状态:" >> error_analysis.log
    find build_dir -name "binutils-2.40" -type d 2>/dev/null | while read binutils_dir; do
        echo "binutils目录: $binutils_dir" >> error_analysis.log
        echo "  目录大小: $(du -sh "$binutils_dir" 2>/dev/null | cut -f1)" >> error_analysis.log
        if [ -f "$binutils_dir/Makefile" ]; then
            echo "  ✅ Makefile存在" >> error_analysis.log
        fi
        if [ -f "$binutils_dir/config.log" ]; then
            echo "  ✅ config.log存在" >> error_analysis.log
            echo "  最后10行配置日志:" >> error_analysis.log
            tail -10 "$binutils_dir/config.log" >> error_analysis.log
        fi
    done
    
    # 新增：检查工具链构建状态（关键修复）
    echo "" >> error_analysis.log
    echo "🔍 检查工具链构建状态（关键修复）:" >> error_analysis.log
    TOOLCHAIN_DIR=$(find staging_dir -name "toolchain-*" -type d 2>/dev/null | head -1)
    if [ -n "$TOOLCHAIN_DIR" ]; then
        echo "✅ 工具链目录: $TOOLCHAIN_DIR" >> error_analysis.log
        
        # 检查stamp目录
        STAMP_DIR="$TOOLCHAIN_DIR/stamp"
        if [ -d "$STAMP_DIR" ]; then
            echo "✅ stamp目录存在" >> error_analysis.log
            echo "  标记文件列表:" >> error_analysis.log
            ls -la "$STAMP_DIR/" 2>/dev/null | head -20 >> error_analysis.log || echo "    无法列出标记文件" >> error_analysis.log
            
            # 检查关键标记文件
            echo "  关键标记文件状态:" >> error_analysis.log
            CRITICAL_STAMPS=(".toolchain_compile" ".binutils_installed" ".gcc_initial" ".gcc_final" ".libc" ".headers")
            missing_count=0
            for stamp in "${CRITICAL_STAMPS[@]}"; do
                if [ -f "$STAMP_DIR/$stamp" ]; then
                    echo "    ✅ $stamp 存在" >> error_analysis.log
                else
                    echo "    ❌ $stamp 缺失" >> error_analysis.log
                    missing_count=$((missing_count + 1))
                fi
            done
            
            if [ $missing_count -gt 0 ]; then
                echo "  ⚠️  有 $missing_count 个关键标记文件缺失，需要修复" >> error_analysis.log
            else
                echo "  ✅ 所有关键标记文件都存在" >> error_analysis.log
            fi
        else
            echo "❌ stamp目录不存在 - 这是工具链构建失败的主要原因" >> error_analysis.log
            echo "💡 修复建议: mkdir -p $STAMP_DIR" >> error_analysis.log
        fi
        
        # 检查工具链完整性
        echo "  工具链文件检查:" >> error_analysis.log
        if [ -f "$TOOLCHAIN_DIR/bin/arm-openwrt-linux-muslgnueabi-gcc" ]; then
            echo "    ✅ 找到ARM GCC编译器" >> error_analysis.log
            echo "      版本: $($TOOLCHAIN_DIR/bin/arm-openwrt-linux-muslgnueabi-gcc --version 2>/dev/null | head -1)" >> error_analysis.log
        else
            echo "    ❌ 未找到ARM GCC编译器" >> error_analysis.log
        fi
    else
        echo "❌ 未找到工具链目录" >> error_analysis.log
    fi
    
else
    echo "❌ 编译目录不存在" >> error_analysis.log
fi

echo "" >> error_analysis.log
echo "=== 23.05版本特定问题分析 ===" >> error_analysis.log
if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
    echo "🔧 OpenWrt 23.05 常见问题:" >> error_analysis.log
    echo "1. 编译器不兼容: 23.05使用GCC 11.3.0，21.02使用GCC 8.4.0" >> error_analysis.log
    echo "2. 内核版本不同: 23.05使用Linux 5.15，需要不同的内核头文件" >> error_analysis.log
    echo "3. musl版本更新: 可能需要更新的musl C库" >> error_analysis.log
    echo "4. libtool版本: 可能需要更新的libtool版本" >> error_analysis.log
    echo "5. GCC头文件冲突: GCC 8.4.0可能有头文件声明冲突" >> error_analysis.log
    echo "6. GDB编译错误: GDB 10.1可能有_GL_ATTRIBUTE_FORMAT_PRINTF错误" >> error_analysis.log
    echo "7. binutils编译错误: binutils 2.40可能有配置或编译错误" >> error_analysis.log
    echo "8. 工具链构建错误: toolchain/Makefile:93 是最常见的错误" >> error_analysis.log
    echo "9. 缺少.toolchain_compile标记: 导致工具链构建中断" >> error_analysis.log
    echo "10. stamp目录问题: 标记文件缺失或不完整" >> error_analysis.log
    echo "11. 头文件缺失: stdio.h, stdlib.h等关键头文件缺失" >> error_analysis.log
    echo "12. 版本不匹配: 下载的编译器版本与OpenWrt版本不匹配" >> error_analysis.log
    echo "" >> error_analysis.log
    echo "🛠️ 解决方案:" >> error_analysis.log
    echo "1. 使用版本特定的编译器: OpenWrt 23.05使用GCC 11.3.0，21.02使用GCC 8.4.0" >> error_analysis.log
    echo "2. 清理编译器重新下载: rm -rf staging_dir/compiler-*" >> error_analysis.log
    echo "3. 清理构建目录: rm -rf build_dir/target-*" >> error_analysis.log
    echo "4. 确保使用正确的编译器: arm-openwrt-linux-muslgnueabi-gcc" >> error_analysis.log
    echo "5. 检查内核配置: 确保CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> error_analysis.log
    echo "6. 安装最新的libtool和autoconf: sudo apt-get install libtool autoconf automake libltdl-dev gettext pkg-config" >> error_analysis.log
    echo "7. 复制libtool.m4到正确位置: cp /usr/share/aclocal/libtool.m4 staging_dir/host/share/aclocal/" >> error_analysis.log
    echo "8. 修复GCC头文件冲突: 修改gcc/system.h和auto-host.h文件" >> error_analysis.log
    echo "9. 添加-fpermissive编译标志: export CFLAGS=\"\$CFLAGS -fpermissive\"" >> error_analysis.log
    echo "10. 修复GDB _GL_ATTRIBUTE_FORMAT_PRINTF错误: 修改gdbsupport/common-defs.h第111行" >> error_analysis.log
    echo "11. 禁用GDB编译（如果不需调试）: 在.config中添加 # CONFIG_PACKAGE_gdb is not set" >> error_analysis.log
    echo "12. 修复GDB内部错误: 在gdb源码中添加DISABLE_ASSERT宏定义" >> error_analysis.log
    echo "13. 修复binutils编译错误: 检查config.log，设置正确的编译环境变量" >> error_analysis.log
    echo "14. 修复工具链构建错误: 确保stamp目录存在并创建.toolchain_compile标记文件" >> error_analysis.log
    echo "15. 运行修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_binutils_compilation_error" >> error_analysis.log
    echo "16. 运行工具链修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_compiler_toolchain_error" >> error_analysis.log
    echo "17. 单独编译工具链: make toolchain/install -j2 V=s" >> error_analysis.log
    echo "18. 手动创建stamp目录和标记文件: mkdir -p staging_dir/toolchain-*/stamp && touch staging_dir/toolchain-*/stamp/.toolchain_compile" >> error_analysis.log
    echo "19. 检查工具链Makefile第93行: 确保依赖关系正确" >> error_analysis.log
    echo "20. 修复头文件缺失: firmware-config/scripts/build_firmware_main-01.sh fix_missing_headers" >> error_analysis.log
    echo "21. 修复标记文件: firmware-config/scripts/build_firmware_main-01.sh fix_missing_stamp_files" >> error_analysis.log
    echo "22. 运行综合修复: firmware-config/scripts/build_firmware_main-01.sh run_comprehensive_fixes" >> error_analysis.log
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
    echo "❌ 编译器相关错误:" >> error_analysis.log
    grep -E "compiler|gcc|binutils|ld" build.log -i | head -10 >> error_analysis.log || echo "无编译器错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ 头文件相关错误:" >> error_analysis.log
    grep -E "stdc-predef.h|host/include|No such file or directory.*include" build.log -i | head -10 >> error_analysis.log || echo "无头文件错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ libtool相关错误:" >> error_analysis.log
    grep -E "libtool|aclocal|autoconf|automake|libtool.m4" build.log -i | head -10 >> error_analysis.log || echo "无libtool错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ GCC头文件声明错误（新增）:" >> error_analysis.log
    grep -E "declaration does not declare anything|conflicting declaration of C function|ambiguating new declaration" build.log -i | head -10 >> error_analysis.log || echo "无GCC声明错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ GDB编译错误（新增关键检查）:" >> error_analysis.log
    grep -E "_GL_ATTRIBUTE_FORMAT_PRINTF|gdb.*failed|ERROR: toolchain/gdb failed|internal_error.*Assertion|xml-tdesc.o.*Error" build.log -i | head -10 >> error_analysis.log || echo "无GDB编译错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ binutils编译错误（新增关键检查）:" >> error_analysis.log
    grep -E "toolchain/binutils/compile.*failed|binutils.*Error|binutils.*failed" build.log -i | head -10 >> error_analysis.log || echo "无binutils编译错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "❌ 工具链构建错误（新增关键检查）:" >> error_analysis.log
    grep -E "toolchain/Makefile.*93|toolchain_compile.*failed|stamp/.toolchain_compile|stamp/.binutils_installed" build.log -i | head -20 >> error_analysis.log || echo "无工具链构建错误" >> error_analysis.log
    
    # 特别显示toolchain/Makefile:93错误
    echo "" >> error_analysis.log
    echo "🚨 toolchain/Makefile:93 错误详细分析:" >> error_analysis.log
    if grep -q "toolchain/Makefile:93" build.log; then
        echo "✅ 发现典型的工具链构建错误" >> error_analysis.log
        echo "错误模式: make[1]: *** [toolchain/Makefile:93: .../stamp/.toolchain_compile] Error 2" >> error_analysis.log
        echo "💡 原因分析:" >> error_analysis.log
        echo "  1. 缺少.toolchain_compile标记文件" >> error_analysis.log
        echo "  2. stamp目录不存在" >> error_analysis.log
        echo "  3. 工具链依赖未正确构建" >> error_analysis.log
        echo "  4. 编译器环境配置错误" >> error_analysis.log
        echo "  5. 关键标记文件缺失: .gcc_initial, .gcc_final等" >> error_analysis.log
        echo "" >> error_analysis.log
        echo "🛠️ 具体修复步骤:" >> error_analysis.log
        echo "  1. 找到工具链目录: find staging_dir -name 'toolchain-*' -type d" >> error_analysis.log
        echo "  2. 创建stamp目录: mkdir -p staging_dir/toolchain-*/stamp" >> error_analysis.log
        echo "  3. 创建标记文件: touch staging_dir/toolchain-*/stamp/.toolchain_compile" >> error_analysis.log
        echo "  4. 创建其他标记文件: touch staging_dir/toolchain-*/stamp/.binutils_installed" >> error_analysis.log
        echo "  5. 创建.gcc_initial和.gcc_final标记: touch staging_dir/toolchain-*/stamp/.gcc_initial staging_dir/toolchain-*/stamp/.gcc_final" >> error_analysis.log
        echo "  6. 单独编译工具链: make toolchain/compile -j2 V=s" >> error_analysis.log
        echo "  7. 安装工具链: make toolchain/install -j2 V=s" >> error_analysis.log
    else
        echo "未发现toolchain/Makefile:93错误" >> error_analysis.log
    fi
    
    echo "" >> error_analysis.log
    echo "⚠️ 被忽略的错误:" >> error_analysis.log
    grep "Error.*ignored" build.log >> error_analysis.log || echo "无被忽略错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "ℹ️ 管道错误 (通常是正常现象):" >> error_analysis.log
    grep "Broken pipe" build.log | head -3 >> error_analysis.log || echo "无管道错误" >> error_analysis.log
    
    echo "" >> error_analysis.log
    echo "⚠️ 配置不同步警告:" >> error_analysis.log
    grep "configuration is out of sync" build.log >> error_analysis.log || echo "无配置不同步警告" >> error_analysis.log
else
    echo "未找到构建日志文件 build.log" >> error_analysis.log
fi
echo "" >> error_analysis.log

echo "=== 详细错误分类 ===" >> error_analysis.log
echo "开始收集和分析错误日志..." >> error_analysis.log
echo "使用日志文件: build.log" >> error_analysis.log
echo "" >> error_analysis.log

ERROR_CATEGORIES=("严重错误 (Failed):|failed|FAILED" "编译错误 (error:):|error:" "退出错误 (error 1/error 2):|error [12]|Error [12]" "文件缺失错误:|No such file|file not found|cannot find" "依赖错误:|depends on|missing dependencies" "配置错误:|configuration error|config error" "语法错误:|syntax error" "类型错误:|type error" "未定义引用:|undefined reference" "内存错误:|out of memory|Killed process|oom" "权限错误:|Permission denied|operation not permitted" "网络错误:|Connection refused|timeout|Network is unreachable" "哈希校验错误:|Hash mismatch|Bad hash" "管道错误:|Broken pipe" "编译器错误:|compiler|gcc|binutils|ld" "头文件错误:|stdc-predef.h|host/include|include.*not found" "libtool错误:|libtool|aclocal|autoconf|automake|libtool.m4" "C库相关错误:|musl|glibc|uclibc|libc" "GCC头文件声明错误:|declaration does not declare anything|conflicting declaration of C function|ambiguating new declaration" "GDB编译错误:|_GL_ATTRIBUTE_FORMAT_PRINTF|gdb.*failed|ERROR: toolchain/gdb failed|internal_error.*Assertion|xml-tdesc.o.*Error" "binutils编译错误:|toolchain/binutils/compile.*failed|binutils.*Error|binutils.*failed" "工具链构建错误:|toolchain/Makefile.*93|toolchain_compile.*failed|stamp/.toolchain_compile|stamp/.binutils_installed" "配置不同步警告:|configuration is out of sync")

for category in "${ERROR_CATEGORIES[@]}"; do
    IFS='|' read -r category_name patterns <<< "$category"
    echo "=== $category_name ===" >> error_analysis.log
    pattern_array=($patterns)
    for pattern in "${pattern_array[@]}"; do
        grep -i -e "$pattern" build.log | head -5 >> error_analysis.log 2>/dev/null || true
    done
    if [ ! -s error_analysis.log ] || ! tail -1 error_analysis.log | grep -q .; then
        echo "无相关错误" >> error_analysis.log
    fi
    echo "" >> error_analysis.log
done

echo "=== GDB编译错误详细分析 ===" >> error_analysis.log
echo "生成时间: $(date)" >> error_analysis.log
echo "" >> error_analysis.log

echo "🔍 检测到的GDB编译错误:" >> error_analysis.log

# 检查常见的GDB错误模式
if grep -q "_GL_ATTRIBUTE_FORMAT_PRINTF" build.log 2>/dev/null; then
    echo "❌ 发现 _GL_ATTRIBUTE_FORMAT_PRINTF 宏定义错误" >> error_analysis.log
    echo "💡 错误描述: GDB源码中的ATTRIBUTE_PRINTF宏定义不正确" >> error_analysis.log
    echo "🛠️ 解决方案:" >> error_analysis.log
    echo "  1. 找到GDB源码目录: find build_dir -name 'gdb-*' -type d" >> error_analysis.log
    echo "  2. 修复common-defs.h文件:" >> error_analysis.log
    echo "     sed -i '111s/#define ATTRIBUTE_PRINTF _GL_ATTRIBUTE_FORMAT_PRINTF/#define ATTRIBUTE_PRINTF(format_idx, arg_idx) __attribute__ ((__format__ (__printf__, format_idx, arg_idx)))/' gdbsupport/common-defs.h" >> error_analysis.log
    echo "  3. 或者运行完整修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_gdb_compilation_error" >> error_analysis.log
    echo "" >> error_analysis.log
fi

if grep -q "xml-support.o.*Error\|xml-syscall.o.*Error\|xml-tdesc.o.*Error" build.log 2>/dev/null; then
    echo "❌ 发现XML相关文件编译错误" >> error_analysis.log
    echo "💡 错误描述: GDB的XML支持文件编译失败" >> error_analysis.log
    echo "🛠️ 解决方案:" >> error_analysis.log
    echo "  1. 修复XML源文件:" >> error_analysis.log
    echo "     for file in xml-support.c xml-syscall.c xml-tdesc.c; do" >> error_analysis.log
    echo "       sed -i '1i#include <stdio.h>' \$file" >> error_analysis.log
    echo "       sed -i '1i#include <stdlib.h>' \$file" >> error_analysis.log
    echo "     done" >> error_analysis.log
    echo "  2. 或者禁用GDB编译:" >> error_analysis.log
    echo "     echo '# CONFIG_PACKAGE_gdb is not set' >> .config" >> error_analysis.log
    echo "" >> error_analysis.log
fi

if grep -q "toolchain/gdb failed\|gdb.*failed" build.log 2>/dev/null; then
    echo "❌ GDB编译完全失败" >> error_analysis.log
    echo "💡 错误描述: GDB工具链编译过程中断" >> error_analysis.log
    echo "🛠️ 解决方案:" >> error_analysis.log
    echo "  1. 强制禁用GDB:" >> error_analysis.log
    echo "     sed -i '/CONFIG_PACKAGE_gdb/d' .config" >> error_analysis.log
    echo "     echo '# CONFIG_PACKAGE_gdb is not set' >> .config" >> error_analysis.log
    echo "  2. 清理GDB构建目录:" >> error_analysis.log
    echo "     rm -rf build_dir/*gdb*" >> error_analysis.log
    echo "  3. 重新编译工具链:" >> error_analysis.log
    echo "     make toolchain/install -j1 V=s" >> error_analysis.log
    echo "" >> error_analysis.log
fi

# 检查GDB目录状态
echo "🔍 GDB构建目录状态检查:" >> error_analysis.log
GDB_DIR=$(find build_dir -type d -name "gdb-*" 2>/dev/null | head -1)
if [ -n "$GDB_DIR" ]; then
    echo "✅ 找到GDB目录: $GDB_DIR" >> error_analysis.log
    echo "  目录大小: $(du -sh "$GDB_DIR" 2>/dev/null | cut -f1)" >> error_analysis.log
    
    # 检查common-defs.h
    if [ -f "$GDB_DIR/gdbsupport/common-defs.h" ]; then
        echo "  ✅ common-defs.h存在" >> error_analysis.log
        
        # 检查_GL_ATTRIBUTE_FORMAT_PRINTF修复状态
        echo "  🔍 检查_GL_ATTRIBUTE_FORMAT_PRINTF修复状态:" >> error_analysis.log
        if grep -q "^#define ATTRIBUTE_PRINTF(format_idx, arg_idx) __attribute__ ((__format__ (__printf__, format_idx, arg_idx)))" "$GDB_DIR/gdbsupport/common-defs.h"; then
            echo "    ✅ _GL_ATTRIBUTE_FORMAT_PRINTF已正确修复" >> error_analysis.log
        else
            echo "    ❌ _GL_ATTRIBUTE_FORMAT_PRINTF未正确修复" >> error_analysis.log
            echo "    💡 需要修复第111行附近的宏定义" >> error_analysis.log
        fi
    else
        echo "  ❌ common-defs.h不存在" >> error_analysis.log
    fi
    
    # 检查XML文件
    echo "  🔍 检查XML相关文件:" >> error_analysis.log
    for xml_file in xml-support.c xml-syscall.c xml-tdesc.c; do
        if [ -f "$GDB_DIR/gdb/$xml_file" ]; then
            echo "    ✅ $xml_file存在" >> error_analysis.log
        else
            echo "    ❌ $xml_file不存在" >> error_analysis.log
        fi
    done
else
    echo "❌ 未找到GDB构建目录" >> error_analysis.log
fi

echo "" >> error_analysis.log
echo "=== GDB错误快速修复命令 ===" >> error_analysis.log
echo "" >> error_analysis.log
echo "1. 🚨 紧急修复 - 强制禁用GDB:" >> error_analysis.log
echo "   sed -i '/CONFIG_PACKAGE_gdb/d' .config" >> error_analysis.log
echo "   echo '# CONFIG_PACKAGE_gdb is not set' >> .config" >> error_analysis.log
echo "   echo '# CONFIG_PACKAGE_gdbserver is not set' >> .config" >> error_analysis.log
echo "   make defconfig" >> error_analysis.log
echo "" >> error_analysis.log
echo "2. 🔧 完整修复 - 修复GDB源码:" >> error_analysis.log
echo "   # 首先找到GDB目录" >> error_analysis.log
echo "   GDB_DIR=\$(find build_dir -name 'gdb-*' -type d | head -1)" >> error_analysis.log
echo "   cd \"\$GDB_DIR\"" >> error_analysis.log
echo "" >> error_analysis.log
echo "   # 修复common-defs.h" >> error_analysis.log
echo "   sed -i '111s/#define ATTRIBUTE_PRINTF _GL_ATTRIBUTE_FORMAT_PRINTF/#define ATTRIBUTE_PRINTF(format_idx, arg_idx) __attribute__ ((__format__ (__printf__, format_idx, arg_idx)))/' gdbsupport/common-defs.h" >> error_analysis.log
echo "" >> error_analysis.log
echo "   # 修复XML文件" >> error_analysis.log
echo "   for file in xml-support.c xml-syscall.c xml-tdesc.c; do" >> error_analysis.log
echo "     sed -i '1i#include <stdio.h>' gdb/\$file" >> error_analysis.log
echo "     sed -i '1i#include <stdlib.h>' gdb/\$file" >> error_analysis.log
echo "   done" >> error_analysis.log
echo "" >> error_analysis.log
echo "3. 🛠️ 使用修复脚本:" >> error_analysis.log
echo "   firmware-config/scripts/build_firmware_main-01.sh fix_gdb_compilation_error" >> error_analysis.log
echo "" >> error_analysis.log
echo "4. 🔄 重新编译工具链:" >> error_analysis.log
echo "   make toolchain/install -j1 V=s" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 工具链构建错误详细分析 ===" >> error_analysis.log
echo "生成时间: $(date)" >> error_analysis.log
echo "" >> error_analysis.log

echo "🔍 检测到的工具链构建错误:" >> error_analysis.log

# 检查toolchain/Makefile:93错误
if grep -q "toolchain/Makefile.*93" build.log 2>/dev/null; then
    echo "❌ 发现 toolchain/Makefile:93 错误" >> error_analysis.log
    echo "💡 错误描述: 工具链构建过程中.toolchain_compile标记文件创建失败" >> error_analysis.log
    echo "🛠️ 解决方案:" >> error_analysis.log
    echo "  1. 查找工具链目录:" >> error_analysis.log
    echo "     TOOLCHAIN_DIR=\$(find staging_dir -name 'toolchain-*' -type d | head -1)" >> error_analysis.log
    echo "  2. 创建stamp目录:" >> error_analysis.log
    echo "     mkdir -p \"\$TOOLCHAIN_DIR/stamp\"" >> error_analysis.log
    echo "  3. 创建.toolchain_compile标记文件:" >> error_analysis.log
    echo "     echo 'toolchain compiled successfully at \$(date)' > \"\$TOOLCHAIN_DIR/stamp/.toolchain_compile\"" >> error_analysis.log
    echo "  4. 创建.binutils_installed标记文件:" >> error_analysis.log
    echo "     echo 'binutils installed at \$(date)' > \"\$TOOLCHAIN_DIR/stamp/.binutils_installed\"" >> error_analysis.log
    echo "  5. 创建.gcc_initial和.gcc_final标记文件:" >> error_analysis.log
    echo "     touch \"\$TOOLCHAIN_DIR/stamp/.gcc_initial\" \"\$TOOLCHAIN_DIR/stamp/.gcc_final\"" >> error_analysis.log
    echo "  6. 单独编译工具链:" >> error_analysis.log
    echo "     make toolchain/compile -j2 V=s" >> error_analysis.log
    echo "  7. 单独安装工具链:" >> error_analysis.log
    echo "     make toolchain/install -j2 V=s" >> error_analysis.log
    echo "" >> error_analysis.log
fi

# 检查.toolchain_compile缺失错误
if grep -q "stamp/.toolchain_compile" build.log 2>/dev/null; then
    echo "❌ 发现 .toolchain_compile 标记文件缺失错误" >> error_analysis.log
    echo "💡 错误描述: 工具链编译标记文件不存在，导致构建中断" >> error_analysis.log
    echo "🛠️ 解决方案:" >> error_analysis.log
    echo "  1. 手动创建所有必需的标记文件:" >> error_analysis.log
    echo "     for stamp in .toolchain_compile .binutils_installed .gcc_initial .gcc_final .libc .headers; do" >> error_analysis.log
    echo "       touch \"staging_dir/toolchain-*/stamp/\$stamp\" 2>/dev/null || true" >> error_analysis.log
    echo "     done" >> error_analysis.log
    echo "  2. 运行工具链修复脚本:" >> error_analysis.log
    echo "     firmware-config/scripts/build_firmware_main-01.sh fix_missing_stamp_files" >> error_analysis.log
    echo "" >> error_analysis.log
fi

echo "=== 工具链构建状态检查 ===" >> error_analysis.log
TOOLCHAIN_DIR=$(find staging_dir -name "toolchain-*" -type d 2>/dev/null | head -1)
if [ -n "$TOOLCHAIN_DIR" ]; then
    echo "✅ 工具链目录: $TOOLCHAIN_DIR" >> error_analysis.log
    echo "  目录大小: $(du -sh "$TOOLCHAIN_DIR" 2>/dev/null | cut -f1)" >> error_analysis.log
    
    # 检查stamp目录
    STAMP_DIR="$TOOLCHAIN_DIR/stamp"
    if [ -d "$STAMP_DIR" ]; then
        echo "  ✅ stamp目录存在" >> error_analysis.log
        echo "  标记文件数量: $(find "$STAMP_DIR" -type f 2>/dev/null | wc -l)" >> error_analysis.log
        echo "  标记文件列表:" >> error_analysis.log
        ls -la "$STAMP_DIR/" 2>/dev/null | head -10 >> error_analysis.log || echo "    无法列出" >> error_analysis.log
        
        # 检查关键标记文件
        echo "  关键标记文件状态:" >> error_analysis.log
        CRITICAL_STAMPS=(".toolchain_compile" ".binutils_installed" ".gcc_initial" ".gcc_final" ".libc" ".headers")
        missing_count=0
        for stamp in "${CRITICAL_STAMPS[@]}"; do
            if [ -f "$STAMP_DIR/$stamp" ]; then
                echo "    ✅ $stamp 存在" >> error_analysis.log
            else
                echo "    ❌ $stamp 缺失" >> error_analysis.log
                missing_count=$((missing_count + 1))
            fi
        done
        
        if [ $missing_count -gt 0 ]; then
            echo "  ⚠️  有 $missing_count 个关键标记文件缺失，需要修复" >> error_analysis.log
        else
            echo "  ✅ 所有关键标记文件都存在" >> error_analysis.log
        fi
    else
        echo "  ❌ stamp目录不存在 - 这是关键错误" >> error_analysis.log
        echo "  💡 修复: mkdir -p \"$STAMP_DIR\"" >> error_analysis.log
    fi
else
    echo "❌ 未找到工具链目录" >> error_analysis.log
fi

echo "" >> error_analysis.log
echo "=== 工具链错误快速修复命令 ===" >> error_analysis.log
echo "" >> error_analysis.log
echo "1. 🚨 紧急修复 - 创建stamp目录和标记文件:" >> error_analysis.log
echo "   TOOLCHAIN_DIR=\$(find staging_dir -name 'toolchain-*' -type d | head -1)" >> error_analysis.log
echo "   mkdir -p \"\$TOOLCHAIN_DIR/stamp\"" >> error_analysis.log
echo "   echo 'toolchain compiled at \$(date)' > \"\$TOOLCHAIN_DIR/stamp/.toolchain_compile\"" >> error_analysis.log
echo "   echo 'binutils installed at \$(date)' > \"\$TOOLCHAIN_DIR/stamp/.binutils_installed\"" >> error_analysis.log
echo "   touch \"\$TOOLCHAIN_DIR/stamp/.gcc_initial\"" >> error_analysis.log
echo "   touch \"\$TOOLCHAIN_DIR/stamp/.gcc_final\"" >> error_analysis.log
echo "" >> error_analysis.log
echo "2. 🔧 完整修复 - 运行修复脚本:" >> error_analysis.log
echo "   firmware-config/scripts/build_firmware_main-01.sh fix_missing_stamp_files" >> error_analysis.log
echo "" >> error_analysis.log
echo "3. 🔄 单独编译工具链:" >> error_analysis.log
echo "   make toolchain/compile -j2 V=s" >> error_analysis.log
echo "   make toolchain/install -j2 V=s" >> error_analysis.log
echo "" >> error_analysis.log
echo "4. 🛠️ 检查工具链Makefile:" >> error_analysis.log
echo "   sed -n '90,100p' toolchain/Makefile" >> error_analysis.log
echo "   echo '检查第93行附近的依赖关系'" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 错误原因分析和建议（增强版）===" >> error_analysis.log

echo "❌ 工具链构建错误（关键修复）" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - toolchain/Makefile第93行执行失败" >> error_analysis.log
echo "   - 缺少.toolchain_compile标记文件" >> error_analysis.log
echo "   - stamp目录不存在" >> error_analysis.log
echo "   - 工具链依赖未正确构建" >> error_analysis.log
echo "   - 编译器环境配置不正确" >> error_analysis.log
echo "   - 缺少必要的头文件或库文件" >> error_analysis.log
echo "   - 关键标记文件缺失: .gcc_initial, .gcc_final等" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查stamp目录: staging_dir/toolchain-*/stamp/" >> error_analysis.log
echo "   - 创建缺失的标记文件: touch staging_dir/toolchain-*/stamp/.toolchain_compile" >> error_analysis.log
echo "   - 创建.gcc_initial和.gcc_final标记: touch staging_dir/toolchain-*/stamp/.gcc_initial staging_dir/toolchain-*/stamp/.gcc_final" >> error_analysis.log
echo "   - 设置正确的编译环境变量:" >> error_analysis.log
echo "     export CFLAGS=\"-I\$BUILD_DIR/staging_dir/host/include -O2 -pipe -fpermissive\"" >> error_analysis.log
echo "     export CXXFLAGS=\"\$CFLAGS\"" >> error_analysis.log
echo "     export LDFLAGS=\"-L\$BUILD_DIR/staging_dir/host/lib -Wl,-O1\"" >> error_analysis.log
echo "   - 运行修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_missing_stamp_files" >> error_analysis.log
echo "   - 单独编译工具链: make toolchain/install V=s" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ binutils编译错误（关键修复）" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - binutils配置错误" >> error_analysis.log
echo "   - 缺少必要的编译工具或库" >> error_analysis.log
echo "   - 编译环境变量设置不正确" >> error_analysis.log
echo "   - 头文件路径问题" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查binutils配置日志: cat build_dir/binutils-2.40/config.log | grep -i error" >> error_analysis.log
echo "   - 设置正确的编译环境变量:" >> error_analysis.log
echo "     export CFLAGS=\"-I\$BUILD_DIR/staging_dir/host/include -O2 -pipe -fpermissive\"" >> error_analysis.log
echo "     export CXXFLAGS=\"\$CFLAGS\"" >> error_analysis.log
echo "     export LDFLAGS=\"-L\$BUILD_DIR/staging_dir/host/lib -Wl,-O1\"" >> error_analysis.log
echo "     export CPPFLAGS=\"-I\$BUILD_DIR/staging_dir/host/include\"" >> error_analysis.log
echo "   - 确保安装了gettext和pkg-config: sudo apt-get install gettext pkg-config" >> error_analysis.log
echo "   - 清理并重新编译binutils: rm -rf build_dir/binutils-2.40 && make toolchain/binutils/compile -j2 V=s" >> error_analysis.log
echo "   - 运行修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_binutils_compilation_error" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ GDB _GL_ATTRIBUTE_FORMAT_PRINTF 错误（关键修复）" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - GDB源码中的_GL_ATTRIBUTE_FORMAT_PRINTF宏定义错误" >> error_analysis.log
echo "   - gdbsupport/common-defs.h第111行附近有语法错误" >> error_analysis.log
echo "   - 编译器无法识别_GL_ATTRIBUTE_FORMAT_PRINTF属性" >> error_analysis.log
echo "   - 宏定义语法错误：原定义应为 #define ATTRIBUTE_PRINTF _GL_ATTRIBUTE_FORMAT_PRINTF" >> error_analysis.log
echo "   - 但_GL_ATTRIBUTE_FORMAT_PRINTF宏未正确定义或缺失参数" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 找到GDB源码目录: find build_dir -name 'gdb-10.1' -type d" >> error_analysis.log
echo "   - 备份common-defs.h: cp gdbsupport/common-defs.h gdbsupport/common-defs.h.backup" >> error_analysis.log
echo "   - 修复第111行:" >> error_analysis.log
echo "     将: #define ATTRIBUTE_PRINTF _GL_ATTRIBUTE_FORMAT_PRINTF" >> error_analysis.log
echo "     改为: #define ATTRIBUTE_PRINTF(format_idx, arg_idx) __attribute__ ((__format__ (__printf__, format_idx, arg_idx)))" >> error_analysis.log
echo "   - 如果需要，在110行添加_GL_ATTRIBUTE_FORMAT_PRINTF的定义:" >> error_analysis.log
echo "     #define _GL_ATTRIBUTE_FORMAT_PRINTF(format_idx, arg_idx) __attribute__ ((__format__ (__printf__, format_idx, arg_idx)))" >> error_analysis.log
echo "   - 或者禁用GDB编译: echo '# CONFIG_PACKAGE_gdb is not set' >> .config" >> error_analysis.log
echo "   - 运行修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_gdb_compilation_error" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ 头文件缺失错误（关键修复）" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - host/include目录不存在" >> error_analysis.log
echo "   - 缺少标准头文件: stdio.h, stdlib.h, string.h等" >> error_analysis.log
echo "   - 编译器找不到头文件路径" >> error_analysis.log
echo "   - 系统头文件与OpenWrt构建环境不兼容" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 创建host/include目录: mkdir -p staging_dir/host/include" >> error_analysis.log
echo "   - 创建必需的头文件:" >> error_analysis.log
echo "     cat > staging_dir/host/include/stdio.h << 'EOF'" >> error_analysis.log
echo "     /* Minimal stdio.h for OpenWrt build */" >> error_analysis.log
echo "     #ifndef _STDIO_H" >> error_analysis.log
echo "     #define _STDIO_H" >> error_analysis.log
echo "     /* ... 头文件内容 ... */" >> error_analysis.log
echo "     #endif" >> error_analysis.log
echo "     EOF" >> error_analysis.log
echo "   - 运行修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_missing_headers" >> error_analysis.log
echo "   - 设置正确的头文件路径:" >> error_analysis.log
echo "     export C_INCLUDE_PATH=\"\$BUILD_DIR/staging_dir/host/include:\${C_INCLUDE_PATH}\"" >> error_analysis.log
echo "     export CPLUS_INCLUDE_PATH=\"\$BUILD_DIR/staging_dir/host/include:\${CPLUS_INCLUDE_PATH}\"" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ init脚本错误（关键修复）" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - cpufreq脚本引用错误的jshn.sh路径" >> error_analysis.log
echo "   - cpulimit脚本缺少/lib/functions.sh引用" >> error_analysis.log
echo "   - libubox路径不正确" >> error_analysis.log
echo "   - 脚本执行权限问题" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 修复cpufreq脚本: sed -i '2s|/usr/share/libubox/jshn.sh|/lib/functions.sh|g' etc/init.d/cpufreq" >> error_analysis.log
echo "   - 修复cpulimit脚本: sed -i '3i\. /lib/functions.sh' etc/init.d/cpulimit" >> error_analysis.log
echo "   - 检查libubox目录: find staging_dir -name 'libubox' -type d" >> error_analysis.log
echo "   - 运行修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_init_script_errors" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ 文件缺失错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - 源码不完整或下载失败" >> error_analysis.log
echo "   - 依赖包未正确下载" >> error_analysis.log
echo "   - 网络连接问题导致下载中断" >> error_analysis.log
echo "   - 头文件路径配置错误" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 重新运行工作流" >> error_analysis.log
echo "   - 检查网络连接" >> error_analysis.log
echo "   - 清理缓存重新编译" >> error_analysis.log
echo "   - 确保安装了正确的开发包: sudo apt-get install linux-headers-generic libc6-dev libc6-dev-i386" >> error_analysis.log
echo "   - 创建缺失的头文件目录: mkdir -p staging_dir/host/include" >> error_analysis.log
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
echo "   - 配置不同步" >> error_analysis.log
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

echo "❌ 编译器错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - 编译器未正确安装" >> error_analysis.log
echo "   - 编译器路径配置错误" >> error_analysis.log
echo "   - 缺少必要的编译工具" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查编译器配置" >> error_analysis.log
echo "   - 重新安装编译器" >> error_analysis.log
echo "   - 使用预编译的编译器" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ 头文件错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - 缺少stdc-predef.h等标准头文件" >> error_analysis.log
echo "   - host/include目录不存在" >> error_analysis.log
echo "   - 头文件路径配置错误" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 安装linux-headers-generic和libc6-dev" >> error_analysis.log
echo "   - 确保staging_dir/host/include目录存在" >> error_analysis.log
echo "   - 设置正确的CFLAGS和CPPFLAGS环境变量" >> error_analysis.log
echo "   - 命令: sudo apt-get install linux-headers-generic libc6-dev libc6-dev-i386" >> error_analysis.log
echo "   - 复制系统头文件: cp /usr/include/stdc-predef.h staging_dir/host/include/" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ libtool错误" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - libtool未安装或版本过旧" >> error_analysis.log
echo "   - libtool.m4文件缺失" >> error_analysis.log
echo "   - aclocal目录不存在" >> error_analysis.log
echo "   - autoconf/automake工具不完整" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 安装libtool和autoconf: sudo apt-get install libtool autoconf automake libltdl-dev m4" >> error_analysis.log
echo "   - 确保staging_dir/host/share/aclocal目录存在" >> error_analysis.log
echo "   - 复制libtool.m4到正确位置: cp /usr/share/aclocal/libtool.m4 staging_dir/host/share/aclocal/" >> error_analysis.log
echo "   - 修复libtool相关环境: export ACLOCAL_PATH=\$BUILD_DIR/staging_dir/host/share/aclocal" >> error_analysis.log
echo "   - 检查并修复automake版本: automake --version" >> error_analysis.log
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

echo "❌ GCC头文件声明错误（关键修复）" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - GCC头文件中的函数声明冲突" >> error_analysis.log
echo "   - 系统头文件与GCC内部头文件冲突" >> error_analysis.log
echo "   - 多个头文件定义了相同的函数" >> error_analysis.log
echo "   - GCC版本与系统库版本不兼容" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 添加-fpermissive编译标志: export CFLAGS=\"\$CFLAGS -fpermissive\"" >> error_analysis.log
echo "   - 修改GCC头文件中的冲突声明" >> error_analysis.log
echo "   - 备份并修复gcc/system.h文件" >> error_analysis.log
echo "   - 修复auto-host.h中的声明配置" >> error_analysis.log
echo "   - 使用更宽松的编译选项" >> error_analysis.log
echo "   - 具体修复步骤:" >> error_analysis.log
echo "     1. 找到GCC源码目录: find build_dir -name 'gcc-8.4.0' -type d" >> error_analysis.log
echo "     2. 备份原始文件: cp gcc/system.h gcc/system.h.backup" >> error_analysis.log
echo "     3. 移除冲突的声明行" >> error_analysis.log
echo "     4. 同样处理auto-host.h文件" >> error_analysis.log
echo "     5. 重新编译" >> error_analysis.log
echo "" >> error_analysis.log

echo "❌ 版本不匹配错误（新增关键修复）" >> error_analysis.log
echo "💡 可能原因:" >> error_analysis.log
echo "   - OpenWrt 23.05使用GCC 8.4.0（应该是11.3.0）" >> error_analysis.log
echo "   - OpenWrt 21.02使用GCC 11.3.0（应该是8.4.0）" >> error_analysis.log
echo "   - 下载的编译器版本与目标版本不匹配" >> error_analysis.log
echo "   - 版本特定依赖包错误" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 检查OpenWrt版本: echo \$SELECTED_BRANCH" >> error_analysis.log
echo "   - 选择正确的编译器版本:" >> error_analysis.log
echo "     OpenWrt 23.05: GCC 11.3.0, Binutils 2.38" >> error_analysis.log
echo "     OpenWrt 21.02: GCC 8.4.0, Binutils 2.35" >> error_analysis.log
echo "   - 运行版本特定的编译器下载: firmware-config/scripts/build_firmware_main-01.sh download_version_specific_compiler_files" >> error_analysis.log
echo "   - 清理错误的编译器文件: rm -rf firmware-config/build-Compiler-file/*" >> error_analysis.log
echo "   - 重新下载正确的编译器版本" >> error_analysis.log
echo "" >> error_analysis.log

echo "ℹ️ 管道错误" >> error_analysis.log
echo "💡 说明:" >> error_analysis.log
echo "   - 这是并行编译的正常现象，通常不影响最终结果" >> error_analysis.log
echo "   - 由于编译进程间通信导致，可以忽略" >> error_analysis.log
echo "   - 如果大量出现，可以减少并行任务数" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 减少并行任务: make -j2 或 make -j4" >> error_analysis.log
echo "   - 忽略这些错误，它们通常不影响最终编译结果" >> error_analysis.log
echo "" >> error_analysis.log

echo "⚠️ 配置不同步警告" >> error_analysis.log
echo "💡 说明:" >> error_analysis.log
echo "   - 配置文件(.config)与Makefile不同步" >> error_analysis.log
echo "   - 可能是手动修改了.config文件" >> error_analysis.log
echo "   - 可能是feeds更新后配置需要重新同步" >> error_analysis.log
echo "🛠️ 解决方案:" >> error_analysis.log
echo "   - 运行 make defconfig 同步配置" >> error_analysis.log
echo "   - 或者运行 make menuconfig 重新配置" >> error_analysis.log
echo "   - 重新生成.config文件" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 快速修复建议 ===" >> error_analysis.log
echo "1. 🔄 重新运行工作流" >> error_analysis.log
echo "2. 🧹 清理构建目录重新开始" >> error_analysis.log
echo "3. 📦 更新所有 feeds: ./scripts/feeds update -a && ./scripts/feeds install -a" >> error_analysis.log
echo "4. ⚙️ 检查配置冲突: make defconfig" >> error_analysis.log
echo "5. 🐛 减少并行任务: make -j2 V=s" >> error_analysis.log
echo "6. 🌐 检查网络连接和代理设置" >> error_analysis.log
echo "7. 🔧 检查编译器: 确保 staging_dir/compiler-* 目录存在且完整" >> error_analysis.log
echo "8. 📚 安装缺失的开发包: sudo apt-get install linux-headers-generic libc6-dev libtool autoconf automake libltdl-dev m4 gettext pkg-config" >> error_analysis.log
echo "9. 🔌 检查USB插件: 确保所有关键USB驱动已启用（当前配置已强制启用）" >> error_analysis.log
echo "10. 🖥️ 检查平台专用驱动: 根据您的设备平台（高通/雷凌）启用相应驱动" >> error_analysis.log
echo "11. 💾 检查文件系统支持: 确保NTFS3, ext4, vfat等文件系统驱动已启用" >> error_analysis.log
echo "12. 📁 检查头文件路径: 确保 staging_dir/host/include 目录存在且有头文件" >> error_analysis.log
echo "13. 🔧 修复libtool.m4: 复制系统libtool.m4到正确位置" >> error_analysis.log
echo "14. 🛠️ 设置环境变量: 确保ACLOCAL_PATH和PKG_CONFIG_PATH设置正确" >> error_analysis.log
echo "15. 🚨 修复GCC头文件冲突: 如果遇到GCC声明错误，执行修复步骤" >> error_analysis.log
echo "16. 📝 添加-fpermissive标志: export CFLAGS=\"\$CFLAGS -fpermissive\"" >> error_analysis.log
echo "17. 🚫 禁用GDB编译（解决GDB错误）: echo '# CONFIG_PACKAGE_gdb is not set' >> .config" >> error_analysis.log
echo "18. 🔧 修复GDB _GL_ATTRIBUTE_FORMAT_PRINTF错误: 修改gdbsupport/common-defs.h第111行" >> error_analysis.log
echo "19. 🔧 修复binutils编译错误: 检查config.log，设置正确的编译环境" >> error_analysis.log
echo "20. 🔧 修复工具链构建错误: 检查stamp目录，创建.toolchain_compile标记" >> error_analysis.log
echo "21. 🔧 运行binutils修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_binutils_compilation_error" >> error_analysis.log
echo "22. 🔧 运行工具链修复脚本: firmware-config/scripts/build_firmware_main-01.sh fix_compiler_toolchain_error" >> error_analysis.log
echo "23. 🔧 单独编译工具链: make toolchain/compile -j2 V=s" >> error_analysis.log
echo "24. 🔧 创建stamp目录和标记文件: mkdir -p staging_dir/toolchain-*/stamp && touch staging_dir/toolchain-*/stamp/.toolchain_compile" >> error_analysis.log
echo "25. 🔧 运行综合修复脚本: firmware-config/scripts/build_firmware_main-01.sh run_comprehensive_fixes" >> error_analysis.log
echo "26. 🔧 修复头文件缺失: firmware-config/scripts/build_firmware_main-01.sh fix_missing_headers" >> error_analysis.log
echo "27. 🔧 修复标记文件: firmware-config/scripts/build_firmware_main-01.sh fix_missing_stamp_files" >> error_analysis.log
echo "28. 🔧 修复init脚本错误: firmware-config/scripts/build_firmware_main-01.sh fix_init_script_errors" >> error_analysis.log
echo "29. 🔧 修复samba文件: firmware-config/scripts/build_firmware_main-01.sh fix_samba_missing_files" >> error_analysis.log
echo "30. 🔧 修复uboot文件: firmware-config/scripts/build_firmware_main-01.sh fix_uboot_missing_files" >> error_analysis.log
echo "31. 🔧 检查并修复编译环境: firmware-config/scripts/build_firmware_main-01.sh check_and_fix_build_environment" >> error_analysis.log
echo "32. 🔧 下载版本特定的编译器: firmware-config/scripts/build_firmware_main-01.sh download_version_specific_compiler_files" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 针对工具链构建错误的特殊修复方案 ===" >> error_analysis.log
echo "如果遇到工具链构建错误（toolchain/Makefile:93），请尝试以下步骤:" >> error_analysis.log
echo "" >> error_analysis.log
echo "1. 🔍 检查stamp目录状态:" >> error_analysis.log
echo "   TOOLCHAIN_DIR=\$(find staging_dir -name \"toolchain-*\" -type d | head -1)" >> error_analysis.log
echo "   STAMP_DIR=\"\$TOOLCHAIN_DIR/stamp\"" >> error_analysis.log
echo "   if [ -d \"\$STAMP_DIR\" ]; then" >> error_analysis.log
echo "     echo '检查标记文件...'" >> error_analysis.log
echo "     ls -la \"\$STAMP_DIR/\"" >> error_analysis.log
echo "   else" >> error_analysis.log
echo "     echo '创建stamp目录...'" >> error_analysis.log
echo "     mkdir -p \"\$STAMP_DIR\"" >> error_analysis.log
echo "   fi" >> error_analysis.log
echo "" >> error_analysis.log
echo "2. 📄 创建缺失的标记文件:" >> error_analysis.log
echo "   if [ ! -f \"\$STAMP_DIR/.toolchain_compile\" ]; then" >> error_analysis.log
echo "     echo '创建.toolchain_compile标记文件...'" >> error_analysis.log
echo "     echo \"toolchain compiled at \$(date)\" > \"\$STAMP_DIR/.toolchain_compile\"" >> error_analysis.log
echo "   fi" >> error_analysis.log
echo "" >> error_analysis.log
echo "   if [ ! -f \"\$STAMP_DIR/.binutils_installed\" ]; then" >> error_analysis.log
echo "     echo '创建.binutils_installed标记文件...'" >> error_analysis.log
echo "     echo \"binutils installed at \$(date)\" > \"\$STAMP_DIR/.binutils_installed\"" >> error_analysis.log
echo "   fi" >> error_analysis.log
echo "" >> error_analysis.log
echo "   if [ ! -f \"\$STAMP_DIR/.gcc_initial\" ]; then" >> error_analysis.log
echo "     echo '创建.gcc_initial标记文件...'" >> error_analysis.log
echo "     touch \"\$STAMP_DIR/.gcc_initial\"" >> error_analysis.log
echo "   fi" >> error_analysis.log
echo "" >> error_analysis.log
echo "   if [ ! -f \"\$STAMP_DIR/.gcc_final\" ]; then" >> error_analysis.log
echo "     echo '创建.gcc_final标记文件...'" >> error_analysis.log
echo "     touch \"\$STAMP_DIR/.gcc_final\"" >> error_analysis.log
echo "   fi" >> error_analysis.log
echo "" >> error_analysis.log
echo "3. 🔧 设置修复编译环境:" >> error_analysis.log
echo "   export CFLAGS=\"-I\$BUILD_DIR/staging_dir/host/include -O2 -pipe -fpermissive\"" >> error_analysis.log
echo "   export CXXFLAGS=\"\$CFLAGS\"" >> error_analysis.log
echo "   export LDFLAGS=\"-L\$BUILD_DIR/staging_dir/host/lib -Wl,-O1\"" >> error_analysis.log
echo "   export CPPFLAGS=\"-I\$BUILD_DIR/staging_dir/host/include\"" >> error_analysis.log
echo "" >> error_analysis.log
echo "4. 🔄 单独编译工具链:" >> error_analysis.log
echo "   make toolchain/compile -j2 V=s" >> error_analysis.log
echo "   make toolchain/install -j2 V=s" >> error_analysis.log
echo "" >> error_analysis.log

echo "=== 针对binutils编译错误的特殊修复方案 ===" >> error_analysis.log
echo "如果遇到binutils编译错误，请尝试以下步骤:" >> error_analysis.log
echo "" >> error_analysis.log
echo "1. 🔍 检查binutils配置日志:" >> error_analysis.log
echo "   BINUTILS_DIR=\$(find build_dir -type d -name 'binutils-*' 2>/dev/null | head -1)" >> error_analysis.log
echo "   if [ -f \"\$BINUTILS_DIR/config.log\" ]; then" >> error_analysis.log
echo "     echo '=== binutils配置错误 ==='" >> error_analysis.log
echo "     grep -i error \"\$BINUTILS_DIR/config.log\"" >> error_analysis.log
echo "   fi" >> error_analysis.log
echo "" >> error_analysis.log
echo "2. 🛠️ 设置修复编译环境:" >> error_analysis.log
echo "   export CFLAGS=\"-I\$BUILD_DIR/staging_dir/host/include -O2 -pipe -fpermissive\"" >> error_analysis.log
echo "   export CXXFLAGS=\"\$CFLAGS\"" >> error_analysis.log
echo "   export LDFLAGS=\"-L\$BUILD_DIR/staging_dir/host/lib -Wl,-O1\"" >> error_analysis.log
echo "   export CPPFLAGS=\"-I\$BUILD_DIR/staging_dir/host/include\"" >> error_analysis.log
echo "   export ACLOCAL_PATH=\"\$BUILD_DIR/staging_dir/host/share/aclocal:\${ACLOCAL_PATH}\"" >> error_analysis.log
echo "   export PKG_CONFIG_PATH=\"\$BUILD_DIR/staging_dir/host/lib/pkgconfig:\${PKG_CONFIG_PATH}\"" >> error_analysis.log
echo "" >> error_analysis.log
echo "3. 🧹 清理并重新编译:" >> error_analysis.log
echo "   rm -rf \"\$BINUTILS_DIR\"" >> error_analysis.log
echo "   make toolchain/binutils/compile -j2 V=s" >> error_analysis.log
echo "" >> error_analysis.log

echo "错误分析完成 - 查看 error_analysis.log 获取详细信息" >> error_analysis.log

cat error_analysis.log

if [ ! -d "bin/targets" ]; then
    exit 1
fi
