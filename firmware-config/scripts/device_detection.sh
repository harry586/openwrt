#!/bin/bash

# OpenWrt 设备检测脚本 - 增强版

set -e

# 主检测函数
detect_device() {
    local device_input="$1"
    
    echo "=== 智能设备检测 ==="
    echo "输入设备: $device_input"
    
    # 尝试自动检测设备
    if auto_detect_device "$device_input"; then
        return 0
    else
        echo "❌ 设备检测失败"
        return 1
    fi
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
        local device_full_name="$device_input"
        
        # 验证平台
        if [ ! -d "target/linux/$platform" ]; then
            echo "❌ 检测到的平台目录不存在: target/linux/$platform"
            return 1
        fi
        
        echo "✅ 推断平台: $platform"
        
        # 查找设备定义
        local device_short_name=$(find_device_definition "$platform" "$device_input")
        
        if [ -n "$device_short_name" ]; then
            echo "✅ 找到设备定义: $device_short_name"
        else
            echo "⚠️ 未找到精确的设备定义，使用设备树文件名"
            local dts_basename=$(basename "$dts_files" | head -1 | sed 's/\.dts.*//')
            device_short_name="$dts_basename"
        fi
        
        # 直接输出设备信息，供工作流捕获
        echo "PLATFORM=$platform"
        echo "DEVICE_SHORT_NAME=$device_short_name"
        echo "DEVICE_FULL_NAME=$device_full_name"
        
        # 尝试保存设备信息到文件（可选）
        if save_device_info "$platform" "$device_short_name" "$device_input"; then
            echo "✅ 设备信息保存成功"
        else
            echo "⚠️ 无法保存设备信息文件，但检测结果有效"
        fi
        
        return 0
    else
        echo "❌ 未找到设备树文件: *$device_input*.dts"
        return 1
    fi
}

# 查找设备定义
find_device_definition() {
    local platform="$1"
    local device_input="$2"
    
    echo "在平台 $platform 中查找设备定义..."
    
    # 查找所有可能的设备定义文件
    local mk_files=$(find "target/linux/$platform" -name "*.mk" -type f 2>/dev/null)
    
    # 尝试多种设备名称变体
    local device_variants=(
        "$device_input"
        "rt-$device_input"
        "asus_$device_input"
        "asus_rt-$device_input"
        $(echo "$device_input" | sed 's/ac42u/ac42u/')
        $(echo "$device_input" | sed 's/acrh17/acrh17/')
    )
    
    # 移除重复项
    device_variants=($(printf "%s\n" "${device_variants[@]}" | sort -u))
    
    echo "尝试的设备名称变体: ${device_variants[*]}"
    
    for variant in "${device_variants[@]}"; do
        echo "检查变体: $variant"
        
        for mk_file in $mk_files; do
            # 查找 define Device 行
            local device_line=$(grep -h "define Device.*$variant" "$mk_file" 2>/dev/null | head -1)
            if [ -n "$device_line" ]; then
                echo "✅ 在文件 $mk_file 中找到设备定义"
                echo "设备定义行: $device_line"
                
                # 提取设备名称 (define Device/后面的部分)
                local device_name=$(echo "$device_line" | sed -n 's/.*define Device\/\([^ )]*\).*/\1/p')
                if [ -n "$device_name" ]; then
                    echo "✅ 提取的设备名称: $device_name"
                    # 验证这个设备名称是否在 TARGET_DEVICES 中
                    if grep -q "TARGET_DEVICES.*+=.*$device_name" "$mk_file" 2>/dev/null; then
                        echo "✅ 设备 $device_name 在 TARGET_DEVICES 中"
                        echo "$device_name"
                        return 0
                    else
                        echo "⚠️ 设备 $device_name 不在 TARGET_DEVICES 中，但继续使用"
                        echo "$device_name"
                        return 0
                    fi
                fi
            fi
        done
    done
    
    # 如果没有找到精确匹配，尝试查找包含设备名称的任何定义
    echo "尝试模糊匹配..."
    for mk_file in $mk_files; do
        # 查找包含设备名称的 define Device 行
        local device_line=$(grep -h "define Device.*$device_input" "$mk_file" 2>/dev/null | head -1)
        if [ -n "$device_line" ]; then
            echo "✅ 在文件 $mk_file 中找到模糊匹配的设备定义"
            echo "设备定义行: $device_line"
            
            local device_name=$(echo "$device_line" | sed -n 's/.*define Device\/\([^ )]*\).*/\1/p')
            if [ -n "$device_name" ]; then
                echo "✅ 提取的设备名称: $device_name"
                echo "$device_name"
                return 0
            fi
        fi
    done
    
    return 1
}

# 保存设备信息
save_device_info() {
    local platform="$1"
    local device_short_name="$2"
    local device_input="$3"
    
    # 尝试写入设备信息文件
    if echo "PLATFORM=$platform" > device_info.txt 2>/dev/null; then
        echo "DEVICE_SHORT_NAME=$device_short_name" >> device_info.txt
        echo "DEVICE_FULL_NAME=$device_input" >> device_info.txt
        echo "设备信息已保存到 device_info.txt"
        echo "=== device_info.txt 内容 ==="
        cat device_info.txt
        return 0
    else
        return 1
    fi
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
