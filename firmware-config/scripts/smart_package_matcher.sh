#!/bin/bash

# OpenWrt 智能包匹配器 - 修复版
# 主要修复：包搜索逻辑、feeds更新时机、匹配算法

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

# 初始化日志
init_log() {
    local build_dir="$1"
    cd "$build_dir"
    mkdir -p logs
    echo "=== 智能包匹配器启动 ===" > logs/package_matcher.log
    echo "时间: $(date)" >> logs/package_matcher.log
}

# 获取可用包列表 - 修复版：确保获取完整列表
get_available() {
    local build_dir="$1"
    cd "$build_dir"
    
    # 确保feeds已更新
    if [ ! -f "feeds.conf.default" ]; then
        log_warning "feeds.conf.default 不存在，使用默认feeds配置"
        echo "src-git packages https://github.com/immortalwrt/packages.git;openwrt-23.05" > feeds.conf.default
        echo "src-git luci https://github.com/immortalwrt/luci.git;openwrt-23.05" >> feeds.conf.default
        echo "src-git routing https://github.com/openwrt/routing.git;openwrt-23.05" >> feeds.conf.default
        echo "src-git telephony https://github.com/openwrt/telephony.git;openwrt-23.05" >> feeds.conf.default
    fi
    
    # 更新feeds
    ./scripts/feeds update -a > /dev/null 2>&1
    
    # 获取所有可用包 - 修复版：搜索所有feeds
    local packages=$(./scripts/feeds list -r packages -r luci -r routing -r telephony 2>/dev/null | cut -d' ' -f1 | sort | uniq)
    
    if [ -z "$packages" ]; then
        log_error "无法获取可用包列表"
        return 1
    fi
    
    echo "$packages"
    return 0
}

# 智能包匹配 - 修复版：改进匹配算法
smart_package_match() {
    local target_pkg="$1"
    local available_packages="$2"
    
    # 记录匹配过程
    echo "[COMMAND] 智能匹配包: $target_pkg" >> logs/package_matcher.log
    
    # 1. 直接匹配
    if echo "$available_packages" | grep -q "^$target_pkg$"; then
        echo "[PACKAGE] $target_pkg - DIRECT_MATCH - 包名直接匹配" >> logs/package_matcher.log
        echo "$target_pkg"
        return 0
    fi
    
    # 2. 忽略大小写匹配
    local matched=$(echo "$available_packages" | grep -i "^$target_pkg$" | head -1)
    if [ -n "$matched" ]; then
        echo "[PACKAGE] $target_pkg - CASE_INSENSITIVE_MATCH - 忽略大小写匹配: $matched" >> logs/package_matcher.log
        echo "$matched"
        return 0
    fi
    
    # 3. 前缀匹配（更宽松的匹配）
    matched=$(echo "$available_packages" | grep -i "^$target_pkg" | head -1)
    if [ -n "$matched" ]; then
        echo "[PACKAGE] $target_pkg - PREFIX_MATCH - 前缀匹配: $matched" >> logs/package_matcher.log
        echo "$matched"
        return 0
    fi
    
    # 4. 包含匹配
    matched=$(echo "$available_packages" | grep -i "$target_pkg" | head -1)
    if [ -n "$matched" ]; then
        echo "[PACKAGE] $target_pkg - CONTAINS_MATCH - 包含匹配: $matched" >> logs/package_matcher.log
        echo "$matched"
        return 0
    fi
    
    # 5. 常见包名映射
    local package_mapping=$(get_package_mapping "$target_pkg")
    if [ -n "$package_mapping" ]; then
        if echo "$available_packages" | grep -q "^$package_mapping$"; then
            echo "[PACKAGE] $target_pkg - MAPPED_MATCH - 映射匹配: $package_mapping" >> logs/package_matcher.log
            echo "$package_mapping"
            return 0
        fi
    fi
    
    # 6. 尝试移除版本号匹配
    local clean_pkg=$(echo "$target_pkg" | sed 's/-[0-9].*$//')
    if [ "$clean_pkg" != "$target_pkg" ]; then
        matched=$(echo "$available_packages" | grep -i "^$clean_pkg" | head -1)
        if [ -n "$matched" ]; then
            echo "[PACKAGE] $target_pkg - CLEANED_MATCH - 清理版本号匹配: $matched" >> logs/package_matcher.log
            echo "$matched"
            return 0
        fi
    fi
    
    echo "[PACKAGE] $target_pkg - NO_MATCH - 未找到任何匹配的包" >> logs/package_matcher.log
    echo ""
    return 1
}

# 包名映射表 - 修复版：添加更多常见映射
get_package_mapping() {
    local pkg="$1"
    
    declare -A PACKAGE_MAP=(
        # 常见包名映射
        ["firewall4"]="firewall"
        ["dnsmasq-full"]="dnsmasq"
        ["kmod-usb-storage"]="kmod-usb-storage-uas"
        ["luci-app-turboacc"]="luci-app-turboacc"
        ["luci-app-samba4"]="luci-app-samba4"
        ["luci-app-smartdns"]="luci-app-smartdns"
        ["luci-app-diskman"]="luci-app-diskman"
        ["luci-app-cpulimit"]="luci-app-cpulimit"
        ["luci-app-accesscontrol"]="luci-app-accesscontrol"
        ["luci-app-vlmcsd"]="luci-app-vlmcsd"
        ["luci-app-arpbind"]="luci-app-arpbind"
        
        # 基础包映射
        ["libjson-script"]="libjson-script"
        ["jshn"]="jshn"
        ["shellsync"]="shellsync"
        ["TAR_BZIP2"]="tar"
        ["TAR_GZIP"]="tar" 
        ["TAR_XZ"]="tar"
        ["TAR_ZSTD"]="tar"
        
        # 内核模块映射
        ["kmod-fs-ext4"]="kmod-fs-ext4"
        ["kmod-fs-vfat"]="kmod-fs-vfat"
        ["kmod-fs-ntfs"]="kmod-fs-ntfs"
        ["kmod-fs-exfat"]="kmod-fs-exfat"
        
        # 系统工具映射
        ["block-mount"]="block-mount"
        ["e2fsprogs"]="e2fsprogs"
        ["fdisk"]="fdisk"
        ["blkid"]="blkid"
        ["lsblk"]="lsblk"
    )
    
    if [ -n "${PACKAGE_MAP[$pkg]}" ]; then
        echo "${PACKAGE_MAP[$pkg]}"
        return 0
    fi
    
    echo ""
    return 1
}

# 智能修复配置 - 修复版：改进修复逻辑
smart_fix_config() {
    local build_dir="$1"
    local config_file="$2"
    cd "$build_dir"
    
    log_info "=== 开始智能包匹配修复 ==="
    echo "构建目录: $build_dir"
    echo "配置文件: $config_file"
    
    # 确保feeds就绪
    echo "=== 确保feeds就绪 ==="
    ./scripts/feeds update -a > /dev/null 2>&1
    ./scripts/feeds install -a > /dev/null 2>&1
    
    # 获取可用包列表
    echo "=== 获取可用包列表 ==="
    local available_packages=$(get_available ".")
    if [ $? -ne 0 ]; then
        log_error "无法获取可用包列表"
        return 1
    fi
    
    echo "可用包数量: $(echo "$available_packages" | wc -l)"
    
    # 提取配置中的包
    local config_packages=$(grep "^CONFIG_PACKAGE_" "$config_file" | grep "=y$" | sed 's/CONFIG_PACKAGE_//;s/=y//')
    echo "配置中启用的包数量: $(echo "$config_packages" | wc -l)"
    
    # 修复统计
    local fixed_count=0
    local missing_count=0
    local ok_count=0
    
    # 创建修复报告
    echo "=== 包匹配修复报告 ===" > package_fix_report.txt
    echo "生成时间: $(date)" >> package_fix_report.txt
    echo "" >> package_fix_report.txt
    
    # 检查每个包
    for pkg in $config_packages; do
        echo "[COMMAND] 智能匹配包: $pkg"
        
        # 检查包是否可用
        if echo "$available_packages" | grep -q "^$pkg$"; then
            echo "[PACKAGE] $pkg - OK - 包名正确无需修改"
            echo "✅ $pkg - 包名正确" >> package_fix_report.txt
            ok_count=$((ok_count + 1))
            continue
        fi
        
        # 尝试智能匹配
        local matched_pkg=$(smart_package_match "$pkg" "$available_packages")
        
        if [ -n "$matched_pkg" ]; then
            # 修复包名
            sed -i "s/CONFIG_PACKAGE_${pkg}=y/CONFIG_PACKAGE_${matched_pkg}=y/g" "$config_file"
            # 移除可能的禁用配置
            sed -i "/# CONFIG_PACKAGE_${matched_pkg} is not set/d" "$config_file"
            
            echo "[PACKAGE] $pkg - FIXED - 成功修复为: $matched_pkg"
            echo "🔄 $pkg → $matched_pkg - 已修复" >> package_fix_report.txt
            fixed_count=$((fixed_count + 1))
        else
            # 禁用不可用的包
            sed -i "/CONFIG_PACKAGE_${pkg}=y/d" "$config_file"
            echo "# CONFIG_PACKAGE_${pkg} is not set" >> "$config_file"
            
            echo "[PACKAGE] $pkg - MISSING - 包不可用，已禁用"
            echo "❌ $pkg - 不可用，已禁用" >> package_fix_report.txt
            missing_count=$((missing_count + 1))
            
            log_warning "包 '$pkg' 在当前版本中不可用，已自动禁用"
        fi
    done
    
    # 检查关键包
    echo "" >> package_fix_report.txt
    echo "=== 关键包检查 ===" >> package_fix_report.txt
    check_critical_packages "$available_packages" "$config_file" >> package_fix_report.txt
    
    # 输出统计信息
    echo ""
    echo "=== 匹配结果 ==="
    log_success "修复了 $fixed_count 个包名"
    log_warning "有 $missing_count 个包未找到匹配，已自动禁用"
    log_info "$ok_count 个包名正确无需修改"
    
    echo "" >> package_fix_report.txt
    echo "=== 统计信息 ===" >> package_fix_report.txt
    echo "修复的包数量: $fixed_count" >> package_fix_report.txt
    echo "禁用的包数量: $missing_count" >> package_fix_report.txt
    echo "正确的包数量: $ok_count" >> package_fix_report.txt
    
    # 保存缺失包列表
    if [ $missing_count -gt 0 ]; then
        echo "=== 缺失包列表 ===" > missing_packages.txt
        grep "❌" package_fix_report.txt >> missing_packages.txt
        log_warning "缺失包详情已保存到: ./missing_packages.txt"
    fi
    
    log_success "包修复报告已生成: ./package_fix_report.txt"
    return 0
}

# 检查关键包 - 修复版
check_critical_packages() {
    local available_packages="$1"
    local config_file="$2"
    
    local critical_packages=(
        "firewall" "dnsmasq" "luci-base" "luci" 
        "kmod-usb-storage" "block-mount" 
        "kmod-fs-ext4" "kmod-fs-vfat"
    )
    
    local missing_critical=()
    
    for critical in "${critical_packages[@]}"; do
        # 检查配置中是否启用
        if grep -q "CONFIG_PACKAGE_${critical}=y" "$config_file"; then
            # 检查包是否可用
            if echo "$available_packages" | grep -q "^$critical$"; then
                echo "[PACKAGE] $critical - CRITICAL_OK - 关键包已启用"
            else
                echo "[PACKAGE] $critical - CRITICAL_MISSING - 关键包不可用"
                missing_critical+=("$critical")
            fi
        else
            echo "[PACKAGE] $critical - CRITICAL_DISABLED - 关键包未启用"
        fi
    done
    
    if [ ${#missing_critical[@]} -eq 0 ]; then
        echo "[SUCCESS] 所有关键包都已正确配置"
        return 0
    else
        echo "[ERROR] 缺失关键包: ${missing_critical[*]}"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    echo "OpenWrt 智能包匹配器 - 修复版"
    echo "用法: $0 <功能> [参数...]"
    echo ""
    echo "可用功能:"
    echo "  init_log             - 初始化日志 <构建目录>"
    echo "  get_available        - 获取可用包列表 <构建目录>"
    echo "  smart_package_match  - 智能包匹配 <目标包> <可用包列表>"
    echo "  smart_fix_config     - 智能修复配置 <构建目录> <配置文件>"
    echo ""
    echo "示例:"
    echo "  $0 init_log /mnt/openwrt-build"
    echo "  $0 get_available /mnt/openwrt-build"
    echo "  $0 smart_fix_config /mnt/openwrt-build .config"
}

# 主函数
main() {
    local command="$1"
    shift
    
    case "$command" in
        "init_log")
            init_log "$@"
            ;;
        "get_available")
            get_available "$@"
            ;;
        "smart_package_match")
            smart_package_match "$@"
            ;;
        "smart_fix_config")
            smart_fix_config "$@"
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
