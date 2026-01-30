#!/bin/bash
# firmware-config/support.sh
# 设备支持系统配置文件

# ==================== 设备配置函数 ====================

# 获取所有支持的设备列表
get_all_devices() {
    echo "ac42u acrh17 mi_router_4a_gigabit mi_router_3g netgear_3800"
}

# 获取设备配置
get_device_config() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u")
            echo "ipq40xx generic asus_rt-ac42u ipq40xx"
            ;;
        "acrh17")
            echo "ipq40xx generic asus_rt-acrh17 ipq40xx"
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            echo "ramips mt76x8 xiaomi_mi-router-4a-gigabit ramips"
            ;;
        "mi_router_3g"|"r3g")
            echo "ramips mt7621 xiaomi_mi-router-3g ramips"
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
        "ac42u")
            echo "ASUS RT-AC42U (高通IPQ40xx平台, 双频无线)"
            ;;
        "acrh17")
            echo "ASUS RT-ACRH17 (高通IPQ40xx平台, 四核1.4GHz)"
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            echo "小米路由器4A千兆版 (MT7628/MT7688平台, 128MB内存)"
            ;;
        "mi_router_3g"|"r3g")
            echo "小米路由器3G (MT7621平台, 256MB内存, USB接口)"
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

# 检查设备是否需要特殊配置
check_device_special_config() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17")
            echo "高通IPQ40xx平台需要专用USB驱动和无线驱动"
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            echo "MT76x8平台需要MT76无线驱动"
            ;;
        "mi_router_3g"|"r3g")
            echo "MT7621平台需要专用USB和PCIe驱动"
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

# 获取平台USB驱动配置
get_platform_usb_drivers() {
    local platform="$1"
    
    case "$platform" in
        "ipq40xx")
            echo "kmod-usb-dwc3 kmod-usb-dwc3-qcom kmod-phy-qcom-dwc3"
            ;;
        "ramips")
            echo "kmod-usb-xhci-mtk"
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
        "ramips")
            echo "kmod-mt76 kmod-mt76-core"
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

# 获取推荐的配置模式
get_recommended_config_mode() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17")
            echo "normal"  # 高性能设备建议完整功能
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            echo "normal"  # 中等性能设备建议正常模式
            ;;
        "mi_router_3g"|"r3g")
            echo "normal"  # 带USB接口的设备建议完整功能
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

# 检查设备是否支持USB
check_usb_support() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17"|"mi_router_3g"|"r3g"|"netgear_3800")
            echo "yes"  # 这些设备有USB接口
            ;;
        *)
            echo "no"   # 其他设备可能没有USB
            ;;
    esac
}

# 检查设备是否支持5G WiFi
check_5g_wifi_support() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17"|"mi_router_3g"|"r3g")
            echo "yes"  # 这些设备支持5G WiFi
            ;;
        *)
            echo "no"   # 其他设备可能不支持
            ;;
    esac
}

# ==================== 设备特定提示 ====================

# 获取设备构建提示
get_device_build_hints() {
    local device_name="$1"
    
    case "$device_name" in
        "ac42u"|"acrh17")
            echo "🔧 提示: 高通IPQ40xx平台需要大量内存，建议至少2GB RAM进行编译"
            echo "📶 提示: 此设备支持5G WiFi，确保已启用ath10k驱动"
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            echo "🔧 提示: MT76x8平台资源有限，建议使用基础模式或精简配置"
            echo "💾 提示: 此设备只有128MB内存，避免安装过多插件"
            ;;
        "mi_router_3g"|"r3g")
            echo "🔧 提示: MT7621平台性能较好，适合安装完整功能"
            echo "🔌 提示: 此设备有USB接口，确保已启用USB相关驱动"
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

# 显示所有支持的设备
show_all_devices() {
    echo ""
    echo "📱 支持的设备列表:"
    echo "=================="
    echo "1. ac42u       - ASUS RT-AC42U (高通IPQ40xx, 双频)"
    echo "2. acrh17      - ASUS RT-ACRH17 (高通IPQ40xx, 四核)"
    echo "3. r4ag        - 小米路由器4A千兆版 (MT7628, 千兆)"
    echo "4. r3g         - 小米路由器3G (MT7621, USB接口)"
    echo "5. netgear_3800 - Netgear WNDR3800 (ath79, 经典)"
    echo ""
    echo "💡 使用方法:"
    echo "  在构建工作流中选择设备名称即可"
    echo "  更多设备可通过编辑此文件添加"
}

# 测试函数
test_support_functions() {
    echo "🧪 设备支持系统测试:"
    echo "=================="
    
    local test_devices="ac42u r4ag r3g netgear_3800 unknown"
    
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

# 如果直接运行此脚本，显示帮助信息
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "设备支持系统 v1.0"
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
