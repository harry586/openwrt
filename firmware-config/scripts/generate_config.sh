#!/bin/bash

# 生成 OpenWrt 配置脚本
# 参数: config_type platform device_name extra_packages disable_packages build_dir

CONFIG_TYPE=$1
PLATFORM=$2
DEVICE_NAME=$3
EXTRA_PACKAGES=$4
DISABLE_PACKAGES=$5
BUILD_DIR=$6

cd $BUILD_DIR

echo "生成配置信息:"
echo "  类型: $CONFIG_TYPE"
echo "  平台: $PLATFORM"
echo "  设备: $DEVICE_NAME"
echo "  额外安装插件: $EXTRA_PACKAGES"
echo "  禁用插件: $DISABLE_PACKAGES"

# 清理现有配置
rm -f .config

# 根据配置类型设置基础配置
case $CONFIG_TYPE in
    "minimal")
        # 最小化配置
        echo "创建最小化配置..."
        cat > .config.minimal << EOF
CONFIG_TARGET_${PLATFORM}=y
CONFIG_TARGET_${PLATFORM}_DEVICE_${DEVICE_NAME}=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_BUSYBOX_CONFIG_FEATURE_MOUNT_NFS=n
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_firewall=y
CONFIG_PACKAGE_iptables=y
EOF
        cat .config.minimal > .config
        ;;
        
    "normal")
        # 正常配置
        echo "创建正常配置..."
        cat > .config.normal << EOF
CONFIG_TARGET_${PLATFORM}=y
CONFIG_TARGET_${PLATFORM}_DEVICE_${DEVICE_NAME}=y
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
        cat .config.normal > .config
        ;;
        
    "custom")
        # 自定义配置 - 基于normal配置
        echo "基于正常模板创建自定义配置..."
        cat > .config.normal << EOF
CONFIG_TARGET_${PLATFORM}=y
CONFIG_TARGET_${PLATFORM}_DEVICE_${DEVICE_NAME}=y
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
        cat .config.normal > .config
        
        # 显示可用包列表（示例）
        echo "=== 常用可用插件列表 ==="
        echo "网络服务: adblock wireguard openvpn-openssl ddns-scripts"
        echo "文件共享: vsftpd samba4-server"
        echo "系统工具: htop tmux screen"
        echo "网络工具: iperf3 tcpdump nmap"
        echo "其他: unattended-upgrades usbutils"
        echo ""
        ;;
esac

# 只有在custom类型时才处理插件
if [ "$CONFIG_TYPE" = "custom" ]; then
    # 添加额外包
    if [ ! -z "$EXTRA_PACKAGES" ]; then
        echo "启用额外插件: $EXTRA_PACKAGES"
        for pkg in $EXTRA_PACKAGES; do
            echo "CONFIG_PACKAGE_${pkg}=y" >> .config
        done
    fi

    # 禁用包
    if [ ! -z "$DISABLE_PACKAGES" ]; then
        echo "禁用插件: $DISABLE_PACKAGES"
        for pkg in $DISABLE_PACKAGES; do
            echo "CONFIG_PACKAGE_${pkg}=n" >> .config
            # 同时从配置中删除已启用的设置
            sed -i "/CONFIG_PACKAGE_${pkg}=y/d" .config 2>/dev/null || true
        done
    fi
else
    if [ ! -z "$EXTRA_PACKAGES" ] || [ ! -z "$DISABLE_PACKAGES" ]; then
        echo "警告: 插件管理仅在 custom 配置类型下可用"
        echo "忽略 $CONFIG_TYPE 类型的插件设置"
    fi
fi

echo "最终配置生成完成"
echo "=== 配置摘要 ==="
echo "已启用的插件:"
grep "^CONFIG_PACKAGE.*=y" .config | head -20 2>/dev/null || echo "无启用的插件"
echo ""
echo "已禁用的插件:"
grep "^CONFIG_PACKAGE.*=n" .config | head -10 2>/dev/null || echo "无禁用的插件"

# 保存配置摘要
echo "=== 配置摘要 ===" > config_summary.log
echo "设备: $DEVICE_NAME" >> config_summary.log
echo "平台: $PLATFORM" >> config_summary.log
echo "配置类型: $CONFIG_TYPE" >> config_summary.log
echo "" >> config_summary.log
echo "启用的包:" >> config_summary.log
grep "^CONFIG_PACKAGE.*=y" .config 2>/dev/null >> config_summary.log || echo "无启用的包" >> config_summary.log
echo "" >> config_summary.log
echo "禁用的包:" >> config_summary.log
grep "^CONFIG_PACKAGE.*=n" .config 2>/dev/null >> config_summary.log || echo "无禁用的包" >> config_summary.log

echo "配置脚本执行完成"
