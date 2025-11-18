#!/bin/bash

# OpenWrt 版本检测脚本 - 动态版本选择（稳定版优先）

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

# 动态获取稳定版本列表
get_stable_versions() {
    local repo_url="$1"
    
    log_info "获取 $repo_url 的稳定版本..."
    
    # 获取远程分支列表，过滤出稳定版本
    local stable_versions=$(git ls-remote --heads "$repo_url" 2>/dev/null | \
        grep -E 'openwrt-[0-9]+\.[0-9]+$' | \
        sed 's|.*refs/heads/||' | \
        sort -Vr | head -5)  # 按版本号逆序排列，取前5个
    
    if [ -z "$stable_versions" ]; then
        # 如果无法获取，使用默认的稳定版本列表
        log_warning "无法动态获取稳定版本，使用默认列表"
        echo "openwrt-23.05 openwrt-22.03 openwrt-21.02"
        return 1
    fi
    
    echo "$stable_versions"
    return 0
}

# 动态获取所有可用版本
get_all_versions() {
    local repo_url="$1"
    
    log_info "获取 $repo_url 的所有版本..."
    
    # 获取所有分支，排除master/main开发版
    local all_versions=$(git ls-remote --heads "$repo_url" 2>/dev/null | \
        grep -v -E 'master|main' | \
        sed 's|.*refs/heads/||' | \
        sort -Vr | head -10)
    
    if [ -z "$all_versions" ]; then
        log_warning "无法获取版本列表，使用默认值"
        echo "openwrt-23.05 openwrt-22.03 openwrt-21.02"
        return 1
    fi
    
    echo "$all_versions"
    return 0
}

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
    
    # 获取设备平台
    local device_platform="${DEVICE_PLATFORM_MAP[$device_name]}"
    if [ -z "$device_platform" ]; then
        log_warning "未知设备平台，使用默认检测"
        device_platform="generic"
    else
        log_info "设备平台: $device_platform"
    fi
    
    # 根据设备和平台选择合适的版本
    if [ "$is_old_device" = "true" ]; then
        log_info "检测到老旧设备，选择兼容性最好的稳定版本"
        select_compatible_version "$device_name" "$device_platform"
    else
        log_info "检测到现代设备，选择最新稳定版本"
        select_stable_version "$device_name" "$device_platform"
    fi
}

# 选择稳定版本（现代设备）
select_stable_version() {
    local device_name="$1"
    local device_platform="$2"
    
    log_info "选择最新稳定版本..."
    
    # 动态获取 immortalwrt 的稳定版本
    local immortalwrt_versions=$(get_stable_versions "https://github.com/immortalwrt/immortalwrt.git")
    local openwrt_versions=$(get_stable_versions "https://git.openwrt.org/openwrt/openwrt.git")
    
    log_info "ImmortalWrt 可用版本: $immortalwrt_versions"
    log_info "OpenWrt 可用版本: $openwrt_versions"
    
    # 合并版本列表并去重，按版本号排序
    local all_versions=$(echo "$immortalwrt_versions $openwrt_versions" | tr ' ' '\n' | sort -Vr | uniq)
    log_info "所有可用稳定版本: $all_versions"
    
    # 按照版本号从高到低尝试
    for version in $all_versions; do
        # 优先尝试 immortalwrt
        if try_branch "immortalwrt" "https://github.com/immortalwrt/immortalwrt.git" "$version" "$device_name"; then
            return 0
        fi
        
        # 然后尝试 openwrt
        if try_branch "openwrt" "https://git.openwrt.org/openwrt/openwrt.git" "$version" "$device_name"; then
            return 0
        fi
    done
    
    # 如果所有稳定版本都失败，尝试获取所有可用版本
    log_warning "所有稳定版本检测失败，尝试所有可用版本..."
    select_fallback_version "$device_name" "$device_platform"
}

# 选择兼容版本（老旧设备）
select_compatible_version() {
    local device_name="$1"
    local device_platform="$2"
    
    log_info "选择兼容性最好的稳定版本..."
    
    # 动态获取所有版本（按版本号正序，从旧到新）
    local immortalwrt_versions=$(get_all_versions "https://github.com/immortalwrt/immortalwrt.git")
    local openwrt_versions=$(get_all_versions "https://git.openwrt.org/openwrt/openwrt.git")
    
    # 合并版本列表并去重，按版本号正序排列（从旧到新）
    local all_versions=$(echo "$immortalwrt_versions $openwrt_versions" | tr ' ' '\n' | sort -V | uniq)
    log_info "所有可用版本(从旧到新): $all_versions"
    
    # 按照版本号从低到高尝试（优先旧版本）
    for version in $all_versions; do
        # 优先尝试 immortalwrt
        if try_branch "immortalwrt" "https://github.com/immortalwrt/immortalwrt.git" "$version" "$device_name"; then
            return 0
        fi
        
        # 然后尝试 openwrt
        if try_branch "openwrt" "https://git.openwrt.org/openwrt/openwrt.git" "$version" "$device_name"; then
            return 0
        fi
    done
    
    # 如果所有版本都失败，使用回退方案
    log_warning "所有版本检测失败，使用回退方案..."
    select_fallback_version "$device_name" "$device_platform"
}

# 回退版本选择
select_fallback_version() {
    local device_name="$1"
    local device_platform="$2"
    
    log_warning "使用回退版本选择方案..."
    
    # 回退方案：尝试一些已知的稳定版本
    local fallback_versions="openwrt-23.05 openwrt-22.03 openwrt-21.02"
    
    for version in $fallback_versions; do
        # 优先尝试 immortalwrt
        if try_branch "immortalwrt" "https://github.com/immortalwrt/immortalwrt.git" "$version" "$device_name"; then
            return 0
        fi
        
        # 然后尝试 openwrt
        if try_branch "openwrt" "https://git.openwrt.org/openwrt/openwrt.git" "$version" "$device_name"; then
            return 0
        fi
    done
    
    # 最终回退到 immortalwrt master
    log_warning "所有版本检测失败，使用最终回退版本: immortalwrt master"
    if try_branch "immortalwrt" "https://github.com/immortalwrt/immortalwrt.git" "master" "$device_name"; then
        return 0
    fi
    
    # 如果连master都失败，设置默认值
    log_error "所有版本选择都失败了！"
    export SELECTED_REPO="immortalwrt"
    export SELECTED_BRANCH="master"
    export SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
    return 1
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

# 检查分支支持 - 改进版
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
    
    # 方法4: 检查 profiles 目录
    if [ $device_supported -eq 0 ]; then
        local profile_matches=$(find . -path "*/profiles/*" -name "*.mk" -type f -exec grep -l "$device_name" {} \; 2>/dev/null | head -3)
        if [ -n "$profile_matches" ]; then
            log_success "✅ 在profiles中找到设备: $(echo $profile_matches | tr '\n' ' ')"
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
            export SELECTED_REPO_URL="https://git.openwrt.org/openwrt/openwrt.git"
            ;;
        "lede")
            export SELECTED_REPO="lede"
            export SELECTED_REPO_URL="https://git.lede-project.org/source.git"
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
