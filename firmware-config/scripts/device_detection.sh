#!/bin/bash
detect_device_config() {
    local device_input="$1"
    local platform=""
    local device_short_name=""
    local device_full_name=""
    
    echo "=== 智能设备检测 ==="
    echo "输入设备: $device_input"
    
    # 设备映射表
    case "$device_input" in
        "ac42u"|"rt-ac42u"|"asus_ac42u")
            platform="ipq40xx"
            device_short_name="asus_rt-ac42u"
            device_full_name="asus,rt-ac42u"
            ;;
        "acrh17"|"rt-acrh17"|"asus_acrh17")
            platform="ipq40xx" 
            device_short_name="asus_rt-acrh17"
            device_full_name="asus,rt-acrh17"
            ;;
        "mi3g"|"r3g"|"xiaomi_mi3g")
            platform="ramips"
            device_short_name="xiaomi_mi-router-3g"
            device_full_name="xiaomi,mi-router-3g"
            ;;
        "k2p"|"phicomm_k2p")
            platform="ramips"
            device_short_name="phicomm_k2p"
            device_full_name="phicomm,k2p"
            ;;
        *)
            echo "⚠️ 未知设备，尝试自动检测..."
            # 自动检测逻辑
            detect_platform_and_device "$device_input"
            return
            ;;
    esac
    
    echo "✅ 检测到设备:"
    echo "   平台: $platform"
    echo "   设备简称: $device_short_name"
    echo "   完整名称: $device_full_name"
    
    # 验证平台存在性
    if [ ! -d "target/linux/$platform" ]; then
        echo "❌ 错误: 平台目录不存在: target/linux/$platform"
        return 1
    fi
    
    # 查找配置文件
    find_config_files "$platform"
    
    # 查找设备定义
    find_device_definitions "$platform" "$device_short_name" "$device_full_name"
    
    # 设置环境变量
    export PLATFORM="$platform"
    export DEVICE_SHORT_NAME="$device_short_name" 
    export DEVICE_FULL_NAME="$device_full_name"
}

detect_platform_and_device() {
    local device_input="$1"
    
    echo "=== 自动设备检测 ==="
    
    # 搜索设备树文件
    echo "搜索设备树文件..."
    local dts_files=$(find target/linux -name "*$device_input*.dts" -o -name "*$device_input*.dtsi" | head -5)
    
    if [ -n "$dts_files" ]; then
        echo "✅ 找到设备树文件:"
        echo "$dts_files"
        # 从路径提取平台
        platform=$(echo "$dts_files" | head -1 | cut -d'/' -f3)
        echo "检测到平台: $platform"
    else
        echo "❌ 未找到设备树文件"
    fi
    
    # 搜索Makefile中的设备定义
    echo "搜索设备定义..."
    local makefile_matches=$(grep -r "DEVICE_.*$device_input" target/linux/*/image/Makefile target/linux/*/generic/target.mk 2>/dev/null | head -5)
    
    if [ -n "$makefile_matches" ]; then
        echo "✅ 找到设备定义:"
        echo "$makefile_matches"
    else
        echo "❌ 未找到设备定义"
    fi
    
    # 搜索配置中的设备
    echo "搜索配置文件..."
    local config_matches=$(find target/linux -name "config-*" -exec grep -l "$device_input" {} \; 2>/dev/null | head -3)
    
    if [ -n "$config_matches" ]; then
        echo "✅ 找到配置文件引用:"
        echo "$config_matches"
    fi
}

find_config_files() {
    local platform="$1"
    
    echo "=== 查找配置文件 ==="
    
    # 查找内核配置
    local kernel_configs=$(find "target/linux/$platform" -name "config-*" | head -5)
    if [ -n "$kernel_configs" ]; then
        echo "✅ 内核配置文件:"
        echo "$kernel_configs"
        # 获取最新的内核版本
        local latest_config=$(echo "$kernel_configs" | sort -V | tail -1)
        echo "使用内核配置: $(basename $latest_config)"
        export KERNEL_CONFIG="$latest_config"
    else
        echo "❌ 未找到内核配置文件"
    fi
    
    # 查找目标配置
    local target_mk="target/linux/$platform/generic/target.mk"
    if [ -f "$target_mk" ]; then
        echo "✅ 找到目标配置: $target_mk"
        export TARGET_MK="$target_mk"
    else
        echo "❌ 未找到目标配置: $target_mk"
    fi
    
    # 查找镜像配置
    local image_mk="target/linux/$platform/image/Makefile"
    if [ -f "$image_mk" ]; then
        echo "✅ 找到镜像配置: $image_mk"
        export IMAGE_MK="$image_mk"
    else
        echo "⚠️ 未找到镜像配置: $image_mk"
    fi
}

find_device_definitions() {
    local platform="$1"
    local short_name="$2"
    local full_name="$3"
    
    echo "=== 查找设备定义 ==="
    
    # 在目标配置中查找设备
    if [ -f "$TARGET_MK" ]; then
        echo "在 $TARGET_MK 中查找设备定义..."
        if grep -q "$short_name" "$TARGET_MK"; then
            echo "✅ 在目标配置中找到设备: $short_name"
        else
            echo "❌ 在目标配置中未找到设备: $short_name"
        fi
    fi
    
    # 在镜像配置中查找设备
    if [ -f "$IMAGE_MK" ]; then
        echo "在 $IMAGE_MK 中查找设备定义..."
        if grep -q "$short_name" "$IMAGE_MK"; then
            echo "✅ 在镜像配置中找到设备: $short_name"
        else
            echo "❌ 在镜像配置中未找到设备: $short_name"
        fi
    fi
    
    # 查找设备树文件
    local dts_file=$(find "target/linux/$platform" -name "*$short_name*.dts" | head -1)
    if [ -n "$dts_file" ]; then
        echo "✅ 找到设备树文件: $dts_file"
        export DTS_FILE="$dts_file"
    else
        echo "❌ 未找到设备树文件: *$short_name*.dts"
    fi
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        echo "用法: $0 <设备名称>"
        echo "示例: $0 ac42u"
        echo "示例: $0 rt-acrh17" 
        exit 1
    fi
    
    detect_device_config "$1"
    
    if [ -n "$PLATFORM" ] && [ -n "$DEVICE_SHORT_NAME" ]; then
        echo ""
        echo "=== 检测结果汇总 ==="
        echo "平台: $PLATFORM"
        echo "设备简称: $DEVICE_SHORT_NAME"
        echo "完整名称: $DEVICE_FULL_NAME"
        echo "内核配置: $KERNEL_CONFIG"
        echo "目标配置: $TARGET_MK"
        echo "设备树文件: $DTS_FILE"
    else
        echo "❌ 设备检测失败"
        exit 1
    fi
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
