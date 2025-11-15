#!/bin/bash

# OpenWrt 版本检测脚本 - 无文件写入版本

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

# 主检测函数
detect_best_version() {
    local device_name="$1"
    local user_specified_version="$2"
    local is_old_device="$3"
    
    echo "=== OpenWrt 版本检测 ==="
    echo "目标设备: $device_name"
    echo "老旧设备模式: $is_old_device"
    
    # 如果用户指定了版本，优先使用
    if [ -n "$user_specified_version" ]; then
        log_info "使用用户指定版本: $user_specified_version"
        parse_version_spec "$user_specified_version"
        return 0
    fi
    
    log_info "开始版本检测..."
    
    # 尝试 immortalwrt 的常用分支
    if try_branch "immortalwrt" "https://github.com/immortalwrt/immortalwrt.git" "master" "$device_name"; then
        return 0
    fi
    
    if try_branch "immortalwrt" "https://github.com/immortalwrt/immortalwrt.git" "openwrt-23.05" "$device_name"; then
        return 0
    fi
    
    # 尝试 openwrt 的常用分支
    if try_branch "openwrt" "https://git.openwrt.org/openwrt/openwrt.git" "main" "$device_name"; then
        return 0
    fi
    
    # 如果所有检测都失败，使用默认值
    log_warning "所有版本检测失败，使用默认版本: immortalwrt master"
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
    
    # 简化的设备支持检查：只要找到设备相关文件就认为支持
    local device_files=$(find target/linux -name "*$device_name*" -type f 2>/dev/null | head -3)
    if [ -n "$device_files" ]; then
        log_success "✅ 找到设备相关文件"
        cd /
        rm -rf "$temp_dir"
        return 0
    fi
    
    log_warning "❌ 未找到设备相关文件"
    cd /
    rm -rf "$temp_dir"
    return 1
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

# 主函数
main() {
    if [ $# -lt 1 ]; then
        echo "用法: $0 <设备名称> [版本规格] [是否老旧设备]"
        echo ""
        echo "参数说明:"
        echo "  设备名称: 如 ac42u, acrh17, rt-acrh17"
        echo "  版本规格: (可选) 如 openwrt-23.05 或 immortalwrt:master"
        echo "  是否老旧设备: (可选) true 或 false，默认为 false"
        echo ""
        echo "示例:"
        echo "  $0 ac42u"
        echo "  $0 acrh17"
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
