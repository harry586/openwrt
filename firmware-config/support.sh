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
        "xiaomi_ax360
