#!/bin/bash

# OpenWrt 设备检测脚本
# 使用方法: ./device_detection.sh <设备名称>

set -e

# 设备名称映射表（用于特殊情况的映射）
declare -A DEVICE_MAPPING=(
    ["ac42u"]="asus_rt-acrh17"
    ["rt-acrh17"]="asus_rt-acrh17"
    ["xiaomi_redmi-ax6s"]="xiaomi_redmi-ax6s"
    # 可以添加更多设备映射
)

# 主检测函数
detect_device() {
    local device_input="$1"
    
    echo "=== 智能设备检测 ==="
    echo "输入设备: $device_input"
    
    # 首先显示当前分支所有支持的设备
    echo "=== 当前分支支持的设备 ==="
    find_target_devices
    
    # 尝试自动检测设备
    auto_detect_device "$device_input"
}

# 查找所有目标设备
find_target_devices() {
    echo "扫描所有平台的设备..."
    
    # 查找所有平台
    for platform_dir in target/linux/*; do
        platform=$(basename "$platform_dir")
        if [ "$platform" = "generic" ] || [ "$platform" = "modules" ]; then
            continue
        fi
        
        target_mk="$platform_dir/generic/target.mk"
        if [ -f "$target_mk" ]; then
            echo ""
            echo "平台: $platform"
            echo "支持的设备:"
            # 提取设备定义
            grep "define Device" "$target_mk" | sed 's/.*define Device\///' | head -10
        fi
    done
}

# 自动检测设备
auto_detect_device() {
    local device_input="$1"
    
    echo ""
    echo "=== 自动设备检测 ==="
    
    # 搜索设备树文件
    echo "搜索设备树文件..."
    local dts_files=$(find target/linux -name "*$device_input*.dts" -o -name "*$device_input*.dtsi" 2>/dev/null | head -5)
    
    if [ -n "$dts_files" ]; then
        echo "✅ 找到设备树文件:"
        echo "$dts_files"
        local platform=$(echo "$dts_files" | head -1 | cut -d'/' -f3)
        local dts_basename=$(basename "$dts_files" | head -1 | sed 's/\.dts.*//')
        local device_full_name="$device_input"
        
        # 验证平台
        if [ ! -d "target/linux/$platform" ]; then
            echo "❌ 检测到的平台目录不存在: target/linux/$platform"
            return 1
        fi
        
        # 智能匹配设备名称
        local device_short_name=$(find_matching_device_name "$platform" "$dts_basename" "$device_input")
        
        if [ -n "$device_short_name" ]; then
            echo "✅ 自动检测结果:"
            echo "平台: $platform"
            echo "设备简称: $device_short_name"
            echo "完整名称: $device_full_name"
            
            # 验证设备在目标配置中
            if verify_device "$platform" "$device_short_name"; then
                export PLATFORM="$platform"
                export DEVICE_SHORT_NAME="$device_short_name"
                export DEVICE_FULL_NAME="$device_full_name"
                
                # 输出设备信息到文件
                echo "PLATFORM=$PLATFORM" > device_info.txt
                echo "DEVICE_SHORT_NAME=$DEVICE_SHORT_NAME" >> device_info.txt
                echo "DEVICE_FULL_NAME=$DEVICE_FULL_NAME" >> device_info.txt
                echo "设备信息已保存到 device_info.txt"
                cat device_info.txt
                
                return 0
            else
                echo "❌ 设备 $device_short_name 在目标配置中未定义"
                return 1
            fi
        else
            echo "❌ 无法找到匹配的设备名称"
            return 1
        fi
    else
        echo "❌ 未找到设备树文件: *$device_input*.dts"
        return 1
    fi
}

# 智能匹配设备名称
find_matching_device_name() {
    local platform="$1"
    local dts_basename="$2"
    local device_input="$3"
    
    local target_mk="target/linux/$platform/generic/target.mk"
    
    if [ ! -f "$target_mk" ]; then
        echo "❌ 目标配置文件不存在: $target_mk"
        return 1
    fi
    
    echo "正在智能匹配设备名称..."
    echo "设备树文件名: $dts_basename"
    echo "输入设备名: $device_input"
    
    # 方法1: 检查设备名称映射表
    local mapped_device="${DEVICE_MAPPING[$device_input]}"
    if [ -n "$mapped_device" ]; then
        echo "✅ 通过映射表找到设备: $mapped_device"
        if verify_device "$platform" "$mapped_device"; then
            echo "$mapped_device"
            return 0
        fi
    fi
    
    # 方法2: 在目标配置中搜索设备树引用
    echo "在目标配置中搜索设备树引用..."
    local device_candidates=$(grep -B5 -A5 "DEVICE_DTS.*$dts_basename" "$target_mk" 2>/dev/null | grep "define Device" | head -1 | sed 's/.*define Device\///' | tr -d ' ' || true)
    
    if [ -n "$device_candidates" ]; then
        echo "✅ 通过设备树引用找到设备: $device_candidates"
        if verify_device "$platform" "$device_candidates"; then
            echo "$device_candidates"
            return 0
        fi
    fi
    
    # 方法3: 搜索包含设备输入名称的设备
    echo "搜索包含 '$device_input' 的设备..."
    local name_candidates=$(grep "define Device.*$device_input" "$target_mk" 2>/dev/null | sed 's/.*define Device\///' | head -3)
    
    if [ -n "$name_candidates" ]; then
        echo "找到候选设备:"
        echo "$name_candidates"
        
        # 尝试每个候选设备
        while IFS= read -r candidate; do
            if verify_device "$platform" "$candidate"; then
                echo "✅ 通过名称匹配找到设备: $candidate"
                echo "$candidate"
                return 0
            fi
        done <<< "$name_candidates"
    fi
    
    # 方法4: 搜索包含设备树关键字的设备
    echo "搜索包含设备树关键字的设备..."
    local dts_keyword=$(echo "$dts_basename" | sed 's/qcom-ipq4019-//' | sed 's/\.dts//')
    local dts_candidates=$(grep "define Device.*$dts_keyword" "$target_mk" 2>/dev/null | sed 's/.*define Device\///' | head -3)
    
    if [ -n "$dts_candidates" ]; then
        echo "通过设备树关键字找到候选设备:"
        echo "$dts_candidates"
        
        while IFS= read -r candidate; do
            if verify_device "$platform" "$candidate"; then
                echo "✅ 通过设备树关键字匹配找到设备: $candidate"
                echo "$candidate"
                return 0
            fi
        done <<< "$dts_candidates"
    fi
    
    # 方法5: 列出所有设备并尝试匹配
    echo "尝试在所有设备中匹配..."
    local all_devices=$(grep "define Device" "$target_mk" | sed 's/.*define Device\///')
    
    # 尝试常见的设备名称模式
    local common_patterns=(
        "asus_rt-acrh17"
        "xiaomi_redmi-ax6s"
        "linksys_ea6350"
        "tplink_archer-c7"
    )
    
    for pattern in "${common_patterns[@]}"; do
        if echo "$all_devices" | grep -q "$pattern"; then
            if verify_device "$platform" "$pattern"; then
                echo "✅ 通过常见模式匹配找到设备: $pattern"
                echo "$pattern"
                return 0
            fi
        fi
    done
    
    echo "❌ 无法找到匹配的设备名称"
    return 1
}

# 验证设备在目标配置中定义
verify_device() {
    local platform="$1"
    local device_name="$2"
    
    local target_mk="target/linux/$platform/generic/target.mk"
    if [ -f "$target_mk" ]; then
        if grep -q "define Device.*$device_name" "$target_mk"; then
            echo "✅ 设备 $device_name 在目标配置中已定义"
            return 0
        else
            echo "❌ 设备 $device_name 在目标配置中未定义"
            return 1
        fi
    else
        echo "❌ 目标配置文件不存在: $target_mk"
        return 1
    fi
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        echo "用法: $0 <设备名称>"
        echo "示例: $0 ac42u"
        echo "示例: $0 wr841n"
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
