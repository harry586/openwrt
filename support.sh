#!/bin/bash

#【support.sh-01】
# support.sh - 设备支持管理脚本
# 位置: 根目录 /support.sh
# 版本: 3.1.0
# 最后更新: 2026-03-01
# 功能: 管理支持的设备列表、配置文件
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
# 支持的设备列表（支持变体）
# 格式: DEVICES["设备名称"]="目标平台 子目标 芯片型号 [变体类型]"
declare -A DEVICES

# 设备命名规范：
# 1. 基础名称：厂商_型号（如 cmcc_rax3000m-nand、asus_rt-ac42u）
# 2. 有变体的设备：基础名称-变体（如 cmcc_rax3000m-nand、cmcc_rax3000m-emmc）
# 3. 无变体的设备：直接使用基础名称（如 asus_rt-ac42u）

# 动态检测设备 - 通过扫描配置文件目录和源码
detect_devices_dynamic() {
    local config_dir="$REPO_ROOT/firmware-config/config"
    local devices_found=()
    
    # 1. 从设备配置文件目录检测
    if [ -d "$config_dir/devices" ]; then
        for config in "$config_dir/devices"/*.config; do
            if [ -f "$config" ]; then
                local device_name=$(basename "$config" .config)
                devices_found+=("$device_name")
            fi
        done
    fi
    
    # 2. 从support.sh所在目录检测（如果有device-list文件）
    if [ -f "$REPO_ROOT/device-list.txt" ]; then
        while read line; do
            [ -z "$line" ] && continue
            devices_found+=("$line")
        done < "$REPO_ROOT/device-list.txt"
    fi
    
    # 去重并添加到DEVICES数组
    if [ ${#devices_found[@]} -gt 0 ]; then
        printf '%s\n' "${devices_found[@]}" | sort -u | while read device; do
            # 根据设备名设置平台信息
            case "$device" in
                # ASUS 设备（无变体）
                ac42u|rt-ac42u|asus_rt-ac42u)
                    DEVICES["$device"]="ipq40xx generic bcm47189"
                    ;;
                acrh17|rt-acrh17|asus_rt-acrh17)
                    DEVICES["$device"]="ipq40xx generic bcm47189"
                    ;;
                
                # RAX3000M 设备（有变体）- 默认使用 nand 版本
                cmcc_rax3000m-nand|rax3000m-nand)
                    DEVICES["$device"]="mediatek filogic mt7981 nand"
                    ;;
                cmcc_rax3000m-emmc|rax3000m-emmc)
                    DEVICES["$device"]="mediatek filogic mt7981 emmc"
                    ;;
                cmcc_rax3000m|rax3000m)
                    # 兼容旧名称，指向 nand 版本
                    DEVICES["$device"]="mediatek filogic mt7981 nand"
                    ;;
                
                # Netgear 设备（可能有变体，但目前无）
                netgear_wndr3800|wndr3800)
                    DEVICES["$device"]="ath79 generic ar7161"
                    ;;
                netgear_wndr3700|wndr3700)
                    DEVICES["$device"]="ath79 generic ar7161"
                    ;;
                
                # Xiaomi 设备（可能有变体）
                xiaomi_mi-router-4a-gigabit)
                    DEVICES["$device"]="ramips mt7621 mips_24kc"
                    ;;
                xiaomi_mi-router-4a-100m)
                    DEVICES["$device"]="ramips mt7621 mips_24kc"
                    ;;
                xiaomi_redmi-router-ac2100)
                    DEVICES["$device"]="ramips mt7621 mips_24kc"
                    ;;
                
                # 通用匹配模式
                *)
                    # 尝试从设备名推断平台
                    if [[ "$device" == *"ipq40xx"* ]] || [[ "$device" == *"ac42u"* ]] || [[ "$device" == *"acrh17"* ]]; then
                        DEVICES["$device"]="ipq40xx generic unknown"
                    elif [[ "$device" == *"mediatek"* ]] || [[ "$device" == *"filogic"* ]] || [[ "$device" == *"mt7981"* ]] || [[ "$device" == *"rax3000m"* ]]; then
                        # 检查是否有变体
                        if [[ "$device" == *"nand"* ]]; then
                            DEVICES["$device"]="mediatek filogic mt7981 nand"
                        elif [[ "$device" == *"emmc"* ]]; then
                            DEVICES["$device"]="mediatek filogic mt7981 emmc"
                        else
                            # 默认使用 nand
                            DEVICES["$device"]="mediatek filogic mt7981 nand"
                        fi
                    elif [[ "$device" == *"ath79"* ]] || [[ "$device" == *"wndr"* ]]; then
                        DEVICES["$device"]="ath79 generic unknown"
                    elif [[ "$device" == *"ramips"* ]] || [[ "$device" == *"mt7621"* ]] || [[ "$device" == *"xiaomi"* ]]; then
                        DEVICES["$device"]="ramips mt7621 unknown"
                    else
                        # 未知平台，尝试从配置文件推断
                        if [ -f "$config_dir/devices/$device.config" ]; then
                            if grep -q "ipq40xx" "$config_dir/devices/$device.config" 2>/dev/null; then
                                DEVICES["$device"]="ipq40xx generic unknown"
                            elif grep -q "mediatek\|filogic" "$config_dir/devices/$device.config" 2>/dev/null; then
                                if grep -q "nand" "$config_dir/devices/$device.config" 2>/dev/null; then
                                    DEVICES["$device"]="mediatek filogic unknown nand"
                                elif grep -q "emmc" "$config_dir/devices/$device.config" 2>/dev/null; then
                                    DEVICES["$device"]="mediatek filogic unknown emmc"
                                else
                                    DEVICES["$device"]="mediatek filogic unknown nand"
                                fi
                            elif grep -q "ath79" "$config_dir/devices/$device.config" 2>/dev/null; then
                                DEVICES["$device"]="ath79 generic unknown"
                            else
                                DEVICES["$device"]="unknown unknown unknown"
                            fi
                        else
                            DEVICES["$device"]="unknown unknown unknown"
                        fi
                    fi
                    ;;
            esac
        done
    else
        # 默认设备列表（包含有变体和无变体的设备）
        # 无变体设备
        DEVICES["asus_rt-ac42u"]="ipq40xx generic bcm47189"
        DEVICES["asus_rt-acrh17"]="ipq40xx generic bcm47189"
        DEVICES["netgear_wndr3800"]="ath79 generic ar7161"
        
        # 有变体设备 - 明确指定变体
        DEVICES["cmcc_rax3000m-nand"]="mediatek filogic mt7981 nand"
        DEVICES["cmcc_rax3000m-emmc"]="mediatek filogic mt7981 emmc"
        
        # 基础名称指向 nand 版本
        DEVICES["cmcc_rax3000m"]="mediatek filogic mt7981 nand"
        DEVICES["rax3000m"]="mediatek filogic mt7981 nand"
    fi
}

# 获取设备信息
get_device_info() {
    local device_name="$1"
    local info_type="$2"  # target, subtarget, chip, variant
    
    if [ -z "${DEVICES[$device_name]}" ]; then
        echo ""
        return 1
    fi
    
    local info="${DEVICES[$device_name]}"
    
    case "$info_type" in
        target)
            echo "$info" | awk '{print $1}'
            ;;
        subtarget)
            echo "$info" | awk '{print $2}'
            ;;
        chip)
            echo "$info" | awk '{print $3}'
            ;;
        variant)
            echo "$info" | awk '{print $4}'
            ;;
        *)
            echo "$info"
            ;;
    esac
}

# 获取设备变体信息
get_device_variant() {
    local device_name="$1"
    get_device_info "$device_name" "variant"
}

# 检查设备是否有变体
has_variant() {
    local device_name="$1"
    local variant=$(get_device_variant "$device_name")
    
    if [ -n "$variant" ] && [ "$variant" != "unknown" ]; then
        return 0  # 有明确变体
    else
        return 1  # 无明确变体或未知
    fi
}

# 获取设备的基础名称（不含变体）
get_device_base_name() {
    local device_name="$1"
    
    # 移除常见的变体后缀
    local base_name=$(echo "$device_name" | sed -E 's/-(nand|emmc|spi|nor|sdcard|usb)$//' | sed -E 's/_(nand|emmc|spi|nor|sdcard|usb)$//')
    echo "$base_name"
}

# 获取设备的所有可能变体名称
get_device_variant_names() {
    local device_name="$1"
    local variant_names=()
    
    # 添加原始名称
    variant_names+=("$device_name")
    
    # 获取基础名称
    local base_name=$(get_device_base_name "$device_name")
    if [ "$base_name" != "$device_name" ]; then
        variant_names+=("$base_name")
    fi
    
    # 常见变体后缀
    local variants=("nand" "emmc" "spi" "nor" "sdcard" "usb")
    
    for v in "${variants[@]}"; do
        variant_names+=("${base_name}-${v}")
        variant_names+=("${base_name}_${v}")
    done
    
    # 去重
    printf '%s\n' "${variant_names[@]}" | sort -u
}

# 检查设备是否支持
is_device_supported() {
    local device_name="$1"
    
    if [ -n "${DEVICES[$device_name]}" ]; then
        return 0
    fi
    
    # 检查基础名称
    local base_name=$(get_device_base_name "$device_name")
    if [ -n "${DEVICES[$base_name]}" ]; then
        return 0
    fi
    
    return 1
}

# 初始化时调用动态检测
detect_devices_dynamic
#【support.sh-03-end】

#【support.sh-04】
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数（重定向到stderr，避免污染get-platform输出）
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
#【support.sh-04-end】

#【support.sh-05】
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

# 检查函数是否存在
function_exists() {
    local function_name="$1"
    if [ -n "$(type -t "$function_name")" ] && [ "$(type -t "$function_name")" = "function" ]; then
        return 0
    else
        return 1
    fi
}
#【support.sh-05-end】

#【support.sh-06】
# 显示支持的设备列表
list_devices() {
    log "=== 支持的设备列表 (共 ${#DEVICES[@]} 个) ==="
    
    # 按平台分组显示
    declare -A platform_devices
    
    for device in "${!DEVICES[@]}"; do
        local platform_info="${DEVICES[$device]}"
        local target=$(echo "$platform_info" | awk '{print $1}')
        local variant=$(echo "$platform_info" | awk '{print $4}')
        
        platform_devices["$target"]+="$device|$variant "
    done
    
    local i=1
    for platform in $(echo "${!platform_devices[@]}" | tr ' ' '\n' | sort); do
        echo ""
        echo "📁 平台: $platform"
        echo "----------------------------------------"
        
        for device_info in ${platform_devices[$platform]}; do
            IFS='|' read -r device variant <<< "$device_info"
            
            local platform_info="${DEVICES[$device]}"
            local target=$(echo "$platform_info" | awk '{print $1}')
            local subtarget=$(echo "$platform_info" | awk '{print $2}')
            local chip=$(echo "$platform_info" | awk '{print $3}')
            
            # 显示设备信息
            if [ -n "$variant" ] && [ "$variant" != "unknown" ]; then
                printf "[%2d] 📱 %-30s (变体: %s)\n" $i "$device" "$variant"
            else
                printf "[%2d] 📱 %-30s\n" $i "$device"
            fi
            echo "    目标平台: $target/$subtarget, 芯片: $chip"
            
            # 检查设备专用配置文件
            local device_config="$CONFIG_DIR/devices/$device.config"
            if [ -f "$device_config" ]; then
                echo "    📁 设备专用配置: 存在 ($(basename "$device_config"))"
            else
                echo "    ℹ️ 设备专用配置: 使用通用配置"
            fi
            
            i=$((i+1))
            echo ""
        done
    done
    
    echo "========================================"
    echo ""
    echo "📝 命名规范说明:"
    echo "  - 无变体设备: 直接使用基础名称 (如 asus_rt-ac42u)"
    echo "  - 有变体设备: 基础名称-变体 (如 cmcc_rax3000m-nand)"
    echo ""
    echo "💡 使用建议:"
    echo "  - RAX3000M 请明确指定变体: cmcc_rax3000m-nand 或 cmcc_rax3000m-emmc"
    echo "  - 如果不指定变体，系统会尝试自动检测，但建议明确指定"
    
    success "设备列表显示完成"
}
#【support.sh-06-end】

#【support.sh-07】
# 验证设备是否支持
validate_device() {
    local device_name="$1"
    
    # 检查设备是否存在
    if [ -z "${DEVICES[$device_name]}" ]; then
        # 尝试查找基础名称
        local base_name=$(get_device_base_name "$device_name")
        
        if [ -n "${DEVICES[$base_name]}" ]; then
            log "设备 $device_name 基于 $base_name，使用默认变体"
            # 使用基础设备的信息
            local base_info="${DEVICES[$base_name]}"
            local target=$(echo "$base_info" | awk '{print $1}')
            local subtarget=$(echo "$base_info" | awk '{print $2}')
            local chip=$(echo "$base_info" | awk '{print $3}')
            local variant=$(echo "$base_info" | awk '{print $4}')
            DEVICES["$device_name"]="$target $subtarget $chip $variant"
        else
            # 检查是否有设备配置文件
            if [ -f "$CONFIG_DIR/devices/$device_name.config" ]; then
                log "设备 $device_name 有配置文件，尝试推断平台"
                # 从配置文件推断
                if grep -q "ipq40xx" "$CONFIG_DIR/devices/$device_name.config" 2>/dev/null; then
                    DEVICES["$device_name"]="ipq40xx generic unknown"
                elif grep -q "mediatek\|filogic" "$CONFIG_DIR/devices/$device_name.config" 2>/dev/null; then
                    if [[ "$device_name" == *"nand"* ]]; then
                        DEVICES["$device_name"]="mediatek filogic unknown nand"
                    elif [[ "$device_name" == *"emmc"* ]]; then
                        DEVICES["$device_name"]="mediatek filogic unknown emmc"
                    else
                        DEVICES["$device_name"]="mediatek filogic unknown nand"
                    fi
                elif grep -q "ath79" "$CONFIG_DIR/devices/$device_name.config" 2>/dev/null; then
                    DEVICES["$device_name"]="ath79 generic unknown"
                else
                    error "不支持的设备: $device_name"
                fi
            else
                error "不支持的设备: $device_name"
            fi
        fi
    fi
    
    local platform_info="${DEVICES[$device_name]}"
    local target=$(echo "$platform_info" | awk '{print $1}')
    local subtarget=$(echo "$platform_info" | awk '{print $2}')
    local variant=$(echo "$platform_info" | awk '{print $4}')
    
    log "设备验证通过: $device_name"
    log "目标平台: $target"
    log "子目标: $subtarget"
    
    if [ -n "$variant" ] && [ "$variant" != "unknown" ]; then
        log "设备变体: $variant"
    fi
    
    echo "$target $subtarget"
}

# 获取设备的平台信息
get_device_platform() {
    local device_name="$1"
    
    # 如果在DEVICES数组中找不到，尝试从配置文件推断
    if [ -z "${DEVICES[$device_name]}" ]; then
        # 尝试基础名称
        local base_name=$(get_device_base_name "$device_name")
        if [ -n "${DEVICES[$base_name]}" ]; then
            local base_info="${DEVICES[$base_name]}"
            local target=$(echo "$base_info" | awk '{print $1}')
            local subtarget=$(echo "$base_info" | awk '{print $2}')
            echo "$target $subtarget"
            return 0
        fi
        
        if [ -f "$CONFIG_DIR/devices/$device_name.config" ]; then
            if grep -q "ipq40xx\|ipq806x" "$CONFIG_DIR/devices/$device_name.config" 2>/dev/null; then
                echo "ipq40xx generic"
                return 0
            elif grep -q "mediatek\|filogic" "$CONFIG_DIR/devices/$device_name.config" 2>/dev/null; then
                echo "mediatek filogic"
                return 0
            elif grep -q "ath79" "$CONFIG_DIR/devices/$device_name.config" 2>/dev/null; then
                echo "ath79 generic"
                return 0
            fi
        fi
        echo ""
        return 1
    fi
    
    local info="${DEVICES[$device_name]}"
    local target=$(echo "$info" | awk '{print $1}')
    local subtarget=$(echo "$info" | awk '{print $2}')
    echo "$target $subtarget"
}

# 获取设备的搜索关键词
get_device_search_names() {
    local device_name="$1"
    local search_names=()
    
    # 添加原始名称
    search_names+=("$device_name")
    
    # 获取基础名称
    local base_name=$(get_device_base_name "$device_name")
    search_names+=("$base_name")
    
    # 添加常见变体形式
    local variants=("nand" "emmc" "spi" "nor" "sdcard" "usb")
    
    for v in "${variants[@]}"; do
        search_names+=("${base_name}-${v}")
        search_names+=("${base_name}_${v}")
    done
    
    # 添加下划线/连字符变体
    search_names+=("$(echo "$device_name" | tr '-' '_')")
    search_names+=("$(echo "$device_name" | tr '_' '-')")
    
    # 去重
    printf '%s\n' "${search_names[@]}" | sort -u
}
#【support.sh-07-end】

#【support.sh-08】
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
#【support.sh-08-end】

#【support.sh-09】
# 应用通用配置
apply_generic_config() {
    local config_type="$1"
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
#【support.sh-09-end】

#【support.sh-10】
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
#【support.sh-10-end】

#【support.sh-11】
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
#【support.sh-11-end】

#【support.sh-12】
# 显示配置文件信息
show_config_info() {
    local device_name="$1"
    local config_mode="$2"
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
#【support.sh-12-end】

#【support.sh-13】
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
#【support.sh-13-end】

#【support.sh-14】
# 搜索编译器文件（调用主脚本）
search_compiler_files() {
    local search_root="${1:-/tmp}"
    local target_platform="${2:-generic}"
    
    log "搜索编译器文件..."
    
    check_build_main_script
    
    # 调用主脚本的universal_compiler_search函数
    "$BUILD_MAIN_SCRIPT" universal_compiler_search "$search_root" "$target_platform"
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        success "找到编译器文件"
        return 0
    else
        log "未找到本地编译器文件，将使用源码自带工具链"
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
        log "智能编译器搜索未找到本地编译器，将使用源码自带工具链"
        return 1
    fi
}
#【support.sh-14-end】

#【support.sh-15】
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
        log "通用编译器搜索未找到本地编译器，将使用源码自带工具链"
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
        log "简单编译器搜索未找到本地编译器，将使用源码自带工具链"
        return 1
    fi
}
#【support.sh-15-end】

#【support.sh-16】
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
#【support.sh-16-end】

#【support.sh-17】
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
    
    # 验证设备
    validate_device "$device_name" > /dev/null
    
    # 检查构建目录
    if [ ! -d "$build_dir" ]; then
        error "构建目录不存在: $build_dir"
    fi
    
    # 切换到构建目录
    cd "$build_dir" || error "无法进入构建目录: $build_dir"
    
    # 生成基础配置（调用主脚本）
    log "生成基础配置..."
    "$BUILD_MAIN_SCRIPT" generate_config "$extra_packages"
    
    if [ $? -ne 0 ]; then
        error "生成基础配置失败"
    fi
    
    # 应用USB通用配置
    apply_generic_config "usb-generic" "$build_dir"
    
    # 应用模式配置
    apply_generic_config "$config_mode" "$build_dir"
    
    # 应用设备专用配置
    apply_device_config "$device_name" "$build_dir"
    
    # 应用配置（调用主脚本）
    apply_config
    
    # 显示配置信息
    show_config_info "$device_name" "$config_mode" "$build_dir"
    
    success "完整配置流程完成"
}
#【support.sh-17-end】

#【support.sh-18】
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
    echo "  ./support.sh full-config ac42u normal /mnt/openwrt-build"
    echo "  ./support.sh initialize-compiler ac42u"
    echo ""
}
#【support.sh-18-end】

#【support.sh-19】
# 主函数
main() {
    local command="$1"
    
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
#【support.sh-19-end】

#【support.sh-20】
# 运行主函数
main "$@"
#【support.sh-20-end】
