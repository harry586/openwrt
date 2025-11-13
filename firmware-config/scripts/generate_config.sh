#!/bin/bash

# 生成 OpenWrt 配置脚本
# 参数: config_type platform device_short_name device_full_name extra_packages disable_packages build_dir

CONFIG_TYPE=$1
PLATFORM=$2
DEVICE_SHORT_NAME=$3
DEVICE_FULL_NAME=$4
EXTRA_PACKAGES=$5
DISABLE_PACKAGES=$6
BUILD_DIR=$7

cd $BUILD_DIR

echo "生成配置信息:"
echo "  类型: $CONFIG_TYPE"
echo "  平台: $PLATFORM"
echo "  设备简称: $DEVICE_SHORT_NAME"
echo "  完整设备名称: $DEVICE_FULL_NAME"
echo "  额外安装插件: $EXTRA_PACKAGES"
echo "  禁用插件: $DISABLE_PACKAGES"

# 完全清理配置
rm -f .config

# 创建基础配置
echo "创建基础配置..."
cat > .config << EOF
CONFIG_TARGET_ipq40xx=y
CONFIG_TARGET_ipq40xx_generic=y
CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y
CONFIG_TARGET_PER_DEVICE_ROOTFS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_VMLINUX_INITRD=y
CONFIG_VMLINUX_KERNEL_IMAGE=y
EOF

# 根据配置类型添加包
case $CONFIG_TYPE in
    "minimal")
        echo "添加最小化配置包..."
        cat >> .config << 'EOF'
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_firewall=y
CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_kmod-ipt-offload=y
EOF
        ;;
        
    "normal"|"custom")
        echo "添加标准配置包..."
        cat >> .config << 'EOF'
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-proto-ppp=y
CONFIG_PACKAGE_luci-proto-ipv6=y
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_firewall=y
CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_ip6tables=y
CONFIG_PACKAGE_ppp=y
CONFIG_PACKAGE_ppp-mod-pppoe=y
CONFIG_PACKAGE_kmod-ipt-offload=y
EOF
        ;;
esac

# 只有在custom类型时才处理额外插件
if [ "$CONFIG_TYPE" = "custom" ]; then
    if [ ! -z "$EXTRA_PACKAGES" ]; then
        echo "启用额外插件: $EXTRA_PACKAGES"
        for pkg in $EXTRA_PACKAGES; do
            echo "CONFIG_PACKAGE_${pkg}=y" >> .config
        done
    fi

    if [ ! -z "$DISABLE_PACKAGES" ]; then
        echo "禁用插件: $DISABLE_PACKAGES"
        for pkg in $DISABLE_PACKAGES; do
            echo "CONFIG_PACKAGE_${pkg}=n" >> .config
            sed -i "/CONFIG_PACKAGE_${pkg}=y/d" .config 2>/dev/null || true
        done
    fi
else
    if [ ! -z "$EXTRA_PACKAGES" ] || [ ! -z "$DISABLE_PACKAGES" ]; then
        echo "警告: 插件管理仅在 custom 配置类型下可用"
    fi
fi

echo "配置生成完成"
echo "=== 配置验证 ==="

# 验证关键配置
echo "关键配置检查:"
if grep -q "CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y" .config; then
    echo "✅ 设备配置正确"
else
    echo "❌ 设备配置错误"
    exit 1
fi

if grep -q "CONFIG_TARGET_ipq40xx=y" .config; then
    echo "✅ 平台配置正确"
else
    echo "❌ 平台配置错误"
    exit 1
fi

# 保存配置摘要
echo "=== 配置摘要 ===" > config_summary.log
echo "设备简称: $DEVICE_SHORT_NAME" >> config_summary.log
echo "完整设备名称: $DEVICE_FULL_NAME" >> config_summary.log
echo "平台: $PLATFORM" >> config_summary.log
echo "配置类型: $CONFIG_TYPE" >> config_summary.log
echo "" >> config_summary.log
echo "目标配置:" >> config_summary.log
grep "CONFIG_TARGET" .config >> config_summary.log
echo "" >> config_summary.log
echo "启用的包:" >> config_summary.log
grep "^CONFIG_PACKAGE.*=y" .config 2>/dev/null >> config_summary.log || echo "无启用的包" >> config_summary.log

echo "配置脚本执行完成"
