#!/bin/bash

# OpenWrt 设备检测脚本
# 使用方法: ./device_detection.sh <设备名称>

set -e

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
            grep "define Device" "$target_mk" | sed 's/.*define Device\///' | sed 's/.*define Device\///' | head -10
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
        
        # 从设备树文件名提取设备名称
        local device_short_name=$(extract_device_name "$dts_basename" "$device_input")
        
        echo "✅ 自动检测结果:"
        echo "平台: $platform"
        echo "设备简称: $device_short_name"
        echo "完整名称: $device_full_name"
        
        # 验证设备在目标配置中
        if verify_device "$platform" "$device_short_name"; then
            export PLATFORM="$platform"
            export DEVICE_SHORT_NAME="$device_short_name"
            export DEVICE_FULL_NAME="$device_full_name"
            return 0
        else
            echo "❌ 设备 $device_short_name 在目标配置中未定义"
            return 1
        fi
    else
        echo "❌ 未找到设备树文件: *$device_input*.dts"
        return 1
    fi
}

# 从设备树文件名提取设备名称
extract_device_name() {
    local dts_basename="$1"
    local device_input="$2"
    
    # 调试信息输出到stderr，不影响函数返回值
    echo "设备树文件名: $dts_basename" >&2
    echo "输入设备名: $device_input" >&2
    
    # 特殊处理已知的设备名称映射
    case "$device_input" in
        "ac42u"|"rt-acrh17")
            # 对于 RT-ACRH17，使用标准的设备名称
            echo "asus_rt-acrh17"
            ;;
        "xiaomi_redmi-ax6s")
            echo "xiaomi_redmi-ax6s"
            ;;
        *)
            # 默认使用设备树文件名（去掉扩展名）
            echo "$dts_basename"
            ;;
    esac
}

# 验证设备在目标配置中定义
verify_device() {
    local platform="$1"
    local device_name="$2"
    
    local target_mk="target/linux/$platform/generic/target.mk"
    if [ -f "$target_mk" ]; then
        if grep -q "define Device.*$device_name" "$target_mk"; then
            echo "✅ 设备 $device_name 在目标配置中已定义"
            
            # 输出设备信息到文件
            echo "PLATFORM=$platform" > device_info.txt
            echo "DEVICE_SHORT_NAME=$device_name" >> device_info.txt
            echo "DEVICE_FULL_NAME=$device_input" >> device_info.txt
            
            echo "设备信息已保存到 device_info.txt"
            echo "=== device_info.txt 内容 ==="
            cat device_info.txt
            
            return 0
        else
            echo "❌ 设备 $device_name 在目标配置中未定义"
            echo "=== 目标配置文件中定义的设备 ==="
            grep "define Device" "$target_mk" | head -10
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
