#!/bin/bash

# OpenWrt 构建辅助功能脚本
# 包含诊断、包检查等辅助功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 包诊断功能
diagnose_packages() {
    local build_dir="${1:-.}"
    cd "$build_dir"
    
    log_info "=== 包可用性诊断 ==="
    
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
}

# 显示使用说明
show_usage() {
    echo "OpenWrt 构建辅助工具"
    echo "用法: $0 <功能> [参数...]"
    echo ""
    echo "可用功能:"
    echo "  diagnose_packages - 包可用性诊断 [构建目录]"
    echo ""
    echo "示例:"
    echo "  $0 diagnose_packages /mnt/openwrt-build"
}

# 主函数
main() {
    local command="$1"
    shift
    
    case "$command" in
        "diagnose_packages")
            diagnose_packages "$@"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi
    main "$@"
fi
