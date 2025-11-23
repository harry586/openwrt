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

# 包诊断功能 - 修复版
diagnose_packages() {
    local build_dir="${1:-.}"
    cd "$build_dir"
    
    log_info "=== 包可用性诊断 ==="
    
    # 首先检查.config文件是否存在
    if [ ! -f ".config" ]; then
        log_error "错误: .config 文件不存在，请先运行配置加载"
        return 1
    fi
    
    # 更新feeds
    echo "更新feeds..."
    ./scripts/feeds update -a > /dev/null 2>&1
    
    # 检查配置文件中的包
    echo ""
    echo "=== 检查配置文件中的包 ==="
    CONFIG_PACKAGES=$(grep "^CONFIG_PACKAGE_" .config | grep "=y$" | sed 's/CONFIG_PACKAGE_//;s/=y//' | sort)
    echo "配置中启用的包数量: $(echo "$CONFIG_PACKAGES" | wc -l)"
    
    # 检查每个包是否在feeds中
    MISSING_COUNT=0
    MISSING_PACKAGES=()
    
    for pkg in $CONFIG_PACKAGES; do
        if ./scripts/feeds list | grep -q "^$pkg"; then
            echo "✅ $pkg"
        else
            echo "❌ $pkg"
            MISSING_COUNT=$((MISSING_COUNT + 1))
            MISSING_PACKAGES+=("$pkg")
        fi
    done
    
    echo ""
    echo "=== 检查结果 ==="
    echo "缺失包数量: $MISSING_COUNT"
    
    if [ $MISSING_COUNT -gt 0 ]; then
        log_error "发现 $MISSING_COUNT 个缺失包，构建可能失败！"
        
        # 显示缺失包的详细信息
        echo ""
        echo "=== 缺失包详细信息 ==="
        for pkg in "${MISSING_PACKAGES[@]}"; do
            echo "❌ $pkg"
            # 尝试查找相似的包
            SIMILAR=$(./scripts/feeds list | grep -i "$pkg" | head -3 | tr '\n' ' ')
            if [ -n "$SIMILAR" ]; then
                echo "   相似包: $SIMILAR"
            fi
        done
        return 1
    else
        log_success "所有包都在feeds中可用"
    fi
    
    echo ""
    echo "=== 按类别检查包 ==="
    echo "内核模块 (前10个):"
    ./scripts/feeds list | grep -E "^(kmod-|usb|fs-)" | sort | head -10
    
    echo ""
    echo "Luci应用 (前10个):"
    ./scripts/feeds list | grep -E "^(luci-)" | sort | head -10
    
    echo ""
    echo "网络工具 (前10个):"
    ./scripts/feeds list | grep -E "^(firewall|dnsmasq|hostapd|wpad)" | sort | head -10
    
    echo ""
    echo "系统工具 (前10个):"
    ./scripts/feeds list | grep -E "^(fdisk|blkid|lsblk|block-mount|e2fsprogs)" | sort | head -10
    
    echo ""
    echo "=== 建议 ==="
    echo "如果找不到对应的包，可以尝试:"
    echo "1. 运行: ./scripts/feeds update -a && ./scripts/feeds install -a"
    echo "2. 使用 make menuconfig 查看所有可用包"
    echo "3. 检查不同feed中的包名"
    echo "4. 查看 OpenWrt 官方文档获取正确的包名"
    
    return 0
}

# 包依赖检查
check_dependencies() {
    local build_dir="${1:-.}"
    cd "$build_dir"
    
    log_info "=== 包依赖检查 ==="
    
    # 更新feeds
    ./scripts/feeds update -a > /dev/null 2>&1
    
    # 检查配置文件中的包依赖
    if [ -f ".config" ]; then
        echo "检查包依赖关系..."
        
        # 临时启用详细输出
        set +e
        make defconfig
        MAKE_OUTPUT=$(make -j1 V=s 2>&1 | grep -E "depends on|missing|not found" | head -20)
        set -e
        
        if [ -n "$MAKE_OUTPUT" ]; then
            echo "❌ 发现依赖问题:"
            echo "$MAKE_OUTPUT"
            return 1
        else
            echo "✅ 未发现明显的依赖问题"
            return 0
        fi
    else
        log_warning "未找到.config文件，跳过依赖检查"
        return 0
    fi
}

# 显示使用说明
show_usage() {
    echo "OpenWrt 构建辅助工具"
    echo "用法: $0 <功能> [参数...]"
    echo ""
    echo "可用功能:"
    echo "  diagnose_packages - 包可用性诊断 [构建目录]"
    echo "  check_dependencies - 包依赖检查 [构建目录]"
    echo ""
    echo "示例:"
    echo "  $0 diagnose_packages /mnt/openwrt-build"
    echo "  $0 check_dependencies /mnt/openwrt-build"
}

# 主函数
main() {
    local command="$1"
    shift
    
    case "$command" in
        "diagnose_packages")
            diagnose_packages "$@"
            ;;
        "check_dependencies")
            check_dependencies "$@"
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
