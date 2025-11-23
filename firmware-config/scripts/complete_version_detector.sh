#!/bin/bash

# OpenWrt 版本检测脚本 - 动态版本选择（按指定顺序检测）

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 设备平台映射
declare -A DEVICE_PLATFORM_MAP=(
    ["ac42u"]="ipq40xx"
    ["acrh17"]="ipq40xx"
    ["rt-acrh17"]="ipq40xx"
    ["ac58u"]="ipq40xx"
    ["acrh13"]="ipq40xx"
    ["rt-ac58u"]="ipq40xx"
    ["rt-acrh13"]="ipq40xx"
    ["xiaomi_redmi-ax6s"]="mediatek"
    ["wr841n"]="ar71xx"
    ["mi3g"]="ramips"
)

# 版本检测顺序定义
# ImmortalWrt: 次稳定版 -> 次次稳定版 -> ... -> 较新古老版本 -> 最古老版本
IMMORTALWRT_VERSIONS=("23.05" "22.03" "21.02" "19.07" "18.06" "master")
LEDE_VERSIONS=("17.01" "reborn" "master")
OPENWRT_VERSIONS=("23.05" "22.03" "21.02" "19.07" "18.06" "master")

# 主检测函数
detect_best_version() {
    local device_name="$1"
    local user_specified_version="$2"
    local is_old_device="$3"
    
    echo "=== OpenWrt 智能版本检测 ==="
    echo "目标设备: $device_name"
    echo "用户指定版本: ${user_specified_version:-未指定}"
    echo "老旧设备模式: $is_old_device"
    
    # 如果用户指定了版本，优先使用
    if [ -n "$user_specified_version" ]; then
        log_info "使用用户指定版本: $user_specified_version"
        if parse_version_spec "$user_specified_version"; then
            return 0
        else
            log_error "用户指定版本解析失败"
            return 1
        fi
    fi
    
    log_info "开始智能版本检测..."
    
    # 按照指定顺序检测版本
    # 1. 首先检测 ImmortalWrt
    log_info "=== 检测 ImmortalWrt 版本 ==="
    for version in "${IMMORTALWRT_VERSIONS[@]}"; do
        log_info "尝试 ImmortalWrt $version"
        if try_branch "immortalwrt" "https://github.com/immortalwrt/immortalwrt.git" "$version" "$device_name"; then
            log_success "✅ 选择 ImmortalWrt $version"
            return 0
        fi
    done
    
    # 2. 然后检测 LEDE
    log_info "=== ImmortalWrt 无匹配，检测 LEDE 版本 ==="
    for version in "${LEDE_VERSIONS[@]}"; do
        log_info "尝试 LEDE $version"
        if try_branch "lede" "https://github.com/coolsnowwolf/lede.git" "$version" "$device_name"; then
            log_success "✅ 选择 LEDE $version"
            return 0
        fi
    done
    
    # 3. 最后检测 OpenWrt
    log_info "=== LEDE 无匹配，检测 OpenWrt 版本 ==="
    for version in "${OPENWRT_VERSIONS[@]}"; do
        log_info "尝试 OpenWrt $version"
        if try_branch "openwrt" "https://github.com/openwrt/openwrt.git" "$version" "$device_name"; then
            log_success "✅ 选择 OpenWrt $version"
            return 0
        fi
    done
    
    # 如果都没有匹配，使用默认值
    log_warning "⚠️ 无匹配版本，使用默认值"
    export SELECTED_REPO="immortalwrt"
    export SELECTED_BRANCH="master"
    export SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
    return 0
}

# 尝试特定分支
try_branch() {
    local repo="$1"
    local repo_url="$2"
    local branch="$3"
    local device_name="$4"
    
    log_info "测试 $repo:$branch"
    
    # 首先检查分支是否存在
    if ! check_branch_exists "$repo_url" "$branch"; then
        log_warning "❌ 分支 $branch 不存在于 $repo"
        return 1
    fi
    
    if check_branch_support "$repo_url" "$branch" "$device_name"; then
        export SELECTED_REPO="$repo"
        export SELECTED_BRANCH="$branch"
        export SELECTED_REPO_URL="$repo_url"
        log_success "✅ 版本 $branch 支持设备 $device_name"
        return 0
    else
        log_warning "❌ 版本 $branch 不支持设备 $device_name"
        return 1
    fi
}

# 检查分支支持
check_branch_support() {
    local repo_url="$1"
    local branch="$2"
    local device_name="$3"
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # 尝试克隆
    log_info "克隆 $repo_url 分支 $branch..."
    if ! git clone --depth 1 --branch "$branch" "$repo_url" . 2>/dev/null; then
        log_warning "无法克隆 $repo_url $branch"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_info "✅ 成功克隆 $branch"
    
    # 检查设备支持
    local device_supported=0
    
    # 方法1: 检查设备树文件
    local dts_files=$(find target/linux -name "*$device_name*" -type f 2>/dev/null | head -3)
    if [ -n "$dts_files" ]; then
        log_success "✅ 找到设备树文件: $(echo $dts_files | tr '\n' ' ')"
        device_supported=1
    fi
    
    # 方法2: 检查设备定义文件
    if [ $device_supported -eq 0 ]; then
        local device_defs=$(find target/linux -name "*.mk" -type f -exec grep -l "$device_name" {} \; 2>/dev/null | head -3)
        if [ -n "$device_defs" ]; then
            log_success "✅ 找到设备定义文件: $(echo $device_defs | tr '\n' ' ')"
            device_supported=1
        fi
    fi
    
    # 方法3: 检查配置中的设备
    if [ $device_supported -eq 0 ]; then
        local config_matches=$(find . -name "config-*" -type f -exec grep -l "$device_name" {} \; 2>/dev/null | head -3)
        if [ -n "$config_matches" ]; then
            log_success "✅ 在配置中找到设备: $(echo $config_matches | tr '\n' ' ')"
            device_supported=1
        fi
    fi
    
    cd /
    rm -rf "$temp_dir"
    
    if [ $device_supported -eq 1 ]; then
        return 0
    else
        log_warning "❌ 未找到设备 $device_name 的支持文件"
        return 1
    fi
}

# 解析版本规格
parse_version_spec() {
    local version_spec="$1"
    
    if [[ "$version_spec" == *":"* ]]; then
        IFS=':' read -r repo branch <<< "$version_spec"
    else
        repo="immortalwrt"
        branch="$version_spec"
    fi
    
    case "$repo" in
        "immortalwrt")
            export SELECTED_REPO="immortalwrt"
            export SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
            ;;
        "openwrt")
            export SELECTED_REPO="openwrt"
            export SELECTED_REPO_URL="https://github.com/openwrt/openwrt.git"
            ;;
        "lede")
            export SELECTED_REPO="lede"
            export SELECTED_REPO_URL="https://github.com/coolsnowwolf/lede.git"
            ;;
        *)
            log_error "未知仓库: $repo"
            return 1
            ;;
    esac
    
    # 验证分支是否存在
    if check_branch_exists "$SELECTED_REPO_URL" "$branch"; then
        export SELECTED_BRANCH="$branch"
        return 0
    else
        log_error "分支 $branch 不存在于 $repo"
        return 1
    fi
}

# 检查分支是否存在
check_branch_exists() {
    local repo_url="$1"
    local branch="$2"
    
    log_info "检查分支是否存在: $repo_url $branch"
    if git ls-remote --heads "$repo_url" "$branch" 2>/dev/null | grep -q "$branch"; then
        log_info "✅ 分支 $branch 存在"
        return 0
    else
        log_warning "❌ 分支 $branch 不存在"
        return 1
    fi
}

# 主函数
main() {
    if [ $# -lt 1 ]; then
        echo "用法: $0 <设备名称> [版本规格] [是否老旧设备]"
        echo ""
        echo "参数说明:"
        echo "  设备名称: 如 ac42u, acrh17, rt-acrh17, ac58u, acrh13"
        echo "  版本规格: (可选) 如 openwrt-23.05 或 immortalwrt:master"
        echo "  是否老旧设备: (可选) true 或 false，默认为 false"
        echo ""
        echo "示例:"
        echo "  $0 ac42u"
        echo "  $0 acrh17 immortalwrt:openwrt-23.05"
        echo "  $0 wr841n '' true"
        exit 1
    fi
    
    local device_name="$1"
    local user_version="$2"
    local old_device="${3:-false}"
    
    if detect_best_version "$device_name" "$user_version" "$old_device"; then
        echo ""
        echo "=== 版本检测结果 ==="
        echo "设备: $device_name"
        echo "推荐仓库: $SELECTED_REPO"
        echo "推荐分支: $SELECTED_BRANCH"
        echo "仓库URL: $SELECTED_REPO_URL"
        echo ""
        
        # 直接输出环境变量，供工作流捕获
        echo "SELECTED_REPO=$SELECTED_REPO"
        echo "SELECTED_BRANCH=$SELECTED_BRANCH"
        echo "SELECTED_REPO_URL=$SELECTED_REPO_URL"
        
        log_success "版本检测完成"
    else
        log_error "版本检测失败"
        exit 1
    fi
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
