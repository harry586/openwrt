#!/bin/bash
# diagnose-packages.sh - 诊断包可用性

set -e

BUILD_DIR="${1:-.}"
cd "$BUILD_DIR"

echo "=== 包可用性诊断 ==="

# 更新feeds
echo "更新feeds..."
./scripts/feeds update -a > /dev/null 2>&1

# 检查特定类别的包
echo ""
echo "=== 检查内核模块 ==="
./scripts/feeds list | grep -E "^(kmod-|usb|fs-)" | sort

echo ""
echo "=== 检查Luci应用 ==="
./scripts/feeds list | grep -E "^(luci-)" | sort

echo ""
echo "=== 检查网络工具 ==="
./scripts/feeds list | grep -E "^(firewall|dnsmasq|hostapd|wpad)" | sort

echo ""
echo "=== 检查系统工具 ==="
./scripts/feeds list | grep -E "^(fdisk|blkid|lsblk|block-mount|e2fsprogs)" | sort

echo ""
echo "=== 建议 ==="
echo "如果找不到对应的包，可以尝试:"
echo "1. 使用 make menuconfig 查看所有可用包"
echo "2. 检查不同feed中的包名"
echo "3. 查看 OpenWrt 官方文档获取正确的包名"
