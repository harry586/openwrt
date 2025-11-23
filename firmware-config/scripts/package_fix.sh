#!/bin/bash

# OpenWrt 包名修复脚本 - 完整版

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 完整的包名映射表 - 针对 ImmortalWrt 23.05
declare -A PACKAGE_MAPPING=(
    # 基础系统包映射
    ["6in4"]="6in4"
    ["firewall"]="firewall4"
    ["dnsmasq"]="dnsmasq-full"
    ["dnsmasq-dhcpv6"]="dnsmasq-full"
    ["hostapd-common"]="hostapd"
    ["hostapd-utils"]="hostapd-utils"
    ["kmod-ip6tables"]="kmod-ipt6"
    ["kmod-nf-ipt6"]="kmod-ipt6"
    ["libopenssl"]="libopenssl"
    ["libstdcpp"]="libstdcpp"
    ["odhcp6c"]="odhcp6c"
    ["odhcpd"]="odhcpd"
    ["wpad-openssl"]="wpad-basic"
    ["ipv6helper"]="odhcp6c"
    
    # 内核模块映射
    ["kmod-usb-storage"]="kmod-usb-storage"
    ["kmod-usb-storage-uas"]="kmod-usb-storage-uas"
    ["kmod-usb2"]="kmod-usb2"
    ["kmod-usb3"]="kmod-usb3"
    ["kmod-fs-ext4"]="kmod-fs-ext4"
    ["kmod-fs-vfat"]="kmod-fs-vfat"
    ["kmod-fs-ntfs"]="kmod-fs-ntfs"
    ["kmod-fs-exfat"]="kmod-fs-exfat"
    ["kmod-ipt-extra"]="kmod-ipt-extra"
    ["kmod-ipt-offload"]="kmod-ipt-offload"
    ["kmod-nf-nathelper"]="kmod-nf-nathelper"
    ["kmod-nf-nathelper-extra"]="kmod-nf-nathelper-extra"
    ["kmod-usb-core"]="kmod-usb-core"
    ["kmod-scsi-core"]="kmod-scsi-core"
    ["kmod-crypto-crc32c"]="kmod-crypto-crc32c"
    ["kmod-crypto-hash"]="kmod-crypto-hash"
    ["kmod-crypto-aead"]="kmod-crypto-aead"
    ["kmod-crypto-manager"]="kmod-crypto-manager"
    ["kmod-lib-crc16"]="kmod-lib-crc16"
    ["kmod-ipv6"]="kmod-ipv6"
    ["kmod-nf-conntrack6"]="kmod-nf-conntrack6"
    ["kmod-nf-reject6"]="kmod-nf-reject6"
    ["kmod-nf-nat6"]="kmod-nf-nat6"
    ["kmod-nls-base"]="kmod-nls-base"
    ["kmod-nls-utf8"]="kmod-nls-utf8"
    ["kmod-nls-cp437"]="kmod-nls-cp437"
    ["kmod-nls-iso8859-1"]="kmod-nls-iso8859-1"
    ["kmod-nls-iso8859-15"]="kmod-nls-iso8859-15"
    
    # 系统工具映射
    ["fdisk"]="fdisk"
    ["lsblk"]="lsblk"
    ["blkid"]="blkid"
    ["block-mount"]="block-mount"
    ["e2fsprogs"]="e2fsprogs"
    ["bash"]="bash"
    ["nano"]="nano"
    ["htop"]="htop"
    ["tree"]="tree"
    ["file"]="file"
    ["curl"]="curl"
    ["wget"]="wget"
    ["wget-ssl"]="wget"
    ["aria2"]="aria2"
    ["openssh-sftp-server"]="openssh-sftp-server"
    ["usbutils"]="usbutils"
    ["ntfs-3g"]="ntfs-3g"
    ["exfat-mkfs"]="exfat-utils"
    ["git"]="git"
    ["git-http"]="git-http"
    ["rsync"]="rsync"
    ["unzip"]="unzip"
    ["zip"]="zip"
    ["tar"]="tar"
    ["gzip"]="gzip"
    ["procps-ng"]="procps-ng"
    ["procps-ng-pkill"]="procps-ng-pkill"
    ["procps-ng-w"]="procps-ng-w"
    ["procps"]="procps-ng"
    ["procps-ng-free"]="procps-ng-free"
    ["procps-ng-kill"]="procps-ng-kill"
    ["procps-ng-pgrep"]="procps-ng-pgrep"
    ["procps-ng-pidof"]="procps-ng-pidof"
    ["procps-ng-ps"]="procps-ng-ps"
    ["procps-ng-sysctl"]="procps-ng-sysctl"
    ["procps-ng-top"]="procps-ng-top"
    ["procps-ng-uptime"]="procps-ng-uptime"
    ["procps-ng-watch"]="procps-ng-watch"
    ["iptables-mod-extra"]="iptables-mod-extra"
    ["iptables-mod-tproxy"]="iptables-mod-tproxy"
    ["ca-certificates"]="ca-certificates"
    ["ca-bundle"]="ca-bundle"
    ["ip-full"]="ip-full"
    ["resolveip"]="resolveip"
    ["tcpdump"]="tcpdump"
    
    # 库文件映射
    ["libopenssl-conf"]="libopenssl-conf"
    ["libopenssl-devcrypto"]="libopenssl-devcrypto"
    ["libpam"]="libpam"
    ["libblobmsg-json"]="libblobmsg-json"
    ["libjson-c"]="libjson-c"
    ["libjson-script"]="libjson-script"
    ["libuuid"]="libuuid"
    ["libpcre"]="libpcre"
    ["zlib"]="zlib"
    ["libcurl"]="libcurl"
    ["libevent2"]="libevent2"
    ["libelf"]="libelf"
    ["libpthread"]="libpthread"
    ["librt"]="librt"
    ["libatomic"]="libatomic"
    
    # Luci应用映射
    ["luci"]="luci"
    ["luci-base"]="luci-base"
    ["luci-theme-bootstrap"]="luci-theme-bootstrap"
    ["luci-i18n-base-zh-cn"]="luci-i18n-base-zh-cn"
    ["luci-i18n-firewall-zh-cn"]="luci-i18n-firewall-zh-cn"
    ["luci-app-turboacc"]="luci-app-turboacc"
    ["luci-i18n-turboacc-zh-cn"]="luci-i18n-turboacc-zh-cn"
    ["luci-app-sqm"]="luci-app-sqm"
    ["luci-i18n-sqm-zh-cn"]="luci-i18n-sqm-zh-cn"
    ["luci-app-upnp"]="luci-app-upnp"
    ["luci-i18n-upnp-zh-cn"]="luci-i18n-upnp-zh-cn"
    ["luci-app-vsftpd"]="luci-app-vsftpd"
    ["luci-app-samba4"]="luci-app-samba4"
    ["luci-i18n-samba4-zh-cn"]="luci-i18n-samba4-zh-cn"
    ["luci-app-smartdns"]="luci-app-smartdns"
    ["luci-i18n-smartdns-zh-cn"]="luci-i18n-smartdns-zh-cn"
    ["luci-app-arpbind"]="luci-app-arpbind"
    ["luci-i18n-arpbind-zh-cn"]="luci-i18n-arpbind-zh-cn"
    ["luci-app-cpulimit"]="luci-app-cpulimit"
    ["luci-i18n-cpulimit-zh-cn"]="luci-i18n-cpulimit-zh-cn"
    ["luci-app-diskman"]="luci-app-diskman"
    ["luci-i18n-diskman-zh-cn"]="luci-i18n-diskman-zh-cn"
    ["luci-app-accesscontrol"]="luci-app-accesscontrol"
    ["luci-i18n-accesscontrol-zh-cn"]="luci-i18n-accesscontrol-zh-cn"
    ["luci-app-vlmcsd"]="luci-app-vlmcsd"
    ["luci-i18n-vlmcsd-zh-cn"]="luci-i18n-vlmcsd-zh-cn"
)

# 修复包名映射
fix_package_names() {
    local build_dir="${1:-.}"
    cd "$build_dir"
    
    log_info "=== 修复包名映射 ==="
    
    if [ ! -f ".config" ]; then
        log_error "错误: .config 文件不存在"
        return 1
    fi
    
    # 创建临时配置文件
    cp .config .config.backup
    
    # 更新feeds确保包列表最新
    ./scripts/feeds update -a > /dev/null 2>&1
    
    # 获取feeds列表
    local feeds_list=$(./scripts/feeds list 2>/dev/null)
    
    local fixed_count=0
    local missing_count=0
    local missing_packages=()
    
    for original_pkg in "${!PACKAGE_MAPPING[@]}"; do
        local mapped_pkg="${PACKAGE_MAPPING[$original_pkg]}"
        
        # 检查原始包名是否在配置中启用
        if grep -q "CONFIG_PACKAGE_${original_pkg}=y" .config; then
            # 检查映射后的包名是否在feeds中
            if echo "$feeds_list" | grep -q "^${mapped_pkg}"; then
                # 替换包名
                sed -i "s/CONFIG_PACKAGE_${original_pkg}=y/CONFIG_PACKAGE_${mapped_pkg}=y/" .config
                echo "✅ 修复: $original_pkg → $mapped_pkg"
                fixed_count=$((fixed_count + 1))
            else
                # 如果映射包不存在，尝试查找替代包
                local alternative=$(echo "$feeds_list" | grep -i "$original_pkg" | head -1 | cut -f1)
                if [ -n "$alternative" ] && [ "$alternative" != "$mapped_pkg" ]; then
                    sed -i "s/CONFIG_PACKAGE_${original_pkg}=y/CONFIG_PACKAGE_${alternative}=y/" .config
                    echo "🔄 替代: $original_pkg → $alternative"
                    fixed_count=$((fixed_count + 1))
                else
                    echo "❌ 缺失: $original_pkg (映射: $mapped_pkg)"
                    # 注释掉不存在的包
                    sed -i "s/CONFIG_PACKAGE_${original_pkg}=y/# CONFIG_PACKAGE_${original_pkg} is not set/" .config
                    missing_count=$((missing_count + 1))
                    missing_packages+=("$original_pkg")
                fi
            fi
        fi
    done
    
    echo ""
    echo "=== 修复结果 ==="
    log_success "修复了 $fixed_count 个包名"
    
    if [ $missing_count -gt 0 ]; then
        log_warning "有 $missing_count 个包在feeds中找不到:"
        for pkg in "${missing_packages[@]}"; do
            echo "  ❌ $pkg"
        done
    fi
    
    # 重新运行defconfig
    make -j1 defconfig
    
    # 检查关键包是否配置正确
    check_critical_packages
}

# 检查关键包配置
check_critical_packages() {
    log_info "=== 检查关键包配置 ==="
    
    local critical_packages=("firewall4" "dnsmasq-full" "luci-base" "kmod-usb-storage" "block-mount")
    local missing_critical=0
    
    for pkg in "${critical_packages[@]}"; do
        if grep -q "CONFIG_PACKAGE_${pkg}=y" .config; then
            echo "✅ 关键包: $pkg"
        else
            echo "❌ 关键包缺失: $pkg"
            missing_critical=$((missing_critical + 1))
        fi
    done
    
    if [ $missing_critical -gt 0 ]; then
        log_error "发现 $missing_critical 个关键包缺失，构建可能失败"
        return 1
    else
        log_success "所有关键包都已正确配置"
        return 0
    fi
}

# 显示包状态报告
package_status_report() {
    local build_dir="${1:-.}"
    cd "$build_dir"
    
    log_info "=== 包状态报告 ==="
    
    if [ ! -f ".config" ]; then
        log_error "错误: .config 文件不存在"
        return 1
    fi
    
    # 统计启用的包数量
    local enabled_count=$(grep "^CONFIG_PACKAGE_.*=y" .config | wc -l)
    echo "启用的包数量: $enabled_count"
    
    # 显示各类包的统计
    echo ""
    echo "=== 包分类统计 ==="
    echo "Luci应用: $(grep "^CONFIG_PACKAGE_luci" .config | wc -l)"
    echo "内核模块: $(grep "^CONFIG_PACKAGE_kmod" .config | wc -l)"
    echo "网络工具: $(grep "^CONFIG_PACKAGE_.*ftp\\|ssh\\|dns\\|ip" .config | wc -l)"
    echo "系统工具: $(grep "^CONFIG_PACKAGE_bash\\|nano\\|htop\\|tree\\|file" .config | wc -l)"
    
    # 显示启用的Luci应用
    echo ""
    echo "=== 启用的Luci应用 ==="
    grep "^CONFIG_PACKAGE_luci-app" .config | sed 's/CONFIG_PACKAGE_//;s/=y//' | sort
}

show_usage() {
    echo "OpenWrt 包名修复工具"
    echo "用法: $0 <功能> [参数...]"
    echo ""
    echo "可用功能:"
    echo "  fix_package_names - 修复包名映射 [构建目录]"
    echo "  check_critical_packages - 检查关键包配置 [构建目录]"
    echo "  package_status_report - 包状态报告 [构建目录]"
    echo ""
    echo "示例:"
    echo "  $0 fix_package_names /mnt/openwrt-build"
    echo "  $0 package_status_report /mnt/openwrt-build"
}

main() {
    local command="$1"
    shift
    
    case "$command" in
        "fix_package_names")
            fix_package_names "$@"
            ;;
        "check_critical_packages")
            check_critical_packages "$@"
            ;;
        "package_status_report")
            package_status_report "$@"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi
    main "$@"
fi
