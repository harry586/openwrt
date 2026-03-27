#!/bin/bash

#【support.sh-01】
# support.sh - 设备支持管理脚本
# 位置: 根目录 /support.sh
# 版本: 3.0.5
# 功能: 管理支持的设备列表、配置文件、工具链下载
# 特点: 无硬编码，通过调用现有脚本和配置文件实现
#【support.sh-01-end】

#【support.sh-02】
set -e

# 脚本目录（根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# 构建主脚本路径
BUILD_MAIN_SCRIPT="$REPO_ROOT/firmware-config/scripts/build_firmware_main.sh"

# 配置文件目录
CONFIG_DIR="$REPO_ROOT/firmware-config/config"
#【support.sh-02-end】

#【support.sh-03】
# 支持的设备列表
# 格式: DEVICES["设备名称"]="目标平台 子目标 芯片型号"
declare -A DEVICES
DEVICES["ac42u"]="ipq40xx generic bcm47189"
DEVICES["cmcc_rax3000m"]="mediatek filogic mt7981"
DEVICES["cmcc_rax3000m-nand"]="mediatek filogic mt7981"
DEVICES["netgear_wndr3800"]="ath79 generic ar7161"
#【support.sh-03-end】

#【support.sh-04】
# OpenWrt官方SDK下载信息
# 格式: SDK_INFO["目标/子目标/版本"]="SDK_URL"
declare -A SDK_INFO

# 初始化SDK信息
init_sdk_info() {
    # OpenWrt 21.02 SDK
    SDK_INFO["ipq40xx/generic/21.02"]="https://downloads.openwrt.org/releases/21.02.7/targets/ipq40xx/generic/openwrt-sdk-21.02.7-ipq40xx-generic_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
    SDK_INFO["mediatek/filogic/21.02"]=""
    SDK_INFO["ath79/generic/21.02"]="https://downloads.openwrt.org/releases/21.02.7/targets/ath79/generic/openwrt-sdk-21.02.7-ath79-generic_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
    
    # OpenWrt 23.05 SDK
    SDK_INFO["ipq40xx/generic/23.05"]="https://downloads.openwrt.org/releases/23.05.5/targets/ipq40xx/generic/openwrt-sdk-23.05.5-ipq40xx-generic_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
    SDK_INFO["mediatek/filogic/23.05"]="https://downloads.openwrt.org/releases/23.05.5/targets/mediatek/filogic/openwrt-sdk-23.05.5-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
    SDK_INFO["ath79/generic/23.05"]="https://downloads.openwrt.org/releases/23.05.5/targets/ath79/generic/openwrt-sdk-23.05.5-ath79-generic_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
    
    # LEDE 没有官方SDK，使用源码自带工具链
    SDK_INFO["ipq40xx/generic/lede"]=""
    SDK_INFO["mediatek/filogic/lede"]=""
    SDK_INFO["ath79/generic/lede"]=""
    
    # 通用SDK（如果找不到精确匹配）
    SDK_INFO["generic/21.02"]="https://downloads.openwrt.org/releases/21.02.7/targets/x86/64/openwrt-sdk-21.02.7-x86-64_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
    SDK_INFO["generic/23.05"]="https://downloads.openwrt.org/releases/23.05.5/targets/x86/64/openwrt-sdk-23.05.5-x86-64_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
    SDK_INFO["generic/lede"]=""
}
#【support.sh-04-end】

#【support.sh-05】
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数（重定向到stderr，避免污染get-sdk-info输出）
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
}

error() {
    echo -e "${RED}❌ 错误: $1${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}⚠️ 警告: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✅ $1${NC}" >&2
}
#【support.sh-05-end】

#【support.sh-06】
# 检查构建主脚本是否存在
check_build_main_script() {
    if [ ! -f "$BUILD_MAIN_SCRIPT" ]; then
        error "构建主脚本不存在: $BUILD_MAIN_SCRIPT"
    fi
    if [ ! -x "$BUILD_MAIN_SCRIPT" ]; then
        chmod +x "$BUILD_MAIN_SCRIPT"
        log "已添加执行权限: $BUILD_MAIN_SCRIPT"
    fi
}

# 检查配置文件目录
check_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        error "配置文件目录不存在: $CONFIG_DIR"
    fi
}

# 检查函数是否存在（修复has-function问题）
function_exists() {
    local function_name="$1"
    if [ -n "$(type -t "$function_name")" ] && [ "$(type -t "$function_name")" = "function" ]; then
        return 0  # 函数存在
    else
        return 1  # 函数不存在
    fi
}
#【support.sh-06-end】

#【support.sh-07】
# 显示支持的设备列表
list_devices() {
    log "=== 支持的设备列表 (共 ${#DEVICES[@]} 个) ==="
    
    local i=1
    for device in "${!DEVICES[@]}"; do
        local platform_info="${DEVICES[$device]}"
        local target=$(echo "$platform_info" | awk '{print $1}')
        local subtarget=$(echo "$platform_info" | awk '{print $2}')
        
        echo "$i. 📱 $device"
        echo "   目标平台: $target"
        echo "   子目标: $subtarget"
        
        # 检查设备专用配置文件
        local device_config="$CONFIG_DIR/devices/$device.config"
        if [ -f "$device_config" ]; then
            echo "   📁 设备专用配置: 存在 ($(basename "$device_config"))"
        else
            echo "   ℹ️  设备专用配置: 使用通用配置"
        fi
        
        echo ""
        i=$((i+1))
    done
    
    success "设备列表显示完成"
}
#【support.sh-07-end】

#【support.sh-08】
# 验证设备是否支持
validate_device() {
    local device_name="$1"
    
    if [ -z "${DEVICES[$device_name]}" ]; then
        error "不支持的设备: $device_name。支持的设备列表: ${!DEVICES[*]}"
    fi
    
    local platform_info="${DEVICES[$device_name]}"
    local target=$(echo "$platform_info" | awk '{print $1}')
    local subtarget=$(echo "$platform_info" | awk '{print $2}')
    
    log "设备验证通过: $device_name"
    log "目标平台: $target"
    log "子目标: $subtarget"
    
    echo "$target $subtarget"
}

# 获取设备的平台信息
get_device_platform() {
    local device_name="$1"
    
    if [ -z "${DEVICES[$device_name]}" ]; then
        echo ""
        return 1
    fi
    
    echo "${DEVICES[$device_name]}"
}
#【support.sh-08-end】

#【support.sh-09】
# 获取SDK下载信息函数 - 已废弃，所有源码使用自带工具链
get_sdk_info() {
    local target="$1"
    local subtarget="$2"
    local version="$3"
    
    # 所有版本都返回空，表示使用源码自带工具链
    log "ℹ️ 所有源码类型均使用源码自带工具链，无需下载SDK"
    echo ""
    return 1
}
#【support.sh-09-end】

#【support.sh-10】
# 应用设备专用配置
apply_device_config() {
    local device_name="$1"
    local build_dir="$2"
    
    log "应用设备专用配置: $device_name"
    
    # 设备专用配置文件路径
    local device_config="$CONFIG_DIR/devices/$device_name.config"
    
    if [ ! -f "$device_config" ]; then
        log "ℹ️ 设备专用配置文件不存在: $device_config"
        log "💡 将使用通用配置"
        return 0
    fi
    
    # 检查构建目录
    if [ ! -d "$build_dir" ]; then
        error "构建目录不存在: $build_dir"
    fi
    
    # 检查.config文件
    local config_file="$build_dir/.config"
    if [ ! -f "$config_file" ]; then
        error "配置文件不存在: $config_file"
    fi
    
    log "📁 设备配置文件: $device_config"
    log "📁 构建目录: $build_dir"
    
    # 应用设备专用配置
    if [ -f "$device_config" ]; then
        log "应用设备配置..."
        cat "$device_config" >> "$config_file"
        success "设备专用配置已应用到: $config_file"
        
        # 统计添加的配置行数
        local added_lines=$(wc -l < "$device_config")
        log "添加了 $added_lines 行设备专用配置"
    else
        warn "设备配置文件不存在，跳过设备专用配置"
    fi
}
#【support.sh-10-end】

#【support.sh-11】
# 应用通用配置
apply_generic_config() {
    local config_type="$1"  # usb-generic, normal, base
    local build_dir="$2"
    
    log "应用通用配置: $config_type"
    
    # 通用配置文件路径
    local generic_config="$CONFIG_DIR/$config_type.config"
    
    if [ ! -f "$generic_config" ]; then
        error "通用配置文件不存在: $generic_config"
    fi
    
    # 检查构建目录
    if [ ! -d "$build_dir" ]; then
        error "构建目录不存在: $build_dir"
    fi
    
    # 检查.config文件
    local config_file="$build_dir/.config"
    if [ ! -f "$config_file" ]; then
        error "配置文件不存在: $config_file"
    fi
    
    log "📁 通用配置文件: $generic_config"
    log "📁 构建目录: $build_dir"
    
    # 应用通用配置
    if [ -f "$generic_config" ]; then
        log "应用通用配置: $config_type"
        cat "$generic_config" >> "$config_file"
        success "通用配置已应用到: $config_file"
        
        # 统计添加的配置行数
        local added_lines=$(wc -l < "$generic_config")
        log "添加了 $added_lines 行通用配置"
    else
        error "通用配置文件不存在: $generic_config"
    fi
}
#【support.sh-11-end】

#【support.sh-12】
# 初始化编译器环境（调用主脚本）
initialize_compiler() {
    local device_name="$1"
    
    log "初始化编译器环境（所有源码类型均使用源码自带工具链）..."
    
    check_build_main_script
    
    # 调用主脚本的initialize_compiler_env函数
    "$BUILD_MAIN_SCRIPT" initialize_compiler_env "$device_name"
    
    if [ $? -eq 0 ]; then
        success "编译器环境初始化完成"
    else
        warn "编译器环境初始化可能有问题，但继续执行"
    fi
}

# 验证编译器文件
verify_compiler() {
    log "验证编译器文件..."
    
    check_build_main_script
    
    # 调用主脚本的verify_compiler_files函数
    "$BUILD_MAIN_SCRIPT" verify_compiler_files
    
    if [ $? -eq 0 ]; then
        success "编译器文件验证通过"
    else
        warn "编译器文件验证发现问题，但继续执行"
    fi
}
#【support.sh-12-end】

#【support.sh-13】
# 检查编译器调用状态
check_compiler_invocation() {
    log "检查编译器调用状态..."
    
    check_build_main_script
    
    # 调用主脚本的check_compiler_invocation函数
    "$BUILD_MAIN_SCRIPT" check_compiler_invocation
    
    success "编译器调用状态检查完成"
}

# 检查USB配置
check_usb_config() {
    local build_dir="$1"
    
    log "检查USB配置..."
    
    check_build_main_script
    
    # 切换到构建目录
    cd "$build_dir" || error "无法进入构建目录: $build_dir"
    
    # 调用主脚本的verify_usb_config函数
    "$BUILD_MAIN_SCRIPT" verify_usb_config
    
    success "USB配置检查完成"
}
#【support.sh-13-end】

#【support.sh-14】
# 检查USB驱动完整性
check_usb_drivers_integrity() {
    local build_dir="$1"
    
    log "检查USB驱动完整性..."
    
    check_build_main_script
    
    # 切换到构建目录
    cd "$build_dir" || error "无法进入构建目录: $build_dir"
    
    # 调用主脚本的check_usb_drivers_integrity函数
    "$BUILD_MAIN_SCRIPT" check_usb_drivers_integrity
    
    success "USB驱动完整性检查完成"
}
#【support.sh-14-end】

#【support.sh-15】
# 显示配置文件信息
show_config_info() {
    local device_name="$1"
    local config_mode="$2"  # normal 或 base
    local build_dir="$3"
    
    log "=== 配置文件信息 ==="
    
    # 显示设备信息
    local platform_info=$(get_device_platform "$device_name")
    if [ -n "$platform_info" ]; then
        local target=$(echo "$platform_info" | awk '{print $1}')
        local subtarget=$(echo "$platform_info" | awk '{print $2}')
        
        echo "📱 设备: $device_name"
        echo "🎯 目标平台: $target/$subtarget"
    else
        warn "未知设备: $device_name"
    fi
    
    echo "⚙️ 配置模式: $config_mode"
    echo "📁 构建目录: $build_dir"
    
    # 显示配置文件状态
    echo ""
    echo "📋 配置文件状态:"
    
    # 通用配置文件
    local usb_config="$CONFIG_DIR/usb-generic.config"
    local mode_config="$CONFIG_DIR/$config_mode.config"
    local device_config="$CONFIG_DIR/devices/$device_name.config"
    
    if [ -f "$usb_config" ]; then
        echo "  ✅ USB通用配置: $(basename "$usb_config") ($(wc -l < "$usb_config") 行)"
    else
        echo "  ❌ USB通用配置: 不存在"
    fi
    
    if [ -f "$mode_config" ]; then
        echo "  ✅ 模式配置: $(basename "$mode_config") ($(wc -l < "$mode_config") 行)"
    else
        echo "  ❌ 模式配置: 不存在"
    fi
    
    if [ -f "$device_config" ]; then
        echo "  ✅ 设备专用配置: $(basename "$device_config") ($(wc -l < "$device_config") 行)"
    else
        echo "  ⚪ 设备专用配置: 未配置（使用通用配置）"
    fi
    
    # 检查最终配置文件
    local final_config="$build_dir/.config"
    if [ -f "$final_config" ]; then
        echo ""
        echo "📄 最终配置文件: $(basename "$final_config")"
        echo "📏 文件大小: $(ls -lh "$final_config" | awk '{print $5}')"
        echo "📝 总行数: $(wc -l < "$final_config") 行"
        
        # 统计启用的包数量
        local enabled_count=$(grep -c "^CONFIG_PACKAGE_.*=y$" "$final_config" 2>/dev/null || echo "0")
        local disabled_count=$(grep -c "^# CONFIG_PACKAGE_.* is not set$" "$final_config" 2>/dev/null || echo "0")
        
        echo "📊 包统计:"
        echo "  ✅ 已启用: $enabled_count 个"
        echo "  ❌ 已禁用: $disabled_count 个"
        
        # 检查关键USB配置
        echo ""
        echo "🔧 关键USB配置状态:"
        local critical_drivers=(
            "kmod-usb-core"
            "kmod-usb2"
            "kmod-usb3"
            "kmod-usb-xhci-hcd"
            "kmod-usb-storage"
            "kmod-scsi-core"
        )
        
        for driver in "${critical_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" "$final_config"; then
                echo "  ✅ $driver"
            else
                echo "  ❌ $driver"
            fi
        done
        
        # 检查libustream冲突
        echo ""
        echo "🚨 libustream冲突检查:"
        local openssl_enabled=$(grep -c "^CONFIG_PACKAGE_libustream-openssl" "$final_config" 2>/dev/null || echo "0")
        local wolfssl_enabled=$(grep -c "^CONFIG_PACKAGE_libustream-wolfssl" "$final_config" 2>/dev/null || echo "0")
        
        if [ $openssl_enabled -gt 0 ] && [ $wolfssl_enabled -gt 0 ]; then
            echo "  ⚠️ 发现libustream-openssl和libustream-wolfssl冲突"
            echo "  💡 需要在配置中禁用其中一个"
        else
            echo "  ✅ 没有libustream冲突"
        fi
    else
        echo ""
        warn "最终配置文件不存在: $final_config"
    fi
    
    success "配置文件信息显示完成"
}
#【support.sh-15-end】

#【support.sh-16】
# 保存源代码信息
save_source_info() {
    local build_dir="$1"
    
    log "保存源代码信息..."
    
    check_build_main_script
    
    # 切换到构建目录
    cd "$build_dir" || error "无法进入构建目录: $build_dir"
    
    # 调用主脚本的save_source_code_info函数
    "$BUILD_MAIN_SCRIPT" save_source_code_info
    
    success "源代码信息保存完成"
}
#【support.sh-16-end】

#【support.sh-17】
# 搜索编译器文件（调用主脚本）
search_compiler_files() {
    local search_root="${1:-/tmp}"
    local target_platform="${2:-generic}"
    
    log "搜索编译器文件..."
    
    check_build_main_script
    
    # 调用主脚本的search_compiler_files函数
    "$BUILD_MAIN_SCRIPT" search_compiler_files "$search_root" "$target_platform"
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "找到编译器文件"
        return 0
    else
        log "未找到本地编译器文件，将下载OpenWrt官方SDK"
        return 1
    fi
}

# 智能平台感知的编译器搜索（调用主脚本）
intelligent_platform_aware_compiler_search() {
    local search_root="${1:-/tmp}"
    local target_platform="$2"
    local device_name="$3"
    
    log "智能平台感知的编译器搜索..."
    
    check_build_main_script
    
    # 调用主脚本的intelligent_platform_aware_compiler_search函数
    "$BUILD_MAIN_SCRIPT" intelligent_platform_aware_compiler_search "$search_root" "$target_platform" "$device_name"
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "智能编译器搜索完成"
        return 0
    else
        log "智能编译器搜索未找到本地编译器，将下载OpenWrt官方SDK"
        return 1
    fi
}
#【support.sh-17-end】

#【support.sh-18】
# 通用编译器搜索（调用主脚本）
universal_compiler_search() {
    local search_root="${1:-/tmp}"
    local device_name="${2:-unknown}"
    
    log "通用编译器搜索..."
    
    check_build_main_script
    
    # 调用主脚本的universal_compiler_search函数
    "$BUILD_MAIN_SCRIPT" universal_compiler_search "$search_root" "$device_name"
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "通用编译器搜索完成"
        return 0
    else
        log "通用编译器搜索未找到本地编译器，将下载OpenWrt官方SDK"
        return 1
    fi
}

# 简单编译器文件搜索（调用主脚本）
search_compiler_files_simple() {
    local search_root="${1:-/tmp}"
    local target_platform="${2:-generic}"
    
    log "简单编译器文件搜索..."
    
    check_build_main_script
    
    # 调用主脚本的search_compiler_files_simple函数
    "$BUILD_MAIN_SCRIPT" search_compiler_files_simple "$search_root" "$target_platform"
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "简单编译器搜索完成"
        return 0
    else
        log "简单编译器搜索未找到本地编译器，将下载OpenWrt官方SDK"
        return 1
    fi
}
#【support.sh-18-end】

#【support.sh-19】
# 前置错误检查（调用主脚本）
pre_build_error_check() {
    log "前置错误检查..."
    
    check_build_main_script
    
    # 调用主脚本的pre_build_error_check函数
    "$BUILD_MAIN_SCRIPT" pre_build_error_check
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "前置错误检查通过"
        return 0
    else
        error "前置错误检查失败"
    fi
}

# 应用配置（调用主脚本）
apply_config() {
    log "应用配置..."
    
    check_build_main_script
    
    # 调用主脚本的apply_config函数
    "$BUILD_MAIN_SCRIPT" apply_config
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "配置应用完成"
        return 0
    else
        error "配置应用失败"
    fi
}
#【support.sh-19-end】

#【support.sh-20】
# 完整配置流程
full_config_process() {
    local device_name="$1"
    local config_mode="$2"
    local build_dir="$3"
    local extra_packages="${4:-}"
    
    log "=== 开始完整配置流程 ==="
    log "设备: $device_name"
    log "配置模式: $config_mode"
    log "构建目录: $build_dir"
    log "额外包: $extra_packages"
    
    # 设备名转换：将带后缀的设备名转换为基础设备名
    local converted_device="$device_name"
    case "$device_name" in
        cmcc_rax3000m-nand|cmcc_rax3000m-emmc|cmcc_rax3000m-sd)
            converted_device="cmcc_rax3000m"
            log "🔧 设备名转换: $device_name -> $converted_device (使用 DTS overlay)"
            ;;
    esac
    
    # 验证设备
    validate_device "$converted_device" > /dev/null
    
    # 检查构建目录
    if [ ! -d "$build_dir" ]; then
        error "构建目录不存在: $build_dir"
    fi
    
    # 切换到构建目录
    cd "$build_dir" || error "无法进入构建目录: $build_dir"
    
    # 生成基础配置（调用主脚本）
    log "生成基础配置..."
    "$BUILD_MAIN_SCRIPT" generate_config "$extra_packages" "$converted_device"
    
    if [ $? -ne 0 ]; then
        error "生成基础配置失败"
    fi
    
    # 应用USB通用配置
    apply_generic_config "usb-generic" "$build_dir"
    
    # 应用模式配置
    apply_generic_config "$config_mode" "$build_dir"
    
    # 应用设备专用配置
    apply_device_config "$converted_device" "$build_dir"
    
    # 应用配置（调用主脚本）
    apply_config
    
    # 显示配置信息
    show_config_info "$converted_device" "$config_mode" "$build_dir"
    
    success "完整配置流程完成"
}
#【support.sh-20-end】

#【support.sh-21】
# 显示帮助信息
show_help() {
    echo "📱 设备支持管理脚本 (support.sh)"
    echo "位置: 根目录 /support.sh"
    echo ""
    echo "使用方法: ./support.sh [命令] [参数]"
    echo ""
    echo "命令列表:"
    echo "  list-devices              显示支持的设备列表"
    echo "  validate-device <设备名>   验证设备是否支持"
    echo "  get-platform <设备名>      获取设备的平台信息"
    echo "  get-sdk-info <目标> <子目标> <版本>"
    echo "                           获取SDK下载信息"
    echo "  full-config <设备名> <模式> <构建目录> [额外包]"
    echo "                           执行完整配置流程"
    echo "  apply-device-config <设备名> <构建目录>"
    echo "                           应用设备专用配置"
    echo "  apply-generic-config <类型> <构建目录>"
    echo "                           应用通用配置 (usb-generic, normal, base)"
    echo "  initialize-compiler <设备名>"
    echo "                           初始化编译器环境"
    echo "  verify-compiler           验证编译器文件"
    echo "  check-compiler            检查编译器调用状态"
    echo "  check-usb <构建目录>      检查USB配置"
    echo "  check-usb-drivers <构建目录>"
    echo "                           检查USB驱动完整性"
    echo "  show-config-info <设备名> <模式> <构建目录>"
    echo "                           显示配置文件信息"
    echo "  save-source-info <构建目录>"
    echo "                           保存源代码信息"
    echo "  pre-build-check           前置错误检查"
    echo "  apply-config             应用配置"
    echo ""
    echo "编译器搜索命令 (调用主脚本):"
    echo "  search-compiler [搜索根目录] [目标平台]"
    echo "  intelligent-search [搜索根目录] [目标平台] [设备名]"
    echo "  universal-search [搜索根目录] [设备名]"
    echo "  simple-search [搜索根目录] [目标平台]"
    echo ""
    echo "支持的设备列表 (仅3个设备):"
    for device in "${!DEVICES[@]}"; do
        echo "  📱 $device"
    done
    echo ""
    echo "配置文件位置:"
    echo "  USB通用配置: firmware-config/config/usb-generic.config"
    echo "  正常模式: firmware-config/config/normal.config"
    echo "  基础模式: firmware-config/config/base.config"
    echo "  设备配置: firmware-config/config/devices/[设备名].config"
    echo ""
    echo "示例:"
    echo "  ./support.sh list-devices"
    echo "  ./support.sh validate-device ac42u"
    echo "  ./support.sh get-sdk-info ipq40xx generic 21.02"
    echo "  ./support.sh full-config ac42u normal /mnt/openwrt-build"
    echo "  ./support.sh initialize-compiler ac42u"
    echo ""
}
#【support.sh-21-end】

#【support.sh-22】
# 主函数
main() {
    local command="$1"
    
    # 初始化SDK信息
    init_sdk_info
    
    # 检查构建主脚本和配置目录
    check_build_main_script
    check_config_dir
    
    case "$command" in
        "list-devices")
            list_devices
            ;;
        "validate-device")
            if [ -z "$2" ]; then
                error "请提供设备名称"
            fi
            validate_device "$2"
            ;;
        "get-platform")
            if [ -z "$2" ]; then
                error "请提供设备名称"
            fi
            get_device_platform "$2"
            ;;
        "get-sdk-info")
            if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
                error "使用方法: ./support.sh get-sdk-info <目标> <子目标> <版本>"
            fi
            get_sdk_info "$2" "$3" "$4"
            ;;
        "full-config")
            if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
                error "使用方法: ./support.sh full-config <设备名> <模式> <构建目录> [额外包]"
            fi
            full_config_process "$2" "$3" "$4" "$5"
            ;;
        "apply-device-config")
            if [ -z "$2" ] || [ -z "$3" ]; then
                error "使用方法: ./support.sh apply-device-config <设备名> <构建目录>"
            fi
            apply_device_config "$2" "$3"
            ;;
        "apply-generic-config")
            if [ -z "$2" ] || [ -z "$3" ]; then
                error "使用方法: ./support.sh apply-generic-config <类型> <构建目录>"
            fi
            apply_generic_config "$2" "$3"
            ;;
        "initialize-compiler")
            if [ -z "$2" ]; then
                error "请提供设备名称"
            fi
            initialize_compiler "$2"
            ;;
        "verify-compiler")
            verify_compiler
            ;;
        "check-compiler")
            check_compiler_invocation
            ;;
        "check-usb")
            if [ -z "$2" ]; then
                error "请提供构建目录"
            fi
            check_usb_config "$2"
            ;;
        "check-usb-drivers")
            if [ -z "$2" ]; then
                error "请提供构建目录"
            fi
            check_usb_drivers_integrity "$2"
            ;;
        "show-config-info")
            if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
                error "使用方法: ./support.sh show-config-info <设备名> <模式> <构建目录>"
            fi
            show_config_info "$2" "$3" "$4"
            ;;
        "save-source-info")
            if [ -z "$2" ]; then
                error "请提供构建目录"
            fi
            save_source_info "$2"
            ;;
        "search-compiler")
            search_compiler_files "$2" "$3"
            ;;
        "intelligent-search")
            intelligent_platform_aware_compiler_search "$2" "$3" "$4"
            ;;
        "universal-search")
            universal_compiler_search "$2" "$3"
            ;;
        "simple-search")
            search_compiler_files_simple "$2" "$3"
            ;;
        "pre-build-check")
            pre_build_error_check
            ;;
        "apply-config")
            apply_config
            ;;
        "help"|"-h"|"--help"|"")
            show_help
            ;;
        *)
            error "未知命令: $command。使用 './support.sh help' 查看帮助信息"
            ;;
    esac
}
#【support.sh-22-end】

#【support.sh-23】
# 运行主函数
main "$@"
#【support.sh-23-end】
