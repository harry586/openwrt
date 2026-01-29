#!/bin/bash

# 设备支持脚本
# 用于管理设备配置映射和SDK下载URL

# 获取设备配置信息
get_device_config() {
    local device_name=$1
    
    case "$device_name" in
        "ac42u"|"acrh17")
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="asus_rt-ac42u"
            PLATFORM="ipq40xx"
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            TARGET="ramips"
            SUBTARGET="mt76x8"
            DEVICE="xiaomi_mi-router-4a-gigabit"
            PLATFORM="ramips"
            ;;
        "mi_router_3g"|"r3g")
            TARGET="ramips"
            SUBTARGET="mt7621"
            DEVICE="xiaomi_mi-router-3g"
            PLATFORM="ramips"
            ;;
        "netgear_3800")
            # 注意：Netgear WNDR3800 使用 ath79 架构
            TARGET="ath79"
            SUBTARGET="generic"
            DEVICE="netgear_wndr3800"
            PLATFORM="ath79"
            ;;
        "rax3000m"|"cmcc_rax3000m")
            TARGET="mediatek"
            SUBTARGET="mt7981"
            DEVICE="cmcc_rax3000m"
            PLATFORM="mediatek"
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
                echo "https://downloads.openwrt.org/releases/23.05.6/targets/ipq40xx/generic/openwrt-sdk-23.05.6-ipq40xx-generic_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                ;;
            "ramips")
                if [ "$subtarget" = "mt76x8" ]; then
                    echo "https://downloads.openwrt.org/releases/23.05.6/targets/ramips/mt76x8/openwrt-sdk-23.05.6-ramips-mt76x8_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                elif [ "$subtarget" = "mt7621" ]; then
                    echo "https://downloads.openwrt.org/releases/23.05.6/targets/ramips/mt7621/openwrt-sdk-23.05.6-ramips-mt7621_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
                fi
                ;;
            "ath79")
                # ath79通用SDK（如果有的话）
                echo "https://downloads.openwrt.org/releases/23.05.6/targets/ath79/generic/openwrt-sdk-23.05.6-ath79-generic_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
                ;;
            "mediatek")
                # MT7981属于filogic子目标
                echo "https://downloads.openwrt.org/releases/23.05.6/targets/mediatek/filogic/openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
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
            "ath79")
                # ath79通用SDK（如果有的话）
                echo "https://downloads.openwrt.org/releases/21.02.7/targets/ath79/generic/openwrt-sdk-21.02.7-ath79-generic_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
                ;;
            "mediatek")
                # 21.02可能不支持MT7981，留空或使用其他版本
                echo ""
                ;;
        esac
    fi
}

# 获取设备描述
get_device_description() {
    local device_name=$1
    
    case "$device_name" in
        "ac42u"|"acrh17") echo "华硕RT-AC42U/RT-ACRH17 (高通IPQ40xx平台)" ;;
        "mi_router_4a_gigabit"|"r4ag") echo "小米4A千兆版 (雷凌MT76x8平台)" ;;
        "mi_router_3g"|"r3g") echo "小米路由器3G (雷凌MT7621平台)" ;;
        "netgear_3800") echo "网件WNDR3800 (高通AR71xx/ath79平台)" ;;
        "rax3000m"|"cmcc_rax3000m") echo "中国移动RAX3000M (联发科MT7981平台, 128MB NAND)" ;;
        *) echo "未知设备" ;;
    esac
}

# 获取平台类型
get_platform_type() {
    local platform="$1"
    
    case "$platform" in
        "ipq40xx") echo "arm" ;;
        "ramips") echo "mips" ;;
        "ath79") echo "mips" ;;
        "mediatek") echo "arm" ;;
        *) echo "generic" ;;
    esac
}
