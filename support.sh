#!/bin/bash

# OpenWrt 设备支持配置 - 简化版
# 仅用于前端界面读取设备列表

# 设备配置映射表（关联数组）
declare -A DEVICES

# ASUS 华硕系列
DEVICES["ac42u"]="ipq40xx generic asus_rt-ac42u"
DEVICES["acrh17"]="ipq40xx generic asus_rt-ac42u"

# 小米/红米系列
DEVICES["ax6s"]="mediatek mt7622 xiaomi_redmi-router-ax6s"
DEVICES["ax6"]="qualcommax ipq807x xiaomi_ax3600"
DEVICES["wr30u"]="mediatek mt7981 xiaomi_wr30u"
DEVICES["miwifi-mini"]="ramips mt7620 xiaomi_miwifi-mini"
DEVICES["miwifi-3g"]="ramips mt7621 xiaomi_mi-router-3g"
DEVICES["redmi-ac2100"]="ramips mt7621 xiaomi_redmi-router-ac2100"

# 360 安全路由器
DEVICES["360t7"]="mediatek mt7981 360_t7"

# 斐讯系列
DEVICES["k2p"]="ramips mt7621 phicomm_k2p"
DEVICES["k2"]="ramips mt7620 phicomm_k2"

# 极路由系列
DEVICES["hc5962"]="ramips mt7621 hiwifi_hc5962"

# 新添加的设备可以在这里扩展
# DEVICES["new_device"]="target subtarget device_model"

# 获取设备配置函数
get_device_config() {
    local device_name="$1"
    
    if [ -z "${DEVICES[$device_name]}" ]; then
        echo ""
        return 1
    else
        echo "${DEVICES[$device_name]}"
        return 0
    fi
}

# 获取设备列表（用于前端界面）
list_devices() {
    for device_name in "${!DEVICES[@]}"; do
        echo "$device_name"
    done | sort
}

# 如果直接运行此脚本，输出设备列表（每行一个设备）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    list_devices
fi
