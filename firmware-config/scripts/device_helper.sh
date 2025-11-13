#!/bin/bash
# device_helper.sh - 设备名称辅助函数

# 将设备树兼容名称转换为配置系统名称
# 输入: asus,rt-ac42u
# 输出: asus_rt-ac42u (用于配置系统)
convert_dts_to_config() {
    local dts_name="$1"
    echo "$dts_name" | sed 's/,/_/g'
}

# 将设备名称转换为搜索模式
# 用于在 generic.mk 中查找设备定义
create_search_pattern() {
    local device_name="$1"
    echo "$device_name" | sed 's/,.*//'  # 提取制造商部分
}

# 验证设备在源码中的存在
validate_device() {
    local build_dir="$1"
    local platform="$2"
    local device_name="$3"
    
    echo "验证设备 $device_name 在 $platform 平台上的支持..."
    
    # 检查设备树文件
    if find "$build_dir/target/linux/$platform" -name "*.dts" -o -name "*.dtsi" 2>/dev/null | xargs grep -l "$device_name" > /dev/null; then
        echo "✅ 找到设备树定义: $device_name"
        return 0
    fi
    
    # 检查 generic.mk
    if [ -f "$build_dir/target/linux/$platform/image/generic.mk" ]; then
        if grep -q "$device_name" "$build_dir/target/linux/$platform/image/generic.mk"; then
            echo "✅ 找到设备配置: $device_name"
            return 0
        fi
    fi
    
    echo "❌ 未找到设备 $device_name 的定义"
    return 1
}

# 获取实际的设备配置名称
get_device_config_name() {
    local build_dir="$1"
    local platform="$2"
    local device_name="$3"
    
    if [ -f "$build_dir/target/linux/$platform/image/generic.mk" ]; then
        # 尝试在 generic.mk 中查找设备定义
        local config_name=$(grep "define Device" "$build_dir/target/linux/$platform/image/generic.mk" | \
                           grep -i "$device_name" | \
                           sed 's/.*define Device\///' | \
                           sed 's/).*//' | \
                           head -1)
        
        if [ -n "$config_name" ]; then
            echo "$config_name"
            return 0
        fi
    fi
    
    # 如果找不到，返回转换后的名称
    convert_dts_to_config "$device_name"
}

# 检查设备特定的包依赖
get_device_packages() {
    local device_name="$1"
    
    case "$device_name" in
        *asus_rt-ac42u*)
            echo "ath10k-firmware-qca9984-ct kmod-usb-ledtrig-usbport"
            ;;
        *asus_rt-ac58u*)
            echo "-kmod-ath10k-ct kmod-ath10k-ct-smallbuffers kmod-usb-ledtrig-usbport"
            ;;
        *8dev_habanero-dvk*)
            echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}
