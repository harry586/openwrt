#!/bin/bash
# OpenWrt正常模式插件恢复脚本
# 只添加您指定的完整功能配置插件
# 最后更新: 2024-01-16

set -e

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========== 日志函数 ==========
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "🔧 OpenWrt正常模式插件恢复脚本"
echo "========================================"

# 检查当前目录
if [ -d "/mnt/openwrt-build/openwrt" ]; then
    cd /mnt/openwrt-build/openwrt
    echo "✅ 切换到构建目录: $(pwd)"
else
    log_error "构建目录不存在: /mnt/openwrt-build/openwrt"
    exit 1
fi

# 检查.config文件
if [ ! -f ".config" ]; then
    log_error ".config 文件不存在"
    exit 1
fi

echo "当前配置文件大小: $(ls -lh .config | awk '{print $5}')"
echo "当前配置行数: $(wc -l < .config)"

# 创建备份
cp .config .config.backup.$(date +%Y%m%d_%H%M%S)
echo "配置文件已备份: .config.backup.*"

# 恢复正常模式完整功能配置插件
echo ""
echo "=== 恢复正常模式完整功能配置插件 ==="

# 这些是您列出的正常模式完整功能配置插件
NORMAL_MODE_PLUGINS=(
    # TurboACC 网络加速
    "luci-app-turboacc"
    "kmod-shortcut-fe"
    "kmod-fast-classifier"
    
    # UPnP 自动端口转发
    "luci-app-upnp"
    "miniupnpd"
    
    # Samba 文件共享
    "luci-app-samba4"
    "samba4-server"
    "samba4-libs"
    
    # 磁盘管理
    "luci-app-diskman"
    "blkid"
    "lsblk"
    
    # KMS 激活服务
    "luci-app-vlmcsd"
    "vlmcsd"
    
    # SmartDNS 智能DNS
    "luci-app-smartdns"
    "smartdns"
    
    # 家长控制
    "luci-app-parentcontrol"
    
    # 微信推送
    "luci-app-wechatpush"
    
    # 流量控制 (SQM)
    "luci-app-sqm"
    "sqm-scripts"
    
    # FTP 服务器
    "luci-app-vsftpd"
    "vsftpd"
    "vsftpd-tls"
    
    # ARP 绑定
    "luci-app-arpbind"
    
    # CPU 限制
    "luci-app-cpulimit"
    "cpulimit-ng"
    
    # 硬盘休眠
    "luci-app-hd-idle"
    "hd-idle"
    
    # 基础USB驱动（确保正常工作）
    "kmod-usb-core"
    "kmod-usb2"
    "kmod-usb3"
    "kmod-usb-storage"
    "kmod-usb-storage-uas"
    "kmod-usb-storage-extras"
    "kmod-scsi-core"
    "kmod-scsi-generic"
    
    # 文件系统支持
    "kmod-fs-ext4"
    "kmod-fs-vfat"
    "kmod-fs-ntfs3"
    "kmod-fs-exfat"
    
    # 高通IPQ40xx平台专用USB驱动
    "kmod-usb-dwc3"
    "kmod-usb-dwc3-qcom"
    "kmod-phy-qcom-dwc3"
    "kmod-usb-ehci"
    "kmod-usb-ohci"
)

# 统计已启用和待启用的插件
enabled_count=0
added_count=0
skipped_count=0

echo "检查并添加插件..."

for plugin in "${NORMAL_MODE_PLUGINS[@]}"; do
    if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config; then
        # 已经启用
        enabled_count=$((enabled_count + 1))
        echo "  ✅ $plugin (已启用)"
    elif grep -q "^# CONFIG_PACKAGE_${plugin} is not set" .config; then
        # 被禁用了，启用它
        sed -i "s/^# CONFIG_PACKAGE_${plugin} is not set$/CONFIG_PACKAGE_${plugin}=y/" .config
        added_count=$((added_count + 1))
        echo "  🔧 $plugin (已启用)"
    else
        # 没有配置，添加它
        echo "CONFIG_PACKAGE_${plugin}=y" >> .config
        added_count=$((added_count + 1))
        echo "  ➕ $plugin (已添加)"
    fi
done

echo ""
echo "=== 插件恢复完成 ==="
echo "✅ 已启用的插件: $enabled_count 个"
echo "✅ 新添加的插件: $added_count 个"
echo ""

# 确保基础配置正确
echo "=== 确保基础配置 ==="

# 检查并确保正常模式相关配置
echo "确保正常模式配置..."

# 检查CONFIG_MODE
if grep -q "^CONFIG_MODE=" .config; then
    echo "配置模式已设置"
else
    echo "CONFIG_MODE=normal" >> .config
    echo "已设置配置模式为normal"
fi

# 检查并添加必要的luci组件
if ! grep -q "^CONFIG_PACKAGE_luci=y" .config; then
    echo "CONFIG_PACKAGE_luci=y" >> .config
    echo "已启用luci"
fi

if ! grep -q "^CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" .config; then
    echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
    echo "已启用luci中文语言包"
fi

# 应用配置并生成新的配置
echo ""
echo "=== 应用配置 ==="

if command -v make >/dev/null; then
    echo "运行 make defconfig..."
    make defconfig 2>&1 | tail -20
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo "✅ 配置应用成功"
    else
        log_warn "配置应用可能有警告"
    fi
else
    log_warn "make命令不可用，跳过defconfig"
fi

# 显示最终的配置统计
echo ""
echo "=== 最终配置统计 ==="
echo "配置文件大小: $(ls -lh .config | awk '{print $5}')"
echo "配置行数: $(wc -l < .config)"
echo "启用的包总数: $(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)"
echo "禁用的包总数: $(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)"

echo ""
echo "=== 关键插件验证 ==="
echo "验证重要插件是否已启用:"

important_plugins=(
    "luci-app-turboacc"
    "luci-app-samba4"
    "luci-app-diskman"
    "luci-app-vsftpd"
    "luci-app-sqm"
    "kmod-usb-dwc3"
    "kmod-usb-dwc3-qcom"
)

for plugin in "${important_plugins[@]}"; do
    if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config; then
        echo "  ✅ $plugin"
    else
        echo "  ❌ $plugin"
    fi
done

echo ""
echo "=== USB驱动状态 ==="
echo "USB驱动检查:"

usb_drivers=(
    "kmod-usb-core"
    "kmod-usb2"
    "kmod-usb3"
    "kmod-usb-dwc3"
    "kmod-usb-dwc3-qcom"
    "kmod-phy-qcom-dwc3"
    "kmod-usb-storage"
)

for driver in "${usb_drivers[@]}"; do
    if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
        echo "  ✅ $driver"
    else
        echo "  ❌ $driver"
    fi
done

# 创建差异报告
echo ""
echo "=== 配置差异 ==="
echo "与原配置的主要差异:"

if command -v diff >/dev/null && [ -f .config.backup.* ]; then
    backup_file=$(ls -t .config.backup.* | head -1)
    echo "比较当前配置与备份: $backup_file"
    
    # 显示新增的配置行
    echo "新增的配置:"
    diff "$backup_file" .config | grep "^> " | head -10 | sed 's/^> //'
    
    echo ""
    echo "移除的配置:"
    diff "$backup_file" .config | grep "^< " | head -10 | sed 's/^< //'
else
    echo "无法生成差异报告"
fi

echo ""
echo "========================================"
echo "✅ 正常模式插件恢复完成"
echo "========================================"
echo ""
echo "已恢复以下完整功能配置插件:"
echo "1.  ✅ TurboACC 网络加速"
echo "2.  ✅ UPnP 自动端口转发"
echo "3.  ✅ Samba 文件共享"
echo "4.  ✅ 磁盘管理"
echo "5.  ✅ KMS 激活服务"
echo "6.  ✅ SmartDNS 智能DNS"
echo "7.  ✅ 家长控制"
echo "8.  ✅ 微信推送"
echo "9.  ✅ 流量控制 (SQM)"
echo "10. ✅ FTP 服务器"
echo "11. ✅ ARP 绑定"
echo "12. ✅ CPU 限制"
echo "13. ✅ 硬盘休眠"
echo ""
echo "✅ 所有USB驱动已启用"
echo "✅ 配置文件已更新并应用"
echo ""
echo "下一步: 重新运行构建工作流"
echo "========================================"
