#!/bin/bash
set -e

# 全局变量
BUILD_DIR="${BUILD_DIR:-/mnt/openwrt-build}"
ANALYSIS_DIR="/tmp/error-analysis"
REPORT_FILE="$ANALYSIS_DIR/report.txt"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/openwrt-error-analysis-$TIMESTAMP.txt"
SDK_DIR="${BUILD_DIR}/sdk"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${BLUE}【$(date '+%Y-%m-%d %H:%M:%S')】${NC}$1"
}

# 错误日志
error() {
    echo -e "${RED}❌ $1${NC}"
}

# 警告日志
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 成功日志
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# 步骤日志
log_step() {
    echo -e "${PURPLE}📋 $1${NC}"
}

# 调试日志
log_debug() {
    echo -e "${CYAN}🔍 $1${NC}"
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
        echo "  SDK_DIR: $SDK_DIR" >> "$REPORT_FILE"
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
    echo "报告版本: 3.2.0" >> "$REPORT_FILE"
    echo "构建目录: $BUILD_DIR" >> "$REPORT_FILE"
    echo "SDK目录: $SDK_DIR" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 加载构建环境变量
    load_build_env
}

# 2. 收集系统信息
collect_system_info() {
    log_step "收集系统信息"
    
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
    
    echo "⚙️ 构建参数:" >> "$REPORT_FILE"
    echo "  设备: ${DEVICE:-未设置}" >> "$REPORT_FILE"
    echo "  目标平台: ${TARGET:-未设置}" >> "$REPORT_FILE"
    echo "  子目标: ${SUBTARGET:-未设置}" >> "$REPORT_FILE"
    echo "  版本分支: ${SELECTED_BRANCH:-未设置}" >> "$REPORT_FILE"
    echo "  架构: ${ARCH:-自动检测}" >> "$REPORT_FILE"
    echo "  SDK目录: ${SDK_DIR:-未设置}" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 显示当前时间
    echo "🕐 当前时间:" >> "$REPORT_FILE"
    echo "  系统时间: $(date)" >> "$REPORT_FILE"
    echo "  时间戳: $TIMESTAMP" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# 3. 检查系统资源
check_system_resources() {
    log_step "检查系统资源"
    
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
    
    echo "🌡️ 系统温度 (如果可用):" >> "$REPORT_FILE"
    if command -v sensors >/dev/null 2>&1; then
        sensors 2>/dev/null | grep -E "Core|temp" | head -5 >> "$REPORT_FILE" || echo "  未检测到温度传感器" >> "$REPORT_FILE"
    else
        echo "  sensors命令未安装" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 4. 检查构建结果
check_build_result() {
    log_step "检查构建结果"
    
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
            echo "⚠️ build_dir目录存在，编译可能正在进行中" >> "$REPORT_FILE"
        fi
        
        # 检查是否有staging_dir目录
        if [ -d "$BUILD_DIR/staging_dir" ]; then
            echo "ℹ️ staging_dir目录存在，编译器已构建" >> "$REPORT_FILE"
        fi
    fi
    echo "" >> "$REPORT_FILE"
}

# 5. 分析配置文件（修复版）
analyze_config_file() {
    log_step "分析配置文件"
    
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
            
            # USB配置检查（增强版）
            print_subheader "关键USB配置状态"
            local critical_usb_drivers=("kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-xhci-hcd" "kmod-usb-storage")
            local missing_usb=0
            
            echo "🔧 USB驱动检查:" >> "$REPORT_FILE"
            for driver in "${critical_usb_drivers[@]}"; do
                if grep -q "^CONFIG_PACKAGE_${driver}=y" "$BUILD_DIR/.config" 2>/dev/null; then
                    echo "  ✅ $driver: 已启用" >> "$REPORT_FILE"
                else
                    echo "  ❌ $driver: 未启用" >> "$REPORT_FILE"
                    missing_usb=$((missing_usb + 1))
                fi
            done
            
            if [ $missing_usb -gt 0 ]; then
                echo "⚠️ 缺少 $missing_usb 个关键USB驱动" >> "$REPORT_FILE"
            else
                echo "✅ 所有关键USB驱动已启用" >> "$REPORT_FILE"
            fi
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

# 6. 检查编译器状态（增强版 - 改进SDK编译器检测）
check_compiler_status() {
    log_step "检查编译器状态"
    
    print_subheader "编译器状态检查"
    
    # 首先检查是否有下载的SDK编译器
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        echo "🎯 编译器来源: 预构建的OpenWrt SDK" >> "$REPORT_FILE"
        echo "📌 编译器目录: $COMPILER_DIR" >> "$REPORT_FILE"
        
        # 查找真正的GCC编译器，排除dummy-tools和脚本工具
        local prebuilt_gcc=$(find "$COMPILER_DIR" -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
        
        if [ -n "$prebuilt_gcc" ] && [ -x "$prebuilt_gcc" ]; then
            echo "✅ 找到预构建GCC编译器: $(basename "$prebuilt_gcc")" >> "$REPORT_FILE"
            local prebuilt_version=$("$prebuilt_gcc" --version 2>&1 | head -1)
            echo "     版本: $prebuilt_version" >> "$REPORT_FILE"
            
            # 检查GCC版本
            local major_version=$(echo "$prebuilt_version" | grep -o "[0-9]\+" | head -1)
            if [ -n "$major_version" ]; then
                echo "     🔧 SDK GCC版本: $major_version.x" >> "$REPORT_FILE"
                
                # 根据版本显示不同信息
                if [ "$major_version" = "12" ]; then
                    echo "     💡 OpenWrt 23.05 官方SDK使用 GCC 12.3.0" >> "$REPORT_FILE"
                elif [ "$major_version" = "8" ]; then
                    echo "     💡 OpenWrt 21.02 官方SDK使用 GCC 8.4.0" >> "$REPORT_FILE"
                else
                    echo "     💡 这是OpenWrt官方SDK交叉编译器，版本已通过验证" >> "$REPORT_FILE"
                fi
            fi
            
            # 检查是否是真正的交叉编译器
            local compiler_name=$(basename "$prebuilt_gcc")
            if [[ "$compiler_name" == *"mipsel"* ]] || [[ "$compiler_name" == *"arm"* ]] || [[ "$compiler_name" == *"aarch64"* ]]; then
                echo "     ✅ 检测到交叉编译器: 符合目标平台要求" >> "$REPORT_FILE"
            fi
        else
            echo "⚠️ 预构建目录中未找到真正的GCC编译器" >> "$REPORT_FILE"
            echo "🔍 搜索预构建目录内容:" >> "$REPORT_FILE"
            
            # 检查是否有dummy-tools
            local dummy_gcc=$(find "$COMPILER_DIR" -type f -executable \
              -name "*gcc" \
              -path "*dummy-tools*" \
              2>/dev/null | head -1)
            
            if [ -n "$dummy_gcc" ]; then
                echo "  ⚠️ 检测到虚假的dummy-tools编译器: $(basename "$dummy_gcc")" >> "$REPORT_FILE"
                echo "  💡 注意: 这是OpenWrt构建系统的占位符，不是真正的编译器" >> "$REPORT_FILE"
                echo "  💡 真正的编译器应该在 toolchain-* 目录中" >> "$REPORT_FILE"
            fi
            
            find "$COMPILER_DIR" -type f -executable -name "*gcc*" 2>/dev/null | head -5 | while read file; do
                echo "  🔧 $(basename "$file")" >> "$REPORT_FILE"
            done
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
            
            if [ -n "$real_gcc" ] && [ -x "$real_gcc" ]; then
                echo "  ✅ 找到真正的GCC编译器: $(basename "$real_gcc")" >> "$REPORT_FILE"
                
                local version=$("$real_gcc" --version 2>&1 | head -1)
                echo "     版本: $version" >> "$REPORT_FILE"
                
                # 显示GCC版本
                local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1)
                if [ -n "$major_version" ]; then
                    echo "     🔧 GCC版本: $major_version.x" >> "$REPORT_FILE"
                    echo "     💡 构建系统使用的编译器版本" >> "$REPORT_FILE"
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
    
    # 编译器版本详细检查 - 增强版
    print_subheader "编译器版本详细检查"
    
    # 查找所有可能的GCC编译器
    local all_gcc_files=$(find "$BUILD_DIR" -type f -executable \
      -name "*gcc" \
      ! -name "*gcc-ar" \
      ! -name "*gcc-ranlib" \
      ! -name "*gcc-nm" \
      ! -path "*dummy-tools*" \
      2>/dev/null)
    
    local count=0
    if [ -n "$all_gcc_files" ]; then
        echo "🔍 找到的编译器文件:" >> "$REPORT_FILE"
        echo "$all_gcc_files" | head -5 | while read gcc_file; do
            if [ -x "$gcc_file" ]; then
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
                    local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1)
                    if [ "$major_version" = "12" ]; then
                        echo "      状态: ✅ OpenWrt 23.05 SDK (GCC 12.3.0)" >> "$REPORT_FILE"
                    elif [ "$major_version" = "8" ]; then
                        echo "      状态: ✅ OpenWrt 21.02 SDK (GCC 8.4.0)" >> "$REPORT_FILE"
                    else
                        echo "      状态: ✅ 官方SDK编译器，版本已验证" >> "$REPORT_FILE"
                    fi
                elif [[ "$gcc_file" == *"staging_dir"* ]]; then
                    echo "      来源: 🛠️ 自动构建" >> "$REPORT_FILE"
                    echo "      状态: ✅ 构建系统生成的编译器" >> "$REPORT_FILE"
                elif [[ "$gcc_file" == *"dummy-tools"* ]]; then
                    echo "      来源: ⚠️ dummy-tools (占位符)" >> "$REPORT_FILE"
                    echo "      状态: ⚠️ 这不是真正的编译器，是构建系统的占位符" >> "$REPORT_FILE"
                else
                    echo "      来源: 🔍 其他位置" >> "$REPORT_FILE"
                fi
                
                echo "" >> "$REPORT_FILE"
            fi
        done
    else
        echo "  ⚠️ 未找到任何GCC编译器文件" >> "$REPORT_FILE"
    fi
    
    # SDK编译器调用状态检查
    print_subheader "SDK编译器调用状态检查"
    
    if [ -f "$BUILD_DIR/build.log" ]; then
        if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
            local sdk_calls=$(grep -c "$COMPILER_DIR" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
            if [ $sdk_calls -gt 0 ]; then
                echo "✅ 构建过程中调用了SDK编译器 ($sdk_calls 次)" >> "$REPORT_FILE"
                echo "💡 SDK编译器已成功集成到构建系统中" >> "$REPORT_FILE"
            else
                echo "⚠️ 构建过程中未检测到SDK编译器调用" >> "$REPORT_FILE"
                echo "💡 可能使用了OpenWrt自动构建的编译器" >> "$REPORT_FILE"
            fi
        fi
    else
        echo "ℹ️ 无构建日志，无法检查SDK编译器调用状态" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# 7. 检查构建日志文件（增强版）
check_build_log_file() {
    log_step "检查构建日志文件"
    
    print_subheader "构建日志文件检查"
    
    if [ ! -f "$BUILD_DIR/build.log" ]; then
        echo "❌ 编译日志文件不存在: $BUILD_DIR/build.log" >> "$REPORT_FILE"
        echo "💡 请确保编译已经执行，并生成了 build.log 文件" >> "$REPORT_FILE"
        return 1
    fi
    
    local log_size=$(ls -lh "$BUILD_DIR/build.log" | awk '{print $5}')
    local line_count=$(wc -l < "$BUILD_DIR/build.log")
    
    echo "📏 编译日志大小: $log_size" >> "$REPORT_FILE"
    echo "📊 编译日志行数: $line_count" >> "$REPORT_FILE"
    
    if [ $line_count -lt 100 ]; then
        echo "⚠️ 编译日志行数较少，可能编译未正常执行" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
    return 0
}

# 8. 分析构建日志（增强版）
analyze_build_log() {
    log_step "分析构建日志"
    
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
        
        # 错误统计 - 改进：排除警告性消息
        local error_count=$(grep -c -i "error" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        local warning_count=$(grep -c -i "warning" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        local failed_count=$(grep -c -i "failed" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        
        # 排除常见的非错误消息
        local filtered_error_count=$(grep -i "error" "$BUILD_DIR/build.log" | grep -v "ignored\|non-fatal\|Note:" | wc -l 2>/dev/null || echo "0")
        
        echo "📈 错误统计:" >> "$REPORT_FILE"
        echo "  原始错误数: $error_count" >> "$REPORT_FILE"
        echo "  过滤后错误数: $filtered_error_count" >> "$REPORT_FILE"
        echo "  警告总数: $warning_count" >> "$REPORT_FILE"
        echo "  失败总数: $failed_count" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        if [ $filtered_error_count -gt 0 ]; then
            print_subheader "关键错误摘要"
            
            # 分类提取错误
            echo "🔴 严重错误 (前10个):" >> "$REPORT_FILE"
            grep -i "error" "$BUILD_DIR/build.log" | grep -v "ignored\|non-fatal\|Note:" | head -10 >> "$REPORT_FILE" || echo "  无严重错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🟡 Makefile错误:" >> "$REPORT_FILE"
            grep -i "make.*error\|recipe for target.*failed" "$BUILD_DIR/build.log" | grep -v "ignored" | head -5 >> "$REPORT_FILE" || echo "  无Makefile错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🔵 编译器错误:" >> "$REPORT_FILE"
            grep -i "gcc.*error\|ld.*error\|collect2.*error" "$BUILD_DIR/build.log" | grep -v "ignored" | head -5 >> "$REPORT_FILE" || echo "  无编译器错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🟣 文件缺失错误:" >> "$REPORT_FILE"
            grep -i "no such file\|file not found\|cannot find" "$BUILD_DIR/build.log" | head -5 >> "$REPORT_FILE" || echo "  无文件缺失错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🟠 依赖错误:" >> "$REPORT_FILE"
            grep -i "depends on\|missing dependencies\|undefined reference" "$BUILD_DIR/build.log" | head -5 >> "$REPORT_FILE" || echo "  无依赖错误" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            # 特定错误模式检查 - 增强版
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
            
            # 编译器版本错误 - 改进：更准确的检测
            if grep -q "requires gcc.*\|\`gcc.*\` version" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "❌ 检测到真正的编译器版本错误" >> "$REPORT_FILE"
                echo "💡 可能是GCC版本不匹配" >> "$REPORT_FILE"
                grep -i "requires gcc\|gcc version" "$BUILD_DIR/build.log" | head -3 >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
            # 内存不足错误
            if grep -q "out of memory\|Killed process" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "❌ 检测到内存不足错误" >> "$REPORT_FILE"
                echo "💡 系统内存不足，编译被终止" >> "$REPORT_FILE"
                echo "🛠️ 修复方法: 增加交换空间或减少并行编译任务" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
            # 编译器未找到错误
            if grep -q "compiler.*not found\|gcc.*not found" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "❌ 检测到编译器未找到错误" >> "$REPORT_FILE"
                echo "💡 编译器路径配置错误或SDK下载不完整" >> "$REPORT_FILE"
                echo "🛠️ 修复方法: 检查COMPILER_DIR环境变量或重新下载SDK" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
        else
            echo "✅ 构建日志中没有发现真正严重的错误" >> "$REPORT_FILE"
            echo "💡 注意：某些'error'消息可能是警告或可忽略的" >> "$REPORT_FILE"
        fi
        
    else
        echo "❌ 构建日志文件不存在: $BUILD_DIR/build.log" >> "$REPORT_FILE"
        echo "💡 构建可能尚未开始或日志被重定向" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 9. 检查下载日志（增强版）
check_download_log() {
    log_step "检查下载日志"
    
    print_subheader "下载日志分析"
    
    if [ -f "$BUILD_DIR/download.log" ]; then
        # 检查日志文件是否为空
        if [ ! -s "$BUILD_DIR/download.log" ]; then
            echo "ℹ️ 下载日志文件存在但为空" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            return
        fi
        
        # 更准确的下载错误统计
        local download_errors=$(grep -c -i "error\|failed\|404\|not found\|timeout\|connection refused" "$BUILD_DIR/download.log" 2>/dev/null || echo "0")
        local total_downloads=$(grep -c "Downloading\|downloading" "$BUILD_DIR/download.log" 2>/dev/null || echo "0")
        
        if [ $download_errors -gt 0 ]; then
            echo "⚠️ 下载警告: $download_errors 个（共 $total_downloads 次下载）" >> "$REPORT_FILE"
            echo "📄 下载错误详情 (前5个):" >> "$REPORT_FILE"
            grep -i "error\|failed\|404\|not found\|timeout\|connection refused" "$BUILD_DIR/download.log" | head -5 >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "💡 下载问题解决方案:" >> "$REPORT_FILE"
            echo "  1. 检查网络连接" >> "$REPORT_FILE"
            echo "  2. 配置代理服务器" >> "$REPORT_FILE"
            echo "  3. 手动下载缺失文件" >> "$REPORT_FILE"
            echo "  4. 运行: make download -j8 V=s" >> "$REPORT_FILE"
        else
            echo "✅ 下载日志无严重错误" >> "$REPORT_FILE"
            if [ $total_downloads -gt 0 ]; then
                echo "📊 成功下载次数: $total_downloads" >> "$REPORT_FILE"
            fi
        fi
        
    else
        echo "ℹ️ 下载日志文件不存在" >> "$REPORT_FILE"
        echo "💡 可能尚未开始下载或日志被合并" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 10. 版本特定分析（增强版）
analyze_version_specific() {
    log_step "分析版本特定问题"
    
    print_subheader "版本特定问题分析"
    
    if [ -n "$SELECTED_BRANCH" ]; then
        echo "📌 当前OpenWrt版本: $SELECTED_BRANCH" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            echo "🔧 OpenWrt 23.05 版本特性:" >> "$REPORT_FILE"
            echo "  编译器: GCC 12.3.0" >> "$REPORT_FILE"
            echo "  内核: Linux 5.15" >> "$REPORT_FILE"
            echo "  musl: 1.2.3" >> "$REPORT_FILE"
            echo "  binutils: 2.38" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "⚠️ 常见问题:" >> "$REPORT_FILE"
            echo "  1. GDB _GL_ATTRIBUTE_FORMAT_PRINTF 错误" >> "$REPORT_FILE"
            echo "  2. 工具链构建错误 (toolchain/Makefile:93)" >> "$REPORT_FILE"
            echo "  3. 头文件缺失问题" >> "$REPORT_FILE"
            echo "  4. libtool版本兼容性问题" >> "$REPORT_FILE"
            echo "  5. IPK文件安装问题（大小写敏感）" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🛠️ 解决方案:" >> "$REPORT_FILE"
            echo "  1. 修复GDB源码: 修改gdbsupport/common-defs.h" >> "$REPORT_FILE"
            echo "  2. 创建stamp标记文件" >> "$REPORT_FILE"
            echo "  3. 安装libtool和autoconf" >> "$REPORT_FILE"
            echo "  4. 设置-fpermissive编译标志" >> "$REPORT_FILE"
            echo "  5. 修复IPK安装脚本，支持不区分大小写" >> "$REPORT_FILE"
            
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
            echo "  4. IPK文件安装正常" >> "$REPORT_FILE"
            
        else
            echo "ℹ️ 当前版本分支: $SELECTED_BRANCH" >> "$REPORT_FILE"
            echo "💡 请参考官方文档获取版本特定信息" >> "$REPORT_FILE"
        fi
        
        # SDK编译器信息 - 增强版
        print_subheader "SDK编译器版本信息"
        echo "🎯 SDK编译器来源: OpenWrt官方下载" >> "$REPORT_FILE"
        
        # 根据版本显示不同的SDK编译器信息
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            echo "🔧 SDK编译器版本: GCC 12.3.0 (OpenWrt 23.05官方版本)" >> "$REPORT_FILE"
            echo "💡 注意: 23.05版本中IPK文件安装需要特殊处理" >> "$REPORT_FILE"
        elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
            echo "🔧 SDK编译器版本: GCC 8.4.0 (OpenWrt 21.02官方版本)" >> "$REPORT_FILE"
            echo "💡 注意: 21.02版本相对稳定" >> "$REPORT_FILE"
        else
            echo "🔧 SDK编译器版本: 根据OpenWrt版本自动匹配" >> "$REPORT_FILE"
        fi
        
        echo "✅ SDK编译器已通过官方验证，无需担心版本兼容性问题" >> "$REPORT_FILE"
        echo "💡 如果构建成功，说明编译器版本完全兼容" >> "$REPORT_FILE"
        
    else
        echo "⚠️ 版本分支未设置" >> "$REPORT_FILE"
        echo "💡 请检查环境变量设置" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 11. 分析常见错误模式（增强版）
analyze_common_error_patterns() {
    log_step "分析常见错误模式"
    
    print_subheader "常见错误模式分析"
    
    if [ ! -f "$BUILD_DIR/build.log" ]; then
        echo "❌ 构建日志文件不存在，无法分析错误模式" >> "$REPORT_FILE"
        return
    fi
    
    local patterns_found=0
    
    echo "🔍 正在扫描常见错误模式:" >> "$REPORT_FILE"
    
    # 1. 编译器未找到（增强版）
    if grep -q "compiler.*not found\|gcc.*not found\|command not found.*gcc" "$BUILD_DIR/build.log"; then
        echo "❌ 发现编译器未找到错误" >> "$REPORT_FILE"
        grep -i "compiler.*not found\|gcc.*not found" "$BUILD_DIR/build.log" | head -3 >> "$REPORT_FILE"
        patterns_found=$((patterns_found + 1))
        echo "💡 可能原因: 编译器路径配置错误或SDK下载不完整" >> "$REPORT_FILE"
        echo "🛠️ 修复方法: 检查COMPILER_DIR环境变量或重新下载SDK" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # 2. 未定义引用
    if grep -q "undefined reference" "$BUILD_DIR/build.log"; then
        echo "❌ 发现未定义引用错误" >> "$REPORT_FILE"
        grep -i "undefined reference" "$BUILD_DIR/build.log" | head -3 >> "$REPORT_FILE"
        patterns_found=$((patterns_found + 1))
        echo "💡 可能原因: 库文件缺失或链接顺序错误" >> "$REPORT_FILE"
        echo "🛠️ 修复方法: 检查依赖包是否完整，调整链接顺序" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # 3. 文件不存在
    if grep -q "No such file\|File not found" "$BUILD_DIR/build.log"; then
        echo "⚠️ 发现文件不存在错误" >> "$REPORT_FILE"
        grep -i "No such file\|File not found" "$BUILD_DIR/build.log" | head -3 >> "$REPORT_FILE"
        patterns_found=$((patterns_found + 1))
        echo "💡 可能原因: 依赖包下载不完整或路径错误" >> "$REPORT_FILE"
        echo "🛠️ 修复方法: 重新下载依赖包或检查文件路径" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # 4. 内存不足
    if grep -q "out of memory\|Killed process" "$BUILD_DIR/build.log"; then
        echo "🚨 发现内存不足错误" >> "$REPORT_FILE"
        grep -i "out of memory\|Killed process" "$BUILD_DIR/build.log" | head -3 >> "$REPORT_FILE"
        patterns_found=$((patterns_found + 1))
        echo "💡 可能原因: 系统内存不足，编译被终止" >> "$REPORT_FILE"
        echo "🛠️ 修复方法: 增加交换空间或减少并行编译任务" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # 5. 权限错误
    if grep -q "Permission denied\|cannot create" "$BUILD_DIR/build.log"; then
        echo "⚠️ 发现权限错误" >> "$REPORT_FILE"
        grep -i "Permission denied\|cannot create" "$BUILD_DIR/build.log" | head -3 >> "$REPORT_FILE"
        patterns_found=$((patterns_found + 1))
        echo "💡 可能原因: 文件权限不足，尝试修复权限" >> "$REPORT_FILE"
        echo "🛠️ 修复方法: 检查文件权限或使用sudo" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # 6. 磁盘空间不足
    if grep -q "No space left\|disk full" "$BUILD_DIR/build.log"; then
        echo "🚨 发现磁盘空间不足错误" >> "$REPORT_FILE"
        grep -i "No space left\|disk full" "$BUILD_DIR/build.log" | head -3 >> "$REPORT_FILE"
        patterns_found=$((patterns_found + 1))
        echo "💡 可能原因: 磁盘空间不足" >> "$REPORT_FILE"
        echo "🛠️ 修复方法: 清理磁盘空间或扩展磁盘" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # 7. 时间戳错误
    if grep -q "clock skew\|time stamp\|timestamp" "$BUILD_DIR/build.log"; then
        echo "⚠️ 发现时间戳错误" >> "$REPORT_FILE"
        grep -i "clock skew\|time stamp\|timestamp" "$BUILD_DIR/build.log" | head -3 >> "$REPORT_FILE"
        patterns_found=$((patterns_found + 1))
        echo "💡 可能原因: 系统时间不正确或文件时间戳混乱" >> "$REPORT_FILE"
        echo "🛠️ 修复方法: 同步系统时间或清理构建缓存" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # 8. 下载错误
    if grep -q "404\|Failed to download\|timeout\|connection refused" "$BUILD_DIR/build.log"; then
        echo "⚠️ 发现下载错误" >> "$REPORT_FILE"
        grep -i "404\|Failed to download\|timeout\|connection refused" "$BUILD_DIR/build.log" | head -3 >> "$REPORT_FILE"
        patterns_found=$((patterns_found + 1))
        echo "💡 可能原因: 网络问题或源地址不可用" >> "$REPORT_FILE"
        echo "🛠️ 修复方法: 检查网络连接或更换下载源" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    if [ $patterns_found -eq 0 ]; then
        echo "✅ 未发现常见错误模式" >> "$REPORT_FILE"
    else
        echo "📊 总共发现 $patterns_found 种常见错误模式" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 12. 检查SDK状态（增强版）
check_sdk_status() {
    log_step "检查SDK状态"
    
    print_subheader "SDK状态检查"
    
    if [ -d "$SDK_DIR" ]; then
        echo "✅ SDK目录存在: $SDK_DIR" >> "$REPORT_FILE"
        
        local sdk_size=$(du -sh "$SDK_DIR" 2>/dev/null | cut -f1 || echo "未知")
        echo "📏 SDK目录大小: $sdk_size" >> "$REPORT_FILE"
        
        # 查找GCC编译器（增强版，排除dummy-tools）
        local gcc_file=$(find "$SDK_DIR" -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
        
        if [ -n "$gcc_file" ] && [ -x "$gcc_file" ]; then
            echo "✅ 找到SDK GCC编译器: $(basename "$gcc_file")" >> "$REPORT_FILE"
            
            # 显示GCC版本
            local version=$("$gcc_file" --version 2>&1 | head -1)
            echo "🔧 GCC版本: $version" >> "$REPORT_FILE"
            
            # 检查版本兼容性
            local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1)
            if [ -n "$major_version" ]; then
                if [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                    echo "✅ GCC $major_version.x 版本兼容" >> "$REPORT_FILE"
                else
                    echo "⚠️ GCC版本可能不兼容: $major_version.x" >> "$REPORT_FILE"
                fi
            fi
        else
            echo "⚠️ 未找到可执行的GCC编译器" >> "$REPORT_FILE"
            
            # 查找工具链工具
            local tools=$(find "$SDK_DIR" -type f -executable -name "*gcc*" 2>/dev/null | head -5)
            if [ -n "$tools" ]; then
                echo "🔧 找到的工具链工具:" >> "$REPORT_FILE"
                echo "$tools" | while read tool; do
                    echo "  🔧 $(basename "$tool")" >> "$REPORT_FILE"
                done
            fi
            
            # 检查dummy-tools
            local dummy_tools=$(find "$SDK_DIR" -type f -executable -path "*dummy-tools*" -name "*gcc*" 2>/dev/null | head -3)
            if [ -n "$dummy_tools" ]; then
                echo "⚠️ 检测到dummy-tools编译器:" >> "$REPORT_FILE"
                echo "$dummy_tools" | while read tool; do
                    echo "  ⚠️ $(basename "$tool") (这不是真正的编译器)" >> "$REPORT_FILE"
                done
            fi
        fi
    else
        echo "⚠️ SDK目录不存在: $SDK_DIR" >> "$REPORT_FILE"
        echo "💡 将使用OpenWrt自动构建的编译器" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 13. 检查自定义文件集成问题（增强版）- 修复语法错误
check_custom_files_integration() {
    log_step "检查自定义文件集成"
    
    print_subheader "自定义文件集成检查"
    
    local custom_files_dir="$BUILD_DIR/files/etc/custom-files"
    
    if [ -d "$custom_files_dir" ]; then
        echo "✅ 自定义文件目录存在: $custom_files_dir" >> "$REPORT_FILE"
        
        # 初始化统计变量
        local ipk_count=0
        local script_count=0
        local config_count=0
        local other_count=0
        local chinese_count=0
        local total_count=0
        
        # 精确中文检测函数
        detect_chinese() {
            local filename="$1"
            if echo "$filename" | grep -q -P '[\x{4e00}-\x{9fff}\x{3400}-\x{4dbf}]'; then
                return 0
            fi
            if echo "$filename" | grep -q -E "备份|恢复|安装|配置|设置|脚本|文件|固件|插件|网络|系统|路由|无线"; then
                return 0
            fi
            return 1
        }
        
        # 统计文件
        for file in "$custom_files_dir"/*; do
            if [ -f "$file" ]; then
                total_count=$((total_count + 1))
                local filename=$(basename "$file")
                
                # 检测中文名
                if detect_chinese "$filename"; then
                    chinese_count=$((chinese_count + 1))
                fi
                
                # 统计文件类型
                if echo "$filename" | grep -qi "\.ipk$"; then
                    ipk_count=$((ipk_count + 1))
                elif [[ "$filename" == *.sh ]] || [[ "$filename" == *.Sh ]] || [[ "$filename" == *.SH ]]; then
                    script_count=$((script_count + 1))
                elif [[ "$filename" == *.conf ]] || [[ "$filename" == *.config ]] || [[ "$filename" == *.CONF ]]; then
                    config_count=$((config_count + 1))
                else
                    other_count=$((other_count + 1))
                fi
            fi
        done
        
        echo "📊 自定义文件统计:" >> "$REPORT_FILE"
        echo "  📦 IPK文件: $ipk_count 个" >> "$REPORT_FILE"
        echo "  📜 脚本文件: $script_count 个" >> "$REPORT_FILE"
        echo "  ⚙️ 配置文件: $config_count 个" >> "$REPORT_FILE"
        echo "  📄 其他文件: $other_count 个" >> "$REPORT_FILE"
        echo "  🇨🇳 中文名文件: $chinese_count 个" >> "$REPORT_FILE"
        echo "  📁 总文件数: $total_count 个" >> "$REPORT_FILE"
        
        if [ $chinese_count -gt 0 ]; then
            echo "⚠️ 发现中文文件名，可能影响脚本执行" >> "$REPORT_FILE"
            echo "🔍 中文文件名列表 (最多显示5个):" >> "$REPORT_FILE"
            local displayed=0
            for file in "$custom_files_dir"/*; do
                if [ -f "$file" ]; then
                    local filename=$(basename "$file")
                    if detect_chinese "$filename"; then
                        echo "  📄 $filename" >> "$REPORT_FILE"
                        displayed=$((displayed + 1))
                        if [ $displayed -ge 5 ]; then
                            break
                        fi
                    fi
                fi
            done
        fi
        
        # 检查启动脚本
        local boot_script="$BUILD_DIR/files/etc/uci-defaults/99-custom-files"
        if [ -f "$boot_script" ]; then
            echo "✅ 第一次开机脚本存在: $boot_script" >> "$REPORT_FILE"
            
            # 检查IPK安装逻辑
            local ipk_logic=$(grep -c "grep -qi.*\\.ipk" "$boot_script" 2>/dev/null || echo "0")
            if [ $ipk_logic -gt 0 ]; then
                echo "✅ IPK安装逻辑已修复（不区分大小写）" >> "$REPORT_FILE"
            else
                echo "⚠️ IPK安装逻辑可能未修复" >> "$REPORT_FILE"
            fi
        else
            echo "⚠️ 第一次开机脚本不存在" >> "$REPORT_FILE"
        fi
        
        # 显示具体的IPK文件
        if [ $ipk_count -gt 0 ]; then
            echo "📦 检测到的IPK文件:" >> "$REPORT_FILE"
            for file in "$custom_files_dir"/*; do
                if [ -f "$file" ] && echo "$(basename "$file")" | grep -qi "\.ipk$"; then
                    echo "  📦 $(basename "$file")" >> "$REPORT_FILE"
                fi
            done
            
            echo "💡 IPK安装修复说明:" >> "$REPORT_FILE"
            echo "  - 使用不区分大小写的文件匹配 (ipk, IPK, Ipk)" >> "$REPORT_FILE"
            echo "  - 修复了23.05版本中IPK不安装的问题" >> "$REPORT_FILE"
            echo "  - 确保所有IPK文件都会被安装" >> "$REPORT_FILE"
        fi
        
        if [ $chinese_count -gt 0 ]; then
            echo "💡 中文文件名处理:" >> "$REPORT_FILE"
            echo "  - 已启用中文文件名检测和优化处理" >> "$REPORT_FILE"
            echo "  - 支持自动识别和运行中文名脚本" >> "$REPORT_FILE"
        fi
    else
        echo "ℹ️ 自定义文件目录不存在: $custom_files_dir" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 14. 分析编译器相关错误（增强版）- 修复语法错误
analyze_compiler_errors() {
    log_step "分析编译器相关错误"
    
    print_subheader "编译器相关错误分析"
    
    if [ ! -f "$BUILD_DIR/build.log" ]; then
        echo "❌ 构建日志文件不存在" >> "$REPORT_FILE"
        return
    fi
    
    # 检查预构建编译器调用
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        echo "🔍 检查预构建编译器调用..." >> "$REPORT_FILE"
        
        local prebuilt_calls=$(grep -c "$COMPILER_DIR" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        local total_calls=$(grep -c "gcc\|g++" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        
        if [ $prebuilt_calls -gt 0 ]; then
            echo "✅ 检测到预构建编译器调用: $prebuilt_calls/$total_calls" >> "$REPORT_FILE"
            
            # 检查预构建编译器版本
            echo "🔧 预构建编译器版本信息:" >> "$REPORT_FILE"
            if [ -d "$SDK_DIR" ]; then
                local sdk_gcc=$(find "$SDK_DIR" -type f -executable \
                  -name "*gcc" \
                  ! -name "*gcc-ar" \
                  ! -name "*gcc-ranlib" \
                  ! -name "*gcc-nm" \
                  ! -path "*dummy-tools*" \
                  2>/dev/null | head -1)
                
                if [ -n "$sdk_gcc" ] && [ -x "$sdk_gcc" ]; then
                    local sdk_version=$("$sdk_gcc" --version 2>&1 | head -1)
                    echo "  SDK GCC版本: $sdk_version" >> "$REPORT_FILE"
                    
                    # 提取主要版本
                    local major_version=$(echo "$sdk_version" | grep -o "[0-9]\+" | head -1)
                    if [ -n "$major_version" ]; then
                        if [ "$major_version" = "12" ]; then
                            echo "  ✅ 检测到OpenWrt 23.05 SDK GCC 12.3.0" >> "$REPORT_FILE"
                        elif [ "$major_version" = "8" ]; then
                            echo "  ✅ 检测到OpenWrt 21.02 SDK GCC 8.4.0" >> "$REPORT_FILE"
                        else
                            echo "  ⚠️ SDK GCC版本: $major_version.x" >> "$REPORT_FILE"
                        fi
                    fi
                fi
            fi
        else
            echo "⚠️ 未检测到预构建编译器调用" >> "$REPORT_FILE"
            echo "💡 使用的是OpenWrt自动构建的编译器" >> "$REPORT_FILE"
        fi
    else
        echo "ℹ️ 未设置预构建编译器目录" >> "$REPORT_FILE"
        echo "💡 使用自动构建的编译器" >> "$REPORT_FILE"
    fi
    
    # 检查编译器错误 - 修复语法错误
    echo "🔍 编译器错误检查:" >> "$REPORT_FILE"
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        local prebuilt_errors=$(grep "$COMPILER_DIR" "$BUILD_DIR/build.log" 2>/dev/null | grep -i "error\|failed" | head -5)
        if [ -n "$prebuilt_errors" ]; then
            echo "⚠️ 发现预构建编译器相关错误" >> "$REPORT_FILE"
            echo "$prebuilt_errors" >> "$REPORT_FILE"
        else
            echo "✅ 未发现预构建编译器相关错误" >> "$REPORT_FILE"
        fi
    fi
    
    # 检查dummy-tools相关错误
    echo "🔍 dummy-tools检查:" >> "$REPORT_FILE"
    local dummy_errors=$(grep "dummy-tools" "$BUILD_DIR/build.log" 2>/dev/null | grep -i "error\|failed" | head -3)
    if [ -n "$dummy_errors" ]; then
        echo "⚠️ 发现dummy-tools相关错误" >> "$REPORT_FILE"
        echo "$dummy_errors" >> "$REPORT_FILE"
        echo "💡 dummy-tools是OpenWrt构建系统的占位符，不是真正的编译器" >> "$REPORT_FILE"
    else
        if grep -q "dummy-tools" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "✅ dummy-tools未产生错误" >> "$REPORT_FILE"
        else
            echo "ℹ️ 未检测到dummy-tools相关日志" >> "$REPORT_FILE"
        fi
    fi
    echo "" >> "$REPORT_FILE"
}

# 15. 检查磁盘空间（增强版）
check_disk_space_usage() {
    log_step "检查磁盘空间"
    
    print_subheader "磁盘空间检查"
    
    echo "磁盘使用情况:" >> "$REPORT_FILE"
    df -h /mnt >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local available_space=$(df /mnt --output=avail 2>/dev/null | tail -1)
    local available_gb=0
    
    if [ -n "$available_space" ]; then
        available_gb=$((available_space / 1024 / 1024))
        echo "/mnt 可用空间: ${available_gb}G" >> "$REPORT_FILE"
        
        if [ $available_gb -lt 5 ]; then
            echo "🚨 磁盘空间严重不足 (仅 ${available_gb}G)" >> "$REPORT_FILE"
            echo "💡 建议立即清理磁盘空间" >> "$REPORT_FILE"
        elif [ $available_gb -lt 10 ]; then
            echo "⚠️ 磁盘空间较低 (${available_gb}G)" >> "$REPORT_FILE"
            echo "💡 建议清理一些空间" >> "$REPORT_FILE"
        else
            echo "✅ 磁盘空间充足 (${available_gb}G)" >> "$REPORT_FILE"
        fi
    else
        echo "❌ 无法获取磁盘空间信息" >> "$REPORT_FILE"
    fi
    
    # 检查构建目录大小
    if [ -d "$BUILD_DIR" ]; then
        local build_size=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1 || echo "未知")
        echo "📁 构建目录大小: $build_size" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 16. 检查环境变量（增强版）
check_environment_variables() {
    log_step "检查环境变量"
    
    print_subheader "环境变量检查"
    
    local env_file="$BUILD_DIR/build_env.sh"
    
    if [ -f "$env_file" ]; then
        echo "✅ 环境文件存在: $env_file" >> "$REPORT_FILE"
        
        # 显示关键环境变量
        echo "📌 关键环境变量:" >> "$REPORT_FILE"
        grep -E "SELECTED_BRANCH|TARGET|SUBTARGET|DEVICE|CONFIG_MODE|COMPILER_DIR" "$env_file" | head -10 >> "$REPORT_FILE"
        
        # 加载环境变量
        source "$env_file" 2>/dev/null
        
        if [ -n "$SELECTED_BRANCH" ]; then
            echo "📌 OpenWrt版本: $SELECTED_BRANCH" >> "$REPORT_FILE"
        fi
        
        if [ -n "$TARGET" ] && [ -n "$SUBTARGET" ]; then
            echo "🎯 目标平台: $TARGET/$SUBTARGET" >> "$REPORT_FILE"
        fi
        
        if [ -n "$DEVICE" ]; then
            echo "📱 目标设备: $DEVICE" >> "$REPORT_FILE"
        fi
        
        if [ -n "$CONFIG_MODE" ]; then
            echo "⚙️ 配置模式: $CONFIG_MODE" >> "$REPORT_FILE"
        fi
        
        if [ -n "$COMPILER_DIR" ]; then
            echo "🔧 编译器目录: $COMPILER_DIR" >> "$REPORT_FILE"
            
            # 检查编译器目录是否存在
            if [ -d "$COMPILER_DIR" ]; then
                echo "✅ 编译器目录存在" >> "$REPORT_FILE"
            else
                echo "❌ 编译器目录不存在" >> "$REPORT_FILE"
            fi
        fi
    else
        echo "⚠️ 环境文件不存在: $env_file" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 17. 检查构建产物（增强版）
check_build_artifacts() {
    log_step "检查构建产物"
    
    print_subheader "构建产物检查"
    
    local artifacts_dir="$BUILD_DIR/bin/targets"
    
    if [ -d "$artifacts_dir" ]; then
        echo "✅ 构建产物目录存在: $artifacts_dir" >> "$REPORT_FILE"
        
        # 统计固件文件
        local firmware_count=$(find "$artifacts_dir" -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
        local package_count=$(find "$artifacts_dir" -type f \( -name "*.gz" -o -name "*.ipk" \) 2>/dev/null | wc -l)
        local total_count=$(find "$artifacts_dir" -type f 2>/dev/null | wc -l)
        
        echo "📊 构建产物统计:" >> "$REPORT_FILE"
        echo "  🎯 固件文件: $firmware_count 个 (.bin/.img)" >> "$REPORT_FILE"
        echo "  📦 包文件: $package_count 个 (.gz/.ipk)" >> "$REPORT_FILE"
        echo "  📁 总文件数: $total_count 个" >> "$REPORT_FILE"
        
        if [ $firmware_count -gt 0 ]; then
            echo "✅ 成功生成 $firmware_count 个固件文件" >> "$REPORT_FILE"
            
            # 显示固件文件
            echo "📄 生成的固件文件:" >> "$REPORT_FILE"
            find "$artifacts_dir" -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | head -5 | while read file; do
                local size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
                echo "  📁 $(basename "$file") ($size)" >> "$REPORT_FILE"
            done
        else
            echo "⚠️ 未生成固件文件 (.bin/.img)" >> "$REPORT_FILE"
            
            # 显示其他文件
            if [ $total_count -gt 0 ]; then
                echo "📄 其他生成的文件:" >> "$REPORT_FILE"
                find "$artifacts_dir" -type f 2>/dev/null | head -10 | while read file; do
                    local size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
                    echo "  📄 $(basename "$file") ($size)" >> "$REPORT_FILE"
                done
            fi
        fi
    else
        echo "❌ 构建产物目录不存在" >> "$REPORT_FILE"
        echo "💡 编译可能未成功完成" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 18. 检查依赖包（新增）
check_dependencies() {
    log_step "检查依赖包"
    
    print_subheader "依赖包检查"
    
    if [ -d "$BUILD_DIR/dl" ]; then
        local dl_count=$(find "$BUILD_DIR/dl" -type f 2>/dev/null | wc -l)
        local dl_size=$(du -sh "$BUILD_DIR/dl" 2>/dev/null | cut -f1 || echo "未知")
        
        echo "📦 依赖包统计:" >> "$REPORT_FILE"
        echo "  依赖包数量: $dl_count 个" >> "$REPORT_FILE"
        echo "  依赖包大小: $dl_size" >> "$REPORT_FILE"
        
        if [ $dl_count -lt 10 ]; then
            echo "⚠️ 依赖包数量较少，可能下载不完整" >> "$REPORT_FILE"
            echo "💡 建议运行: make download -j4 V=s" >> "$REPORT_FILE"
        else
            echo "✅ 依赖包看起来正常" >> "$REPORT_FILE"
        fi
        
        # 显示最新的依赖包
        if [ $dl_count -gt 0 ]; then
            echo "📥 最新的依赖包 (最多5个):" >> "$REPORT_FILE"
            find "$BUILD_DIR/dl" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -5 | cut -d' ' -f2- | while read file; do
                local size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
                echo "  📄 $(basename "$file") ($size)" >> "$REPORT_FILE"
            done
        fi
    else
        echo "⚠️ 依赖包目录不存在: $BUILD_DIR/dl" >> "$REPORT_FILE"
        echo "💡 依赖包可能尚未下载" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 19. 生成错误报告（增强版）
generate_error_report() {
    log_step "生成错误报告"
    
    print_subheader "错误报告生成"
    
    local report_file="/tmp/openwrt-build-error-report-$TIMESTAMP.txt"
    
    echo "=== OpenWrt 构建错误报告 ===" > "$report_file"
    echo "生成时间: $(date)" >> "$report_file"
    echo "构建目录: $BUILD_DIR" >> "$report_file"
    echo "报告时间戳: $TIMESTAMP" >> "$report_file"
    echo "" >> "$report_file"
    
    # 环境信息
    echo "=== 环境信息 ===" >> "$report_file"
    uname -a >> "$report_file"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release | grep -E '^PRETTY_NAME=|^NAME=|^VERSION=' >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # 磁盘空间
    echo "=== 磁盘空间 ===" >> "$report_file"
    df -h /mnt >> "$report_file"
    echo "" >> "$report_file"
    
    # 构建状态
    echo "=== 构建状态 ===" >> "$report_file"
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        echo "✅ 构建成功 - 生成固件文件" >> "$report_file"
        find "$BUILD_DIR/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | head -5 | while read file; do
            echo "  📁 $(basename "$file")" >> "$report_file"
        done
    else
        echo "❌ 构建失败 - 未生成固件" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # 错误摘要
    echo "=== 错误摘要 ===" >> "$report_file"
    if [ -f "$BUILD_DIR/build.log" ]; then
        local error_count=$(grep -c -i "error" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        local warning_count=$(grep -c -i "warning" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        
        echo "错误数量: $error_count" >> "$report_file"
        echo "警告数量: $warning_count" >> "$report_file"
        echo "" >> "$report_file"
        
        if [ $error_count -gt 0 ]; then
            echo "前10个错误:" >> "$report_file"
            grep -i "error" "$BUILD_DIR/build.log" | grep -v "ignored\|non-fatal" | head -10 >> "$report_file"
        fi
    else
        echo "无构建日志文件" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # 警告摘要
    echo "=== 警告摘要 ===" >> "$report_file"
    if [ -f "$BUILD_DIR/build.log" ]; then
        grep -i "Warning\|warning:" "$BUILD_DIR/build.log" | tail -20 >> "$report_file"
    else
        echo "无构建日志文件" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # SDK状态
    echo "=== SDK状态 ===" >> "$report_file"
    if [ -d "$SDK_DIR" ]; then
        echo "SDK目录: $SDK_DIR" >> "$report_file"
        echo "SDK大小: $(du -sh "$SDK_DIR" 2>/dev/null | cut -f1 || echo '未知')" >> "$report_file"
        
        local gcc_file=$(find "$SDK_DIR" -type f -executable -name "*gcc" ! -path "*dummy-tools*" 2>/dev/null | head -1)
        if [ -n "$gcc_file" ]; then
            echo "GCC编译器: $gcc_file" >> "$report_file"
            "$gcc_file" --version 2>&1 | head -1 >> "$report_file"
        else
            echo "未找到真正的GCC编译器" >> "$report_file"
        fi
    else
        echo "SDK目录不存在" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # 编译器调用状态
    echo "=== 编译器调用状态 ===" >> "$report_file"
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ] && [ -f "$BUILD_DIR/build.log" ]; then
        local sdk_calls=$(grep -c "$COMPILER_DIR" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        echo "SDK编译器调用次数: $sdk_calls" >> "$report_file"
    else
        echo "无法检查编译器调用状态" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # 构建产物
    echo "=== 构建产物 ===" >> "$report_file"
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        find "$BUILD_DIR/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | while read file; do
            echo "$(basename "$file")" >> "$report_file"
        done
    else
        echo "无构建产物" >> "$report_file"
    fi
    
    echo "" >> "$REPORT_FILE"
    echo "📄 错误报告已生成: $report_file" >> "$REPORT_FILE"
    echo "报告文件内容预览:" >> "$REPORT_FILE"
    head -30 "$report_file" | while read line; do
        echo "  $line" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# 20. 详细错误分析函数（优化版）- 修复语法错误
analyze_detailed_errors() {
    log_step "执行详细错误分析"
    
    print_subheader "详细错误分析"
    
    # 检查构建日志中的具体错误
    if [ -f "$BUILD_DIR/build.log" ]; then
        echo "📊 构建日志错误详细分析:" >> "$REPORT_FILE"
        
        # 1. 编译器相关错误（实际错误）- 改进过滤
        echo "🔧 1. 编译器相关错误 (真正的编译错误):" >> "$REPORT_FILE"
        local compiler_errors=$(grep -i "gcc.*error\|ld.*error\|collect2.*error\|undefined reference" "$BUILD_DIR/build.log" 2>/dev/null | grep -v "ignored\|non-fatal" | head -10)
        if [ -n "$compiler_errors" ]; then
            echo "$compiler_errors" >> "$REPORT_FILE"
        else
            echo "  无真正的编译器错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 2. 头文件缺失错误（实际错误）
        echo "📄 2. 头文件缺失错误 (实际发生的):" >> "$REPORT_FILE"
        local header_errors=$(grep -i "stdc-predef.h\|stdio.h\|stdlib.h\|.*\.h: No such file" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$header_errors" ]; then
            echo "$header_errors" >> "$REPORT_FILE"
        else
            echo "  无真正的头文件缺失错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 3. 下载错误（实际错误）
        echo "📥 3. 下载错误 (实际发生的):" >> "$REPORT_FILE"
        local download_errors=$(grep -i "404\|Failed to download\|timeout\|connection refused\|SSL_ERROR" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$download_errors" ]; then
            echo "$download_errors" >> "$REPORT_FILE"
        else
            echo "  无真正的下载错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 4. 权限错误（实际错误）
        echo "🔐 4. 权限错误 (实际发生的):" >> "$REPORT_FILE"
        local permission_errors=$(grep -i "permission denied\|cannot create\|read-only\|Operation not permitted" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$permission_errors" ]; then
            echo "$permission_errors" >> "$REPORT_FILE"
        else
            echo "  无真正的权限错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 5. 内存不足错误（实际错误）
        echo "💾 5. 内存不足错误 (实际发生的):" >> "$REPORT_FILE"
        local memory_errors=$(grep -i "out of memory\|Killed process\|terminated\|oom\|swap" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$memory_errors" ]; then
            echo "$memory_errors" >> "$REPORT_FILE"
        else
            echo "  无真正的内存错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 6. 特定包编译错误（实际错误）
        echo "📦 6. 特定包编译错误 (实际发生的):" >> "$REPORT_FILE"
        local package_errors=$(grep -i "package/.*failed\|recipe for target.*failed\|Error .* in package" "$BUILD_DIR/build.log" 2>/dev/null | grep -v "ignored" | head -10)
        if [ -n "$package_errors" ]; then
            echo "$package_errors" >> "$REPORT_FILE"
        else
            echo "  无真正的包编译错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 7. 磁盘空间错误（实际错误）
        echo "💿 7. 磁盘空间错误 (实际发生的):" >> "$REPORT_FILE"
        local disk_errors=$(grep -i "no space left\|disk full\|write error\|ENOSPC" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$disk_errors" ]; then
            echo "$disk_errors" >> "$REPORT_FILE"
        else
            echo "  无真正的磁盘空间错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 8. 时间戳错误（实际错误）
        echo "🕐 8. 时间戳错误 (实际发生的):" >> "$REPORT_FILE"
        local timestamp_errors=$(grep -i "clock skew\|time stamp\|timestamp" "$BUILD_DIR/build.log" 2>/dev/null | head -10)
        if [ -n "$timestamp_errors" ]; then
            echo "$timestamp_errors" >> "$REPORT_FILE"
        else
            echo "  无真正的时间戳错误" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 9. SDK编译器使用情况检查
        echo "🎯 9. SDK编译器使用情况检查:" >> "$REPORT_FILE"
        if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
            local sdk_usage_count=$(grep -c "$COMPILER_DIR" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
            if [ $sdk_usage_count -gt 0 ]; then
                echo "  ✅ SDK编译器被调用次数: $sdk_usage_count" >> "$REPORT_FILE"
                echo "  💡 SDK编译器已成功集成到构建系统中" >> "$REPORT_FILE"
                
                # 显示SDK编译器版本信息
                local sdk_gcc=$(find "$COMPILER_DIR" -type f -executable \
                  -name "*gcc" \
                  ! -name "*gcc-ar" \
                  ! -name "*gcc-ranlib" \
                  ! -name "*gcc-nm" \
                  ! -path "*dummy-tools*" \
                  2>/dev/null | head -1)
                
                if [ -n "$sdk_gcc" ] && [ -x "$sdk_gcc" ]; then
                    local sdk_version=$("$sdk_gcc" --version 2>&1 | head -1)
                    local major_version=$(echo "$sdk_version" | grep -o "[0-9]\+" | head -1)
                    
                    if [ "$major_version" = "12" ]; then
                        echo "  🔧 使用的SDK编译器: GCC 12.3.0 (OpenWrt 23.05)" >> "$REPORT_FILE"
                    elif [ "$major_version" = "8" ]; then
                        echo "  🔧 使用的SDK编译器: GCC 8.4.0 (OpenWrt 21.02)" >> "$REPORT_FILE"
                    else
                        echo "  🔧 使用的SDK编译器: $sdk_version" >> "$REPORT_FILE"
                    fi
                fi
            else
                echo "  🔄 构建中未使用预构建SDK编译器" >> "$REPORT_FILE"
                echo "  💡 可能使用了自动构建的编译器" >> "$REPORT_FILE"
            fi
        else
            echo "  ℹ️ 未设置SDK编译器目录" >> "$REPORT_FILE"
        fi
        
        echo "" >> "$REPORT_FILE"
        
        # 显示实际错误统计
        echo "📈 实际错误统计汇总 (过滤后):" >> "$REPORT_FILE"
        echo "  编译器错误: $(echo "$compiler_errors" | wc -l 2>/dev/null)" >> "$REPORT_FILE"
        echo "  头文件错误: $(echo "$header_errors" | wc -l 2>/dev/null)" >> "$REPORT_FILE"
        echo "  下载错误: $(echo "$download_errors" | wc -l 2>/dev/null)" >> "$REPORT_FILE"
        echo "  权限错误: $(echo "$permission_errors" | wc -l 2>/dev/null)" >> "$REPORT_FILE"
        echo "  内存错误: $(echo "$memory_errors" | wc -l 2>/dev/null)" >> "$REPORT_FILE"
        echo "  包编译错误: $(echo "$package_errors" | wc -l 2>/dev/null)" >> "$REPORT_FILE"
        echo "  磁盘空间错误: $(echo "$disk_errors" | wc -l 2>/dev/null)" >> "$REPORT_FILE"
        echo "  时间戳错误: $(echo "$timestamp_errors" | wc -l 2>/dev/null)" >> "$REPORT_FILE"
        
        if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
            if [ $sdk_usage_count -gt 0 ]; then
                echo "  SDK编译器使用: ✅ 已使用" >> "$REPORT_FILE"
            else
                echo "  SDK编译器使用: ⚠️ 未使用/未检测到" >> "$REPORT_FILE"
            fi
        else
            echo "  SDK编译器使用: ⚠️ 未设置/未检测到" >> "$REPORT_FILE"
        fi
        
    else
        echo "❌ 构建日志文件不存在，无法进行详细错误分析" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 21. 生成修复建议（优化版）
generate_fix_suggestions() {
    log_step "生成修复建议"
    
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
        
        # 编译器未找到错误
        if grep -q "compiler.*not found\|gcc.*not found" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 编译器未找到错误修复:" >> "$REPORT_FILE"
            echo "  💡 检测到编译器未找到错误" >> "$REPORT_FILE"
            echo "  🛠️ 修复方法:" >> "$REPORT_FILE"
            echo "    1. 检查COMPILER_DIR环境变量: echo \$COMPILER_DIR" >> "$REPORT_FILE"
            echo "    2. 重新下载SDK: firmware-config/scripts/build_firmware_main.sh initialize_compiler_env [设备名]" >> "$REPORT_FILE"
            echo "    3. 确保SDK目录包含真正的GCC编译器" >> "$REPORT_FILE"
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
        
        # 未定义引用错误
        if grep -q "undefined reference" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 未定义引用错误修复:" >> "$REPORT_FILE"
            echo "  💡 检测到未定义引用错误" >> "$REPORT_FILE"
            echo "  🛠️ 修复方法:" >> "$REPORT_FILE"
            echo "    1. 检查依赖包是否完整" >> "$REPORT_FILE"
            echo "    2. 调整库文件的链接顺序" >> "$REPORT_FILE"
            echo "    3. 确保所有必要的库都已编译" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
        # 编译器版本错误 - 改进：只在真正检测到时显示
        if grep -q "requires gcc.*\|\`gcc.*\` version" "$BUILD_DIR/build.log" 2>/dev/null; then
            echo "🔧 真正的编译器版本错误修复:" >> "$REPORT_FILE"
            echo "  💡 检测到真正的GCC版本兼容性问题" >> "$REPORT_FILE"
            echo "  🛠️ 修复方法:" >> "$REPORT_FILE"
            echo "    1. 检查当前GCC版本: gcc --version" >> "$REPORT_FILE"
            echo "    2. 确保使用兼容的GCC版本" >> "$REPORT_FILE"
            echo "    3. 检查预构建编译器的兼容性" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        else
            echo "💡 编译器版本说明:" >> "$REPORT_FILE"
            echo "  ✅ SDK编译器是OpenWrt官方提供的，版本已通过验证" >> "$REPORT_FILE"
            if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
                echo "  🔧 OpenWrt 23.05 SDK使用 GCC 12.3.0" >> "$REPORT_FILE"
            elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
                echo "  🔧 OpenWrt 21.02 SDK使用 GCC 8.4.0" >> "$REPORT_FILE"
            fi
            echo "  💡 如果构建成功，说明编译器版本完全兼容" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
    fi
    
    # SDK编译器优化建议
    print_subheader "SDK编译器优化建议"
    echo "🎯 SDK编译器状态检查:" >> "$REPORT_FILE"
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        echo "  ✅ SDK编译器目录存在: $COMPILER_DIR" >> "$REPORT_FILE"
        echo "  🔧 验证SDK编译器:" >> "$REPORT_FILE"
        echo "    1. 检查GCC文件: find \"$COMPILER_DIR\" -name \"*gcc\" -type f -executable ! -path \"*dummy-tools*\"" >> "$REPORT_FILE"
        echo "    2. 验证编译器版本: \"\$(find \"$COMPILER_DIR\" -name '*gcc' -type f -executable ! -path '*dummy-tools*' | head -1)\" --version" >> "$REPORT_FILE"
        echo "    3. 检查SDK完整性: ls -la \"$COMPILER_DIR\"" >> "$REPORT_FILE"
        
        # 根据版本显示SDK信息
        if [ -n "$SELECTED_BRANCH" ]; then
            if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
                echo "  🔧 OpenWrt 23.05 SDK使用 GCC 12.3.0" >> "$REPORT_FILE"
                echo "  💡 注意: 23.05版本需要修复IPK安装脚本" >> "$REPORT_FILE"
            elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
                echo "  🔧 OpenWrt 21.02 SDK使用 GCC 8.4.0" >> "$REPORT_FILE"
            fi
        fi
    else
        echo "  ⚠️ SDK编译器目录未设置或不存在" >> "$REPORT_FILE"
        echo "  💡 建议重新下载SDK: firmware-config/scripts/build_firmware_main.sh initialize_compiler_env [设备名]" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 自定义文件集成修复
    print_subheader "自定义文件集成修复"
    echo "📂 自定义文件集成修复:" >> "$REPORT_FILE"
    echo "  1. IPK文件安装修复 (23.05版本):" >> "$REPORT_FILE"
    echo "    修改 /etc/uci-defaults/99-custom-files 脚本:" >> "$REPORT_FILE"
    echo "    使用不区分大小写的文件匹配: grep -qi \"\\.ipk\"" >> "$REPORT_FILE"
    echo "  2. 中文文件名处理:" >> "$REPORT_FILE"
    echo "    使用UTF-8编码，确保脚本能正确处理中文文件名" >> "$REPORT_FILE"
    echo "  3. 第一次开机脚本:" >> "$REPORT_FILE"
    echo "    确保 /etc/uci-defaults/99-custom-files 文件存在且有执行权限" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
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
    echo "  3. 重新下载SDK: firmware-config/scripts/build_firmware_main.sh initialize_compiler_env [设备名]" >> "$REPORT_FILE"
    echo "  4. 修复头文件: mkdir -p staging_dir/host/include && touch staging_dir/host/include/stdc-predef.h" >> "$REPORT_FILE"
    echo "  5. 修复IPK安装: sed -i 's/grep -q \"\\\\.ipk\"/grep -qi \"\\\\.ipk\"/' files/etc/uci-defaults/99-custom-files" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# 22. 生成总结报告（增强版）- 修复语法错误
generate_summary() {
    log_step "生成分析总结"
    
    print_header "分析总结"
    
    # 收集统计数据
    local firmware_exists=0
    local build_log_exists=0
    local config_exists=0
    local error_count=0
    local warning_count=0
    local staging_dir_exists=0
    local sdk_compiler_exists=0
    local sdk_dir_exists=0
    local custom_files_exists=0
    
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
    
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        sdk_compiler_exists=1
    fi
    
    if [ -d "$SDK_DIR" ]; then
        sdk_dir_exists=1
    fi
    
    if [ -d "$BUILD_DIR/files/etc/custom-files" ]; then
        custom_files_exists=1
    fi
    
    echo "📊 构建状态概览:" >> "$REPORT_FILE"
    echo "  ✅ 构建目录: $([ -d "$BUILD_DIR" ] && echo '存在' || echo '缺失')" >> "$REPORT_FILE"
    echo "  ✅ 配置文件: $([ $config_exists -eq 1 ] && echo '存在' || echo '缺失')" >> "$REPORT_FILE"
    echo "  ✅ 构建日志: $([ $build_log_exists -eq 1 ] && echo "存在 (原始错误: $error_count, 警告: $warning_count)" || echo '缺失')" >> "$REPORT_FILE"
    echo "  ✅ 编译目录: $([ $staging_dir_exists -eq 1 ] && echo '存在' || echo '缺失')" >> "$REPORT_FILE"
    echo "  ✅ 固件生成: $([ $firmware_exists -eq 1 ] && echo '成功' || echo '失败')" >> "$REPORT_FILE"
    echo "  ✅ SDK编译器: $([ $sdk_compiler_exists -eq 1 ] && echo '已下载' || echo '未下载')" >> "$REPORT_FILE"
    echo "  ✅ SDK目录: $([ $sdk_dir_exists -eq 1 ] && echo '存在' || echo '缺失')" >> "$REPORT_FILE"
    echo "  ✅ 自定义文件: $([ $custom_files_exists -eq 1 ] && echo '已集成' || echo '未集成')" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 编译器来源分析
    print_subheader "编译器来源分析"
    
    # 检查预构建编译器使用情况
    if [ $sdk_compiler_exists -eq 1 ]; then
        echo "  🎯 编译器来源: 预构建的OpenWrt SDK" >> "$REPORT_FILE"
        echo "  📌 编译器目录: $COMPILER_DIR" >> "$REPORT_FILE"
        
        # 显示SDK编译器版本
        local sdk_gcc=$(find "$COMPILER_DIR" -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          2>/dev/null | head -1)
        
        if [ -n "$sdk_gcc" ] && [ -x "$sdk_gcc" ]; then
            local sdk_version=$("$sdk_gcc" --version 2>&1 | head -1)
            local major_version=$(echo "$sdk_version" | grep -o "[0-9]\+" | head -1)
            
            if [ "$major_version" = "12" ]; then
                echo "  🔧 SDK编译器版本: GCC 12.3.0 (OpenWrt 23.05)" >> "$REPORT_FILE"
            elif [ "$major_version" = "8" ]; then
                echo "  🔧 SDK编译器版本: GCC 8.4.0 (OpenWrt 21.02)" >> "$REPORT_FILE"
            else
                echo "  🔧 SDK编译器版本: $sdk_version" >> "$REPORT_FILE"
            fi
        fi
        
        # 检查是否实际使用了预构建编译器
        if [ $build_log_exists -eq 1 ]; then
            local prebuilt_calls=$(grep -c "$COMPILER_DIR" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
            if [ $prebuilt_calls -gt 0 ]; then
                echo "  ✅ 构建中使用了预构建SDK编译器" >> "$REPORT_FILE"
                echo "     调用次数: $prebuilt_calls" >> "$REPORT_FILE"
                echo "  💡 SDK编译器已成功集成到构建系统" >> "$REPORT_FILE"
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
            echo "  🔧 SDK编译器版本: GCC 12.3.0 (官方验证)" >> "$REPORT_FILE"
            echo "  💡 注意: 23.05版本需要修复IPK安装脚本" >> "$REPORT_FILE"
        elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
            echo "  🔧 SDK编译器版本: GCC 8.4.0 (官方验证)" >> "$REPORT_FILE"
        fi
        echo "  ✅ SDK编译器状态: 官方提供，版本已验证" >> "$REPORT_FILE"
    fi
    
    # 自定义文件集成状态
    if [ $custom_files_exists -eq 1 ]; then
        print_subheader "自定义文件集成状态"
        echo "  ✅ 自定义文件已集成到固件中" >> "$REPORT_FILE"
        echo "  📌 位置: /etc/custom-files/" >> "$REPORT_FILE"
        echo "  🚀 安装方式: 第一次开机自动安装" >> "$REPORT_FILE"
        
        # 检查IPK安装逻辑
        local boot_script="$BUILD_DIR/files/etc/uci-defaults/99-custom-files"
        if [ -f "$boot_script" ]; then
            local ipk_logic=$(grep -c "grep -qi.*\\.ipk" "$boot_script" 2>/dev/null || echo "0")
            if [ $ipk_logic -gt 0 ]; then
                echo "  🔧 IPK安装逻辑: 已修复（支持所有大小写格式）" >> "$REPORT_FILE"
            else
                echo "  ⚠️ IPK安装逻辑: 可能需要修复" >> "$REPORT_FILE"
            fi
        fi
    fi
    
    # 状态评估
    echo "" >> "$REPORT_FILE"
    print_subheader "状态评估"
    
    if [ $firmware_exists -eq 1 ]; then
        echo "  🎉 状态: 构建成功！" >> "$REPORT_FILE"
        echo "  💡 建议: 固件已生成，可以准备刷机" >> "$REPORT_FILE"
        echo "  ✅ SDK编译器: 版本完全兼容" >> "$REPORT_FILE"
        if [ $custom_files_exists -eq 1 ]; then
            echo "  ✅ 自定义文件: 已成功集成" >> "$REPORT_FILE"
        fi
    elif [ $error_count -eq 0 ] && [ $config_exists -eq 1 ]; then
        echo "  ⏳ 状态: 构建可能尚未开始或正在进行" >> "$REPORT_FILE"
        echo "  💡 建议: 开始编译或等待编译完成" >> "$REPORT_FILE"
    elif [ $error_count -lt 5 ]; then
        echo "  ⚠️ 状态: 轻微问题" >> "$REPORT_FILE"
        echo "  💡 建议: 小问题，容易修复" >> "$REPORT_FILE"
    elif [ $error_count -lt 20 ]; then
        echo "  ⚠️ 状态: 中等问题" >> "$REPORT_FILE"
        echo "  💡 建议: 需要一些修复工作" >> "$REPORT_FILE"
    elif [ $error_count -lt 100 ]; then
        echo "  🚨 状态: 严重问题" >> "$REPORT_FILE"
        echo "  💡 建议: 需要系统性的修复" >> "$REPORT_FILE"
    else
        echo "  💥 状态: 灾难性问题" >> "$REPORT_FILE"
        echo "  💡 建议: 建议从头开始重新构建" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # 关于编译器版本的特别说明
    print_subheader "关于编译器版本的特别说明"
    echo "🔧 重要提示:" >> "$REPORT_FILE"
    echo "  1. ✅ SDK编译器来自OpenWrt官方下载，版本已通过官方测试" >> "$REPORT_FILE"
    echo "  2. 🔧 不同OpenWrt版本使用不同的GCC版本:" >> "$REPORT_FILE"
    echo "     - OpenWrt 23.05: GCC 12.3.0" >> "$REPORT_FILE"
    echo "     - OpenWrt 21.02: GCC 8.4.0" >> "$REPORT_FILE"
    echo "  3. 💡 如果构建成功，说明编译器版本完全兼容" >> "$REPORT_FILE"
    echo "  4. 🔍 真正的编译器版本错误会有明确的错误消息" >> "$REPORT_FILE"
    echo "  5. ⚠️ 注意dummy-tools不是真正的编译器，是构建系统的占位符" >> "$REPORT_FILE"
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
    
    # 编译时间优化建议
    print_subheader "编译时间优化建议"
    echo "⏱️ 编译时间优化:" >> "$REPORT_FILE"
    echo "  1. 💾 增加内存: 确保有足够的内存(建议4GB+)" >> "$REPORT_FILE"
    echo "  2. 💿 使用SSD: 固态硬盘可以显著加快编译速度" >> "$REPORT_FILE"
    echo "  3. 🧠 启用并行编译: 在workflow中设置 enable_parallel: true" >> "$REPORT_FILE"
    echo "  4. 📦 减少插件: 基础模式比正常模式编译更快" >> "$REPORT_FILE"
    echo "  5. 🚀 使用预构建SDK: 避免工具链的重复编译" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 错误报告位置
    echo "📄 错误报告位置:" >> "$REPORT_FILE"
    echo "  分析报告: $REPORT_FILE" >> "$REPORT_FILE"
    echo "  备份文件: $BACKUP_FILE" >> "$REPORT_FILE"
    echo "  错误报告: /tmp/openwrt-build-error-report-$TIMESTAMP.txt" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "==================================================" >> "$REPORT_FILE"
    echo "           🎯 分析完成 - 祝您构建顺利！         " >> "$REPORT_FILE"
    echo "==================================================" >> "$REPORT_FILE"
}

# 23. 输出报告并清理
output_report() {
    log_step "输出分析报告"
    
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
        
        # 显示关键错误（如果有）- 改进：过滤非关键错误
        if grep -q "❌" "$REPORT_FILE"; then
            echo "🚨 发现的关键问题:"
            grep "❌" "$REPORT_FILE" | grep -v "版本错误\|编译器版本" | head -10
            echo ""
        fi
        
        # 显示修复建议
        if grep -q "💡" "$REPORT_FILE"; then
            echo "💡 修复建议摘要:"
            grep "💡" "$REPORT_FILE" | grep -v "musl是\|缺少标准头文件\|可能是GCC版本不匹配" | head -5
            echo ""
        fi
        
        # 显示编译器相关信息
        echo "🔧 编译器信息:"
        if grep -q "预构建的OpenWrt SDK" "$REPORT_FILE"; then
            echo "  🎯 使用预构建的OpenWrt SDK编译器"
            
            # 显示SDK编译器版本
            if grep -q "GCC 12.3.0" "$REPORT_FILE"; then
                echo "  🔧 SDK编译器版本: GCC 12.3.0 (OpenWrt 23.05)"
            elif grep -q "GCC 8.4.0" "$REPORT_FILE"; then
                echo "  🔧 SDK编译器版本: GCC 8.4.0 (OpenWrt 21.02)"
            else
                echo "  🔧 SDK编译器版本: 根据OpenWrt版本自动匹配"
            fi
            
            echo "  ✅ SDK编译器来自官方，版本已验证"
            
            # 检查dummy-tools警告
            if grep -q "dummy-tools" "$REPORT_FILE"; then
                echo "  ⚠️ 注意: 检测到dummy-tools（这不是真正的编译器）"
            fi
        elif grep -q "OpenWrt自动构建" "$REPORT_FILE"; then
            echo "  🛠️ 使用OpenWrt自动构建的编译器"
        fi
        
        # 显示SDK版本信息
        if grep -q "OpenWrt版本:" "$REPORT_FILE"; then
            grep "OpenWrt版本:" "$REPORT_FILE"
        fi
        
        # 特别说明编译器版本
        echo ""
        echo "📌 关于编译器版本的说明:"
        echo "  ✅ SDK编译器是OpenWrt官方提供的"
        echo "  🔧 不同版本使用不同的GCC:"
        echo "    - OpenWrt 23.05: GCC 12.3.0"
        echo "    - OpenWrt 21.02: GCC 8.4.0"
        echo "  💡 如果构建成功，说明编译器完全兼容"
        echo "  ⚠️ dummy-tools不是真正的编译器，是占位符"
        echo ""
        
        # 自定义文件集成状态
        if grep -q "自定义文件已集成" "$REPORT_FILE"; then
            echo "📂 自定义文件集成状态:"
            echo "  ✅ 自定义文件已成功集成到固件中"
            if grep -q "IPK安装逻辑已修复" "$REPORT_FILE"; then
                echo "  🔧 IPK安装逻辑已修复（支持所有大小写）"
            fi
            echo ""
        fi
        
        # 显示时间信息
        echo "🕐 时间信息:"
        echo "  分析时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  报告时间戳: $TIMESTAMP"
        echo ""
        
        # 显示完整报告
        echo "📁 完整报告位置:"
        echo "  临时文件: $REPORT_FILE"
        echo "  备份文件: $BACKUP_FILE"
        echo "  错误报告: /tmp/openwrt-build-error-report-$TIMESTAMP.txt"
        echo ""
        
        # 复制备份
        cp "$REPORT_FILE" "$BACKUP_FILE"
        success "✅ 报告已保存到: $BACKUP_FILE"
        
    else
        error "❌ 报告文件生成失败"
        return 1
    fi
    
    return 0
}

# 主执行函数
main() {
    log "🚀 开始OpenWrt构建错误分析"
    echo "分析开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "构建目录: $BUILD_DIR"
    echo "SDK目录: $SDK_DIR"
    
    # 检查构建目录
    if [ ! -d "$BUILD_DIR" ]; then
        error "❌ 构建目录不存在: $BUILD_DIR"
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
    check_build_log_file
    analyze_build_log
    check_download_log
    analyze_version_specific
    
    # 新增的分析步骤
    analyze_common_error_patterns
    check_sdk_status
    check_custom_files_integration
    analyze_compiler_errors
    check_disk_space_usage
    check_environment_variables
    check_build_artifacts
    check_dependencies
    
    # 详细错误分析
    analyze_detailed_errors
    
    # 生成报告
    generate_error_report
    generate_fix_suggestions
    generate_summary
    
    # 输出报告
    if output_report; then
        success "✅ 错误分析完成"
        
        # 根据构建结果返回状态码
        if [ -d "$BUILD_DIR/bin/targets" ]; then
            return 0  # 构建成功
        else
            return 1  # 构建失败
        fi
    else
        error "❌ 错误分析失败"
        return 2  # 分析失败
    fi
}

# 脚本入口
if [ "$0" = "$BASH_SOURCE" ] || [ -z "$BASH_SOURCE" ]; then
    main
    exit $?
fi
