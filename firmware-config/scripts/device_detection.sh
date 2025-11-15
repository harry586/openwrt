#!/bin/bash

# OpenWrt 设备检测脚本 - 宽松版

set -e

# 设备名称映射
declare -A DEVICE_NAME_MAP=(
    ["ac42u"]="asus_rt-acrh17"
    ["acrh17"]="asus_rt-acrh17"
    ["rt-acrh17"]="asus_rt-acrh17"
    ["xiaomi_redmi-ax6s"]="xiaomi_redmi-ax6s"
    ["wr841n"]="tl-wr841n-v9"
    ["mi3g"]="xiaomi_mi-router-3g"
)

# 主检测函数
detect_device() {
    local device_input="$1"
    
    echo "=== 智能设备检测 ==="
    echo "输入设备: $device_input"
    
    # 首先尝试预定义的设备映射
    if [ -n "${DEVICE_NAME_MAP[$device_input]}" ]; then
        echo "使用预定义的设备映射: ${DEVICE_NAME_MAP[$device_input]}"
        if auto_detect_with_mapping "$device_input" "${DEVICE_NAME_MAP[$device_input]}"; then
            return 0
        fi
    fi
    
    # 尝试自动检测
    echo "尝试自动设备检测..."
    if auto_detect_device "$device_input"; then
        return 0
    fi
    
    # 如果自动检测失败，使用默认值
    echo "⚠️ 自动检测失败，使用默认值"
    use_default_mapping "$device_input"
}

# 使用预定义映射检测
auto_detect_with_mapping() {
    local device_input="$1"
    local mapped_name="$2"
    
    echo "使用映射名称: $mapped_name"
    
    # 查找平台
    local platform=$(find_device_platform "$mapped_name")
    if [ -n "$platform" ]; then
        echo "✅ 找到平台: $platform"
        
        # 验证设备定义
        if verify_device "$platform" "$mapped_name"; then
            export PLATFORM="$platform"
            export DEVICE_SHORT_NAME="$mapped_name"
            export DEVICE_FULL_NAME="$device_input"
            return 0
        fi
    fi
    
    return 1
}

# 查找设备平台
find_device_platform() {
    local device_name="$1"
    
    # 在所有平台中查找设备
    for platform_dir in target/linux/*; do
        local platform=$(basename "$platform_dir")
        if [ "$platform" = "generic" ] || [ "$platform" = "modules" ]; then
            continue
        fi
        
        # 检查目标配置文件
        local target_mk="$platform_dir/generic/target.mk"
        if [ -f "$target_mk" ] && grep -q "define Device.*$device_name" "$target_mk" 2>/dev/null; then
            echo "$platform"
            return 0
        fi
        
        # 检查 image 配置文件
        local image_mk="$platform_dir/image/target.mk"
        if [ -f "$image_mk" ] && grep -q "define Device.*$device_name" "$image_mk" 2>/dev/null; then
            echo "$platform"
            return 0
        fi
    done
    
    # 如果没有找到，尝试通过设备树文件推断
    local dts_files=$(find target/linux -name "*$device_name*" -type f 2>/dev/null | head -1)
    if [ -n "$dts_files" ]; then
        local platform=$(echo "$dts_files" | cut -d'/' -f3)
        echo "$platform"
        return 0
    fi
    
    return 1
}

# 自动检测设备
auto_detect_device() {
    local device_input="$1"
    
    echo "搜索设备相关文件..."
    
    # 搜索设备树文件
    local dts_files=$(find target/linux -name "*$device_input*" -type f 2>/dev/null | head -5)
    
    if [ -n "$dts_files" ]; then
        echo "✅ 找到设备文件:"
        echo "$dts_files"
        
        local platform=$(echo "$dts_files" | head -1 | cut -d'/' -f3)
        local dts_basename=$(basename "$dts_files" | head -1 | sed 's/\..*//')
        
        echo "推断平台: $platform"
        echo "推断设备名: $dts_basename"
        
        # 尝试使用推断的设备名
        if verify_device "$platform" "$dts_basename"; then
            export PLATFORM="$platform"
            export DEVICE_SHORT_NAME="$dts_basename"
            export DEVICE_FULL_NAME="$device_input"
            return 0
        fi
        
        # 如果失败，尝试常见设备名变体
        local name_variants=(
            "$device_input"
            "rt-$device_input"
            "asus_$device_input"
            "asus_rt-$device_input"
        )
        
        for variant in "${name_variants[@]}"; do
            if verify_device "$platform" "$variant"; then
                export PLATFORM="$platform"
                export DEVICE_SHORT_NAME="$variant"
                export DEVICE_FULL_NAME="$device_input"
                return 0
            fi
        done
    fi
    
    return 1
}

# 验证设备在目标配置中定义
verify_device() {
    local platform="$1"
    local device_name="$2"
    
    echo "验证设备: $device_name (平台: $platform)"
    
    # 检查 generic/target.mk
    local target_mk="target/linux/$platform/generic/target.mk"
    if [ -f "$target_mk" ]; then
        if grep -q "define Device.*$device_name" "$target_mk" 2>/dev/null; then
            echo "✅ 设备 $device_name 在目标配置中已定义"
            save_device_info "$platform" "$device_name"
            return 0
        fi
    fi
    
    # 检查 image/target.mk
    local image_mk="target/linux/$platform/image/target.mk"
    if [ -f "$image_mk" ]; then
        if grep -q "define Device.*$device_name" "$image_mk" 2>/dev/null; then
            echo "✅ 设备 $device_name 在镜像配置中已定义"
            save_device_info "$platform" "$device_name"
            return 0
        fi
    fi
    
    echo "❌ 设备 $device_name 在平台 $platform 中未定义"
    return 1
}

# 保存设备信息
save_device_info() {
    local platform="$1"
    local device_name="$2"
    
    echo "PLATFORM=$platform" > device_info.txt
    echo "DEVICE_SHORT_NAME=$device_name" >> device_info.txt
    echo "DEVICE_FULL_NAME=$device_input" >> device_info.txt
    
    echo "设备信息已保存到 device_info.txt"
    echo "=== device_info.txt 内容 ==="
    cat device_info.txt
}

# 使用默认映射
use_default_mapping() {
    local device_input="$1"
    
    # 常见设备的默认平台映射
    case "$device_input" in
        "ac42u"|"acrh17"|"rt-acrh17")
            export PLATFORM="ipq40xx"
            export DEVICE_SHORT_NAME="asus_rt-acrh17"
            export DEVICE_FULL_NAME="$device_input"
            ;;
        "xiaomi_redmi-ax6s")
            export PLATFORM="mediatek"
            export DEVICE_SHORT_NAME="xiaomi_redmi-ax6s"
            export DEVICE_FULL_NAME="$device_input"
            ;;
        "wr841n")
            export PLATFORM="ar71xx"
            export DEVICE_SHORT_NAME="tl-wr841n-v9"
            export DEVICE_FULL_NAME="$device_input"
            ;;
        "mi3g")
            export PLATFORM="ramips"
            export DEVICE_SHORT_NAME="xiaomi_mi-router-3g"
            export DEVICE_FULL_NAME="$device_input"
            ;;
        *)
            # 通用默认值
            export PLATFORM="ipq40xx"
            export DEVICE_SHORT_NAME="$device_input"
            export DEVICE_FULL_NAME="$device_input"
            ;;
    esac
    
    echo "⚠️ 使用默认设备映射:"
    echo "平台: $PLATFORM"
    echo "设备: $DEVICE_SHORT_NAME"
    
    save_device_info "$PLATFORM" "$DEVICE_SHORT_NAME"
    return 0
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        echo "用法: $0 <设备名称>"
        echo "示例: $0 ac42u"
        echo "示例: $0 acrh17"
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
