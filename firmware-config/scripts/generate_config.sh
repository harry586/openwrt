#!/bin/bash
set -e

CONFIG_TYPE=$1
PLATFORM=$2
DEVICE_SHORT_NAME=$3
DEVICE_FULL_NAME=$4
EXTRA_PACKAGES=$5
DISABLE_PACKAGES=$6
BUILD_DIR=${7:-/mnt/openwrt-build}

cd "$BUILD_DIR"

echo "=== 生成配置 ==="
echo "配置类型: $CONFIG_TYPE"
echo "平台: $PLATFORM"
echo "设备: $DEVICE_FULL_NAME"

# 创建基础配置
rm -f .config
echo "# 目标平台配置" > .config
echo "CONFIG_TARGET_${PLATFORM}=y" >> .config
echo "CONFIG_TARGET_${PLATFORM}_GENERIC=y" >> .config
echo "CONFIG_TARGET_DEVICE_${PLATFORM}_GENERIC_${DEVICE_FULL_NAME}=y" >> .config
echo "CONFIG_TARGET_PER_DEVICE_ROOTFS=y" >> .config
echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config

# 基础包配置
echo "" >> .config
echo "# 基础包" >> .config
echo "CONFIG_PACKAGE_luci=y" >> .config
echo "CONFIG_PACKAGE_luci-base=y" >> .config
echo "CONFIG_PACKAGE_luci-compat=y" >> .config
echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
echo "CONFIG_PACKAGE_firewall=y" >> .config
echo "CONFIG_PACKAGE_iptables=y" >> .config
echo "CONFIG_PACKAGE_kmod-ipt-offload=y" >> .config
echo "CONFIG_PACKAGE_opkg=y" >> .config
echo "CONFIG_PACKAGE_procd=y" >> .config
echo "CONFIG_PACKAGE_uci=y" >> .config
echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y" >> .config

# 根据配置类型添加包
case "$CONFIG_TYPE" in
    "normal"|"custom")
        echo "" >> .config
        echo "# 网络功能包" >> .config
        echo "CONFIG_PACKAGE_luci-proto-ppp=y" >> .config
        echo "CONFIG_PACKAGE_luci-proto-ipv6=y" >> .config
        echo "CONFIG_PACKAGE_ip6tables=y" >> .config
        echo "CONFIG_PACKAGE_ppp=y" >> .config
        echo "CONFIG_PACKAGE_ppp-mod-pppoe=y" >> .config
        ;;
esac

# 设备特定包
echo "" >> .config
echo "# 设备特定包" >> .config
case "$DEVICE_FULL_NAME" in
    "asus_rt-ac42u")
        echo "CONFIG_PACKAGE_ath10k-firmware-qca9984-ct=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-ledtrig-usbport=y" >> .config
        ;;
esac

# 自定义配置的包管理
if [ "$CONFIG_TYPE" = "custom" ]; then
    echo "" >> .config
    echo "# 自定义包" >> .config
    
    if [ -n "$EXTRA_PACKAGES" ]; then
        for pkg in $EXTRA_PACKAGES; do
            clean_pkg=$(echo "$pkg" | tr -d '[:space:]')
            if [ -n "$clean_pkg" ]; then
                echo "CONFIG_PACKAGE_${clean_pkg}=y" >> .config
            fi
        done
    fi
    
    if [ -n "$DISABLE_PACKAGES" ]; then
        for pkg in $DISABLE_PACKAGES; do
            clean_pkg=$(echo "$pkg" | tr -d '[:space:]')
            if [ -n "$clean_pkg" ]; then
                echo "# CONFIG_PACKAGE_${clean_pkg} is not set" >> .config
            fi
        done
    fi
fi

echo "✅ 配置生成完成"
echo "配置摘要:"
grep "CONFIG_TARGET" .config
echo "启用的包:"
grep "^CONFIG_PACKAGE" .config | head -15
