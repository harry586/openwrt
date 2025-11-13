#!/bin/bash
# generate_config.sh - 动态生成 OpenWrt 配置

set -e

# 参数检查
if [ $# -lt 6 ]; then
    echo "用法: $0 <config_type> <platform> <device_short_name> <device_full_name> <extra_packages> <disable_packages> [build_dir]"
    exit 1
fi

CONFIG_TYPE=$1
PLATFORM=$2
DEVICE_SHORT_NAME=$3
DEVICE_FULL_NAME=$4
EXTRA_PACKAGES=$5
DISABLE_PACKAGES=$6
BUILD_DIR=${7:-/mnt/openwrt-build}

echo "=== 生成配置 ==="
echo "配置类型: $CONFIG_TYPE"
echo "平台: $PLATFORM"
echo "设备简称: $DEVICE_SHORT_NAME"
echo "完整设备名称: $DEVICE_FULL_NAME"
echo "额外包: $EXTRA_PACKAGES"
echo "禁用包: $DISABLE_PACKAGES"
echo "构建目录: $BUILD_DIR"

cd "$BUILD_DIR"

# 清理现有配置
if [ -f ".config" ]; then
    echo "备份现有配置..."
    cp .config .config.backup
fi

echo "创建基础配置..."

# 生成基础配置
echo "# 基础系统配置" > .config.base
echo "CONFIG_TARGET_${PLATFORM}=y" >> .config.base
echo "CONFIG_TARGET_${PLATFORM}_GENERIC=y" >> .config.base
echo "CONFIG_TARGET_DEVICE_${PLATFORM}_GENERIC_${DEVICE_FULL_NAME}=y" >> .config.base
echo "CONFIG_TARGET_PER_DEVICE_ROOTFS=y" >> .config.base
echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config.base

# 基础包
echo "" >> .config.base
echo "# 基础包" >> .config.base
echo "CONFIG_BUSYBOX_CUSTOM=y" >> .config.base
echo "CONFIG_PACKAGE_busybox=y" >> .config.base
echo "CONFIG_PACKAGE_base-files=y" >> .config.base
echo "CONFIG_PACKAGE_block-mount=y" >> .config.base
echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config.base
echo "CONFIG_PACKAGE_dropbear=y" >> .config.base
echo "CONFIG_PACKAGE_firewall=y" >> .config.base
echo "CONFIG_PACKAGE_fstools=y" >> .config.base
echo "CONFIG_PACKAGE_iptables=y" >> .config.base
echo "CONFIG_PACKAGE_iptables-mod-extra=y" >> .config.base
echo "CONFIG_PACKAGE_iptables-mod-filter=y" >> .config.base
echo "CONFIG_PACKAGE_iptables-mod-ipopt=y" >> .config.base
echo "CONFIG_PACKAGE_iptables-mod-conntrack-extra=y" >> .config.base
echo "CONFIG_PACKAGE_kmod-ipt-offload=y" >> .config.base
echo "CONFIG_PACKAGE_kmod-nf-conntrack=y" >> .config.base
echo "CONFIG_PACKAGE_kmod-nf-conntrack-netlink=y" >> .config.base
echo "CONFIG_PACKAGE_kmod-nf-ipt=y" >> .config.base
echo "CONFIG_PACKAGE_kmod-nf-nat=y" >> .config.base
echo "CONFIG_PACKAGE_kmod-nf-reject=y" >> .config.base
echo "CONFIG_PACKAGE_kmod-nfnetlink=y" >> .config.base
echo "CONFIG_PACKAGE_libc=y" >> .config.base
echo "CONFIG_PACKAGE_libgcc=y" >> .config.base
echo "CONFIG_PACKAGE_logd=y" >> .config.base
echo "CONFIG_PACKAGE_mtd=y" >> .config.base
echo "CONFIG_PACKAGE_netifd=y" >> .config.base
echo "CONFIG_PACKAGE_opkg=y" >> .config.base
echo "CONFIG_PACKAGE_procd=y" >> .config.base
echo "CONFIG_PACKAGE_swconfig=y" >> .config.base
echo "CONFIG_PACKAGE_uci=y" >> .config.base
echo "CONFIG_PACKAGE_urandom-seed=y" >> .config.base
echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y" >> .config.base

# 根据配置类型添加特定包
case "$CONFIG_TYPE" in
    "minimal")
        echo "# 最小配置 - 仅基础系统" >> .config.base
        ;;
    "normal")
        echo "" >> .config.base
        echo "# 正常配置 - 添加Web界面和常用功能" >> .config.base
        echo "CONFIG_PACKAGE_luci=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-base=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-compat=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-mod-admin-full=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-app-firewall=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-proto-ppp=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-proto-ipv6=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-theme-bootstrap=y" >> .config.base
        echo "CONFIG_PACKAGE_ip6tables=y" >> .config.base
        echo "CONFIG_PACKAGE_ip6tables-extra=y" >> .config.base
        echo "CONFIG_PACKAGE_ip6tables-mod-nat=y" >> .config.base
        echo "CONFIG_PACKAGE_kmod-ip6tables=y" >> .config.base
        echo "CONFIG_PACKAGE_kmod-ip6tables-extra=y" >> .config.base
        echo "CONFIG_PACKAGE_kmod-ipt-nat6=y" >> .config.base
        echo "CONFIG_PACKAGE_ppp=y" >> .config.base
        echo "CONFIG_PACKAGE_ppp-mod-pppoe=y" >> .config.base
        echo "CONFIG_PACKAGE_6in4=y" >> .config.base
        echo "CONFIG_PACKAGE_6rd=y" >> .config.base
        echo "CONFIG_PACKAGE_6to4=y" >> .config.base
        ;;
    "custom")
        echo "" >> .config.base
        echo "# 自定义配置 - 基础Web界面" >> .config.base
        echo "CONFIG_PACKAGE_luci=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-base=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-compat=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-mod-admin-full=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-app-firewall=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-proto-ppp=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-proto-ipv6=y" >> .config.base
        echo "CONFIG_PACKAGE_luci-theme-bootstrap=y" >> .config.base
        echo "CONFIG_PACKAGE_ip6tables=y" >> .config.base
        echo "CONFIG_PACKAGE_ip6tables-extra=y" >> .config.base
        echo "CONFIG_PACKAGE_ip6tables-mod-nat=y" >> .config.base
        echo "CONFIG_PACKAGE_kmod-ip6tables=y" >> .config.base
        echo "CONFIG_PACKAGE_kmod-ip6tables-extra=y" >> .config.base
        echo "CONFIG_PACKAGE_kmod-ipt-nat6=y" >> .config.base
        echo "CONFIG_PACKAGE_ppp=y" >> .config.base
        echo "CONFIG_PACKAGE_ppp-mod-pppoe=y" >> .config.base
        ;;
    *)
        echo "未知配置类型: $CONFIG_TYPE"
        exit 1
        ;;
esac

# 对于自定义配置，处理额外的包管理
if [ "$CONFIG_TYPE" = "custom" ]; then
    echo "" >> .config.base
    echo "# 自定义包配置" >> .config.base
    echo "处理自定义包配置..."
    
    # 启用额外包
    if [ -n "$EXTRA_PACKAGES" ]; then
        echo "启用额外包: $EXTRA_PACKAGES"
        for pkg in $EXTRA_PACKAGES; do
            # 清理包名，移除可能的空格
            clean_pkg=$(echo "$pkg" | tr -d '[:space:]')
            if [ -n "$clean_pkg" ]; then
                echo "CONFIG_PACKAGE_${clean_pkg}=y" >> .config.base
            fi
        done
    fi
    
    # 禁用包
    if [ -n "$DISABLE_PACKAGES" ]; then
        echo "禁用包: $DISABLE_PACKAGES"
        for pkg in $DISABLE_PACKAGES; do
            # 清理包名，移除可能的空格
            clean_pkg=$(echo "$pkg" | tr -d '[:space:]')
            if [ -n "$clean_pkg" ]; then
                echo "# CONFIG_PACKAGE_${clean_pkg} is not set" >> .config.base
            fi
        done
    fi
fi

# 应用基础配置
mv .config.base .config

echo "=== 生成的配置摘要 ==="
echo "目标平台和设备:"
grep "CONFIG_TARGET" .config | head -10
echo ""
echo "启用的主要包:"
grep "^CONFIG_PACKAGE.*=y" .config | head -20

echo "✅ 配置生成完成"
