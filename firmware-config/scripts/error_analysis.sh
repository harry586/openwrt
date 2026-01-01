#!/bin/bash
set -e

# 全局变量
BUILD_DIR="${BUILD_DIR:-/mnt/openwrt-build}"
ANALYSIS_DIR="/tmp/error-analysis"
REPORT_FILE="$ANALYSIS_DIR/report.txt"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/openwrt-error-analysis-$TIMESTAMP.txt"

# 日志函数
log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

# 标题函数
print_header() {
    echo "" >> "$REPORT_FILE"
    echo "==================================================" >> "$REPORT_FILE"
    echo "           $1" >> "$REPORT_FILE"
    echo "==================================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# 子标题函数
print_subheader() {
    echo "" >> "$REPORT_FILE"
    echo "=== $1 ===" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# 1. 初始化报告
init_report() {
    log "📝 初始化错误分析报告..."
    mkdir -p "$ANALYSIS_DIR"
    
    echo "==================================================" > "$REPORT_FILE"
    echo "        🚨 OpenWrt固件构建错误分析报告           " >> "$REPORT_FILE"
    echo "==================================================" >> "$REPORT_FILE"
    echo "分析时间: $(date)" >> "$REPORT_FILE"
    echo "报告版本: 2.0.0" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# 2. 收集系统信息
collect_system_info() {
    log "💻 收集系统信息..."
    
    print_header "系统环境信息"
    
    echo "📋 基本信息:" >> "$REPORT_FILE"
    echo "  构建目录: $BUILD_DIR" >> "$REPORT_FILE"
    echo "  主机名: $(hostname)" >> "$REPORT_FILE"
    echo "  用户: $(whoami)" >> "$REPORT_FILE"
    echo "  终端: $TERM" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "📊 系统版本:" >> "$REPORT_FILE"
    if [ -f /etc/os-release ]; then
        grep -E '^PRETTY_NAME=|^NAME=|^VERSION=' /etc/os-release >> "$REPORT_FILE"
    else
        uname -a >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    echo "⚙️  构建参数:" >> "$REPORT_FILE"
    echo "  设备: ${DEVICE:-未设置}" >> "$REPORT_FILE"
    echo "  目标平台: ${TARGET:-未设置}" >> "$REPORT_FILE"
    echo "  子目标: ${SUBTARGET:-未设置}" >> "$REPORT_FILE"
    echo "  版本分支: ${SELECTED_BRANCH:-未设置}" >> "$REPORT_FILE"
    echo "  架构: ${ARCH:-自动检测}" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# 3. 检查系统资源
check_system_resources() {
    log "💾 检查系统资源..."
    
    print_subheader "系统资源状态"
    
    echo "💿 磁盘使用情况:" >> "$REPORT_FILE"
    df -h --total / /home /tmp /mnt /boot 2>/dev/null | grep -v "tmpfs" | while read line; do
        echo "  $line" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    echo "🧠 内存使用情况:" >> "$REPORT_FILE"
    free -h | while read line; do
        echo "  $line" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    echo "⚡ CPU信息:" >> "$REPORT_FILE"
    echo "  核心数: $(nproc 2>/dev/null || echo '未知')" >> "$REPORT_FILE"
    echo "  架构: $(uname -m)" >> "$REPORT_FILE"
    echo "  负载: $(uptime | awk -F'load average:' '{print $2}' | xargs)" >> "$REPORT_FILE"
    echo "  运行时间: $(uptime -p 2>/dev/null || uptime)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "🌡️  系统温度 (如果可用):" >> "$REPORT_FILE"
    if command -v sensors >/dev/null 2>&1; then
        sensors 2>/dev/null | grep -E "Core|temp" | head -5 >> "$REPORT_FILE" || echo "  未检测到温度传感器" >> "$REPORT_FILE"
    else
        echo "  sensors命令未安装" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 4. 检查构建结果
check_build_result() {
    log "📦 检查构建结果..."
    
    print_subheader "构建结果摘要"
    
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        local firmware_count=$(find "$BUILD_DIR/bin/targets" -name '*.bin' -o -name '*.img' -o -name '*.gz' 2>/dev/null | wc -l)
        local initramfs_count=$(find "$BUILD_DIR/bin/targets" -name '*initramfs*' 2>/dev/null | wc -l)
        local squashfs_count=$(find "$BUILD_DIR/bin/targets" -name '*squashfs*' 2>/dev/null | wc -l)
        
        echo "✅ 构建状态: 成功" >> "$REPORT_FILE"
        echo "📊 文件统计:" >> "$REPORT_FILE"
        echo "  固件总数: $firmware_count" >> "$REPORT_FILE"
        echo "  initramfs固件: $initramfs_count" >> "$REPORT_FILE"
        echo "  squashfs固件: $squashfs_count" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        if [ $firmware_count -gt 0 ]; then
            echo "📄 生成的固件文件 (最多显示10个):" >> "$REPORT_FILE"
            find "$BUILD_DIR/bin/targets" \( -name "*.bin" -o -name "*.img" -o -name "*.gz" \) -type f 2>/dev/null | head -10 | while read file; do
                local size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
                echo "  📁 $(basename "$file") ($size)" >> "$REPORT_FILE"
            done
        fi
        
        # 检查固件大小
        echo "" >> "$REPORT_FILE"
        echo "📏 固件大小统计:" >> "$REPORT_FILE"
        find "$BUILD_DIR/bin/targets" \( -name "*.bin" -o -name "*.img" \) -type f 2>/dev/null | head -5 | while read file; do
            local size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
            echo "  $(basename "$file"): $size" >> "$REPORT_FILE"
        done
    else
        echo "❌ 构建状态: 失败" >> "$REPORT_FILE"
        echo "❌ 未找到固件输出目录: $BUILD_DIR/bin/targets" >> "$REPORT_FILE"
        
        # 检查是否有build_dir目录
        if [ -d "$BUILD_DIR/build_dir" ]; then
            echo "⚠️  build_dir目录存在，编译可能正在进行中" >> "$REPORT_FILE"
        fi
    fi
    echo "" >> "$REPORT_FILE"
}

# 5. 分析配置文件
analyze_config_file() {
    log "⚙️  分析配置文件..."
    
    print_subheader "配置文件分析"
    
    if [ -f "$BUILD_DIR/.config" ]; then
        local config_size=$(ls -lh "$BUILD_DIR/.config" 2>/dev/null | awk '{print $5}' || echo "未知")
        local config_lines=$(wc -l < "$BUILD_DIR/.config" 2>/dev/null || echo "0")
        
        echo "✅ 配置文件状态: 存在" >> "$REPORT_FILE"
        echo "📊 配置信息:" >> "$REPORT_FILE"
        echo "  文件大小: $config_size" >> "$REPORT_FILE"
        echo "  配置行数: $config_lines" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # 统计各种配置
        echo "📈 配置统计:" >> "$REPORT_FILE"
        
        local total_configs=$(grep -c "^CONFIG_" "$BUILD_DIR/.config" 2>/dev/null || echo "0")
        local enabled_configs=$(grep -c "^CONFIG_[A-Z_]*=y" "$BUILD_DIR/.config" 2>/dev/null || echo "0")
        local disabled_configs=$(grep -c "^# CONFIG_[A-Z_]* is not set" "$BUILD_DIR/.config" 2>/dev/null || echo "0")
        local module_configs=$(grep -c "^CONFIG_[A-Z_]*=m" "$BUILD_DIR/.config" 2>/dev/null || echo "0")
        
        echo "  配置总数: $total_configs" >> "$REPORT_FILE"
        echo "  已启用: $enabled_configs" >> "$REPORT_FILE"
        echo "  已禁用: $disabled_configs" >> "$REPORT_FILE"
        echo "  模块形式: $module_configs" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # 检查包配置
        local enabled_packages=$(grep "^CONFIG_PACKAGE_[A-Za-z0-9_-]*=y" "$BUILD_DIR/.config" 2>/dev/null | wc -l)
        local disabled_packages=$(grep "^# CONFIG_PACKAGE_[A-Za-z0-9_-]* is not set" "$BUILD_DIR/.config" 2>/dev/null | wc -l)
        
        echo "📦 包配置统计:" >> "$REPORT_FILE"
        echo "  已启用包: $enabled_packages" >> "$REPORT_FILE"
        echo "  已禁用包: $disabled_packages" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # C库配置
        print_subheader "C库配置状态"
        if grep -q "CONFIG_USE_MUSL=y" "$BUILD_DIR/.config" 2>/dev/null; then
            echo "✅ C库: musl (现代OpenWrt默认使用)" >> "$REPORT_FILE"
            echo "💡 musl是轻量级C库，适用于嵌入式系统" >> "$REPORT_FILE"
        elif grep -q "CONFIG_USE_GLIBC=y" "$BUILD_DIR/.config" 2>/dev/null; then
            echo "✅ C库: glibc (功能完整的C库)" >> "$REPORT_FILE"
            echo "💡 glibc功能更完整，但体积较大" >> "$REPORT_FILE"
        elif grep -q "CONFIG_USE_UCLIBC=y" "$BUILD_DIR/.config" 2>/dev/null; then
            echo "✅ C库: uclibc (旧版OpenWrt使用)" >> "$REPORT_FILE"
            echo "💡 uclibc是较旧的C库，现代OpenWrt已转向musl" >> "$REPORT_FILE"
        else
            echo "⚠️ C库: 未明确指定" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 内核配置
        print_subheader "内核配置状态"
        local kernel_version=$(grep "^CONFIG_LINUX_[0-9]*_[0-9]*.*=y" "$BUILD_DIR/.config" 2>/dev/null | head -1 | sed 's/CONFIG_LINUX_//;s/=y//;s/_/./g')
        if [ -n "$kernel_version" ]; then
            echo "✅ 内核版本: Linux $kernel_version" >> "$REPORT_FILE"
        else
            echo "⚠️ 内核版本: 未明确指定" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # USB配置详细分析
        print_subheader "USB配置详细分析"
        local usb_configs=(
            "kmod-usb-core:USB核心驱动"
            "kmod-usb2:USB 2.0支持"
            "kmod-usb3:USB 3.0支持"
            "kmod-usb-storage:USB存储支持"
            "kmod-usb-dwc3:USB 3.0主机控制器"
            "kmod-usb-xhci-hcd:USB 3.0扩展主机控制器"
            "kmod-usb-ehci:USB 2.0增强主机控制器"
            "kmod-usb-ohci:USB 1.1开放主机控制器"
            "kmod-usb-storage-uas:USB Attached SCSI协议"
            "kmod-scsi-core:SCSI核心驱动"
            "kmod-usb-dwc3-qcom:高通平台USB 3.0驱动"
            "kmod-phy-qcom-dwc3:高通USB物理层驱动"
            "kmod-usb-xhci-mtk:雷凌平台USB 3.0驱动"
            "kmod-usb2-pci:USB 2.0 PCI支持"
            "kmod-usb-ohci-pci:USB 1.1 PCI支持"
            "kmod-usb-xhci-pci:USB 3.0 PCI支持"
        )
        
        local usb_enabled=0
        local usb_total=${#usb_configs[@]}
        
        for config_entry in "${usb_configs[@]}"; do
            IFS=':' read -r config_name config_desc <<< "$config_entry"
            if grep -q "^CONFIG_PACKAGE_${config_name}=y" "$BUILD_DIR/.config" 2>/dev/null; then
                echo "✅ $config_name: 已启用 ($config_desc)" >> "$REPORT_FILE"
                ((usb_enabled++))
            else
                echo "❌ $config_name: 未启用 ($config_desc)" >> "$REPORT_FILE"
            fi
        done
        echo "" >> "$REPORT_FILE"
        
        echo "📊 USB配置统计:" >> "$REPORT_FILE"
        echo "  总USB驱动数: $usb_total" >> "$REPORT_FILE"
        echo "  已启用: $usb_enabled" >> "$REPORT_FILE"
        echo "  未启用: $((usb_total - usb_enabled))" >> "$REPORT_FILE"
        
        if [ $usb_enabled -eq $usb_total ]; then
            echo "🎉 所有关键USB驱动都已启用！" >> "$REPORT_FILE"
        elif [ $usb_enabled -ge $((usb_total * 8 / 10)) ]; then
            echo "⚠️ 大部分USB驱动已启用，但仍有部分未启用" >> "$REPORT_FILE"
        else
            echo "❌ 大量USB驱动未启用，USB功能可能受限" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 文件系统支持
        print_subheader "文件系统支持状态"
        local fs_configs=(
            "kmod-fs-ext4:ext4文件系统"
            "kmod-fs-vfat:FAT/VFAT文件系统"
            "kmod-fs-exfat:exFAT文件系统"
            "kmod-fs-ntfs3:NTFS文件系统"
            "kmod-fs-btrfs:Btrfs文件系统"
            "kmod-fs-f2fs:F2FS文件系统"
            "kmod-fs-xfs:XFS文件系统"
        )
        
        for fs_entry in "${fs_configs[@]}"; do
            IFS=':' read -r fs_name fs_desc <<< "$fs_entry"
            if grep -q "^CONFIG_PACKAGE_${fs_name}=y" "$BUILD_DIR/.config" 2>/dev/null; then
                echo "✅ $fs_name: 已启用 ($fs_desc)" >> "$REPORT_FILE"
            else
                echo "❌ $fs_name: 未启用 ($fs_desc)" >> "$REPORT_FILE"
            fi
        done
        echo "" >> "$REPORT_FILE"
        
        # 编码支持
        local nls_configs=(
            "kmod-nls-utf8:UTF-8编码"
            "kmod-nls-cp437:CP437编码"
            "kmod-nls-iso8859-1:ISO-8859-1编码"
            "kmod-nls-cp936:CP936编码(简体中文)"
            "kmod-nls-cp950:CP950编码(繁体中文)"
        )
        
        for nls_entry in "${nls_configs[@]}"; do
            IFS=':' read -r nls_name nls_desc <<< "$nls_entry"
            if grep -q "^CONFIG_PACKAGE_${nls_name}=y" "$BUILD_DIR/.config" 2>/dev/null; then
                echo "✅ $nls_name: 已启用 ($nls_desc)" >> "$REPORT_FILE"
            else
                echo "❌ $nls_name: 未启用 ($nls_desc)" >> "$REPORT_FILE"
            fi
        done
        echo "" >> "$REPORT_FILE"
        
        # 显示前10个被禁用的重要包
        print_subheader "重要禁用包列表"
        grep "^# CONFIG_PACKAGE_[A-Za-z0-9_-]* is not set" "$BUILD_DIR/.config" 2>/dev/null | \
            grep -E "(kmod-|luci-|base)" | head -10 | while read line; do
            pkg_name=$(echo "$line" | sed 's/# CONFIG_PACKAGE_//;s/ is not set//')
            echo "❌ $pkg_name" >> "$REPORT_FILE"
        done
        
    else
        echo "❌ 配置文件不存在: $BUILD_DIR/.config" >> "$REPORT_FILE"
        echo "💡 建议: 运行 make menuconfig 或 make defconfig 生成配置文件" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 6. 检查编译器状态
check_compiler_status() {
    log "🔧 检查编译器状态..."
    
    print_subheader "编译器状态检查"
    
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        echo "✅ 编译目录存在: staging_dir" >> "$REPORT_FILE"
        
        # 检查工具链目录
        local toolchain_dirs=$(find "$BUILD_DIR/staging_dir" -name "toolchain-*" -type d 2>/dev/null | wc -l)
        echo "📊 工具链目录数: $toolchain_dirs" >> "$REPORT_FILE"
        
        if [ $toolchain_dirs -gt 0 ]; then
            local toolchain_dir=$(find "$BUILD_DIR/staging_dir" -name "toolchain-*" -type d 2>/dev/null | head -1)
            echo "🔍 工具链目录: $(basename "$toolchain_dir")" >> "$REPORT_FILE"
            
            # 检查编译器
            echo "🔍 编译器检查:" >> "$REPORT_FILE"
            find "$toolchain_dir/bin" -name "*gcc*" -type f 2>/dev/null | head -5 | while read compiler; do
                local compiler_name=$(basename "$compiler")
                if [ -x "$compiler" ]; then
                    echo "  ✅ $compiler_name: 可执行" >> "$REPORT_FILE"
                    # 尝试获取版本
                    local version=$("$compiler" --version 2>&1 | head -1)
                    echo "     版本: $version" >> "$REPORT_FILE"
                else
                    echo "  ❌ $compiler_name: 不可执行" >> "$REPORT_FILE"
                fi
            done
            echo "" >> "$REPORT_FILE"
            
            # 检查头文件目录
            echo "🔍 头文件目录检查:" >> "$REPORT_FILE"
            if [ -d "$BUILD_DIR/staging_dir/host/include" ]; then
                local header_count=$(find "$BUILD_DIR/staging_dir/host/include" -name "*.h" 2>/dev/null | wc -l)
                echo "  ✅ host/include目录存在" >> "$REPORT_FILE"
                echo "     头文件数量: $header_count" >> "$REPORT_FILE"
                
                # 检查关键头文件
                local critical_headers=("stdio.h" "stdlib.h" "string.h" "stddef.h" "stdint.h" "stdbool.h" "stdarg.h")
                echo "     关键头文件状态:" >> "$REPORT_FILE"
                for header in "${critical_headers[@]}"; do
                    if find "$BUILD_DIR/staging_dir/host/include" -name "$header" -type f 2>/dev/null | grep -q .; then
                        echo "       ✅ $header" >> "$REPORT_FILE"
                    else
                        echo "       ❌ $header - 缺失" >> "$REPORT_FILE"
                    fi
                done
            else
                echo "  ❌ host/include目录不存在" >> "$REPORT_FILE"
                echo "  💡 建议: 创建目录并复制系统头文件" >> "$REPORT_FILE"
            fi
            echo "" >> "$REPORT_FILE"
            
            # 检查lib目录
            echo "🔍 库文件目录检查:" >> "$REPORT_FILE"
            if [ -d "$BUILD_DIR/staging_dir/host/lib" ]; then
                local lib_count=$(find "$BUILD_DIR/staging_dir/host/lib" -name "*.so*" -o -name "*.a" 2>/dev/null | wc -l)
                echo "  ✅ host/lib目录存在" >> "$REPORT_FILE"
                echo "     库文件数量: $lib_count" >> "$REPORT_FILE"
            else
                echo "  ❌ host/lib目录不存在" >> "$REPORT_FILE"
            fi
            echo "" >> "$REPORT_FILE"
            
            # 检查stamp目录
            local stamp_dir="$toolchain_dir/stamp"
            if [ -d "$stamp_dir" ]; then
                echo "✅ stamp目录存在" >> "$REPORT_FILE"
                local stamp_count=$(find "$stamp_dir" -type f 2>/dev/null | wc -l)
                echo "  标记文件数量: $stamp_count" >> "$REPORT_FILE"
                
                # 检查关键标记文件
                local critical_stamps=(".toolchain_compile" ".binutils_installed" ".gcc_initial" ".gcc_final" ".libc" ".headers")
                echo "  关键标记文件状态:" >> "$REPORT_FILE"
                for stamp in "${critical_stamps[@]}"; do
                    if [ -f "$stamp_dir/$stamp" ]; then
                        echo "    ✅ $stamp" >> "$REPORT_FILE"
                    else
                        echo "    ❌ $stamp - 缺失" >> "$REPORT_FILE"
                    fi
                done
            else
                echo "❌ stamp目录不存在" >> "$REPORT_FILE"
                echo "💡 建议: mkdir -p \"$stamp_dir\"" >> "$REPORT_FILE"
            fi
            
        else
            echo "❌ 未找到工具链目录" >> "$REPORT_FILE"
            echo "💡 工具链可能尚未编译完成" >> "$REPORT_FILE"
        fi
        
    else
        echo "❌ 编译目录不存在: staging_dir" >> "$REPORT_FILE"
        echo "💡 构建可能尚未开始或已清理" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 7. 分析构建日志
analyze_build_log() {
    log "📝 分析构建日志..."
    
    print_subheader "构建日志分析"
    
    if [ -f "$BUILD_DIR/build.log" ]; then
        local log_size=$(ls -lh "$BUILD_DIR/build.log" 2>/dev/null | awk '{print $5}' || echo "未知")
        local log_lines=$(wc -l < "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        
        echo "✅ 构建日志状态: 存在" >> "$REPORT_FILE"
        echo "📊 日志信息:" >> "$REPORT_FILE"
        echo "  文件大小: $log_size" >> "$REPORT_FILE"
        echo "  行数: $log_lines" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # 错误统计
        local error_count=$(grep -c -i "error" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        local warning_count=$(grep -c -i "warning" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        local failed_count=$(grep -c -i "failed" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        
        echo "📈 错误统计:" >> "$REPORT_FILE"
        echo "  错误总数: $error_count" >> "$REPORT_FILE"
        echo "  警告总数: $warning_count" >> "$REPORT_FILE"
        echo "  失败总数: $failed_count" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        if [ $error_count -gt 0 ]; then
            print_subheader "关键错误摘要"
            
            # 分类提取错误
            echo "🔴 严重错误 (前20个):" >> "$REPORT_FILE"
            grep -i "error" "$BUILD_DIR/build.log" | grep -v "ignored" | head -20 >> "$REPORT_FILE" || echo "  无严重错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🟡 Makefile错误:" >> "$REPORT_FILE"
            grep -i "make.*error\|recipe for target.*failed" "$BUILD_DIR/build.log" | head -10 >> "$REPORT_FILE" || echo "  无Makefile错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🔵 编译器错误:" >> "$REPORT_FILE"
            grep -i "gcc.*error\|ld.*error\|collect2.*error" "$BUILD_DIR/build.log" | head -10 >> "$REPORT_FILE" || echo "  无编译器错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🟣 文件缺失错误:" >> "$REPORT_FILE"
            grep -i "no such file\|file not found\|cannot find" "$BUILD_DIR/build.log" | head -10 >> "$REPORT_FILE" || echo "  无文件缺失错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🟠 依赖错误:" >> "$REPORT_FILE"
            grep -i "depends on\|missing dependencies\|undefined reference" "$BUILD_DIR/build.log" | head -10 >> "$REPORT_FILE" || echo "  无依赖错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🔴 内存错误:" >> "$REPORT_FILE"
            grep -i "out of memory\|killed process\|oom" "$BUILD_DIR/build.log" | head -5 >> "$REPORT_FILE" || echo "  无内存错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            # 特定错误模式检查
            print_subheader "特定错误模式检测"
            
            # 工具链错误
            if grep -q "toolchain/Makefile.*93" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "❌ 检测到 toolchain/Makefile:93 错误" >> "$REPORT_FILE"
                echo "💡 这是常见的工具链构建错误" >> "$REPORT_FILE"
                echo "🛠️ 修复方法: 创建stamp目录和标记文件" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
            # GDB错误
            if grep -q "_GL_ATTRIBUTE_FORMAT_PRINTF" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "❌ 检测到 GDB _GL_ATTRIBUTE_FORMAT_PRINTF 错误" >> "$REPORT_FILE"
                echo "💡 GDB源码中的宏定义错误" >> "$REPORT_FILE"
                echo "🛠️ 修复方法: 修改gdbsupport/common-defs.h第111行" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
            # 头文件错误
            if grep -q "stdc-predef.h\|stdio.h\|stdlib.h" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "❌ 检测到头文件缺失错误" >> "$REPORT_FILE"
                echo "💡 缺少标准头文件" >> "$REPORT_FILE"
                echo "🛠️ 修复方法: 创建host/include目录并复制头文件" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
            # 显示日志最后100行
            if [ $log_lines -gt 100 ]; then
                print_subheader "构建日志尾部 (最后100行)"
                tail -100 "$BUILD_DIR/build.log" >> "$REPORT_FILE"
            fi
            
        else
            echo "✅ 构建日志中没有发现错误" >> "$REPORT_FILE"
        fi
        
    else
        echo "❌ 构建日志文件不存在: $BUILD_DIR/build.log" >> "$REPORT_FILE"
        echo "💡 构建可能尚未开始或日志被重定向" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 8. 检查下载日志
check_download_log() {
    log "📥 检查下载日志..."
    
    print_subheader "下载日志分析"
    
    if [ -f "$BUILD_DIR/download.log" ]; then
        local download_errors=$(grep -c -i "error\|failed\|404\|not found" "$BUILD_DIR/download.log" 2>/dev/null || echo "0")
        
        if [ $download_errors -gt 0 ]; then
            echo "❌ 下载错误: $download_errors 个" >> "$REPORT_FILE"
            echo "📄 下载错误详情 (前10个):" >> "$REPORT_FILE"
            grep -i "error\|failed\|404\|not found" "$BUILD_DIR/download.log" | head -10 >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "💡 下载问题解决方案:" >> "$REPORT_FILE"
            echo "  1. 检查网络连接" >> "$REPORT_FILE"
            echo "  2. 配置代理服务器" >> "$REPORT_FILE"
            echo "  3. 手动下载缺失文件" >> "$REPORT_FILE"
            echo "  4. 运行: make download -j8 V=s" >> "$REPORT_FILE"
        else
            echo "✅ 下载日志无错误" >> "$REPORT_FILE"
        fi
        
    else
        echo "ℹ️ 下载日志文件不存在" >> "$REPORT_FILE"
        echo "💡 可能尚未开始下载或日志被合并" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 9. 版本特定分析
analyze_version_specific() {
    log "🔍 分析版本特定问题..."
    
    print_subheader "版本特定问题分析"
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        echo "🔧 OpenWrt 23.05 版本特性:" >> "$REPORT_FILE"
        echo "  编译器: GCC 11.3.0" >> "$REPORT_FILE"
        echo "  内核: Linux 5.15" >> "$REPORT_FILE"
        echo "  musl: 1.2.3" >> "$REPORT_FILE"
        echo "  binutils: 2.38" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "⚠️ 常见问题:" >> "$REPORT_FILE"
        echo "  1. GDB _GL_ATTRIBUTE_FORMAT_PRINTF 错误" >> "$REPORT_FILE"
        echo "  2. 工具链构建错误 (toolchain/Makefile:93)" >> "$REPORT_FILE"
        echo "  3. 头文件缺失问题" >> "$REPORT_FILE"
        echo "  4. libtool版本兼容性问题" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "🛠️ 解决方案:" >> "$REPORT_FILE"
        echo "  1. 修复GDB源码: 修改gdbsupport/common-defs.h" >> "$REPORT_FILE"
        echo "  2. 创建stamp标记文件" >> "$REPORT_FILE"
        echo "  3. 安装libtool和autoconf" >> "$REPORT_FILE"
        echo "  4. 设置-fpermissive编译标志" >> "$REPORT_FILE"
        
    elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
        echo "🔧 OpenWrt 21.02 版本特性:" >> "$REPORT_FILE"
        echo "  编译器: GCC 8.4.0" >> "$REPORT_FILE"
        echo "  内核: Linux 5.4" >> "$REPORT_FILE"
        echo "  musl: 1.1.24" >> "$REPORT_FILE"
        echo "  binutils: 2.35" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "✅ 版本特点:" >> "$REPORT_FILE"
        echo "  1. 相对稳定，问题较少" >> "$REPORT_FILE"
        echo "  2. 文档和教程丰富" >> "$REPORT_FILE"
        echo "  3. 兼容性好" >> "$REPORT_FILE"
        
    else
        echo "ℹ️ 未知版本分支: $SELECTED_BRANCH" >> "$REPORT_FILE"
        echo "💡 请确认版本分支设置是否正确" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 10. 生成修复建议
generate_fix_suggestions() {
    log "💡 生成修复建议..."
    
    print_header "综合修复建议"
    
    # 基本修复步骤
    echo "🔧 基本修复步骤 (按顺序尝试):" >> "$REPORT_FILE"
    echo "  1. 🧹 清理构建: cd $BUILD_DIR && make clean" >> "$REPORT_FILE"
    echo "  2. 📦 更新feeds: ./scripts/feeds update -a && ./scripts/feeds install -a" >> "$REPORT_FILE"
    echo "  3. ⚙️ 同步配置: make defconfig" >> "$REPORT_FILE"
    echo "  4. 🚀 重新构建: make -j2 V=s 2>&1 | tee build.log" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 根据问题类型给出建议
    echo "🎯 针对性修复方案:" >> "$REPORT_FILE"
    
    # 检查常见问题并给出建议
    if [ -f "$BUILD_DIR/build.log" ]; then
        # 工具链错误
        if grep -q "toolchain/Makefile" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 工具链构建错误修复:" >> "$REPORT_FILE"
            echo "  TOOLCHAIN_DIR=\$(find $BUILD_DIR/staging_dir -name 'toolchain-*' -type d | head -1)" >> "$REPORT_FILE"
            echo "  mkdir -p \"\$TOOLCHAIN_DIR/stamp\"" >> "$REPORT_FILE"
            echo "  echo '修复标记' > \"\$TOOLCHAIN_DIR/stamp/.toolchain_compile\"" >> "$REPORT_FILE"
            echo "  echo '修复标记' > \"\$TOOLCHAIN_DIR/stamp/.binutils_installed\"" >> "$REPORT_FILE"
            echo "  touch \"\$TOOLCHAIN_DIR/stamp/.gcc_initial\"" >> "$REPORT_FILE"
            echo "  touch \"\$TOOLCHAIN_DIR/stamp/.gcc_final\"" >> "$REPORT_FILE"
            echo "  make toolchain/install -j2 V=s" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
        # GDB错误
        if grep -q "_GL_ATTRIBUTE_FORMAT_PRINTF" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 GDB编译错误修复:" >> "$REPORT_FILE"
            echo "  GDB_DIR=\$(find $BUILD_DIR/build_dir -name 'gdb-*' -type d | head -1)" >> "$REPORT_FILE"
            echo "  cd \"\$GDB_DIR\"" >> "$REPORT_FILE"
            echo "  sed -i '111s/#define ATTRIBUTE_PRINTF _GL_ATTRIBUTE_FORMAT_PRINTF/#define ATTRIBUTE_PRINTF(format_idx, arg_idx) __attribute__ ((__format__ (__printf__, format_idx, arg_idx)))/' gdbsupport/common-defs.h" >> "$REPORT_FILE"
            echo "  或者禁用GDB: echo '# CONFIG_PACKAGE_gdb is not set' >> $BUILD_DIR/.config" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
        # 头文件错误
        if grep -q "stdc-predef.h\|stdio.h" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 头文件缺失修复:" >> "$REPORT_FILE"
            echo "  mkdir -p $BUILD_DIR/staging_dir/host/include" >> "$REPORT_FILE"
            echo "  cp /usr/include/stdc-predef.h $BUILD_DIR/staging_dir/host/include/ 2>/dev/null || true" >> "$REPORT_FILE"
            echo "  echo '/* 最小头文件 */' > $BUILD_DIR/staging_dir/host/include/stdio.h" >> "$REPORT_FILE"
            echo "  echo '#ifndef _STDIO_H' >> $BUILD_DIR/staging_dir/host/include/stdio.h" >> "$REPORT_FILE"
            echo "  echo '#define _STDIO_H' >> $BUILD_DIR/staging_dir/host/include/stdio.h" >> "$REPORT_FILE"
            echo "  echo '#endif' >> $BUILD_DIR/staging_dir/host/include/stdio.h" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
        # 内存错误
        if grep -q "out of memory\|Killed process" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 内存不足修复:" >> "$REPORT_FILE"
            echo "  1. 减少并行任务: make -j1 V=s" >> "$REPORT_FILE"
            echo "  2. 增加交换空间:" >> "$REPORT_FILE"
            echo "     sudo fallocate -l 4G /swapfile" >> "$REPORT_FILE"
            echo "     sudo chmod 600 /swapfile" >> "$REPORT_FILE"
            echo "     sudo mkswap /swapfile" >> "$REPORT_FILE"
            echo "     sudo swapon /swapfile" >> "$REPORT_FILE"
            echo "  3. 清理内存缓存: sync && echo 3 | sudo tee /proc/sys/vm/drop_caches" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
    fi
    
    # USB配置建议
    if [ -f "$BUILD_DIR/.config" ]; then
        local usb_enabled=$(grep -c "^CONFIG_PACKAGE_kmod-usb.*=y" "$BUILD_DIR/.config" 2>/dev/null || echo "0")
        if [ $usb_enabled -lt 8 ]; then
            echo "🔧 USB配置建议:" >> "$REPORT_FILE"
            echo "  当前USB驱动较少，建议启用更多USB驱动:" >> "$REPORT_FILE"
            echo "  cd $BUILD_DIR && make menuconfig" >> "$REPORT_FILE"
            echo "  进入: Kernel modules -> USB Support" >> "$REPORT_FILE"
            echo "  启用: kmod-usb-core, kmod-usb2, kmod-usb3, kmod-usb-storage等" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
    fi
    
    # 系统依赖建议
    echo "🔧 系统依赖检查:" >> "$REPORT_FILE"
    echo "  建议安装以下构建依赖:" >> "$REPORT_FILE"
    echo "  sudo apt-get update" >> "$REPORT_FILE"
    echo "  sudo apt-get install build-essential libncurses5-dev gawk git libssl-dev gettext zlib1g-dev swig unzip time xsltproc python3 python3-setuptools rsync wget" >> "$REPORT_FILE"
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        echo "  sudo apt-get install libtool autoconf automake libltdl-dev pkg-config gettext texinfo" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 快速命令
    echo "🚀 快速修复命令:" >> "$REPORT_FILE"
    echo "  1. 一键清理重建: cd $BUILD_DIR && make clean && ./scripts/feeds update -a && ./scripts/feeds install -a && make defconfig && make -j2 V=s" >> "$REPORT_FILE"
    echo "  2. 仅重新编译: cd $BUILD_DIR && make -j1 V=s" >> "$REPORT_FILE"
    echo "  3. 修复工具链: firmware-config/scripts/build_firmware_main-01.sh fix_compiler_toolchain_error" >> "$REPORT_FILE"
    echo "  4. 修复GDB: firmware-config/scripts/build_firmware_main-01.sh fix_gdb_compilation_error" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# 11. 生成总结报告
generate_summary() {
    log "📋 生成分析总结..."
    
    print_header "分析总结"
    
    # 收集统计数据
    local firmware_exists=0
    local build_log_exists=0
    local config_exists=0
    local error_count=0
    local warning_count=0
    local staging_dir_exists=0
    
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        firmware_exists=1
    fi
    
    if [ -f "$BUILD_DIR/build.log" ]; then
        build_log_exists=1
        error_count=$(grep -c -i "error" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        warning_count=$(grep -c -i "warning" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
    fi
    
    if [ -f "$BUILD_DIR/.config" ]; then
        config_exists=1
    fi
    
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        staging_dir_exists=1
    fi
    
    echo "📊 构建状态概览:" >> "$REPORT_FILE"
    echo "  ✅ 构建目录: $(if [ -d "$BUILD_DIR" ]; then echo '存在'; else echo '缺失'; fi)" >> "$REPORT_FILE"
    echo "  ✅ 配置文件: $(if [ $config_exists -eq 1 ]; then echo '存在'; else echo '缺失'; fi)" >> "$REPORT_FILE"
    echo "  ✅ 构建日志: $(if [ $build_log_exists -eq 1 ]; then echo "存在 (错误: $error_count, 警告: $warning_count)"; else echo '缺失'; fi)" >> "$REPORT_FILE"
    echo "  ✅ 编译目录: $(if [ $staging_dir_exists -eq 1 ]; then echo '存在'; else echo '缺失'; fi)" >> "$REPORT_FILE"
    echo "  ✅ 固件生成: $(if [ $firmware_exists -eq 1 ]; then echo '成功'; else echo '失败'; fi)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 状态评估
    echo "📈 状态评估:" >> "$REPORT_FILE"
    if [ $firmware_exists -eq 1 ]; then
        echo "  🎉 状态: 构建成功！" >> "$REPORT_FILE"
        echo "  💡 建议: 固件已生成，可以准备刷机" >> "$REPORT_FILE"
    elif [ $error_count -eq 0 ] && [ $config_exists -eq 1 ]; then
        echo "  ⏳ 状态: 构建可能尚未开始或正在进行" >> "$REPORT_FILE"
        echo "  💡 建议: 开始编译或等待编译完成" >> "$REPORT_FILE"
    elif [ $error_count -lt 5 ]; then
        echo "  ⚠️  状态: 轻微问题" >> "$REPORT_FILE"
        echo "  💡 建议: 小问题，容易修复" >> "$REPORT_FILE"
    elif [ $error_count -lt 20 ]; then
        echo "  ⚠️  状态: 中等问题" >> "$REPORT_FILE"
        echo "  💡 建议: 需要一些修复工作" >> "$REPORT_FILE"
    elif [ $error_count -lt 100 ]; then
        echo "  🚨 状态: 严重问题" >> "$REPORT_FILE"
        echo "  💡 建议: 需要系统性的修复" >> "$REPORT_FILE"
    else
        echo "  💥 状态: 灾难性问题" >> "$REPORT_FILE"
        echo "  💡 建议: 建议从头开始重新构建" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 下一步行动
    echo "🚀 下一步行动建议:" >> "$REPORT_FILE"
    if [ $firmware_exists -eq 1 ]; then
        echo "  1. 📁 检查固件文件: ls -la $BUILD_DIR/bin/targets/" >> "$REPORT_FILE"
        echo "  2. 🔧 准备刷机工具" >> "$REPORT_FILE"
        echo "  3. 💾 备份原系统配置" >> "$REPORT_FILE"
        echo "  4. ⚡ 刷入新固件" >> "$REPORT_FILE"
    elif [ $error_count -gt 0 ]; then
        echo "  1. 🔍 查看上方错误详情" >> "$REPORT_FILE"
        echo "  2. 🛠️ 执行对应的修复方案" >> "$REPORT_FILE"
        echo "  3. 🔄 重新编译: cd $BUILD_DIR && make -j2 V=s" >> "$REPORT_FILE"
        echo "  4. 📊 监控进度: tail -f build.log" >> "$REPORT_FILE"
    else
        echo "  1. ⚙️ 检查配置: make menuconfig" >> "$REPORT_FILE"
        echo "  2. 🚀 开始编译: make -j2 V=s" >> "$REPORT_FILE"
        echo "  3. 📝 监控日志: tail -f build.log" >> "$REPORT_FILE"
        echo "  4. ⏳ 耐心等待编译完成" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    echo "==================================================" >> "$REPORT_FILE"
    echo "           🎯 分析完成 - 祝您构建顺利！         " >> "$REPORT_FILE"
    echo "==================================================" >> "$REPORT_FILE"
}

# 12. 输出报告并清理
output_report() {
    log "📄 输出分析报告..."
    
    # 显示报告
    echo ""
    echo "=================================================="
    echo "           OpenWrt构建错误分析报告               "
    echo "=================================================="
    echo ""
    
    # 显示关键信息
    if [ -f "$REPORT_FILE" ]; then
        # 显示报告头
        head -20 "$REPORT_FILE"
        echo ""
        echo "... (完整报告请看下方或保存的文件) ..."
        echo ""
        
        # 显示关键错误（如果有）
        if grep -q "❌" "$REPORT_FILE"; then
            echo "🚨 发现的关键问题:"
            grep "❌" "$REPORT_FILE" | head -10
            echo ""
        fi
        
        # 显示修复建议
        if grep -q "💡" "$REPORT_FILE"; then
            echo "💡 修复建议摘要:"
            grep "💡" "$REPORT_FILE" | head -5
            echo ""
        fi
        
        # 显示完整报告
        echo "📁 完整报告位置:"
        echo "  临时文件: $REPORT_FILE"
        echo "  备份文件: $BACKUP_FILE"
        echo ""
        
        # 复制备份
        cp "$REPORT_FILE" "$BACKUP_FILE"
        log "✅ 报告已保存到: $BACKUP_FILE"
        
    else
        echo "❌ 报告文件生成失败"
        return 1
    fi
    
    return 0
}

# 主执行函数
main() {
    log "🚀 开始OpenWrt构建错误分析"
    
    # 检查构建目录
    if [ ! -d "$BUILD_DIR" ]; then
        log "❌ 构建目录不存在: $BUILD_DIR"
        echo "错误: 构建目录 $BUILD_DIR 不存在" >&2
        return 1
    fi
    
    log "📁 构建目录: $BUILD_DIR"
    
    # 执行所有分析步骤
    init_report
    collect_system_info
    check_system_resources
    check_build_result
    analyze_config_file
    check_compiler_status
    analyze_build_log
    check_download_log
    analyze_version_specific
    generate_fix_suggestions
    generate_summary
    
    # 输出报告
    if output_report; then
        log "✅ 错误分析完成"
        
        # 根据构建结果返回状态码
        if [ -d "$BUILD_DIR/bin/targets" ]; then
            return 0  # 构建成功
        else
            return 1  # 构建失败
        fi
    else
        log "❌ 错误分析失败"
        return 2  # 分析失败
    fi
}

# 脚本入口
if [ "$0" = "$BASH_SOURCE" ] || [ -z "$BASH_SOURCE" ]; then
    main
    exit $?
fi
