#!/bin/bash

# OpenWrt 设备支持配置 - 简化版
# 仅用于前端界面读取设备列表

# 设备配置映射表（关联数组）
declare -A DEVICES

# 支持的设备列表（仅3个设备）
DEVICES["ac42u"]="ipq40xx generic"
DEVICES["cmcc_rax3000m"]="mediatek mt7981"
DEVICES["netgear_3800"]="ath79 generic"

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
