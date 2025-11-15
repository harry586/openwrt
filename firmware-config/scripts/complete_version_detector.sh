#!/bin/bash

# OpenWrt 智能版本检测脚本 - 宽松版
# 如果无法自动检测，提供合理的默认值

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

# 设备到版本的映射
declare -A DEVICE_MAPPING=(
    ["ac42u"]="immortalwrt:master"
    ["acrh17"]="immortalwrt:master" 
    ["rt-acrh17"]="immortalwrt:master"
    ["xiaomi_redmi-ax6s"]="immortalwrt:master"
    ["wr841n"]="openwrt:22.03"
    ["mi3g"]="immortalwrt:openwrt-21.02"
)

# 主检测函数 - 宽松版
detect_best_version() {
    local device_name="$1"
    local user_specified_version="$2"
    local is_old_device="$3"
    
    echo "=== OpenWrt 智能版本检测 ==="
    echo "目标设备: $device_name"
    echo "老旧设备模式: $is_old_device"
    
    # 如果用户指定了版本，优先使用
    if [ -n "$user_specified_version" ]; then
        log_info "使用用户指定版本: $user_specified_version"
        parse_version_spec "$user_specified_version"
        return 0
    fi
    
    # 检查设备映射
    if [ -n "${DEVICE_MAPPING[$device_name]}" ]; then
        log_info "使用预定义的设备映射"
        parse_version_spec "${DEVICE_MAPPING[$device_name]}"
        return 0
    fi
    
    # 尝试自动检测
    log_info "开始自动版本检测..."
    
    # 首先尝试 immortalwrt
    if try_repository "immortalwrt" "https://github.com/immortalwrt/immortalwrt.git" "$device_name" "$is_old_device"; then
        return 0
    fi
    
    # 然后尝试 openwrt
    if try_repository "openwrt" "https://git.openwrt.org/openwrt/openwrt.git" "$device_name" "$is_old_device"; then
        return 0
    fi
    
    # 如果自动检测失败，使用合理的默认值
    log_warning "自动检测失败，使用默认版本"
    if [ "$is_old_device" = "true" ]; then
        export SELECTED_REPO="openwrt"
        export SELECTED_BRANCH="22.03"
        export SELECTED_REPO_URL="https://git.openwrt.org/openwrt/openwrt.git"
    else
        export SELECTED_REPO="immortalwrt"
        export SELECTED_BRANCH="master"
        export SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
    fi
    
    return 0
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
        *)
            log_error "未知仓库: $repo"
            return 1
            ;;
    esac
    
    export SELECTED_BRANCH="$branch"
    return 0
}

# 尝试检测仓库支持
try_repository() {
    local repo="$1"
    local repo_url="$2"
    local device_name="$3"
    local is_old_device="$4"
    
    log_info "尝试仓库: $repo"
    
    # 测试常用分支
    local branches=()
    if [ "$is_old_device" = "true" ]; then
        branches=("openwrt-22.03" "openwrt-21.02" "openwrt-19.07" "master")
    else
        branches=("master" "openwrt-23.05" "openwrt-22.03" "main")
    fi
    
    # 根据仓库调整分支名称
    if [ "$repo" = "openwrt" ]; then
        # 将 immortalwrt 分支名映射到 openwrt
        for i in "${!branches[@]}"; do
            if [ "${branches[i]}" = "master" ]; then
                branches[i]="main"
            fi
        done
    fi
    
    for branch in "${branches[@]}"; do
        log_info "测试分支: $branch"
        if check_branch_support "$repo_url" "$branch" "$device_name"; then
            export SELECTED_REPO="$repo"
            export SELECTED_BRANCH="$branch"
            export SELECTED_REPO_URL="$repo_url"
            log_success "✅ 找到支持的版本: $repo:$branch"
            return 0
        fi
    done
    
    log_warning "❌ 仓库 $repo 中没有找到支持的版本"
    return 1
}

# 检查分支支持 - 简化版
check_branch_support() {
    local repo_url="$1"
    local branch="$2"
    local device_name="$3"
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # 尝试克隆
    if ! git clone --depth 1 --branch "$branch" "$repo_url" . 2>/dev/null; then
        log_warning "无法克隆 $repo_url $branch"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_info "✅ 成功克隆 $branch"
    
    # 简化的设备支持检查
    # 1. 检查设备树文件
    local dts_files=$(find target/linux -name "*$device_name*" -type f 2>/dev/null | head -3)
    if [ -n "$dts_files" ]; then
        log_success "✅ 找到设备相关文件"
        cd /
        rm -rf "$temp_dir"
        return 0
    fi
    
    # 2. 检查目标配置文件
    local target_files=$(find target/linux -name "target.mk" -o -name "*.mk" 2>/dev/null | head -5)
    for target_file in $target_files; do
        if grep -q -i "$device_name" "$target_file" 2>/dev/null; then
            log_success "✅ 在配置文件中找到设备"
            cd /
            rm -rf "$temp_dir"
            return 0
        fi
    done
    
    # 3. 检查设备定义
    local device_variants=(
        "$device_name"
        "rt-$device_name"
        "asus_$device_name"
        "asus_rt-$device_name"
        $(echo "$device_name" | sed 's/acrh17/acrh17/')
        $(echo "$device_name" | sed 's/ac42u/ac42u/')
    )
    
    for variant in "${device_variants[@]}"; do
        if find target/linux -type f -name "*.mk" -exec grep -l "define Device.*$variant" {} \; 2>/dev/null | head -1; then
            log_success "✅ 找到设备定义: $variant"
            cd /
            rm -rf "$temp_dir"
            return 0
        fi
    done
    
    log_warning "❌ 分支 $branch 不支持设备 $device_name"
    cd /
    rm -rf "$temp_dir"
    return 1
}

# 安全写入版本信息
safe_write_version_info() {
    local output_file="version_info.txt"
    
    echo "=== 安全写入版本信息 ==="
    
    # 直接写入当前目录，依赖工作流中的权限修复
    {
        echo "SELECTED_REPO=$SELECTED_REPO"
        echo "SELECTED_BRANCH=$SELECTED_BRANCH"
        echo "SELECTED_REPO_URL=$SELECTED_REPO_URL"
        echo "DEVICE_NAME=$device_name"
        echo "DETECTION_TIME=$(date)"
    } > "$output_file"
    
    if [ -f "$output_file" ]; then
        echo "✅ 版本信息成功写入"
        echo "文件内容:"
        cat "$output_file"
        return 0
    else
        echo "❌ 无法写入版本信息文件"
        return 1
    fi
}

# 主函数
main() {
    if [ $# -lt 1 ]; then
        echo "用法: $0 <设备名称> [版本规格] [是否老旧设备]"
        echo ""
        echo "参数说明:"
        echo "  设备名称: 如 ac42u, acrh17, rt-acrh17, wr841n, mi3g"
        echo "  版本规格: (可选) 如 openwrt-23.05 或 immortalwrt:master"
        echo "  是否老旧设备: (可选) true 或 false，默认为 false"
        echo ""
        echo "示例:"
        echo "  $0 ac42u"
        echo "  $0 acrh17"
        echo "  $0 rt-acrh17"
        echo "  $0 wr841n \"\" true"
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
        echo "在 .config 中使用:"
        echo "# 智能选择的版本"
        echo "# $SELECTED_REPO - $SELECTED_BRANCH"
        
        log_success "版本检测完成"
        
        # 使用安全的文件写入方法
        if safe_write_version_info; then
            log_success "版本信息文件保存成功"
        else
            log_error "无法保存版本信息文件，但检测结果有效"
        fi
    else
        log_error "版本检测失败"
        exit 1
    fi
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
