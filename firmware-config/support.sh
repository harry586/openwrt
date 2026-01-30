#!/bin/bash
# firmware-config/support.sh
# 设备支持系统配置文件
#【support.sh-01】设备支持系统配置文件 v1.1

# ==================== 设备配置函数 ====================
#【support.sh-02】设备配置函数部分开始

# 获取所有支持的设备列表
get_all_devices() {
    echo "acrh17 cmcc_rax3000m netgear_3800"
}

# 获取设备配置
get_device_config() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17")
            echo "ipq40xx generic asus_rt-acrh17 ipq40xx"
            ;;
        "cmcc_rax3000m")
            echo "mediatek mt7981 DEVICE_cmcc_rax3000m mt7981"
            ;;
        "netgear_3800")
            echo "ath79 generic netgear_wndr3800 ath79"
            ;;
        *)
            echo "ipq40xx generic unknown generic"
            ;;
    esac
}

# 获取设备描述
get_device_description() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17")
            echo "ASUS RT-ACRH17/AC42U (高通IPQ40xx平台, 四核1.4GHz)"
            ;;
        "cmcc_rax3000m")
            echo "中国移动 RAX3000M (联发科MT7981平台, 512MB内存, WiFi 6)"
            ;;
        "netgear_3800")
            echo "Netgear WNDR3800 (ath79平台, 680MHz, 128MB内存)"
            ;;
        *)
            echo "未知设备"
            ;;
    esac
}

# ==================== SDK下载函数 ====================
#【support.sh-03】SDK下载函数部分开始

# 获取SDK下载URL（可选）
get_sdk_url() {
    local target="$1"
    local subtarget="$2"
    local version="$3"
    
    # 这里可以根据需要返回自定义SDK URL
    # 如果不自定义，返回空字符串，脚本会使用默认URL
    echo ""
}

# ==================== 设备特定配置检查 ====================
#【support.sh-04】设备特定配置检查部分开始

# 检查设备是否需要特殊配置
check_device_special_config() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17")
            echo "高通IPQ40xx平台需要专用USB驱动和无线驱动"
            ;;
        "cmcc_rax3000m")
            echo "联发科MT7981平台需要mt7915e/mt7916无线驱动"
            ;;
        "netgear_3800")
            echo "ath79平台需要专用网络和USB驱动"
            ;;
        *)
            echo "通用平台，使用默认配置"
            ;;
    esac
}

# ==================== 平台特性函数 ====================
#【support.sh-05】平台特性函数部分开始

# 获取平台USB驱动配置
get_platform_usb_drivers() {
    local platform="$1"
    
    case "$platform" in
        "ipq40xx")
            echo "kmod-usb-dwc3 kmod-usb-dwc3-qcom kmod-phy-qcom-dwc3"
            ;;
        "mt7981")
            echo "kmod-usb-xhci-mtk kmod-usb3"
            ;;
        "ath79")
            echo "kmod-usb2-ath79"
            ;;
        *)
            echo "kmod-usb-core kmod-usb2 kmod-usb3"
            ;;
    esac
}

# 获取平台网络驱动
get_platform_network_drivers() {
    local platform="$1"
    
    case "$platform" in
        "ipq40xx")
            echo "kmod-ath10k kmod-ath10k-ct"
            ;;
        "mt7981")
            echo "kmod-mt7915e kmod-mt7916"
            ;;
        "ath79")
            echo "kmod-ath9k"
            ;;
        *)
            echo ""
            ;;
    esac
}

# ==================== 构建配置函数 ====================
#【support.sh-06】构建配置函数部分开始

# 获取推荐的配置模式
get_recommended_config_mode() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17")
            echo "normal"  # 高性能设备建议完整功能
            ;;
        "cmcc_rax3000m")
            echo "normal"  # 高性能MT7981平台建议完整功能
            ;;
        "netgear_3800")
            echo "normal"  # 传统设备建议正常模式
            ;;
        *)
            echo "base"    # 未知设备建议基础模式
            ;;
    esac
}

# ==================== 固件特性检查 ====================
#【support.sh-07】固件特性检查部分开始

# 检查设备是否支持USB
check_usb_support() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17"|"netgear_3800")
            echo "yes"  # 这些设备有USB接口
            ;;
        "cmcc_rax3000m")
            echo "no"   # RAX3000M没有USB接口
            ;;
        *)
            echo "no"
            ;;
    esac
}

# 检查设备是否支持5G WiFi
check_5g_wifi_support() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17"|"cmcc_rax3000m")
            echo "yes"  # 这些设备支持5G WiFi
            ;;
        *)
            echo "no"
            ;;
    esac
}

# ==================== 设备特定提示 ====================
#【support.sh-08】设备特定提示部分开始

# 获取设备构建提示
get_device_build_hints() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17")
            echo "🔧 提示: 高通IPQ40xx平台需要大量内存，建议至少2GB RAM进行编译"
            echo "📶 提示: 此设备支持5G WiFi，确保已启用ath10k驱动"
            ;;
        "cmcc_rax3000m")
            echo "🔧 提示: 联发科MT7981平台为64位ARM架构，性能强劲"
            echo "📶 提示: 此设备支持WiFi 6，确保已启用mt7915e/mt7916驱动"
            echo "💾 提示: 512MB大内存，适合安装大量插件"
            ;;
        "netgear_3800")
            echo "🔧 提示: ath79平台编译较简单，适合初学者"
            echo "📡 提示: 此设备使用传统atheros无线方案"
            ;;
        *)
            echo "⚠️  未知设备，建议先使用基础模式测试编译"
            ;;
    esac
}

# ==================== 帮助函数 ====================
#【support.sh-09】帮助函数部分开始

# 显示所有支持的设备
show_all_devices() {
    echo ""
    echo "📱 支持的设备列表:"
    echo "=================="
    echo "1. acrh17|ac42u  - ASUS RT-ACRH17/AC42U (高通IPQ40xx, 四核1.4GHz)"
    echo "2. cmcc_rax3000m - 中国移动RAX3000M (MT7981, WiFi 6, 512MB)"
    echo "3. netgear_3800  - Netgear WNDR3800 (ath79, 680MHz, 128MB)"
    echo ""
    echo "💡 使用方法:"
    echo "  在构建工作流中选择设备名称即可"
    echo "  更多设备可通过编辑此文件添加"
}

# 测试函数
test_support_functions() {
    echo "🧪 设备支持系统测试:"
    echo "=================="
    
    local test_devices="acrh17 cmcc_rax3000m netgear_3800 ac42u unknown"
    
    for device in $test_devices; do
        echo ""
        echo "📱 测试设备: $device"
        echo "  描述: $(get_device_description "$device")"
        echo "  配置: $(get_device_config "$device")"
        echo "  USB支持: $(check_usb_support "$device")"
        echo "  5G WiFi: $(check_5g_wifi_support "$device")"
    done
    
    echo ""
    echo "✅ 设备支持系统测试完成"
}

# ==================== 主函数 ====================
#【support.sh-10】主函数部分开始

# 如果直接运行此脚本，显示帮助信息
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "设备支持系统 v1.1"
    echo "使用方法:"
    echo "  source support.sh"
    echo "  然后调用相关函数"
    echo ""
    show_all_devices
    echo ""
    echo "🔧 可用函数:"
    echo "  get_all_devices              # 获取所有设备列表"
    echo "  get_device_config <设备名>   # 获取设备配置"
    echo "  get_device_description <设备名> # 获取设备描述"
    echo "  show_all_devices             # 显示所有设备信息"
    echo "  test_support_functions       # 测试所有函数"
fi
