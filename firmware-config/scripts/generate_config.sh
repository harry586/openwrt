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

# 清理现有配置
rm -f .config

# 根据配置类型设置基础配置
case $CONFIG_TYPE in
    "minimal")
        # 最小化配置
        echo "创建最小化配置..."
        cat > .config << EOF
CONFIG_TARGET_ipq40xx=y
CONFIG_TARGET_ipq40xx_generic=y
CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_BUSYBOX_CONFIG_FEATURE_MOUNT_NFS=n
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_firewall=y
CONFIG_PACKAGE_iptables=y
EOF
        ;;
        
    "normal")
        # 正常配置
        echo "创建正常配置..."
        cat > .config << EOF
CONFIG_TARGET_ipq40xx=y
CONFIG_TARGET_ipq40xx_generic=y
CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y
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
        
    "custom")
        # 自定义配置 - 基于normal配置
        echo "基于正常模板创建自定义配置..."
        cat > .config << EOF
CONFIG_TARGET_ipq40xx=y
CONFIG_TARGET_ipq40xx_generic=y
CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y
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
        
        # 只有在custom类型时才处理插件
        if [ ! -z "$EXTRA_PACKAGES" ]; then
            echo "启用额外插件: $EXTRA_PACKAGES"
            for pkg in $EXTRA_PACKAGES; do
                echo "CONFIG_PACKAGE_${pkg}=y" >> .config
                echo "已启用: $pkg"
            done
        fi

        if [ ! -z "$DISABLE_PACKAGES" ]; then
            echo "禁用插件: $DISABLE_PACKAGES"
            for pkg in $DISABLE_PACKAGES; do
                echo "CONFIG_PACKAGE_${pkg}=n" >> .config
                # 同时从配置中删除已启用的设置
                sed -i "/CONFIG_PACKAGE_${pkg}=y/d" .config 2>/dev/null || true
                echo "已禁用: $pkg"
            done
        fi
        ;;
    *)
        echo "错误: 未知的配置类型: $CONFIG_TYPE"
        exit 1
        ;;
esac

echo "配置生成完成"
echo "=== 初始配置验证 ==="
if grep -q "CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y" .config; then
    echo "✅ 设备配置正确设置: $DEVICE_FULL_NAME"
else
    echo "❌ 设备配置设置失败"
    echo "当前配置中的设备设置:"
    grep "CONFIG_TARGET_DEVICE" .config || echo "未找到设备配置"
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
