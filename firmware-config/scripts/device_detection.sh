#!/bin/bash

# OpenWrt 智能设备检测脚本
# 使用方法: ./device_detection.sh <设备名称>

set -e

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
    
    # 斐讯设备
    ["k2p"]="ramips:phicomm_k2p:phicomm,k2p"
    ["phicomm_k2p"]="ramips:phicomm_k2p:phicomm,k2p"
    
    # 其他设备
    ["newifi-d2"]="ramips:newifi_d2:newifi,d2"
    ["newifi_d2"]="ramips:newifi_d2:newifi,d2"
)

# 主检测函数
detect_device() {
    local device_input="$1"
    
    echo "=== 智能设备检测 ==="
    echo "输入设备: $device_input"
    
    local platform=""
    local device_short_name=""
    local device_full_name=""
    
    # 检查设备映射表
    if [ -n "${DEVICE_MAP[$device_input]}" ]; then
        IFS=':' read -r platform device_short_name device_full_name <<< "${DEVICE_MAP[$device_input]}"
        echo "✅ 在设备映射表中找到设备配置"
    else
        echo "❌ 未知设备: $device_input"
        echo "尝试自动检测..."
        auto_detect_device "$device_input"
        return $?
    fi
    
    # 验证平台存在性
    if [ ! -d "target/linux/$platform" ]; then
        echo "❌ 错误: 平台目录不存在: target/linux/$platform"
        return 1
    fi
    
    echo "✅ 检测到设备:"
    echo "平台: $platform"
    echo "设备简称: $device_short_name"
    echo "完整名称: $device_full_name"
    
    # 查找配置文件
    find_config_files "$platform"
    
    # 查找设备定义
    if ! find_device_definitions "$platform" "$device_short_name"; then
        echo "⚠️ 设备 $device_short_name 在目标配置中未找到，尝试查找替代设备..."
        find_alternative_device "$platform" "$device_input"
        return $?
    fi
    
    # 输出结果
    export PLATFORM="$platform"
    export DEVICE_SHORT_NAME="$device_short_name"
    export DEVICE_FULL_NAME="$device_full_name"
    
    echo "=== 检测结果 ==="
    echo "PLATFORM=$platform"
    echo "DEVICE_SHORT_NAME=$device_short_name"
    echo "DEVICE_FULL_NAME=$device_full_name"
    
    return 0
}

# 自动检测设备
auto_detect_device() {
    local device_input="$1"
    
    echo "=== 自动设备检测 ==="
    
    # 搜索设备树文件
    echo "搜索设备树文件..."
    local dts_files=$(find target/linux -name "*$device_input*.dts" -o -name "*$device_input*.dtsi" 2>/dev/null | head -3)
    
    if [ -n "$dts_files" ]; then
        echo "✅ 找到设备树文件:"
        echo "$dts_files"
        local platform=$(echo "$dts_files" | head -1 | cut -d'/' -f3)
        local device_short_name=$(basename "$dts_files" | head -1 | sed 's/\.dts.*//')
        local device_full_name="$device_input"
        
        # 验证平台
        if [ ! -d "target/linux/$platform" ]; then
            echo "❌ 检测到的平台目录不存在: target/linux/$platform"
            return 1
        fi
        
        echo "✅ 自动检测结果:"
        echo "平台: $platform"
        echo "设备简称: $device_short_name"
        echo "完整名称: $device_full_name"
        
        export PLATFORM="$platform"
        export DEVICE_SHORT_NAME="$device_short_name"
        export DEVICE_FULL_NAME="$device_full_name"
        
        return 0
    else
        echo "❌ 自动检测失败，无法识别设备: $device_input"
        return 1
    fi
}

# 查找配置文件
find_config_files() {
    local platform="$1"
    
    echo "=== 查找配置文件 ==="
    
    # 查找内核配置
    local kernel_configs=$(find "target/linux/$platform" -name "config-*" 2>/dev/null | sort -V | tail -1)
    if [ -n "$kernel_configs" ]; then
        echo "✅ 使用内核配置: $(basename $kernel_configs)"
    else
        echo "❌ 未找到内核配置文件"
        return 1
    fi
    
    # 验证目标配置
    local target_mk="target/linux/$platform/generic/target.mk"
    if [ -f "$target_mk" ]; then
        echo "✅ 找到目标配置: $target_mk"
    else
        echo "❌ 未找到目标配置: $target_mk"
        return 1
    fi
}

# 查找设备定义
find_device_definitions() {
    local platform="$1"
    local short_name="$2"
    
    echo "=== 查找设备定义 ==="
    
    # 在目标配置中查找设备
    local target_mk="target/linux/$platform/generic/target.mk"
    if [ -f "$target_mk" ]; then
        if grep -q "$short_name" "$target_mk"; then
            echo "✅ 在目标配置中找到设备: $short_name"
            return 0
        else
            echo "❌ 在目标配置中未找到设备: $short_name"
            return 1
        fi
    else
        echo "❌ 目标配置文件不存在: $target_mk"
        return 1
    fi
}

# 查找替代设备
find_alternative_device() {
    local platform="$1"
    local device_input="$2"
    
    echo "=== 查找替代设备 ==="
    
    local target_mk="target/linux/$platform/generic/target.mk"
    if [ ! -f "$target_mk" ]; then
        echo "❌ 目标配置文件不存在"
        return 1
    fi
    
    # 显示该平台所有可用设备
    echo "平台 $platform 支持的设备列表:"
    grep -E "define Device" "$target_mk" | sed 's/.*define Device\///' | head -20
    
    # 尝试查找类似的设备
    echo "尝试查找类似设备..."
    
    # 根据设备类型查找替代
    case "$device_input" in
        *ac*)
            echo "查找华硕设备..."
            ALTERNATIVE_DEVICE=$(grep "define Device" "$target_mk" | grep -i "asus" | head -1 | sed 's/.*define Device\///')
            ;;
        *mi*|*xiaomi*)
            echo "查找小米设备..."
            ALTERNATIVE_DEVICE=$(grep "define Device" "$target_mk" | grep -i "xiaomi" | head -1 | sed 's/.*define Device\///')
            ;;
        *phicomm*|*k2p*|*k3*)
            echo "查找斐讯设备..."
            ALTERNATIVE_DEVICE=$(grep "define Device" "$target_mk" | grep -i "phicomm" | head -1 | sed 's/.*define Device\///')
            ;;
        *)
            echo "查找通用设备..."
            ALTERNATIVE_DEVICE=$(grep "define Device" "$target_mk" | head -1 | sed 's/.*define Device\///')
            ;;
    esac
    
    if [ -n "$ALTERNATIVE_DEVICE" ]; then
        echo "✅ 找到替代设备: $ALTERNATIVE_DEVICE"
        export PLATFORM="$platform"
        export DEVICE_SHORT_NAME="$ALTERNATIVE_DEVICE"
        export DEVICE_FULL_NAME="$ALTERNATIVE_DEVICE"
        
        echo "=== 使用替代设备 ==="
        echo "PLATFORM=$platform"
        echo "DEVICE_SHORT_NAME=$ALTERNATIVE_DEVICE"
        echo "DEVICE_FULL_NAME=$ALTERNATIVE_DEVICE"
        
        return 0
    else
        echo "❌ 未找到合适的替代设备"
        return 1
    fi
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        echo "用法: $0 <设备名称>"
        echo "示例: $0 ac42u"
        echo "示例: $0 acrh17"
        echo "支持的设备: ac42u, acrh17, ac58u, mi3g, k2p, newifi-d2"
        exit 1
    fi
    
    # 检查是否在 OpenWrt 源码目录
    if [ ! -d "target/linux" ]; then
        echo "❌ 错误: 请在 OpenWrt 源码根目录中运行此脚本"
        exit 1
    fi
    
    detect_device "$1"
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
