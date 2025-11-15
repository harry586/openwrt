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

# 老旧设备列表
OLD_DEVICES=(
    "wr841n" "wr841nd" "tl-wr841n"
    "wr842n" "wr842nd" "tl-wr842n"
    "wr941n" "wr941nd" "tl-wr941n"
    "mw150r" "fw150r"
    "wr740n" "wr740nd" "tl-wr740n"
    "wr743n" "wr743nd" "tl-wr743n"
    "wr843n" "wr843nd" "tl-wr843n"
    "wr845n" "wr845nd" "tl-wr845n"
    "wr846n" "wr846nd" "tl-wr846n"
    "wr1043n" "wr1043nd" "tl-wr1043n"
    "wr2543n" "wr2543nd" "tl-wr2543n"
    "wdr4300" "wdr4310" "wdr4900"
    "archer-c7" "archer-c5" "archer-c20"
    "dir-615" "dir-620" "dir-825"
    "wnr2000" "wnr2200" "wnr3500"
)

# 主检测函数
detect_best_version() {
    local device_name="$1"
    local user_specified_version="$2"
    local is_old_device="$3"
    
    echo "=== OpenWrt 智能版本检测 ==="
    echo "目标设备: $device_name"
    echo "老旧设备模式: $is_old_device"
    
    # 检测是否为老旧设备
    if [ "$is_old_device" = "false" ]; then
        local detected_old_device=$(check_old_device "$device_name")
        if [ "$detected_old_device" = "true" ]; then
            log_warning "检测到设备 $device_name 可能是老旧设备，建议启用老旧设备模式"
        fi
    fi
    
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

# 检测是否为老旧设备
check_old_device() {
    local device_name="$1"
    local lower_device=$(echo "$device_name" | tr '[:upper:]' '[:lower:]')
    
    for old_device in "${OLD_DEVICES[@]}"; do
        if [[ "$lower_device" == *"$old_device"* ]]; then
            echo "true"
            return 0
        fi
    done
    
    # 额外检查：包含特定年份或旧型号标识
    if [[ "$lower_device" =~ (200[0-9]|201[0-5]|wr[0-9]+[a-z]?|tl-wr[0-9]+|dir-[0-9]+) ]]; then
        echo "true"
        return 0
    fi
    
    echo "false"
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
        
        # 测试该版本
        if test_version "$device_name" "$repo" "$repo_url" "$version"; then
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
        
        # 测试该版本
        if test_version "$device_name" "$repo" "$repo_url" "$version"; then
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

# 测试特定版本
test_version() {
    local device_name="$1"
    local repo="$2"
    local repo_url="$3"
    local version="$4"
    
    local temp_dir="/tmp/version_test_$$"
    
    # 创建临时目录
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    log_info "克隆 $repo - $version ..."
    
    # 尝试克隆特定版本
    if git clone --depth 1 --branch "$version" "$repo_url" . 2>/dev/null; then
        log_info "✅ 版本 $version 克隆成功"
    else
        log_warning "❌ 无法克隆版本 $version，尝试查找替代..."
        
        # 如果是分支不存在，尝试查找类似分支
        if [[ "$version" == *"openwrt"* ]]; then
            local alt_version=$(find_alternative_branch "$repo" "$repo_url" "$version")
            if [ -n "$alt_version" ] && git clone --depth 1 --branch "$alt_version" "$repo_url" . 2>/dev/null; then
                log_info "✅ 使用替代版本: $alt_version"
                version="$alt_version"
            else
                cd /
                rm -rf "$temp_dir"
                return 1
            fi
        else
            cd /
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    # 更新 feeds（基础操作）
    if [ -f "feeds.conf.default" ]; then
        ./scripts/feeds update -a >/dev/null 2>&1
        ./scripts/feeds install -a >/dev/null 2>&1
    fi
    
    # 运行设备检测
    if check_device_support "$device_name"; then
        log_success "✅ 版本 $version 支持设备 $device_name"
        export SELECTED_BRANCH="$version"
        cd /
        rm -rf "$temp_dir"
        return 0
    else
        log_warning "❌ 版本 $version 不支持设备 $device_name"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
}

# 查找替代分支
find_alternative_branch() {
    local repo="$1"
    local repo_url="$2"
    local original_version="$3"
    
    local temp_dir="/tmp/alt_branch_$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    log_info "在 $repo 中查找 $original_version 的替代分支..."
    
    # 克隆仓库并列出所有分支
    git clone --depth 1 "$repo_url" . 2>/dev/null
    
    # 提取版本号
    local version_num=$(echo "$original_version" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    if [ -n "$version_num" ]; then
        # 查找相同主版本号的其他分支
        local alternative_branches=$(git branch -a | grep -E "($version_num|[0-9]+\.[0-9]+)" | sed 's/^.*\///' | sort -V | head -5)
        
        if [ -n "$alternative_branches" ]; then
            log_info "找到的替代分支:"
            echo "$alternative_branches"
            
            # 返回第一个替代分支
            echo "$alternative_branches" | head -1
            cd /
            rm -rf "$temp_dir"
            return 0
        fi
    fi
    
    cd /
    rm -rf "$temp_dir"
    return 1
}

# 检查设备支持
check_device_support() {
    local device_name="$1"
    
    # 方法1: 查找设备树文件
    local dts_files=$(find target/linux -name "*$device_name*.dts" -o -name "*$device_name*.dtsi" 2>/dev/null | head -3)
    if [ -n "$dts_files" ]; then
        log_success "✅ 找到设备树文件"
        echo "$dts_files"
        return 0
    fi
    
    # 方法2: 在目标配置中查找
    local target_files=$(find target/linux -name "target.mk" -o -name "Makefile" 2>/dev/null)
    for target_file in $target_files; do
        if grep -q "$device_name" "$target_file" 2>/dev/null; then
            log_success "✅ 在配置文件中找到设备: $(basename $target_file)"
            return 0
        fi
    done
    
    # 方法3: 查找内核配置中的设备
    local config_files=$(find target/linux -name "config-*" 2>/dev/null | head -3)
    for config_file in $config_files; do
        if grep -q "$device_name" "$config_file" 2>/dev/null; then
            log_success "✅ 在内核配置中找到设备: $(basename $config_file)"
            return 0
        fi
    done
    
    return 1
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
    
    if test_version "$device_name" "$repo" "$repo_url" "$branch"; then
        export SELECTED_REPO="$repo"
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
        
        # 输出版本信息到文件
        echo "SELECTED_REPO=$SELECTED_REPO" > version_info.txt
        echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> version_info.txt
        echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> version_info.txt
        echo "版本信息已保存到 version_info.txt"
        cat version_info.txt
    else
        log_error "版本检测失败"
        exit 1
    fi
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
