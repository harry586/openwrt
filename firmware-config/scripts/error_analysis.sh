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

# 从环境文件加载环境变量 - 增强版
load_build_env() {
    local env_file="$BUILD_DIR/build_env.sh"
    if [ -f "$env_file" ]; then
        source "$env_file"
        log "✅ 从 $env_file 加载环境变量"
        
        # 显示关键环境变量
        echo "📌 构建环境变量:" >> "$REPORT_FILE"
        echo "  SELECTED_REPO_URL: $SELECTED_REPO_URL" >> "$REPORT_FILE"
        echo "  SELECTED_BRANCH: $SELECTED_BRANCH" >> "$REPORT_FILE"
        echo "  TARGET: $TARGET" >> "$REPORT_FILE"
        echo "  SUBTARGET: $SUBTARGET" >> "$REPORT_FILE"
        echo "  DEVICE: $DEVICE" >> "$REPORT_FILE"
        echo "  CONFIG_MODE: $CONFIG_MODE" >> "$REPORT_FILE"
        echo "  REPO_ROOT: $REPO_ROOT" >> "$REPORT_FILE"
        echo "  COMPILER_DIR: $COMPILER_DIR" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    else
        log "⚠️ 环境文件不存在: $env_file"
        echo "⚠️ 环境文件不存在: $env_file" >> "$REPORT_FILE"
        
        # 尝试从其他位置加载
        log "🔍 尝试从其他位置加载环境变量..."
        if [ -n "$GITHUB_ENV" ] && [ -f "$GITHUB_ENV" ]; then
            echo "💡 从GitHub环境变量文件加载..." >> "$REPORT_FILE"
            cat "$GITHUB_ENV" | grep -E "SELECTED|TARGET|DEVICE|COMPILER" >> "$REPORT_FILE"
        fi
        
        # 尝试手动查找编译器目录
        echo "🔍 手动搜索编译器目录..." >> "$REPORT_FILE"
        local found_compiler_dir=$(find "$BUILD_DIR" -name "toolchain-*" -type d 2>/dev/null | head -1)
        if [ -n "$found_compiler_dir" ]; then
            echo "  ✅ 找到编译器目录: $found_compiler_dir" >> "$REPORT_FILE"
            COMPILER_DIR="$found_compiler_dir"
        else
            echo "  ❌ 未找到编译器目录" >> "$REPORT_FILE"
        fi
    fi
}

# 1. 初始化报告
init_report() {
    log "📝 初始化错误分析报告..."
    mkdir -p "$ANALYSIS_DIR"
    
    echo "==================================================" > "$REPORT_FILE"
    echo "        🚨 OpenWrt固件构建错误分析报告           " >> "$REPORT_FILE"
    echo "==================================================" >> "$REPORT_FILE"
    echo "分析时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
    echo "报告时间戳: $TIMESTAMP" >> "$REPORT_FILE"
    echo "报告版本: 2.2.0" >> "$REPORT_FILE"
    echo "构建目录: $BUILD_DIR" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 加载构建环境变量
    load_build_env
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
    echo "  分析时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
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
    
    # 显示当前时间
    echo "🕐 当前时间:" >> "$REPORT_FILE"
    echo "  系统时间: $(date)" >> "$REPORT_FILE"
    echo "  时间戳: $TIMESTAMP" >> "$REPORT_FILE"
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
        
        # 检查是否有staging_dir目录
        if [ -d "$BUILD_DIR/staging_dir" ]; then
            echo "ℹ️  staging_dir目录存在，编译器已构建" >> "$REPORT_FILE"
        fi
    fi
    echo "" >> "$REPORT_FILE"
}

# 5. 分析配置文件（修复版）
analyze_config_file() {
    log "⚙️  分析配置文件..."
    
    print_subheader "配置文件分析"
    
    if [ -f "$BUILD_DIR/.config" ]; then
        # 检查配置文件是否为空
        if [ ! -s "$BUILD_DIR/.config" ]; then
            echo "❌ 配置文件状态: 存在但为空" >> "$REPORT_FILE"
            echo "💡 配置文件为空，可能是构建过程中出现问题" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            return
        fi
        
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
        if [ $total_configs -gt 0 ]; then
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
            
            # USB配置检查（简化版）
            print_subheader "关键USB配置状态"
            local critical_usb_drivers=("kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-storage")
            
            for driver in "${critical_usb_drivers[@]}"; do
                if grep -q "^CONFIG_PACKAGE_${driver}=y" "$BUILD_DIR/.config" 2>/dev/null; then
                    echo "✅ $driver: 已启用" >> "$REPORT_FILE"
                else
                    echo "❌ $driver: 未启用" >> "$REPORT_FILE"
                fi
            done
            echo "" >> "$REPORT_FILE"
        else
            echo "⚠️ 配置文件中没有找到任何配置项" >> "$REPORT_FILE"
        fi
        
    else
        echo "❌ 配置文件不存在: $BUILD_DIR/.config" >> "$REPORT_FILE"
        echo "💡 建议: 运行 make menuconfig 或 make defconfig 生成配置文件" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 6. 检查编译器状态（增强版 - 兼容GCC 8-15版本）
check_compiler_status() {
    log "🔧 检查编译器状态..."
    
    print_subheader "编译器状态检查"
    
    # 首先检查是否有下载的SDK编译器
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        echo "🎯 编译器来源: 预构建的OpenWrt SDK" >> "$REPORT_FILE"
        echo "📌 编译器目录: $COMPILER_DIR" >> "$REPORT_FILE"
        
        # 检查预构建编译器中的GCC版本
        local prebuilt_gcc=$(find "$COMPILER_DIR" -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          2>/dev/null | head -1)
        
        if [ -n "$prebuilt_gcc" ]; then
            echo "✅ 找到预构建GCC编译器: $(basename "$prebuilt_gcc")" >> "$REPORT_FILE"
            local prebuilt_version=$("$prebuilt_gcc" --version 2>&1 | head -1)
            echo "     版本: $prebuilt_version" >> "$REPORT_FILE"
            
            # 检查GCC版本兼容性
            local major_version=$(echo "$prebuilt_version" | grep -o "[0-9]\+" | head -1)
            if [ -n "$major_version" ]; then
                if [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                    echo "     ✅ GCC $major_version.x 版本兼容" >> "$REPORT_FILE"
                else
                    echo "     ⚠️ GCC版本 $major_version.x 可能不兼容（期望8-15）" >> "$REPORT_FILE"
                fi
            fi
        else
            echo "⚠️ 预构建目录中未找到真正的GCC编译器" >> "$REPORT_FILE"
        fi
    else
        echo "🛠️ 编译器来源: OpenWrt自动构建" >> "$REPORT_FILE"
        echo "💡 未找到预构建SDK编译器，将使用自动构建的编译器" >> "$REPORT_FILE"
    fi
    
    # 检查构建目录中的编译器
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        echo "✅ 编译目录存在: staging_dir" >> "$REPORT_FILE"
        
        # 检查工具链目录
        local toolchain_dirs=$(find "$BUILD_DIR/staging_dir" -name "toolchain-*" -type d 2>/dev/null | wc -l)
        echo "📊 工具链目录数: $toolchain_dirs" >> "$REPORT_FILE"
        
        if [ $toolchain_dirs -gt 0 ]; then
            local toolchain_dir=$(find "$BUILD_DIR/staging_dir" -name "toolchain-*" -type d 2>/dev/null | head -1)
            echo "🔍 工具链目录: $(basename "$toolchain_dir")" >> "$REPORT_FILE"
            
            # 检查真正的GCC编译器（排除工具链工具）
            echo "🔍 编译器详细检查:" >> "$REPORT_FILE"
            
            # 查找真正的gcc编译器（不是工具链工具）
            local real_gcc=$(find "$toolchain_dir/bin" -type f -executable \
              -name "*gcc" \
              ! -name "*gcc-ar" \
              ! -name "*gcc-ranlib" \
              ! -name "*gcc-nm" \
              ! -name "*-gcc-ar" \
              2>/dev/null | head -1)
            
            if [ -n "$real_gcc" ]; then
                echo "  ✅ 找到真正的GCC编译器: $(basename "$real_gcc")" >> "$REPORT_FILE"
                
                local version=$("$real_gcc" --version 2>&1 | head -1)
                echo "     版本: $version" >> "$REPORT_FILE"
                
                # 检查GCC版本兼容性（8-15）
                local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1)
                if [ -n "$major_version" ]; then
                    if [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                        echo "     ✅ GCC $major_version.x 版本兼容" >> "$REPORT_FILE"
                    else
                        echo "     ⚠️ GCC版本 $major_version.x 可能不兼容（期望8-15）" >> "$REPORT_FILE"
                    fi
                fi
            else
                echo "  ⚠️ 未找到真正的GCC编译器" >> "$REPORT_FILE"
            fi
            
        else
            echo "❌ 未找到工具链目录" >> "$REPORT_FILE"
            echo "💡 工具链可能尚未编译完成" >> "$REPORT_FILE"
        fi
        
    else
        echo "❌ 编译目录不存在: staging_dir" >> "$REPORT_FILE"
        echo "💡 构建可能尚未开始或已清理" >> "$REPORT_FILE"
    fi
    
    # 编译器版本详细检查
    print_subheader "编译器版本详细检查"
    
    # 查找所有可能的GCC编译器
    local all_gcc_files=$(find "$BUILD_DIR" -type f -executable \
      -name "*gcc" \
      ! -name "*gcc-ar" \
      ! -name "*gcc-ranlib" \
      ! -name "*gcc-nm" \
      2>/dev/null)
    
    local count=0
    if [ -n "$all_gcc_files" ]; then
        echo "🔍 找到的编译器文件:" >> "$REPORT_FILE"
        echo "$all_gcc_files" | head -5 | while read gcc_file; do
            count=$((count + 1))
            local version=$("$gcc_file" --version 2>&1 | head -1)
            local dir_name=$(dirname "$gcc_file")
            
            echo "  编译器 #$count:" >> "$REPORT_FILE"
            echo "      文件: $(basename "$gcc_file")" >> "$REPORT_FILE"
            echo "      目录: $(echo "$dir_name" | sed "s|$BUILD_DIR/||")" >> "$REPORT_FILE"
            echo "      版本: $version" >> "$REPORT_FILE"
            
            # 检查是否来自预构建目录
            if [ -n "$COMPILER_DIR" ] && [[ "$gcc_file" == *"$COMPILER_DIR"* ]]; then
                echo "      来源: 🎯 预构建SDK" >> "$REPORT_FILE"
            elif [[ "$gcc_file" == *"staging_dir"* ]]; then
                echo "      来源: 🛠️ 自动构建" >> "$REPORT_FILE"
            else
                echo "      来源: 🔍 其他位置" >> "$REPORT_FILE"
            fi
            
            echo "" >> "$REPORT_FILE"
        done
    else
        echo "  ⚠️ 未找到任何GCC编译器文件" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# 7. 分析构建日志（修复版）
analyze_build_log() {
    log "📝 分析构建日志..."
    
    print_subheader "构建日志分析"
    
    if [ -f "$BUILD_DIR/build.log" ]; then
        # 检查日志文件是否为空
        if [ ! -s "$BUILD_DIR/build.log" ]; then
            echo "❌ 构建日志状态: 存在但为空" >> "$REPORT_FILE"
            echo "💡 构建日志为空，可能是构建过程被中断" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            return
        fi
        
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
            echo "🔴 严重错误 (前10个):" >> "$REPORT_FILE"
            grep -i "error" "$BUILD_DIR/build.log" | grep -v "ignored" | head -10 >> "$REPORT_FILE" || echo "  无严重错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🟡 Makefile错误:" >> "$REPORT_FILE"
            grep -i "make.*error\|recipe for target.*failed" "$BUILD_DIR/build.log" | head -5 >> "$REPORT_FILE" || echo "  无Makefile错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🔵 编译器错误:" >> "$REPORT_FILE"
            grep -i "gcc.*error\|ld.*error\|collect2.*error" "$BUILD_DIR/build.log" | head -5 >> "$REPORT_FILE" || echo "  无编译器错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🟣 文件缺失错误:" >> "$REPORT_FILE"
            grep -i "no such file\|file not found\|cannot find" "$BUILD_DIR/build.log" | head -5 >> "$REPORT_FILE" || echo "  无文件缺失错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🟠 依赖错误:" >> "$REPORT_FILE"
            grep -i "depends on\|missing dependencies\|undefined reference" "$BUILD_DIR/build.log" | head -5 >> "$REPORT_FILE" || echo "  无依赖错误" >> "$REPORT_FILE"
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
            
            # 编译器版本错误
            if grep -q "requires gcc\|gcc version" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "❌ 检测到编译器版本错误" >> "$REPORT_FILE"
                echo "💡 可能是GCC版本不匹配" >> "$REPORT_FILE"
                echo "🛠️ 修复方法: 使用GCC 8-15版本" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
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
        # 检查日志文件是否为空
        if [ ! -s "$BUILD_DIR/download.log" ]; then
            echo "ℹ️ 下载日志文件存在但为空" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            return
        fi
        
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
    
    if [ -n "$SELECTED_BRANCH" ]; then
        echo "📌 当前OpenWrt版本: $SELECTED_BRANCH" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            echo "🔧 OpenWrt 23.05 版本特性:" >> "$REPORT_FILE"
            echo "  编译器: GCC 11.3.0 或更高" >> "$REPORT_FILE"
            echo "  内核: Linux 5.15" >> "$REPORT_FILE"
            echo "  musl: 1.2.3" >> "$REPORT_FILE"
            echo "  binutils: 2.38" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "⚠️ 常见问题:" >> "$REPORT_FILE"
            echo "  1. GDB _GL_ATTRIBUTE_FORMAT_PRINTF 错误" >> "$REPORT_FILE"
            echo "  2. 工具链构建错误 (toolchain/Makefile:93)" >> "$REPORT_FILE"
            echo "  3. 头文件缺失问题" >> "$REPORT_FILE"
            echo "  4. libtool版本兼容性问题" >> "$REPORT_FILE"
            echo "  5. 编译器版本兼容性问题 (支持GCC 8-15)" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🛠️ 解决方案:" >> "$REPORT_FILE"
            echo "  1. 修复GDB源码: 修改gdbsupport/common-defs.h" >> "$REPORT_FILE"
            echo "  2. 创建stamp标记文件" >> "$REPORT_FILE"
            echo "  3. 安装libtool和autoconf" >> "$REPORT_FILE"
            echo "  4. 设置-fpermissive编译标志" >> "$REPORT_FILE"
            echo "  5. 确保使用GCC 8-15版本编译器" >> "$REPORT_FILE"
            
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
            echo "ℹ️ 当前版本分支: $SELECTED_BRANCH" >> "$REPORT_FILE"
            echo "💡 请参考官方文档获取版本特定信息" >> "$REPORT_FILE"
        fi
    else
        echo "⚠️ 版本分支未设置" >> "$REPORT_FILE"
        echo "💡 请检查环境变量设置" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 10. 新增：详细错误分析函数
analyze_detailed_errors() {
    log "🔍 执行详细错误分析..."
    
    print_subheader "详细错误分析"
    
    # 检查构建日志中的具体错误
    if [ -f "$BUILD_DIR/build.log" ]; then
        echo "📊 构建日志错误详细分析:" >> "$REPORT_FILE"
        
        # 1. 编译器相关错误
        echo "🔧 1. 编译器相关错误:" >> "$REPORT_FILE"
        local compiler_errors=$(grep -i "gcc.*error\|ld.*error\|collect2.*error\|undefined reference" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$compiler_errors" ]; then
            echo "$compiler_errors" >> "$REPORT_FILE"
            
            # 分析常见编译器错误
            echo "💡 编译器错误分析:" >> "$REPORT_FILE"
            if echo "$compiler_errors" | grep -q "undefined reference"; then
                echo "  ❌ 未定义引用错误: 可能是库文件缺失或链接顺序问题" >> "$REPORT_FILE"
                echo "  🛠️ 修复: 检查依赖库是否正确安装，调整链接顺序" >> "$REPORT_FILE"
            fi
            
            if echo "$compiler_errors" | grep -q "No such file"; then
                echo "  ❌ 文件不存在错误: 头文件或源文件缺失" >> "$REPORT_FILE"
                echo "  🛠️ 修复: 检查文件路径，确保所有依赖文件已下载" >> "$REPORT_FILE"
            fi
            
            if echo "$compiler_errors" | grep -q "multiple definition"; then
                echo "  ❌ 多重定义错误: 同一个符号被多次定义" >> "$REPORT_FILE"
                echo "  🛠️ 修复: 检查是否有重复的源文件或库" >> "$REPORT_FILE"
            fi
        else
            echo "  无编译器相关错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 2. 头文件缺失错误
        echo "📄 2. 头文件缺失错误:" >> "$REPORT_FILE"
        local header_errors=$(grep -i "stdc-predef.h\|stdio.h\|stdlib.h\|.*\.h: No such file" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$header_errors" ]; then
            echo "$header_errors" >> "$REPORT_FILE"
            echo "💡 头文件错误分析:" >> "$REPORT_FILE"
            echo "  ❌ 标准头文件缺失" >> "$REPORT_FILE"
            echo "  🛠️ 修复: 创建host/include目录并复制头文件" >> "$REPORT_FILE"
            echo "    mkdir -p $BUILD_DIR/staging_dir/host/include" >> "$REPORT_FILE"
            echo "    touch $BUILD_DIR/staging_dir/host/include/stdc-predef.h" >> "$REPORT_FILE"
            echo "    touch $BUILD_DIR/staging_dir/host/include/stdio.h" >> "$REPORT_FILE"
            echo "    touch $BUILD_DIR/staging_dir/host/include/stdlib.h" >> "$REPORT_FILE"
        else
            echo "  无头文件缺失错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 3. 下载错误
        echo "📥 3. 下载错误:" >> "$REPORT_FILE"
        local download_errors=$(grep -i "404\|Failed\|timeout\|connection refused\|SSL_ERROR" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$download_errors" ]; then
            echo "$download_errors" >> "$REPORT_FILE"
            echo "💡 下载错误分析:" >> "$REPORT_FILE"
            echo "  ❌ 网络下载问题" >> "$REPORT_FILE"
            echo "  🛠️ 修复:" >> "$REPORT_FILE"
            echo "    1. 检查网络连接" >> "$REPORT_FILE"
            echo "    2. 配置代理服务器" >> "$REPORT_FILE"
            echo "    3. 手动下载缺失文件到dl目录" >> "$REPORT_FILE"
            echo "    4. 禁用SSL验证: export GIT_SSL_NO_VERIFY=1" >> "$REPORT_FILE"
        else
            echo "  无下载错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 4. 权限错误
        echo "🔐 4. 权限错误:" >> "$REPORT_FILE"
        local permission_errors=$(grep -i "permission denied\|cannot create\|read-only\|Operation not permitted" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$permission_errors" ]; then
            echo "$permission_errors" >> "$REPORT_FILE"
            echo "💡 权限错误分析:" >> "$REPORT_FILE"
            echo "  ❌ 文件系统权限问题" >> "$REPORT_FILE"
            echo "  🛠️ 修复:" >> "$REPORT_FILE"
            echo "    1. 检查目录权限: ls -la $BUILD_DIR" >> "$REPORT_FILE"
            echo "    2. 修复权限: chmod -R 755 $BUILD_DIR" >> "$REPORT_FILE"
            echo "    3. 修复所有者: chown -R $(whoami) $BUILD_DIR" >> "$REPORT_FILE"
            echo "    4. 检查磁盘是否只读" >> "$REPORT_FILE"
        else
            echo "  无权限错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 5. 内存不足错误
        echo "💾 5. 内存不足错误:" >> "$REPORT_FILE"
        local memory_errors=$(grep -i "out of memory\|Killed process\|terminated\|oom\|swap" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$memory_errors" ]; then
            echo "$memory_errors" >> "$REPORT_FILE"
            echo "💡 内存错误分析:" >> "$REPORT_FILE"
            echo "  ❌ 系统内存或交换空间不足" >> "$REPORT_FILE"
            echo "  🛠️ 修复:" >> "$REPORT_FILE"
            echo "    1. 增加交换空间" >> "$REPORT_FILE"
            echo "    2. 减少并行编译任务: make -j1 V=s" >> "$REPORT_FILE"
            echo "    3. 关闭其他占用内存的程序" >> "$REPORT_FILE"
            echo "    4. 增加物理内存" >> "$REPORT_FILE"
        else
            echo "  无内存错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 6. 特定包编译错误
        echo "📦 6. 特定包编译错误:" >> "$REPORT_FILE"
        local package_errors=$(grep -i "package/.*failed\|recipe for target.*failed\|Error .* in package" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$package_errors" ]; then
            echo "$package_errors" >> "$REPORT_FILE"
            echo "💡 包编译错误分析:" >> "$REPORT_FILE"
            echo "  ❌ 特定软件包编译失败" >> "$REPORT_FILE"
            echo "  🛠️ 修复:" >> "$REPORT_FILE"
            echo "    1. 禁用该包: 在配置中取消选择" >> "$REPORT_FILE"
            echo "    2. 检查包依赖: 确保所有依赖已安装" >> "$REPORT_FILE"
            echo "    3. 查看具体包的错误日志" >> "$REPORT_FILE"
            echo "    4. 更新feeds: ./scripts/feeds update -a" >> "$REPORT_FILE"
        else
            echo "  无特定包编译错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 7. 磁盘空间错误
        echo "💿 7. 磁盘空间错误:" >> "$REPORT_FILE"
        local disk_errors=$(grep -i "no space left\|disk full\|write error\|ENOSPC" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$disk_errors" ]; then
            echo "$disk_errors" >> "$REPORT_FILE"
            echo "💡 磁盘空间错误分析:" >> "$REPORT_FILE"
            echo "  ❌ 磁盘空间不足" >> "$REPORT_FILE"
            echo "  🛠️ 修复:" >> "$REPORT_FILE"
            echo "    1. 清理临时文件: rm -rf $BUILD_DIR/tmp" >> "$REPORT_FILE"
            echo "    2. 清理构建缓存: rm -rf $BUILD_DIR/build_dir" >> "$REPORT_FILE"
            echo "    3. 扩展磁盘空间" >> "$REPORT_FILE"
            echo "    4. 使用更大的磁盘" >> "$REPORT_FILE"
        else
            echo "  无磁盘空间错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 8. 时间戳错误
        echo "🕐 8. 时间戳错误:" >> "$REPORT_FILE"
        local timestamp_errors=$(grep -i "clock skew\|time stamp\|timestamp" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$timestamp_errors" ]; then
            echo "$timestamp_errors" >> "$REPORT_FILE"
            echo "💡 时间戳错误分析:" >> "$REPORT_FILE"
            echo "  ❌ 文件时间戳不一致" >> "$REPORT_FILE"
            echo "  🛠️ 修复:" >> "$REPORT_FILE"
            echo "    1. 同步系统时间" >> "$REPORT_FILE"
            echo "    2. 修复文件时间戳: find $BUILD_DIR -type f -exec touch {} \;" >> "$REPORT_FILE"
            echo "    3. 禁用时间戳检查" >> "$REPORT_FILE"
        else
            echo "  无时间戳错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
    else
        echo "❌ 构建日志文件不存在，无法进行详细错误分析" >> "$REPORT_FILE"
    fi
}

# 11. 生成修复建议
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
    
    # 检查常见的文件缺失错误
    if [ -f "$BUILD_DIR/build.log" ] && [ -s "$BUILD_DIR/build.log" ]; then
        if grep -q "No such file or directory" "$BUILD_DIR/build.log"; then
            echo "🔧 文件缺失错误修复:" >> "$REPORT_FILE"
            echo "  💡 发现文件缺失错误，可能是编译过程中文件下载不完整" >> "$REPORT_FILE"
            echo "  🛠️ 修复方法: 重新下载依赖包" >> "$REPORT_FILE"
            echo "    cd $BUILD_DIR && make download -j4 V=s" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
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
        
        # 编译器版本错误
        if grep -q "requires gcc\|gcc version" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 编译器版本错误修复:" >> "$REPORT_FILE"
            echo "  💡 检测到GCC版本兼容性问题" >> "$REPORT_FILE"
            echo "  🛠️ 修复方法:" >> "$REPORT_FILE"
            echo "    1. 检查当前GCC版本: gcc --version" >> "$REPORT_FILE"
            echo "    2. 确保使用GCC 8-15版本" >> "$REPORT_FILE"
            echo "    3. 如果使用预构建编译器，验证编译器目录是否正确" >> "$REPORT_FILE"
            echo "    4. 检查预构建编译器是否是真正的GCC编译器，而不是工具链工具" >> "$REPORT_FILE"
            echo "    5. 使用两步搜索法查找正确的编译器目录" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
        # 内存不足错误
        if grep -q "out of memory\|Killed process" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 内存不足错误修复:" >> "$REPORT_FILE"
            echo "  💡 检测到内存不足问题" >> "$REPORT_FILE"
            echo "  🛠️ 修复方法:" >> "$REPORT_FILE"
            echo "    1. 增加交换空间:" >> "$REPORT_FILE"
            echo "      sudo fallocate -l 4G /swapfile" >> "$REPORT_FILE"
            echo "      sudo chmod 600 /swapfile" >> "$REPORT_FILE"
            echo "      sudo mkswap /swapfile" >> "$REPORT_FILE"
            echo "      sudo swapon /swapfile" >> "$REPORT_FILE"
            echo "    2. 减少并行编译任务: make -j1 V=s" >> "$REPORT_FILE"
            echo "    3. 关闭其他占用内存的程序" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
        # 磁盘空间错误
        if grep -q "no space left\|disk full" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 磁盘空间错误修复:" >> "$REPORT_FILE"
            echo "  💡 检测到磁盘空间不足" >> "$REPORT_FILE"
            echo "  🛠️ 修复方法:" >> "$REPORT_FILE"
            echo "    1. 清理临时文件:" >> "$REPORT_FILE"
            echo "      rm -rf $BUILD_DIR/tmp/*" >> "$REPORT_FILE"
            echo "      rm -rf $BUILD_DIR/build_dir/*" >> "$REPORT_FILE"
            echo "      rm -rf $BUILD_DIR/staging_dir/*" >> "$REPORT_FILE"
            echo "    2. 清理下载缓存:" >> "$REPORT_FILE"
            echo "      rm -rf $BUILD_DIR/dl/*.tar.*" >> "$REPORT_FILE"
            echo "    3. 扩展磁盘空间" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
    fi
    
    # 系统依赖建议
    echo "🔧 系统依赖检查:" >> "$REPORT_FILE"
    echo "  建议安装以下构建依赖:" >> "$REPORT_FILE"
    echo "  sudo apt-get update" >> "$REPORT_FILE"
    echo "  sudo apt-get install build-essential libncurses5-dev gawk git libssl-dev gettext zlib1g-dev swig unzip time xsltproc python3 python3-setuptools rsync wget" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 快速命令
    echo "🚀 快速修复命令:" >> "$REPORT_FILE"
    echo "  1. 一键清理重建: cd $BUILD_DIR && make clean && ./scripts/feeds update -a && ./scripts/feeds install -a && make defconfig && make -j2 V=s" >> "$REPORT_FILE"
    echo "  2. 仅重新编译: cd $BUILD_DIR && make -j1 V=s" >> "$REPORT_FILE"
    echo "  3. 重新搜索编译器: firmware-config/scripts/build_firmware_main.sh initialize_compiler_env [设备名]" >> "$REPORT_FILE"
    echo "  4. 修复头文件: mkdir -p staging_dir/host/include && touch staging_dir/host/include/stdc-predef.h" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# 12. 生成总结报告
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
    
    if [ -f "$BUILD_DIR/build.log" ] && [ -s "$BUILD_DIR/build.log" ]; then
        build_log_exists=1
        error_count=$(grep -c -i "error" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        warning_count=$(grep -c -i "warning" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
    fi
    
    if [ -f "$BUILD_DIR/.config" ] && [ -s "$BUILD_DIR/.config" ]; then
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
    
    # 编译器来源分析
    print_subheader "编译器来源分析"
    
    # 检查预构建编译器使用情况
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        echo "  🎯 编译器来源: 预构建的OpenWrt SDK" >> "$REPORT_FILE"
        echo "  📌 编译器目录: $COMPILER_DIR" >> "$REPORT_FILE"
        
        # 检查是否实际使用了预构建编译器
        if [ -f "$BUILD_DIR/build.log" ] && [ -s "$BUILD_DIR/build.log" ]; then
            local prebuilt_calls=$(grep -c "$COMPILER_DIR" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
            if [ $prebuilt_calls -gt 0 ]; then
                echo "  ✅ 构建中使用了预构建SDK编译器" >> "$REPORT_FILE"
                echo "     调用次数: $prebuilt_calls" >> "$REPORT_FILE"
            else
                echo "  🔄 构建中未使用预构建SDK编译器" >> "$REPORT_FILE"
                echo "  💡 可能使用了自动构建的编译器" >> "$REPORT_FILE"
            fi
        else
            echo "  ℹ️ 无法确定编译器使用情况（无构建日志）" >> "$REPORT_FILE"
        fi
    else
        echo "  🛠️ 编译器来源: OpenWrt自动构建" >> "$REPORT_FILE"
        echo "  💡 未使用预构建SDK编译器" >> "$REPORT_FILE"
    fi
    
    # SDK编译器信息
    if [ -n "$SELECTED_BRANCH" ]; then
        echo "  📌 OpenWrt版本: $SELECTED_BRANCH" >> "$REPORT_FILE"
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            echo "  🔧 SDK编译器: GCC 11.3.0" >> "$REPORT_FILE"
        elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
            echo "  🔧 SDK编译器: GCC 8.4.0" >> "$REPORT_FILE"
        fi
    fi
    
    # 状态评估
    echo "" >> "$REPORT_FILE"
    print_subheader "状态评估"
    
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
    print_subheader "下一步行动建议"
    
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

# 13. 输出报告并清理
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
        
        # 显示编译器相关信息
        echo "🔧 编译器信息:"
        if grep -q "预构建的OpenWrt SDK" "$REPORT_FILE"; then
            echo "  🎯 使用预构建的OpenWrt SDK编译器"
        elif grep -q "OpenWrt自动构建" "$REPORT_FILE"; then
            echo "  🛠️ 使用OpenWrt自动构建的编译器"
        fi
        
        # 显示SDK版本信息
        if grep -q "OpenWrt版本:" "$REPORT_FILE"; then
            grep "OpenWrt版本:" "$REPORT_FILE"
        fi
        
        # 显示时间信息
        echo ""
        echo "🕐 时间信息:"
        echo "  分析时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  报告时间戳: $TIMESTAMP"
        echo ""
        
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
    echo "分析开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "构建目录: $BUILD_DIR"
    
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
    
    # 新增：详细错误分析
    analyze_detailed_errors
    
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
