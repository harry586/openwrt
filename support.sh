#!/bin/bash

# OpenWrt 设备支持配置
# 格式: "设备名称" "目标平台" "子目标" "设备型号"

# 设备配置映射表（关联数组）
declare -A DEVICES

# ASUS RT-AC42U / RT-ACRH17 (高通IPQ40xx平台)
DEVICES["ac42u"]="ipq40xx generic asus_rt-ac42u"
DEVICES["acrh17"]="ipq40xx generic asus_rt-ac42u"  # AC42U和ACRH17硬件相同

# 小米系列
DEVICES["miwifi-mini"]="ramips mt7620 xiaomi_miwifi-mini"
DEVICES["miwifi-3g"]="ramips mt7621 xiaomi_mi-router-3g"
DEVICES["redmi-ac2100"]="ramips mt7621 xiaomi_redmi-router-ac2100"

# 斐讯系列
DEVICES["k2p"]="ramips mt7621 phicomm_k2p"
DEVICES["k2"]="ramips mt7620 phicomm_k2"

# 极路由系列
DEVICES["hc5962"]="ramips mt7621 hiwifi_hc5962"

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

# 获取SDK下载URL函数
get_sdk_url() {
    local device_name="$1"
    local version="$2"
    
    # 获取设备配置
    local device_config=$(get_device_config "$device_name")
    if [ -z "$device_config" ]; then
        echo ""
        return 1
    fi
    
    local target=$(echo "$device_config" | awk '{print $1}')
    local subtarget=$(echo "$device_config" | awk '{print $2}')
    
    # 根据版本和设备确定SDK URL
    if [ "$version" = "23.05" ]; then
        case "$target" in
            "ipq40xx")
                # 高通IPQ40xx平台SDK
                echo "https://downloads.openwrt.org/releases/23.05.3/targets/ipq40xx/generic/openwrt-sdk-23.05.3-ipq40xx-generic_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                ;;
            "ramips")
                # 雷凌MT76xx平台SDK
                echo "https://downloads.openwrt.org/releases/23.05.3/targets/ramips/mt76x8/openwrt-sdk-23.05.3-ramips-mt76x8_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
                ;;
            *)
                # 默认SDK
                echo "https://downloads.openwrt.org/releases/23.05.3/targets/$target/$subtarget/openwrt-sdk-23.05.3-$target-$subtarget_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
                ;;
        esac
    elif [ "$version" = "21.02" ]; then
        case "$target" in
            "ipq40xx")
                # 高通IPQ40xx平台SDK
                echo "https://downloads.openwrt.org/releases/21.02.7/targets/ipq40xx/generic/openwrt-sdk-21.02.7-ipq40xx-generic_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
                ;;
            "ramips")
                # 雷凌MT76xx平台SDK
                echo "https://downloads.openwrt.org/releases/21.02.7/targets/ramips/mt7621/openwrt-sdk-21.02.7-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
                ;;
            *)
                # 默认SDK
                echo "https://downloads.openwrt.org/releases/21.02.7/targets/$target/$subtarget/openwrt-sdk-21.02.7-$target-$subtarget_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
                ;;
        esac
    else
        # 默认使用21.02版本
        echo "https://downloads.openwrt.org/releases/21.02.7/targets/$target/$subtarget/openwrt-sdk-21.02.7-$target-$subtarget_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
    fi
    
    return 0
}

# 生成合并配置函数
generate_merged_config() {
    local device_name="$1"
    local config_mode="$2"
    local extra_packages="$3"
    local output_file="$4"
    
    echo "=== 生成合并配置 ==="
    echo "设备: $device_name"
    echo "配置模式: $config_mode"
    echo "额外包: $extra_packages"
    echo "输出文件: $output_file"
    
    # 获取设备配置
    local device_config=$(get_device_config "$device_name")
    if [ -z "$device_config" ]; then
        echo "❌ 错误: 设备 '$device_name' 未定义"
        return 1
    fi
    
    local target=$(echo "$device_config" | awk '{print $1}')
    local subtarget=$(echo "$device_config" | awk '{print $2}')
    local device=$(echo "$device_config" | awk '{print $3}')
    
    echo "目标平台: $target/$subtarget/$device"
    
    # 创建临时配置文件
    local temp_config=$(mktemp)
    
    # 1. 基础配置
    echo "# ===== 基础配置 =====" > "$temp_config"
    echo "CONFIG_TARGET_${target}=y" >> "$temp_config"
    echo "CONFIG_TARGET_${target}_${subtarget}=y" >> "$temp_config"
    echo "CONFIG_TARGET_${target}_${subtarget}_DEVICE_${device}=y" >> "$temp_config"
    
    # 2. 内核配置
    echo "" >> "$temp_config"
    echo "# ===== 内核配置 =====" >> "$temp_config"
    echo "CONFIG_KERNEL_BUILD_USER=\"OpenWrt Builder\"" >> "$temp_config"
    echo "CONFIG_KERNEL_BUILD_DOMAIN=\"openwrt.org\"" >> "$temp_config"
    
    # 3. 镜像配置
    echo "" >> "$temp_config"
    echo "# ===== 镜像配置 =====" >> "$temp_config"
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> "$temp_config"
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> "$temp_config"
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=256" >> "$temp_config"
    
    # 4. 基础包配置
    echo "" >> "$temp_config"
    echo "# ===== 基础包配置 =====" >> "$temp_config"
    echo "CONFIG_PACKAGE_block-mount=y" >> "$temp_config"
    echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> "$temp_config"
    echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> "$temp_config"
    echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> "$temp_config"
    echo "CONFIG_PACKAGE_kmod-usb-core=y" >> "$temp_config"
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> "$temp_config"
    echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> "$temp_config"
    echo "CONFIG_PACKAGE_kmod-usb-uhci=y" >> "$temp_config"
    echo "CONFIG_PACKAGE_kmod-usb2=y" >> "$temp_config"
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> "$temp_config"
    
    # 5. 根据配置模式添加额外配置
    if [ "$config_mode" = "normal" ]; then
        echo "" >> "$temp_config"
        echo "# ===== 正常模式配置 =====" >> "$temp_config"
        
        # USB 3.0 支持
        echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> "$temp_config"
        
        # 平台专用USB驱动
        if [ "$target" = "ipq40xx" ]; then
            echo "# 高通IPQ40xx平台专用USB驱动" >> "$temp_config"
            echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> "$temp_config"
            echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> "$temp_config"
            echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> "$temp_config"
        elif [ "$target" = "ramips" ] && { [ "$subtarget" = "mt76x8" ] || [ "$subtarget" = "mt7621" ]; }; then
            echo "# 雷凌MT76xx平台专用USB驱动" >> "$temp_config"
            echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> "$temp_config"
            echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> "$temp_config"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> "$temp_config"
        fi
        
        # SCSI支持
        echo "CONFIG_PACKAGE_kmod-scsi-core=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_kmod-scsi-generic=y" >> "$temp_config"
        
        # 网络加速
        echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_kmod-shortcut-fe=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_kmod-fast-classifier=y" >> "$temp_config"
        
        # 常用功能
        echo "CONFIG_PACKAGE_luci-app-upnp=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_samba4-server=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_luci-app-diskman=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_vlmcsd=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_smartdns=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_luci-app-accesscontrol=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_luci-app-wechatpush=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_sqm-scripts=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_vsftpd=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_luci-app-arpbind=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_luci-app-cpulimit=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_luci-app-hd-idle=y" >> "$temp_config"
        
        # LuCI主题和界面
        echo "CONFIG_PACKAGE_luci-theme-argon=y" >> "$temp_config"
        echo "CONFIG_PACKAGE_luci-app-statistics=y" >> "$temp_config"
        
    elif [ "$config_mode" = "base" ]; then
        echo "" >> "$temp_config"
        echo "# ===== 基础模式配置 =====" >> "$temp_config"
        echo "# 最小化配置，仅包含基本功能" >> "$temp_config"
    fi
    
    # 6. 处理额外包配置
    if [ -n "$extra_packages" ]; then
        echo "" >> "$temp_config"
        echo "# ===== 额外包配置 =====" >> "$temp_config"
        
        # 按分号分割额外包
        IFS=';' read -ra pkg_list <<< "$extra_packages"
        for pkg in "${pkg_list[@]}"; do
            pkg=$(echo "$pkg" | xargs)  # 去除空格
            
            if [[ "$pkg" == +* ]]; then
                # 启用包
                pkg_name="${pkg:1}"
                echo "CONFIG_PACKAGE_${pkg_name}=y" >> "$temp_config"
                echo "✅ 启用包: $pkg_name"
            elif [[ "$pkg" == -* ]]; then
                # 禁用包
                pkg_name="${pkg:1}"
                echo "# CONFIG_PACKAGE_${pkg_name} is not set" >> "$temp_config"
                echo "❌ 禁用包: $pkg_name"
            fi
        done
    fi
    
    # 7. 复制到输出文件
    cp "$temp_config" "$output_file"
    rm -f "$temp_config"
    
    echo "✅ 配置生成完成: $output_file"
    echo "📊 配置文件大小: $(ls -lh "$output_file" | awk '{print $5}')"
    echo "📝 配置文件行数: $(wc -l < "$output_file")"
    
    return 0
}

# 显示支持的设备列表
list_supported_devices() {
    echo "=== 支持的设备列表 ==="
    echo "设备名称       目标平台     子目标     设备型号"
    echo "------------------------------------------------"
    
    for device_name in "${!DEVICES[@]}"; do
        local config="${DEVICES[$device_name]}"
        local target=$(echo "$config" | awk '{print $1}')
        local subtarget=$(echo "$config" | awk '{print $2}')
        local device=$(echo "$config" | awk '{print $3}')
        
        printf "%-12s %-12s %-10s %s\n" "$device_name" "$target" "$subtarget" "$device"
    done
    
    echo ""
    echo "总计: ${#DEVICES[@]} 个设备"
}

# 如果直接运行此脚本，显示设备列表
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    list_supported_devices
fi
