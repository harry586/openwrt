#!/bin/bash

# OpenWrt 设备检测脚本
# 作者: AI Assistant
# 版本: 1.0
# 描述: 自动检测 OpenWrt 设备配置信息

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    echo "OpenWrt 设备检测脚本"
    echo ""
    echo "用法: $0 [选项] <设备名称>"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -v, --verbose       显示详细调试信息"
    echo "  -l, --list          列出所有支持的设备"
    echo "  -a, --auto          启用自动检测模式"
    echo "  -o, --output FILE   将结果输出到文件"
    echo ""
    echo "示例:"
    echo "  $0 ac42u"
    echo "  $0 rt-acrh17"
    echo "  $0 --auto mi3g"
    echo "  $0 --list"
    echo ""
    echo "支持的设备类型:"
    echo "  - 华硕: ac42u, acrh17, ac58u, acrh13"
    echo "  - 小米: mi3g, r3g, r3p, ac2100"
    echo "  - 斐讯: k2p, k3"
    echo "  - 其他: newifi-d2, wrt3200acm"
}

# 列出所有支持的设备
list_devices() {
    echo "支持的设备列表:"
    echo ""
    echo "华硕 (ASUS):"
    echo "  ac42u, rt-ac42u, asus_ac42u"
    echo "  acrh17, rt-acrh17, asus_acrh17" 
    echo "  ac58u, rt-ac58u, asus_ac58u"
    echo "  acrh13, rt-acrh13, asus_acrh13"
    echo ""
    echo "小米 (Xiaomi):"
    echo "  mi3g, r3g, xiaomi_mi3g, mi-router-3g"
    echo "  r3p, xiaomi_r3p, mi-router-3-pro"
    echo "  ac2100, xiaomi_ac2100, redmi-ac2100"
    echo ""
    echo "斐讯 (Phicomm):"
    echo "  k2p, phicomm_k2p"
    echo "  k3, phicomm_k3"
    echo ""
    echo "其他:"
    echo "  newifi-d2, newifi_d2"
    echo "  wrt3200acm, linksys_wrt3200acm"
    echo ""
    echo "使用: $0 <设备名称> 进行检测"
}

# 设备映射表
declare -A DEVICE_MAP=(
    # 华硕设备
    ["ac42u"]="ipq40xx:asus_rt-ac42u:asus,rt-ac42u"
    ["rt-ac42u"]="ipq40xx:asus_rt-ac42u:asus,rt-ac42u"
    ["asus_ac42u"]="ipq40xx:asus_rt-ac42u:asus,rt-ac42u"
    
    ["acrh17"]="ipq40xx:asus_rt-acrh17:asus,rt-acrh17"
    ["rt-acrh17"]="ipq40xx:asus_rt-acrh17:asus,rt-acrh17"
    ["asus_acrh17"]="ipq40xx:asus_rt-acrh17:asus,rt-acrh17"
    
    ["ac58u"]="ipq40xx:asus_rt-ac58u:asus,rt-ac58u"
    ["rt-ac58u"]="ipq40xx:asus_rt-ac58u:asus,rt-ac58u"
    ["asus_ac58u"]="ipq40xx:asus_rt-ac58u:asus,rt-ac58u"
    
    # 小米设备
    ["mi3g"]="ramips:xiaomi_mi-router-3g:xiaomi,mi-router-3g"
    ["r3g"]="ramips:xiaomi_mi-router-3g:xiaomi,mi-router-3g"
    ["xiaomi_mi3g"]="ramips:xiaomi_mi-router-3g:xiaomi,mi-router-3g"
    ["mi-router-3g"]="ramips:xiaomi_mi-router-3g:xiaomi,mi-router-3g"
    
    ["r3p"]="ramips:xiaomi_mi-router-3-pro:xiaomi,mi-router-3-pro"
    ["xiaomi_r3p"]="ramips:xiaomi_mi-router-3-pro:xiaomi,mi-router-3-pro"
    ["mi-router-3-pro"]="ramips:xiaomi_mi-router-3-pro:xiaomi,mi-router-3-pro"
    
    # 斐讯设备
    ["k2p"]="ramips:phicomm_k2p:phicomm,k2p"
    ["phicomm_k2p"]="ramips:phicomm_k2p:phicomm,k2p"
    
    ["k3"]="bcm53xx:phicomm_k3:phicomm,k3"
    ["phicomm_k3"]="bcm53xx:phicomm_k3:phicomm,k3"
    
    # 其他设备
    ["newifi-d2"]="ramips:newifi_d2:newifi,d2"
    ["newifi_d2"]="ramips:newifi_d2:newifi,d2"
    
    ["wrt3200acm"]="mvebu:linksys_wrt3200acm:linksys,wrt3200acm"
    ["linksys_wrt3200acm"]="mvebu:linksys_wrt3200acm:linksys,wrt3200acm"
)

# 主检测函数
detect_device_config() {
    local device_input="$1"
    local enable_auto="$2"
    local verbose="$3"
    
    log_info "=== 开始设备检测 ==="
    log_info "输入设备: $device_input"
    log_info "自动检测模式: $enable_auto"
    
    local platform=""
    local device_short_name=""
    local device_full_name=""
    
    # 检查设备映射表
    if [ -n "${DEVICE_MAP[$device_input]}" ]; then
        IFS=':' read -r platform device_short_name device_full_name <<< "${DEVICE_MAP[$device_input]}"
        log_success "在设备映射表中找到设备配置"
    else
        if [ "$enable_auto" = "true" ]; then
            log_warning "设备未在映射表中，启用自动检测..."
            auto_detect_device "$device_input"
            return
        else
            log_error "未知设备: $device_input"
            log_info "使用 --auto 选项启用自动检测模式"
            return 1
        fi
    fi
    
    # 验证平台存在性
    if [ ! -d "target/linux/$platform" ]; then
        log_error "平台目录不存在: target/linux/$platform"
        return 1
    fi
    
    log_success "检测到设备:"
    echo "   平台: $platform"
    echo "   设备简称: $device_short_name"
    echo "   完整名称: $device_full_name"
    
    # 查找配置文件
    find_config_files "$platform" "$verbose"
    
    # 查找设备定义
    find_device_definitions "$platform" "$device_short_name" "$device_full_name" "$verbose"
    
    # 输出汇总信息
    show_detection_summary
}

# 自动检测设备
auto_detect_device() {
    local device_input="$1"
    
    log_info "=== 自动设备检测 ==="
    
    # 搜索设备树文件
    log_info "搜索设备树文件..."
    local dts_files=$(find target/linux -name "*$device_input*.dts" -o -name "*$device_input*.dtsi" 2>/dev/null | head -5)
    
    if [ -n "$dts_files" ]; then
        log_success "找到设备树文件:"
        echo "$dts_files"
        # 从路径提取平台
        platform=$(echo "$dts_files" | head -1 | cut -d'/' -f3)
        device_short_name=$(basename "$dts_files" | head -1 | sed 's/\.dts.*//')
        device_full_name="$device_input"
        log_info "检测到平台: $platform"
        log_info "设备简称: $device_short_name"
    else
        log_warning "未找到设备树文件，尝试其他方法..."
        
        # 搜索Makefile中的设备定义
        log_info "搜索设备定义..."
        local makefile_matches=$(grep -r "DEVICE_.*$device_input" target/linux/*/image/Makefile target/linux/*/generic/target.mk 2>/dev/null | head -5)
        
        if [ -n "$makefile_matches" ]; then
            log_success "找到设备定义:"
            echo "$makefile_matches"
            # 从定义中提取信息
            platform=$(echo "$makefile_matches" | head -1 | cut -d'/' -f3)
            device_short_name=$(echo "$makefile_matches" | grep -o "DEVICE_.*=" | head -1 | sed 's/DEVICE_//' | sed 's/=//')
            device_full_name="$device_input"
        else
            log_error "自动检测失败，无法识别设备: $device_input"
            return 1
        fi
    fi
    
    # 验证平台
    if [ ! -d "target/linux/$platform" ]; then
        log_error "检测到的平台目录不存在: target/linux/$platform"
        return 1
    fi
    
    log_success "自动检测结果:"
    echo "   平台: $platform"
    echo "   设备简称: $device_short_name"
    echo "   完整名称: $device_full_name"
    
    # 查找配置文件
    find_config_files "$platform" "$verbose"
    
    # 查找设备定义
    find_device_definitions "$platform" "$device_short_name" "$device_full_name" "$verbose"
    
    # 输出汇总信息
    show_detection_summary
}

# 查找配置文件
find_config_files() {
    local platform="$1"
    local verbose="$2"
    
    log_info "=== 查找配置文件 ==="
    
    # 查找内核配置
    local kernel_configs=$(find "target/linux/$platform" -name "config-*" 2>/dev/null | sort -V)
    if [ -n "$kernel_configs" ]; then
        log_success "找到内核配置文件:"
        echo "$kernel_configs"
        # 获取最新的内核版本
        KERNEL_CONFIG=$(echo "$kernel_configs" | tail -1)
        log_info "使用内核配置: $(basename $KERNEL_CONFIG)"
        
        # 显示内核版本信息
        if [ "$verbose" = "true" ]; then
            local kernel_version=$(basename "$KERNEL_CONFIG" | sed 's/config-//')
            log_info "内核版本: $kernel_version"
        fi
    else
        log_error "未找到内核配置文件"
        return 1
    fi
    
    # 查找目标配置
    local target_mk="target/linux/$platform/generic/target.mk"
    if [ -f "$target_mk" ]; then
        log_success "找到目标配置: $target_mk"
        TARGET_MK="$target_mk"
        
        if [ "$verbose" = "true" ]; then
            log_info "目标配置预览:"
            head -20 "$target_mk"
        fi
    else
        log_error "未找到目标配置: $target_mk"
        return 1
    fi
    
    # 查找镜像配置
    local image_mk="target/linux/$platform/image/Makefile"
    if [ -f "$image_mk" ]; then
        log_success "找到镜像配置: $image_mk"
        IMAGE_MK="$image_mk"
    else
        log_warning "未找到镜像配置: $image_mk"
    fi
    
    # 查找设备树目录
    local dts_dir="target/linux/$platform/dts"
    if [ -d "$dts_dir" ]; then
        log_success "找到设备树目录: $dts_dir"
        DTS_DIR="$dts_dir"
        
        if [ "$verbose" = "true" ]; then
            log_info "设备树文件数量: $(find "$dts_dir" -name "*.dts" | wc -l)"
        fi
    else
        log_warning "未找到设备树目录: $dts_dir"
    fi
}

# 查找设备定义
find_device_definitions() {
    local platform="$1"
    local short_name="$2"
    local full_name="$3"
    local verbose="$4"
    
    log_info "=== 查找设备定义 ==="
    
    # 在目标配置中查找设备
    if [ -f "$TARGET_MK" ]; then
        log_info "在目标配置中查找设备定义..."
        if grep -q "$short_name" "$TARGET_MK"; then
            log_success "在目标配置中找到设备: $short_name"
            
            if [ "$verbose" = "true" ]; then
                log_info "设备定义位置:"
                grep -n "$short_name" "$TARGET_MK"
            fi
        else
            log_error "在目标配置中未找到设备: $short_name"
            return 1
        fi
    fi
    
    # 在镜像配置中查找设备
    if [ -f "$IMAGE_MK" ]; then
        log_info "在镜像配置中查找设备定义..."
        if grep -q "$short_name" "$IMAGE_MK"; then
            log_success "在镜像配置中找到设备: $short_name"
        else
            log_warning "在镜像配置中未找到设备: $short_name"
        fi
    fi
    
    # 查找设备树文件
    local dts_file=$(find "target/linux/$platform" -name "*$short_name*.dts" 2>/dev/null | head -1)
    if [ -n "$dts_file" ]; then
        log_success "找到设备树文件: $dts_file"
        DTS_FILE="$dts_file"
        
        if [ "$verbose" = "true" ]; then
            log_info "设备树文件大小: $(stat -c%s "$dts_file" 2>/dev/null || echo "未知") bytes"
        fi
    else
        log_warning "未找到设备树文件: *$short_name*.dts"
    fi
    
    # 查找内核配置中的设备相关设置
    if [ -f "$KERNEL_CONFIG" ]; then
        log_info "在内核配置中查找设备相关设置..."
        local kernel_matches=$(grep -i "$short_name" "$KERNEL_CONFIG" 2>/dev/null | head -5)
        if [ -n "$kernel_matches" ]; then
            log_success "在内核配置中找到设备相关设置:"
            echo "$kernel_matches"
        fi
    fi
}

# 显示检测汇总
show_detection_summary() {
    log_success "=== 设备检测汇总 ==="
    echo "设备名称: $device_input"
    echo "平台: $platform"
    echo "设备简称: $device_short_name"
    echo "完整名称: $device_full_name"
    echo "内核配置: $KERNEL_CONFIG"
    echo "目标配置: $TARGET_MK"
    echo "镜像配置: $IMAGE_MK"
    echo "设备树文件: $DTS_FILE"
    echo "设备树目录: $DTS_DIR"
    
    # 生成配置建议
    generate_config_suggestions
}

# 生成配置建议
generate_config_suggestions() {
    log_info "=== 配置建议 ==="
    
    echo "在 .config 文件中添加以下配置:"
    echo ""
    echo "# 平台配置"
    echo "CONFIG_TARGET_${platform}=y"
    echo "CONFIG_TARGET_${platform}_generic=y"
    echo "CONFIG_TARGET_DEVICE_${platform}_generic_DEVICE_${device_short_name}=y"
    echo ""
    
    # 根据平台提供特定建议
    case "$platform" in
        "ipq40xx")
            echo "# IPQ40xx 平台特定配置"
            echo "CONFIG_PACKAGE_ath10k-firmware-qca4019=y"
            echo "CONFIG_PACKAGE_ath10k-board-qca4019=y"
            echo "CONFIG_PACKAGE_kmod-ath10k=y"
            ;;
        "ramips")
            echo "# RAMIPS 平台特定配置"
            echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y"
            echo "CONFIG_PACKAGE_kmod-mt76=y"
            ;;
        "bcm53xx")
            echo "# Broadcom 平台特定配置"
            echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y"
            echo "CONFIG_PACKAGE_kmod-brcmfmac=y"
            ;;
        "mvebu")
            echo "# Marvell 平台特定配置"
            echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y"
            echo "CONFIG_PACKAGE_kmod-mwlwifi=y"
            ;;
    esac
    
    echo ""
    echo "# 基础系统配置"
    echo "CONFIG_PACKAGE_luci=y"
    echo "CONFIG_PACKAGE_luci-theme-bootstrap=y"
    echo "CONFIG_PACKAGE_dnsmasq=y"
    echo "CONFIG_PACKAGE_firewall=y"
}

# 保存结果到文件
save_results() {
    local output_file="$1"
    
    {
        echo "OpenWrt 设备检测报告"
        echo "生成时间: $(date)"
        echo "设备: $device_input"
        echo "平台: $platform"
        echo "设备简称: $device_short_name"
        echo "完整名称: $device_full_name"
        echo "内核配置: $KERNEL_CONFIG"
        echo "目标配置: $TARGET_MK"
        echo "镜像配置: $IMAGE_MK"
        echo "设备树文件: $DTS_FILE"
        echo ""
        echo "配置建议:"
        echo "CONFIG_TARGET_${platform}=y"
        echo "CONFIG_TARGET_${platform}_generic=y"
        echo "CONFIG_TARGET_DEVICE_${platform}_generic_DEVICE_${device_short_name}=y"
    } > "$output_file"
    
    log_success "结果已保存到: $output_file"
}

# 主函数
main() {
    local device_input=""
    local enable_auto="false"
    local verbose="false"
    local output_file=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_devices
                exit 0
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -a|--auto)
                enable_auto="true"
                shift
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                device_input="$1"
                shift
                ;;
        esac
    done
    
    # 检查设备输入
    if [ -z "$device_input" ]; then
        log_error "请提供设备名称"
        show_help
        exit 1
    fi
    
    # 检查是否在 OpenWrt 源码目录
    if [ ! -d "target/linux" ]; then
        log_error "错误: 请在 OpenWrt 源码根目录中运行此脚本"
        exit 1
    fi
    
    # 执行设备检测
    if detect_device_config "$device_input" "$enable_auto" "$verbose"; then
        log_success "设备检测完成"
        
        # 保存结果到文件
        if [ -n "$output_file" ]; then
            save_results "$output_file"
        fi
    else
        log_error "设备检测失败"
        exit 1
    fi
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
