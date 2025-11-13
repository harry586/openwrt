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
echo "清理现有配置..."
rm -f .config

# 根据配置类型设置基础配置
case $CONFIG_TYPE in
    "minimal")
        echo "创建最小化配置..."
        # 使用多个echo命令代替heredoc
        echo "CONFIG_TARGET_ipq40xx=y" > .config
        echo "CONFIG_TARGET_ipq40xx_generic=y" >> .config
        echo "CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y" >> .config
        echo "CONFIG_PACKAGE_luci=y" >> .config
        echo "CONFIG_PACKAGE_luci-base=y" >> .config
        echo "CONFIG_BUSYBOX_CONFIG_FEATURE_MOUNT_NFS=n" >> .config
        echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
        echo "CONFIG_PACKAGE_firewall=y" >> .config
        echo "CONFIG_PACKAGE_iptables=y" >> .config
        ;;
        
    "normal")
        echo "创建正常配置..."
        echo "CONFIG_TARGET_ipq40xx=y" > .config
        echo "CONFIG_TARGET_ipq40xx_generic=y" >> .config
        echo "CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y" >> .config
        echo "CONFIG_PACKAGE_luci=y" >> .config
        echo "CONFIG_PACKAGE_luci-base=y" >> .config
        echo "CONFIG_PACKAGE_luci-proto-ppp=y" >> .config
        echo "CONFIG_PACKAGE_luci-proto-ipv6=y" >> .config
        echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
        echo "CONFIG_PACKAGE_firewall=y" >> .config
        echo "CONFIG_PACKAGE_iptables=y" >> .config
        echo "CONFIG_PACKAGE_ip6tables=y" >> .config
        echo "CONFIG_PACKAGE_ppp=y" >> .config
        echo "CONFIG_PACKAGE_ppp-mod-pppoe=y" >> .config
        echo "CONFIG_PACKAGE_kmod-ipt-offload=y" >> .config
        ;;
        
    "custom")
        echo "基于正常模板创建自定义配置..."
        echo "CONFIG_TARGET_ipq40xx=y" > .config
        echo "CONFIG_TARGET_ipq40xx_generic=y" >> .config
        echo "CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y" >> .config
        echo "CONFIG_PACKAGE_luci=y" >> .config
        echo "CONFIG_PACKAGE_luci-base=y" >> .config
        echo "CONFIG_PACKAGE_luci-proto-ppp=y" >> .config
        echo "CONFIG_PACKAGE_luci-proto-ipv6=y" >> .config
        echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
        echo "CONFIG_PACKAGE_firewall=y" >> .config
        echo "CONFIG_PACKAGE_iptables=y" >> .config
        echo "CONFIG_PACKAGE_ip6tables=y" >> .config
        echo "CONFIG_PACKAGE_ppp=y" >> .config
        echo "CONFIG_PACKAGE_ppp-mod-pppoe=y" >> .config
        echo "CONFIG_PACKAGE_kmod-ipt-offload=y" >> .config
        
        # 显示可用包列表
        echo "=== 常用可用插件列表 ==="
        echo "网络服务: adblock wireguard openvpn-openssl ddns-scripts"
        echo "文件共享: vsftpd samba4-server"
        echo "系统工具: htop tmux screen"
        echo "网络工具: iperf3 tcpdump nmap"
        echo "其他: unattended-upgrades usbutils"
        echo ""
        
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

# 验证设备配置
echo "=== 初始配置验证 ==="
if grep -q "CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y" .config; then
    echo "✅ 设备配置正确设置: $DEVICE_FULL_NAME"
else
    echo "❌ 设备配置设置失败"
    echo "当前配置中的设备设置:"
    grep "CONFIG_TARGET_DEVICE" .config || echo "未找到设备配置"
    echo "尝试修复设备配置..."
    echo "CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y" >> .config
    if grep -q "CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}=y" .config; then
        echo "✅ 设备配置修复成功"
    else
        echo "❌ 设备配置修复失败"
        exit 1
    fi
fi

# 显示配置摘要
echo ""
echo "=== 配置摘要 ==="
echo "目标平台和设备:"
grep "CONFIG_TARGET" .config | head -10

echo ""
echo "启用的包:"
grep "^CONFIG_PACKAGE.*=y" .config | head -20 2>/dev/null || echo "无启用的包"

echo ""
echo "禁用的包:"
grep "^CONFIG_PACKAGE.*=n" .config | head -10 2>/dev/null || echo "无禁用的包"

# 统计包数量
PACKAGE_COUNT=$(grep "^CONFIG_PACKAGE.*=y" .config 2>/dev/null | wc -l || echo "0")
echo ""
echo "已启用包数量: $PACKAGE_COUNT"

# 保存配置摘要到日志文件
echo "=== 配置摘要 ===" > config_summary.log
echo "生成时间: $(date)" >> config_summary.log
echo "设备简称: $DEVICE_SHORT_NAME" >> config_summary.log
echo "完整设备名称: $DEVICE_FULL_NAME" >> config_summary.log
echo "平台: $PLATFORM" >> config_summary.log
echo "配置类型: $CONFIG_TYPE" >> config_summary.log
echo "额外安装插件: $EXTRA_PACKAGES" >> config_summary.log
echo "禁用插件: $DISABLE_PACKAGES" >> config_summary.log
echo "" >> config_summary.log
echo "目标配置:" >> config_summary.log
grep "CONFIG_TARGET" .config >> config_summary.log
echo "" >> config_summary.log
echo "启用的包 ($PACKAGE_COUNT 个):" >> config_summary.log
grep "^CONFIG_PACKAGE.*=y" .config 2>/dev/null >> config_summary.log || echo "无启用的包" >> config_summary.log
echo "" >> config_summary.log
echo "禁用的包:" >> config_summary.log
grep "^CONFIG_PACKAGE.*=n" .config 2>/dev/null >> config_summary.log || echo "无禁用的包" >> config_summary.log

# 验证配置文件的完整性
echo ""
echo "=== 配置文件验证 ==="
if [ -s .config ]; then
    echo "✅ 配置文件非空"
    CONFIG_SIZE=$(wc -l < .config)
    echo "配置文件行数: $CONFIG_SIZE"
else
    echo "❌ 配置文件为空或不存在"
    exit 1
fi

# 检查关键配置是否存在
echo ""
echo "=== 关键配置检查 ==="
CRITICAL_CONFIGS=(
    "CONFIG_TARGET_ipq40xx"
    "CONFIG_TARGET_ipq40xx_generic"
    "CONFIG_TARGET_DEVICE_ipq40xx_generic_${DEVICE_FULL_NAME}"
)

ALL_CRITICAL_OK=true
for config in "${CRITICAL_CONFIGS[@]}"; do
    if grep -q "$config=y" .config; then
        echo "✅ $config"
    else
        echo "❌ $config (缺失)"
        ALL_CRITICAL_OK=false
    fi
done

if $ALL_CRITICAL_OK; then
    echo "✅ 所有关键配置都存在"
else
    echo "❌ 部分关键配置缺失"
    exit 1
fi

echo ""
echo "配置脚本执行完成 ✅"
echo "配置已保存到: $BUILD_DIR/.config"
echo "配置摘要已保存到: $BUILD_DIR/config_summary.log"
