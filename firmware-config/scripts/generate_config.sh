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
echo "设备: $DEVICE_FULL_NAME"

# 创建基础配置
echo "CONFIG_TARGET_${PLATFORM}=y" > .config
echo "CONFIG_TARGET_${PLATFORM}_GENERIC=y" >> .config
echo "CONFIG_TARGET_DEVICE_${PLATFORM}_GENERIC_${DEVICE_FULL_NAME}=y" >> .config
echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config

# 基础包
echo "CONFIG_PACKAGE_luci=y" >> .config
echo "CONFIG_PACKAGE_luci-base=y" >> .config
echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
echo "CONFIG_PACKAGE_firewall=y" >> .config
echo "CONFIG_PACKAGE_iptables=y" >> .config

# 根据配置类型添加包
case "$CONFIG_TYPE" in
    "normal"|"custom")
        echo "CONFIG_PACKAGE_luci-proto-ppp=y" >> .config
        echo "CONFIG_PACKAGE_luci-proto-ipv6=y" >> .config
        echo "CONFIG_PACKAGE_ppp=y" >> .config
        echo "CONFIG_PACKAGE_ppp-mod-pppoe=y" >> .config
        ;;
esac

# 自定义配置的包管理
if [ "$CONFIG_TYPE" = "custom" ]; then
    if [ -n "$EXTRA_PACKAGES" ]; then
        for pkg in $EXTRA_PACKAGES; do
            echo "CONFIG_PACKAGE_${pkg}=y" >> .config
        done
    fi
    
    if [ -n "$DISABLE_PACKAGES" ]; then
        for pkg in $DISABLE_PACKAGES; do
            echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
        done
    fi
fi

echo "✅ 配置生成完成"
