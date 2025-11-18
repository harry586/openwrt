#!/bin/bash
# check-plugins.sh - 智能检查插件可用性，支持包名映射（修复版）

set -e

BUILD_DIR="${1:-.}"
cd "$BUILD_DIR"

echo "=== 开始智能检查插件在feeds中的可用性 ==="

# 更新feeds
echo "更新feeds..."
./scripts/feeds update -a > /dev/null 2>&1

# 读取normal-new.config文件
CONFIG_FILE="config-templates/normal-new.config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 提取所有启用的包
PACKAGES=$(grep "^CONFIG_PACKAGE_" "$CONFIG_FILE" | grep "=y$" | sed 's/CONFIG_PACKAGE_//;s/=y//')

echo "在 $CONFIG_FILE 中启用的包数量: $(echo "$PACKAGES" | wc -l)"

# 包名映射函数
map_package() {
    local pkg="$1"
    case "$pkg" in
        # 内核模块映射
        kmod-usb-storage) echo "kmod-usb-storage" ;;
        kmod-usb-storage-uas) echo "kmod-usb-storage-uas" ;;
        kmod-usb2) echo "kmod-usb2" ;;
        kmod-usb3) echo "kmod-usb3" ;;
        kmod-fs-ext4) echo "kmod-fs-ext4" ;;
        kmod-fs-vfat) echo "kmod-fs-vfat" ;;
        kmod-fs-ntfs) echo "kmod-fs-ntfs" ;;
        kmod-fs-exfat) echo "kmod-fs-exfat" ;;
        kmod-ip6tables) echo "kmod-ipt6" ;;
        kmod-nf-ipt6) echo "kmod-ipt6" ;;
        kmod-ipt-extra) echo "kmod-ipt-extra" ;;
        kmod-ipt-offload) echo "kmod-ipt-offload" ;;
        kmod-nf-nathelper) echo "kmod-nf-nathelper" ;;
        kmod-nf-nathelper-extra) echo "kmod-nf-nathelper-extra" ;;
        
        # 基础工具映射
        fdisk) echo "fdisk" ;;
        lsblk) echo "lsblk" ;;
        blkid) echo "blkid" ;;
        block-mount) echo "block-mount" ;;
        e2fsprogs) echo "e2fsprogs" ;;
        
        # 核心服务映射
        firewall) echo "firewall" ;;
        dnsmasq) echo "dnsmasq" ;;
        dnsmasq-dhcpv6) echo "dnsmasq-full" ;;
        odhcpd) echo "odhcpd" ;;
        odhcp6c) echo "odhcp6c" ;;
        ipv6helper) echo "ipv6helper" ;;
        
        # 网络相关映射
        wpad-openssl) echo "wpad-basic" ;;
        hostapd-common) echo "hostapd" ;;
        hostapd-utils) echo "hostapd-utils" ;;
        
        # 库文件映射
        libstdcpp) echo "libstdcpp" ;;
        libpthread) echo "libpthread" ;;
        librt) echo "librt" ;;
        libatomic) echo "libatomic" ;;
        libopenssl) echo "libopenssl" ;;
        
        # Luci应用映射
        luci-app-turboacc) echo "luci-app-turboacc" ;;
        luci-i18n-turboacc-zh-cn) echo "luci-i18n-turboacc-zh-cn" ;;
        luci-app-accesscontrol) echo "luci-app-accesscontrol" ;;
        luci-i18n-accesscontrol-zh-cn) echo "luci-i18n-accesscontrol-zh-cn" ;;
        
        # 默认情况
        *) echo "$pkg" ;;
    esac
}

# 检查每个包是否在feeds中
MISSING_PACKAGES=()
AVAILABLE_PACKAGES=()
ALTERNATIVE_PACKAGES=()

check_package_availability() {
    local original_pkg="$1"
    local pkg_to_check="$2"
    
    # 首先检查原始包名
    if ./scripts/feeds list | grep -q "^$pkg_to_check"; then
        AVAILABLE_PACKAGES+=("$original_pkg→$pkg_to_check")
        echo "✅ $original_pkg → $pkg_to_check"
        return 0
    else
        # 尝试常见变体
        local variants=()
        
        # 内核模块变体
        if [[ "$pkg_to_check" == kmod-* ]]; then
            variants=("$pkg_to_check" "${pkg_to_check//kmod-/}" "kmod-${pkg_to_check//kmod-/}")
        fi
        
        # Luci应用变体
        if [[ "$pkg_to_check" == luci-* ]]; then
            variants=("$pkg_to_check" "${pkg_to_check//luci-/}" "${pkg_to_check//app-/}")
        fi
        
        # 检查所有变体
        for variant in "${variants[@]}"; do
            if ./scripts/feeds list | grep -q "^$variant"; then
                ALTERNATIVE_PACKAGES+=("$original_pkg→$variant")
                echo "🔄 $original_pkg → $variant (替代包)"
                return 0
            fi
        done
        
        # 如果都没有找到，标记为缺失
        MISSING_PACKAGES+=("$original_pkg")
        echo "❌ $original_pkg"
        return 1
    fi
}

echo "=== 开始检查包可用性 ==="
for pkg in $PACKAGES; do
    # 使用映射函数查找对应的包名
    mapped_pkg=$(map_package "$pkg")
    check_package_availability "$pkg" "$mapped_pkg"
done

echo ""
echo "=== 检查结果 ==="
echo "可用的包数量: ${#AVAILABLE_PACKAGES[@]}"
echo "找到替代的包数量: ${#ALTERNATIVE_PACKAGES[@]}"
echo "缺失的包数量: ${#MISSING_PACKAGES[@]}"

if [ ${#ALTERNATIVE_PACKAGES[@]} -gt 0 ]; then
    echo ""
    echo "=== 找到的替代包 ==="
    for pkg in "${ALTERNATIVE_PACKAGES[@]}"; do
        echo "  $pkg"
    done
fi

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo ""
    echo "=== 缺失的包 ==="
    for pkg in "${MISSING_PACKAGES[@]}"; do
        echo "  $pkg"
    done
    
    echo ""
    echo "=== 建议的解决方案 ==="
    echo "1. 运行以下命令查看所有可用的包:"
    echo "   ./scripts/feeds list | grep -i '缺失包名关键词'"
    echo ""
    echo "2. 手动更新 feeds:"
    echo "   ./scripts/feeds update -a"
    echo "   ./scripts/feeds install -a"
    echo ""
    echo "3. 使用 make menuconfig 查看可用的包"
    
    # 非关键性包缺失，只警告不退出
    CRITICAL_PACKAGES=("firewall" "dnsmasq" "kmod-usb-storage" "block-mount")
    critical_missing=0
    
    for critical in "${CRITICAL_PACKAGES[@]}"; do
        for missing in "${MISSING_PACKAGES[@]}"; do
            if [ "$missing" = "$critical" ]; then
                echo "❌ 关键包缺失: $critical"
                critical_missing=1
            fi
        done
    done
    
    if [ $critical_missing -eq 1 ]; then
        echo "❌ 有关键包缺失，构建可能失败"
        exit 1
    else
        echo "⚠️ 有非关键包缺失，但构建可以继续"
        exit 0
    fi
else
    echo "✅ 所有包都在feeds中可用或有替代包。"
    exit 0
fi
