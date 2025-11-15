#!/bin/bash

# OpenWrt 智能版本检测脚本 - 简化版

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

# 仓库配置
REPOS=(
    "immortalwrt:https://github.com/immortalwrt/immortalwrt.git"
    "openwrt:https://git.openwrt.org/openwrt/openwrt.git"
    "lede:https://github.com/coolsnowwolf/lede.git"
)

# 主检测函数
detect_best_version() {
    local device_name="$1"
    local user_specified_version="$2"
    
    echo "=== OpenWrt 智能版本检测 ==="
    echo "目标设备: $device_name"
    
    # 如果用户指定了版本，直接使用
    if [ -n "$user_specified_version" ]; then
        log_info "使用用户指定版本: $user_specified_version"
        parse_version_spec "$user_specified_version"
        return $?
    fi
    
    log_info "开始智能版本检测..."
    
    # 为 RT-ACRH17 (ac42u) 推荐稳定版本
    case "$device_name" in
        "ac42u"|"rt-acrh17")
            log_info "检测到华硕 RT-ACRH17 设备，推荐使用稳定版本"
            export SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
            export SELECTED_BRANCH="openwrt-23.05"
            ;;
        *)
            log_info "使用默认版本"
            export SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
            export SELECTED_BRANCH="master"
            ;;
    esac
    
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
    
    # 根据仓库名获取URL
    case "$repo" in
        "immortalwrt")
            export SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
            ;;
        "openwrt")
            export SELECTED_REPO_URL="https://git.openwrt.org/openwrt/openwrt.git"
            ;;
        "lede")
            export SELECTED_REPO_URL="https://github.com/coolsnowwolf/lede.git"
            ;;
        *)
            log_error "未知仓库: $repo"
            return 1
            ;;
    esac
    
    export SELECTED_BRANCH="$branch"
    return 0
}

# 显示版本信息
show_version_info() {
    echo ""
    echo "=== 版本检测结果 ==="
    echo "设备: $device_name"
    echo "仓库URL: $SELECTED_REPO_URL"
    echo "分支: $SELECTED_BRANCH"
}

# 主函数
main() {
    if [ $# -lt 1 ]; then
        echo "用法: $0 <设备名称> [版本规格]"
        echo ""
        echo "示例:"
        echo "  $0 ac42u"
        echo "  $0 rt-acrh17 immortalwrt:openwrt-23.05"
        echo "  $0 mi3g lede:master"
        exit 1
    fi
    
    local device_name="$1"
    local user_version="$2"
    
    if detect_best_version "$device_name" "$user_version"; then
        show_version_info
        log_success "版本检测完成"
        
        # 输出版本信息到文件
        echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" > version_info.txt
        echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> version_info.txt
        echo "版本信息已保存到 version_info.txt"
    else
        log_error "版本检测失败"
        exit 1
    fi
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
