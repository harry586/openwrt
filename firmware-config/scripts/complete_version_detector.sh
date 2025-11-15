#!/bin/bash

# OpenWrt 完整智能版本检测脚本
# 支持老旧设备检测和智能版本选择

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

# 仓库配置
REPOS=(
    "immortalwrt:https://github.com/immortalwrt/immortalwrt.git"
    "openwrt:https://git.openwrt.org/openwrt/openwrt.git"
)

# ... 其他函数保持不变 ...

# 显示版本信息
show_version_info() {
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
}

# 安全写入版本信息
safe_write_version_info() {
    local output_file="version_info.txt"
    
    echo "=== 安全写入版本信息 ==="
    echo "当前工作目录: $(pwd)"
    echo "当前用户: $(whoami)"
    echo "目录权限:"
    ls -la . 2>/dev/null || echo "无法列出目录内容"
    
    # 尝试多个可能的输出位置
    local possible_locations=(
        "."
        "/tmp"
        "/home/runner"
        "$GITHUB_WORKSPACE"
    )
    
    for location in "${possible_locations[@]}"; do
        if [ -w "$location" ] || mkdir -p "$location" 2>/dev/null; then
            local test_file="$location/test_write_$$.txt"
            if touch "$test_file" 2>/dev/null; then
                echo "✅ 位置可写: $location"
                rm -f "$test_file"
                
                # 写入版本信息
                echo "SELECTED_REPO=$SELECTED_REPO" > "$location/$output_file"
                echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> "$location/$output_file"
                echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> "$location/$output_file"
                
                if [ -f "$location/$output_file" ]; then
                    echo "✅ 版本信息成功写入: $location/$output_file"
                    echo "文件内容:"
                    cat "$location/$output_file"
                    
                    # 如果不在当前目录，尝试复制到当前目录
                    if [ "$location" != "." ]; then
                        cp "$location/$output_file" "./$output_file" 2>/dev/null && echo "✅ 已复制到当前目录" || echo "⚠️ 无法复制到当前目录"
                    fi
                    return 0
                fi
            fi
        fi
    done
    
    # 如果所有位置都失败，尝试使用echo直接输出到当前目录
    echo "⚠️ 所有文件写入尝试失败，尝试直接输出"
    {
        echo "SELECTED_REPO=$SELECTED_REPO"
        echo "SELECTED_BRANCH=$SELECTED_BRANCH" 
        echo "SELECTED_REPO_URL=$SELECTED_REPO_URL"
    } > "$output_file" 2>/dev/null && echo "✅ 直接输出成功" && return 0
    
    # 最后尝试使用tee
    {
        echo "SELECTED_REPO=$SELECTED_REPO"
        echo "SELECTED_BRANCH=$SELECTED_BRANCH"
        echo "SELECTED_REPO_URL=$SELECTED_REPO_URL"
    } | tee "$output_file" >/dev/null 2>&1 && echo "✅ 使用tee输出成功" && return 0
    
    return 1
}

# 主函数
main() {
    if [ $# -lt 1 ]; then
        echo "用法: $0 <设备名称> [版本规格] [是否老旧设备]"
        echo ""
        echo "参数说明:"
        echo "  设备名称: 如 ac42u, wr841n, mi3g"
        echo "  版本规格: (可选) 如 openwrt-23.05 或 immortalwrt:master"
        echo "  是否老旧设备: (可选) true 或 false，默认为 false"
        echo ""
        echo "检测策略:"
        echo "  现代设备: 最新稳定版 → 次新稳定版 → 早期稳定版 → 开发版 → 官方源码"
        echo "  老旧设备: LTS稳定版 → 早期稳定版 → 次新稳定版 → 最新稳定版 → 官方LTS版"
        echo ""
        echo "老旧设备示例:"
        echo "  wr841n, wr941n, wdr4300, archer-c7, dir-615 等2015年以前的设备"
        echo ""
        echo "示例:"
        echo "  $0 ac42u"
        echo "  $0 wr841n \"\" true"
        echo "  $0 mi3g openwrt-22.03"
        echo "  $0 wr941n \"\" true"
        exit 1
    fi
    
    local device_name="$1"
    local user_version="$2"
    local old_device="${3:-false}"
    
    if detect_best_version "$device_name" "$user_version" "$old_device"; then
        show_version_info
        log_success "版本检测完成"
        
        # 使用安全的文件写入方法
        if safe_write_version_info; then
            log_success "版本信息文件保存成功"
        else
            log_error "无法保存版本信息文件，但检测结果有效"
            # 即使文件保存失败，也不退出，因为环境变量可能已经设置
            # 工作流可以通过其他方式获取这些信息
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
