#!/bin/bash

# 设备配置映射
get_device_config() {
    local device_name=$1
    
    case "$device_name" in
        "ac42u"|"acrh17")
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="asus_rt-ac42u"
            PLATFORM="arm"
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            TARGET="ramips"
            SUBTARGET="mt76x8"
            DEVICE="xiaomi_mi-router-4a-gigabit"
            PLATFORM="mips"
            ;;
        "mi_router_3g"|"r3g")
            TARGET="ramips"
            SUBTARGET="mt7621"
            DEVICE="xiaomi_mi-router-3g"
            PLATFORM="mips"
            ;;
        # 添加新设备在这里
        "netgear_3800")
            TARGET="ar71xx"
            SUBTARGET="generic"
            DEVICE="netgear_wndr3800"
            PLATFORM="mips"
            ;;
        "xiaomi_ax3600")
            TARGET="ipq60xx"
            SUBTARGET="generic"
            DEVICE="xiaomi_ax3600"
            PLATFORM="arm"
            ;;
        *)
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="$device_name"
            PLATFORM="generic"
            ;;
    esac
    
    echo "$TARGET $SUBTARGET $DEVICE $PLATFORM"
}

# SDK下载URL映射
get_sdk_url() {
    local target="$1"
    local subtarget="$2"
    local version="$3"
    
    # 23.05 SDK配置
    if [ "$version" = "23.05" ] || [ "$version" = "openwrt-23.05" ]; then
        case "$target" in
            "ipq40xx")
                echo "https://downloads.openwrt.org/releases/23.05.3/targets/ipq40xx/generic/openwrt-sdk-23.05.3-ipq40xx-generic_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                ;;
            "ramips")
                if [ "$subtarget" = "mt76x8" ]; then
                    echo "https://downloads.openwrt.org/releases/23.05.3/targets/ramips/mt76x8/openwrt-sdk-23.05.3-ramips-mt76x8_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                elif [ "$subtarget" = "mt7621" ]; then
                    echo "https://downloads.openwrt.org/releases/23.05.3/targets/ramips/mt7621/openwrt-sdk-23.05.3-ramips-mt7621_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
                fi
                ;;
        esac
    # 21.02 SDK配置
    elif [ "$version" = "21.02" ] || [ "$version" = "openwrt-21.02" ]; then
        case "$target" in
            "ipq40xx")
                echo "https://downloads.openwrt.org/releases/21.02.7/targets/ipq40xx/generic/openwrt-sdk-21.02.7-ipq40xx-generic_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
                ;;
            "ramips")
                if [ "$subtarget" = "mt76x8" ]; then
                    echo "https://downloads.openwrt.org/releases/21.02.7/targets/ramips/mt76x8/openwrt-sdk-21.02.7-ramips-mt76x8_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
                elif [ "$subtarget" = "mt7621" ]; then
                    echo "https://downloads.openwrt.org/releases/21.02.7/targets/ramips/mt7621/openwrt-sdk-21.02.7-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
                fi
                ;;
        esac
    fi
}

# 获取设备描述
get_device_description() {
    local device_name=$1
    
    case "$device_name" in
        "ac42u") echo "华硕RT-AC42U (高通IPQ40xx平台)" ;;
        "acrh17") echo "华硕RT-ACRH17 (高通IPQ40xx平台)" ;;
        "mi_router_4a_gigabit"|"r4ag") echo "小米4A千兆版 (雷凌MT76x8平台)" ;;
        "mi_router_3g"|"r3g") echo "小米路由器3G (雷凌MT7621平台)" ;;
        "netgear_3800") echo "网件WNDR3800 (高通AR71xx平台)" ;;
        "xiaomi_ax3600") echo "小米AX3600 (高通IPQ60xx平台)" ;;
        *) echo "未知设备" ;;
    esac
}
