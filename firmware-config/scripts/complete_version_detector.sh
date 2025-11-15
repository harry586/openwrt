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

# 设备支持检测函数
check_device_support() {
    local device_name="$1"
    local repo_url="$2"
    local branch="$3"
    
    local temp_dir="/tmp/device_check_$$"
    
    # 创建临时目录
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    log_info "检查设备 $device_name 在 $repo_url $branch 中的支持情况..."
    
    # 尝试克隆特定版本
    if git clone --depth 1 --branch "$branch" "$repo_url" . 2>/dev/null; then
        log_info "✅ 版本 $branch 克隆成功"
    else
        log_warning "❌ 无法克隆版本 $branch"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 方法1: 查找设备树文件
    local dts_files=$(find target/linux -name "*$device_name*.dts" -o -name "*$device_name*.dtsi" 2>/dev/null | head -3)
    if [ -n "$dts_files" ]; then
        log_success "✅ 找到设备树文件"
        echo "$dts_files"
        cd /
        rm -rf "$temp_dir"
        return 0
    fi
    
    # 方法2: 在目标配置中查找
    local target_files=$(find target/linux -name "target.mk" -o -name "Makefile" 2>/dev/null)
    for target_file in $target_files; do
        if grep -q "$device_name" "$target_file" 2>/dev/null; then
            log_success "✅ 在配置文件中找到设备: $(basename $target_file)"
            cd /
            rm -rf "$temp_dir"
            return 0
        fi
    done
    
    # 方法3: 查找内核配置中的设备
    local config_files=$(find target/linux -name "config-*" 2>/dev/null | head -3)
    for config_file in $config_files; do
        if grep -q "$device_name" "$config_file" 2>/dev/null; then
            log_success "✅ 在内核配置中找到设备: $(basename $config_file)"
            cd /
            rm -rf "$temp_dir"
            return 0
        fi
    done
    
    log_warning "❌ 版本 $branch 不支持设备 $device_name"
    cd /
    rm -rf "$temp_dir"
    return 1
}

# 主检测函数
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
        test_specific_version "$device_name" "$user_specified_version"
        return $?
    fi
    
    log_info "开始智能版本检测..."
    
    # 根据设备类型选择检测策略
    if [ "$is_old_device" = "true" ]; then
        log_info "使用老旧设备检测策略"
        detect_for_old_device "$device_name"
    else
        log_info "使用现代设备检测策略" 
        detect_for_modern_device "$device_name"
    fi
}

# 现代设备检测策略
detect_for_modern_device() {
    local device_name="$1"
    
    log_info "现代设备检测策略: 最新稳定版 → 次新稳定版 → 早期稳定版 → 官方源码"
    
    # 为每个仓库检测最佳版本
    for repo_info in "${REPOS[@]}"; do
        IFS=':' read -r repo repo_url <<< "$repo_info"
        log_info "检测仓库: $repo"
        
        if detect_modern_versions "$device_name" "$repo" "$repo_url"; then
            log_success "在仓库 $repo 中找到支持的版本: $SELECTED_BRANCH"
            export SELECTED_REPO="$repo"
            export SELECTED_REPO_URL="$repo_url"
            return 0
        fi
    done
    
    log_error "所有现代版本均不支持设备: $device_name"
    return 1
}

# 老旧设备检测策略
detect_for_old_device() {
    local device_name="$1"
    
    log_info "老旧设备检测策略: LTS稳定版 → 早期稳定版 → 次新稳定版 → 最新稳定版 → 官方源码"
    
    # 为每个仓库检测最佳版本
    for repo_info in "${REPOS[@]}"; do
        IFS=':' read -r repo repo_url <<< "$repo_info"
        log_info "检测仓库: $repo"
        
        if detect_old_versions "$device_name" "$repo" "$repo_url"; then
            log_success "在仓库 $repo 中找到支持的版本: $SELECTED_BRANCH"
            export SELECTED_REPO="$repo"
            export SELECTED_REPO_URL="$repo_url"
            return 0
        fi
    done
    
    log_error "所有版本均不支持老旧设备: $device_name"
    return 1
}

# 现代设备版本检测（从新到旧）
detect_modern_versions() {
    local device_name="$1"
    local repo="$2"
    local repo_url="$3"
    
    local temp_dir="/tmp/${repo}_modern_test_$$"
    
    # 创建临时目录并克隆仓库
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    log_info "获取 $repo 的现代版本信息..."
    git clone --depth 1 "$repo_url" . 2>/dev/null || return 1
    
    # 获取现代版本列表（从新到旧）
    local modern_versions=$(get_modern_versions_sorted "$repo")
    
    if [ -z "$modern_versions" ]; then
        log_warning "无法获取 $repo 的版本信息"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_info "$repo 现代版本 (从新到旧):"
    echo "$modern_versions"
    
    # 按照从新到旧的顺序测试版本
    local version_count=$(echo "$modern_versions" | wc -l)
    local tested_count=0
    
    while IFS= read -r version_info; do
        tested_count=$((tested_count + 1))
        IFS=':' read -r version stability <<< "$version_info"
        
        log_info "测试版本 [$tested_count/$version_count] - 稳定性: $stability - $version"
        
        # 检查该版本是否支持设备
        if check_device_support "$device_name" "$repo_url" "$version"; then
            log_success "✅ 版本 $version 支持设备 $device_name"
            export SELECTED_BRANCH="$version"
            cd /
            rm -rf "$temp_dir"
            return 0
        fi
        
        # 如果已经测试了足够多的版本，停止测试
        if [ $tested_count -ge 6 ]; then
            log_info "已测试前6个版本，停止测试更多版本"
            break
        fi
    done <<< "$modern_versions"
    
    cd /
    rm -rf "$temp_dir"
    return 1
}

# 老旧设备版本检测（从旧到新）
detect_old_versions() {
    local device_name="$1"
    local repo="$2"
    local repo_url="$3"
    
    local temp_dir="/tmp/${repo}_old_test_$$"
    
    # 创建临时目录并克隆仓库
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    log_info "获取 $repo 的老旧版本信息..."
    git clone --depth 1 "$repo_url" . 2>/dev/null || return 1
    
    # 获取老旧版本列表（从旧到新）
    local old_versions=$(get_old_versions_sorted "$repo")
    
    if [ -z "$old_versions" ]; then
        log_warning "无法获取 $repo 的版本信息"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_info "$repo 老旧版本 (从旧到新):"
    echo "$old_versions"
    
    # 按照从旧到新的顺序测试版本
    local version_count=$(echo "$old_versions" | wc -l)
    local tested_count=0
    
    while IFS= read -r version_info; do
        tested_count=$((tested_count + 1))
        IFS=':' read -r version stability <<< "$version_info"
        
        log_info "测试版本 [$tested_count/$version_count] - 稳定性: $stability - $version"
        
        # 检查该版本是否支持设备
        if check_device_support "$device_name" "$repo_url" "$version"; then
            log_success "✅ 版本 $version 支持设备 $device_name"
            export SELECTED_BRANCH="$version"
            cd /
            rm -rf "$temp_dir"
            return 0
        fi
        
        # 如果已经测试了足够多的版本，停止测试
        if [ $tested_count -ge 8 ]; then
            log_info "已测试前8个版本，停止测试更多版本"
            break
        fi
    done <<< "$old_versions"
    
    cd /
    rm -rf "$temp_dir"
    return 1
}

# 获取现代设备版本列表（从新到旧）
get_modern_versions_sorted() {
    local repo="$1"
    
    # 获取所有分支
    local branches=$(git branch -r | grep -v HEAD | sed 's/^.*origin\///' | sort -u)
    
    # 获取所有标签
    local tags=""
    if [ "$repo" = "openwrt" ]; then
        tags=$(git tag -l "v*" | sort -Vr)
    else
        tags=$(git tag -l | sort -Vr)
    fi
    
    # 现代设备版本排序（从新到旧）
    {
        # 第一优先级：最新的稳定版本分支
        echo "$branches" | grep -E "openwrt-[0-9]+\.[0-9]+$" | sort -Vr | head -1 | awk '{print $0 ":最新稳定版"}'
        
        # 第二优先级：次新的稳定版本分支
        echo "$branches" | grep -E "openwrt-[0-9]+\.[0-9]+$" | sort -Vr | sed -n '2p' | awk '{print $0 ":次新稳定版"}'
        
        # 第三优先级：早期稳定版本分支
        echo "$branches" | grep -E "openwrt-2[1-9]\.[0-9]+$" | sort -Vr | tail -n +3 | awk '{print $0 ":早期稳定版"}'
        
        # 第四优先级：master/main 开发分支
        echo "$branches" | grep -E "^(master|main)$" | awk '{print $0 ":开发版"}'
        
        # 第五优先级：官方OpenWrt稳定标签
        if [ "$repo" = "openwrt" ]; then
            echo "$tags" | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+$" | head -3 | awk '{print $0 ":官方稳定版"}'
        fi
        
    } | grep -v "^$"  # 移除空行
}

# 获取老旧设备版本列表（从旧到新）
get_old_versions_sorted() {
    local repo="$1"
    
    # 获取所有分支
    local branches=$(git branch -r | grep -v HEAD | sed 's/^.*origin\///' | sort -u)
    
    # 获取所有标签
    local tags=""
    if [ "$repo" = "openwrt" ]; then
        tags=$(git tag -l "v*" | sort -V)
    else
        tags=$(git tag -l | sort -V)
    fi
    
    # 老旧设备版本排序（从旧到新）
    {
        # 第一优先级：LTS长期支持版本（老旧设备最可能支持）
        echo "$branches" | grep -E "openwrt-1[8-9]\.[0-9]+" | sort -V | awk '{print $0 ":LTS稳定版"}'
        
        # 第二优先级：早期稳定版本
        echo "$branches" | grep -E "openwrt-2[0-1]\.[0-9]+" | sort -V | awk '{print $0 ":早期稳定版"}'
        
        # 第三优先级：次新稳定版本
        echo "$branches" | grep -E "openwrt-2[2-3]\.[0-9]+" | sort -V | awk '{print $0 ":次新稳定版"}'
        
        # 第四优先级：最新稳定版本
        echo "$branches" | grep -E "openwrt-[0-9]+\.[0-9]+$" | sort -Vr | head -1 | sort -V | awk '{print $0 ":最新稳定版"}'
        
        # 第五优先级：官方OpenWrt LTS标签
        if [ "$repo" = "openwrt" ]; then
            echo "$tags" | grep -E "^v1[8-9]\.[0-9]+\.[0-9]+" | head -3 | awk '{print $0 ":官方LTS版"}'
        fi
        
    } | grep -v "^$"  # 移除空行
}

# 测试用户指定版本
test_specific_version() {
    local device_name="$1"
    local version_spec="$2"
    
    # 解析版本规格 (格式: 仓库:分支)
    if [[ "$version_spec" == *":"* ]]; then
        IFS=':' read -r repo branch <<< "$version_spec"
    else
        # 默认使用 immortalwrt
        repo="immortalwrt"
        branch="$version_spec"
    fi
    
    # 获取仓库URL
    local repo_url=""
    for repo_info in "${REPOS[@]}"; do
        IFS=':' read -r r url <<< "$repo_info"
        if [ "$r" = "$repo" ]; then
            repo_url="$url"
            break
        fi
    done
    
    if [ -z "$repo_url" ]; then
        log_error "未知仓库: $repo"
        return 1
    fi
    
    log_info "测试指定版本: $repo:$branch"
    
    if check_device_support "$device_name" "$repo_url" "$branch"; then
        export SELECTED_REPO="$repo"
        export SELECTED_BRANCH="$branch"
        export SELECTED_REPO_URL="$repo_url"
        return 0
    else
        log_error "指定版本不支持设备: $device_name"
        return 1
    fi
}

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
