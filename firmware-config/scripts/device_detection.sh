#!/bin/bash

# 高级设备检测脚本 - 自动分析所有平台和设备定义
# 支持多种设备树文件命名模式和设备定义搜索

set -e

# 颜色定义（输出到 stderr）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数（输出到 stderr）
log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# 已知的设备映射（作为备用方案）
declare -A DEVICE_MAPPING=(
    ["ac42u"]="asus_rt-ac42u"
    ["acrh17"]="asus_rt-ac42u" 
    ["rt-acrh17"]="asus_rt-ac42u"
    ["ac58u"]="asus_rt-ac58u"
    ["acrh13"]="asus_rt-ac58u"
    ["rt-ac58u"]="asus_rt-ac58u"
    ["rt-acrh13"]="asus_rt-ac58u"
)

# 主检测函数
detect_device() {
    local device_input="$1"
    
    log_info "=== 高级设备检测 ==="
    log_info "输入设备: $device_input"
    
    # 检查是否在 OpenWrt 源码目录
    if [ ! -d "target/linux" ]; then
        log_error "错误: 请在 OpenWrt 源码根目录中运行此脚本"
        return 1
    fi
    
    # 首先尝试自动检测
    log_info "开始自动设备检测..."
    if auto_detect_device "$device_input"; then
        return 0
    fi
    
    # 如果自动检测失败，使用已知映射
    log_warning "自动检测失败，尝试已知映射"
    if use_known_mapping "$device_input"; then
        return 0
    fi
    
    log_error "所有设备检测方法都失败"
    return 1
}

# 自动检测设备
auto_detect_device() {
    local device_input="$1"
    
    log_info "=== 自动设备检测流程 ==="
    
    # 步骤1: 搜索设备树文件 - 使用更智能的搜索模式
    log_info "步骤1: 搜索设备树文件..."
    local dts_files=$(find_device_tree_files "$device_input")
    
    if [ -n "$dts_files" ]; then
        log_success "找到设备树文件:"
        echo "$dts_files" >&2
        
        # 从设备树文件路径推断平台
        local platform=$(echo "$dts_files" | head -1 | cut -d'/' -f3)
        local device_full_name="$device_input"
        
        # 验证平台
        if [ ! -d "target/linux/$platform" ]; then
            log_error "检测到的平台目录不存在: target/linux/$platform"
            return 1
        fi
        
        log_success "从设备树推断平台: $platform"
        
        # 步骤2: 查找设备定义
        local device_short_name=$(find_device_definition "$platform" "$device_input")
        
        if [ -n "$device_short_name" ]; then
            log_success "找到设备定义: $device_short_name"
            output_device_info "$platform" "$device_short_name" "$device_input"
            return 0
        else
            log_warning "未找到精确的设备定义，尝试从设备树文件名推断"
            local dts_basename=$(basename "$dts_files" | head -1 | sed 's/\.dts.*//')
            # 从设备树文件名提取可能的设备名称
            local inferred_device=$(infer_device_from_dts "$dts_basename")
            if [ -n "$inferred_device" ]; then
                output_device_info "$platform" "$inferred_device" "$device_input"
                return 0
            else
                output_device_info "$platform" "$dts_basename" "$device_input"
                return 0
            fi
        fi
    else
        log_warning "未找到设备树文件，跳过设备树搜索"
    fi
    
    # 步骤3: 如果没有找到设备树，直接搜索设备定义
    log_info "步骤2: 直接搜索设备定义..."
    local found_device=$(search_all_device_definitions "$device_input")
    
    if [ -n "$found_device" ]; then
        local platform=$(echo "$found_device" | cut -d':' -f1)
        local device_name=$(echo "$found_device" | cut -d':' -f2)
        log_success "通过直接搜索找到设备: $device_name (平台: $platform)"
        output_device_info "$platform" "$device_name" "$device_input"
        return 0
    fi
    
    return 1
}

# 智能搜索设备树文件
find_device_tree_files() {
    local device_input="$1"
    
    log_info "智能搜索设备树文件..."
    
    # 生成多种可能的设备树文件名模式
    local patterns=($(generate_dts_patterns "$device_input"))
    
    # 搜索所有平台
    local platforms=$(find target/linux -maxdepth 1 -type d | grep -v "^target/linux$" | xargs -n1 basename)
    
    local found_files=""
    
    for platform in $platforms; do
        log_info "搜索平台: $platform 的设备树文件"
        
        for pattern in "${patterns[@]}"; do
            log_info "尝试模式: $pattern"
            
            # 使用find搜索，不限制文件名模式
            local files=$(find "target/linux/$platform" -name "*.dts" -type f 2>/dev/null | \
                         grep -i "$pattern" | head -5)
            
            if [ -n "$files" ]; then
                log_success "在平台 $platform 中找到匹配的设备树文件"
                found_files="$found_files"$'\n'"$files"
            fi
        done
        
        # 额外搜索：通过文件内容搜索
        log_info "通过文件内容搜索设备: $device_input"
        local content_files=$(find "target/linux/$platform" -name "*.dts" -type f 2>/dev/null | \
                             xargs grep -l "$device_input" 2>/dev/null | head -3 || true)
        
        if [ -n "$content_files" ]; then
            log_success "通过文件内容找到设备树文件"
            found_files="$found_files"$'\n'"$content_files"
        fi
    done
    
    # 去重并返回
    echo "$found_files" | grep -v '^$' | sort -u
}

# 生成设备树文件搜索模式
generate_dts_patterns() {
    local device_input="$1"
    
    local patterns=()
    
    # 原始输入
    patterns+=("$device_input")
    
    # 常见转换模式
    # asus_rt-ac42u -> ac42u, rt-ac42u, asus-ac42u, qcom-ipq4019-rt-ac42u
    if [[ "$device_input" =~ asus_rt-(.+) ]]; then
        patterns+=("${BASH_REMATCH[1]}")  # ac42u
        patterns+=("rt-${BASH_REMATCH[1]}")  # rt-ac42u
        patterns+=("asus-${BASH_REMATCH[1]}")  # asus-ac42u
        patterns+=("asus-rt-${BASH_REMATCH[1]}")  # asus-rt-ac42u
        patterns+=("qcom-.*${BASH_REMATCH[1]}")  # qcom-*-ac42u
    fi
    
    # rt-ac42u -> ac42u, asus-rt-ac42u
    if [[ "$device_input" =~ rt-(.+) ]]; then
        patterns+=("${BASH_REMATCH[1]}")  # ac42u
        patterns+=("asus-rt-${BASH_REMATCH[1]}")  # asus-rt-ac42u
    fi
    
    # 通用模式
    patterns+=("$(echo "$device_input" | sed 's/_/-/g')")  # 下划线转连字符
    patterns+=("$(echo "$device_input" | sed 's/rt-//')")   # 移除rt-前缀
    
    # 输出所有模式（去重）
    printf "%s\n" "${patterns[@]}" | sort -u
}

# 从设备树文件名推断设备名称
infer_device_from_dts() {
    local dts_filename="$1"
    
    log_info "从设备树文件名推断设备名称: $dts_filename"
    
    # 移除常见的平台前缀和文件扩展名
    local device_name=$(echo "$dts_filename" | sed -E '
        s/^(qcom-|mtk-|mediatek-|rockchip-|bcm-|brcm-|ar71xx-|ipq40xx-|ramips-)//g
        s/^(ipq4019-|ipq8064-|mt7621-|mt7620-|ar71xx-)//g
        s/\.dts.*$//g
    ')
    
    # 如果推断结果为空或太短，返回原始文件名
    if [ -z "$device_name" ] || [ ${#device_name} -lt 3 ]; then
        echo "$dts_filename"
    else
        echo "$device_name"
    fi
}

# 搜索所有设备定义
search_all_device_definitions() {
    local device_input="$1"
    
    log_info "搜索所有平台的设备定义..."
    
    # 查找所有平台
    local platforms=$(find target/linux -maxdepth 1 -type d | grep -v "^target/linux$" | xargs -n1 basename)
    
    for platform in $platforms; do
        log_info "搜索平台: $platform"
        
        # 查找设备定义
        local device_name=$(find_device_definition "$platform" "$device_input")
        if [ -n "$device_name" ]; then
            echo "$platform:$device_name"
            return 0
        fi
    done
    
    return 1
}

# 查找设备定义
find_device_definition() {
    local platform="$1"
    local device_input="$2"
    
    log_info "在平台 $platform 中查找设备定义..."
    
    # 查找所有可能的设备定义文件
    local mk_files=$(find "target/linux/$platform" -name "*.mk" -type f 2>/dev/null)
    
    if [ -z "$mk_files" ]; then
        log_warning "平台 $platform 中没有找到 .mk 文件"
        return 1
    fi
    
    # 生成设备名称变体
    local device_variants=($(generate_device_variants "$device_input"))
    
    log_info "尝试的设备名称变体: ${device_variants[*]}"
    
    for variant in "${device_variants[@]}"; do
        log_info "检查变体: $variant"
        
        for mk_file in $mk_files; do
            # 查找 define Device 行 - 使用更宽松的匹配
            local device_line=$(grep -h "define Device.*$variant" "$mk_file" 2>/dev/null | head -1)
            if [ -n "$device_line" ]; then
                log_success "在文件 $mk_file 中找到设备定义"
                log_info "设备定义行: $device_line"
                
                # 提取设备名称 (define Device/后面的部分) - 使用更精确的提取
                local device_name=$(echo "$device_line" | sed -n 's/.*define Device\/\([^ )]*\).*/\1/p')
                if [ -n "$device_name" ]; then
                    log_success "提取的设备名称: $device_name"
                    
                    # 检查设备别名
                    local alt_names=$(check_device_aliases "$mk_file" "$device_name")
                    if [ -n "$alt_names" ]; then
                        log_info "设备别名: $alt_names"
                    fi
                    
                    # 验证这个设备名称是否在 TARGET_DEVICES 中
                    if grep -q "TARGET_DEVICES.*+=.*$device_name" "$mk_file" 2>/dev/null; then
                        log_success "设备 $device_name 在 TARGET_DEVICES 中"
                        echo "$device_name"
                        return 0
                    else
                        log_warning "设备 $device_name 不在 TARGET_DEVICES 中，但继续使用"
                        echo "$device_name"
                        return 0
                    fi
                fi
            fi
        done
    done
    
    # 如果没有找到精确匹配，尝试通过别名查找
    log_info "尝试通过别名查找..."
    for mk_file in $mk_files; do
        # 查找包含设备别名的行
        local alt_match=$(grep -h "DEVICE_ALT.*MODEL.*$device_input" "$mk_file" 2>/dev/null | head -1)
        if [ -n "$alt_match" ]; then
            log_success "通过别名找到设备: $alt_match"
            # 向上查找设备定义
            local device_line=$(grep -B 10 "$alt_match" "$mk_file" | grep "define Device/" | tail -1)
            if [ -n "$device_line" ]; then
                local device_name=$(echo "$device_line" | sed -n 's/.*define Device\/\([^ )]*\).*/\1/p')
                log_success "通过别名推断设备名称: $device_name"
                echo "$device_name"
                return 0
            fi
        fi
    done
    
    # 最后尝试直接搜索设备名称
    log_info "尝试直接搜索设备名称..."
    for mk_file in $mk_files; do
        # 直接搜索设备定义块
        if awk "/define Device\/.*$device_input/,/endef/" "$mk_file" | grep -q "define Device"; then
            local device_line=$(awk "/define Device\/.*$device_input/,/endef/" "$mk_file" | grep "define Device" | head -1)
            local device_name=$(echo "$device_line" | sed -n 's/.*define Device\/\([^ )]*\).*/\1/p')
            if [ -n "$device_name" ]; then
                log_success "通过直接搜索找到设备: $device_name"
                echo "$device_name"
                return 0
            fi
        fi
    done
    
    return 1
}

# 生成设备名称变体
generate_device_variants() {
    local device_input="$1"
    
    local variants=(
        "$device_input"
        "rt-$device_input"
        "asus_$device_input"
        "asus_rt-$device_input"
        "tplink_$device_input"
        "xiaomi_$device_input"
        "dlink_$device_input"
        "netgear_$device_input"
        "linksys_$device_input"
        "buffalo_$device_input"
        "gl-inet_$device_input"
    )
    
    # 移除重复项
    printf "%s\n" "${variants[@]}" | sort -u
}

# 检查设备别名
check_device_aliases() {
    local mk_file="$1"
    local device_name="$2"
    
    # 查找设备定义块中的别名
    local aliases=""
    local in_device_block=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ define\ Device/$device_name ]]; then
            in_device_block=1
            continue
        fi
        
        if [ $in_device_block -eq 1 ]; then
            if [[ "$line" =~ endef ]]; then
                break
            fi
            
            if [[ "$line" =~ DEVICE_ALT.*MODEL.*:=[[:space:]]*(.+) ]]; then
                aliases="$aliases ${BASH_REMATCH[1]}"
            fi
        fi
    done < "$mk_file"
    
    echo "$aliases" | sed 's/^ *//'
}

# 使用已知映射
use_known_mapping() {
    local device_input="$1"
    
    if [ -n "${DEVICE_MAPPING[$device_input]}" ]; then
        local device_short_name="${DEVICE_MAPPING[$device_input]}"
        
        # 推断平台
        local platform=""
        case "$device_short_name" in
            *ipq40xx*|*asus_rt-ac*)
                platform="ipq40xx"
                ;;
            *ar71xx*|*tl-wr*)
                platform="ar71xx"
                ;;
            *ramips*|*xiaomi_mi*)
                platform="ramips"
                ;;
            *mediatek*|*redmi-ax6s*)
                platform="mediatek"
                ;;
            *)
                platform="ipq40xx"  # 默认
                ;;
        esac
        
        log_success "使用已知映射: $device_input -> $device_short_name (平台: $platform)"
        output_device_info "$platform" "$device_short_name" "$device_input"
        return 0
    fi
    
    return 1
}

# 输出设备信息
output_device_info() {
    local platform="$1"
    local device_short_name="$2"
    local device_full_name="$3"
    
    # 直接输出设备信息到 stdout（供工作流捕获）
    echo "PLATFORM=$platform"
    echo "DEVICE_SHORT_NAME=$device_short_name"
    echo "DEVICE_FULL_NAME=$device_full_name"
    
    log_success "设备检测完成:"
    log_success "  平台: $platform"
    log_success "  设备: $device_short_name"
    log_success "  全名: $device_full_name"
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        echo "用法: $0 <设备名称>" >&2
        echo "示例: $0 ac42u" >&2
        echo "示例: $0 acrh17" >&2
        echo "示例: $0 ac58u" >&2
        exit 1
    fi
    
    detect_device "$1"
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
