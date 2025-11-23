#!/bin/bash

# OpenWrt 智能包匹配器 - 动态适配不同版本
# 功能：自动检测可用包，智能替换配置中的包名，详细日志记录

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/mnt/openwrt-build/build.log"

log_info() { 
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE"
}

log_success() { 
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "$LOG_FILE"
}

log_warning() { 
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "$LOG_FILE"
}

log_error() { 
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}=== $1 ===${NC}"
    echo "=== $1 ===" >> "$LOG_FILE"
}

# 初始化日志
init_log() {
    local build_dir="$1"
    LOG_FILE="$build_dir/build.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    echo "=== OpenWrt 构建日志 ===" > "$LOG_FILE"
    echo "开始时间: $(date)" >> "$LOG_FILE"
    echo "构建目录: $build_dir" >> "$LOG_FILE"
    echo "==========================================" >> "$LOG_FILE"
}

# 记录命令执行
log_command() {
    echo "[COMMAND] $1" >> "$LOG_FILE"
    echo "命令输出:" >> "$LOG_FILE"
}

# 记录包处理结果
log_package_result() {
    local package="$1"
    local status="$2"
    local message="$3"
    
    echo "[PACKAGE] $package - $status - $message" >> "$LOG_FILE"
}

# 获取所有可用包列表
get_available_packages() {
    local build_dir="$1"
    cd "$build_dir"
    
    log_command "更新feeds并获取包列表"
    ./scripts/feeds update -a >> "$LOG_FILE" 2>&1
    ./scripts/feeds list | cut -d' ' -f1 | sort | uniq
}

# 智能包名匹配
smart_package_match() {
    local original_pkg="$1"
    local available_packages="$2"
    
    log_command "智能匹配包: $original_pkg"
    
    # 如果包名直接存在，直接返回
    if echo "$available_packages" | grep -q "^$original_pkg$"; then
        log_package_result "$original_pkg" "DIRECT_MATCH" "包名直接匹配"
        echo "$original_pkg"
        return 0
    fi
    
    # 常见包名变体匹配
    local variants=()
    
    # 内核模块变体
    if [[ "$original_pkg" == kmod-* ]]; then
        local base_name="${original_pkg#kmod-}"
        variants=(
            "$original_pkg"
            "kmod-$base_name"
            "$base_name"
        )
        
        # 特定内核模块映射
        case "$base_name" in
            "fs-ntfs") variants+=("kmod-fs-ntfs3") ;;
            "nft-fullcone") variants+=("kmod-nft-fullcone") ;;
            "tcp-bbr") variants+=("kmod-tcp-bbr") ;;
        esac
        
        log_package_result "$original_pkg" "KERNEL_VARIANT" "内核模块变体: ${variants[*]}"
    fi
    
    # Luci应用变体
    if [[ "$original_pkg" == luci-* ]]; then
        variants=(
            "$original_pkg"
            "${original_pkg//app-/}"
            "${original_pkg//i18n-/}"
            "${original_pkg//theme-/}"
        )
        log_package_result "$original_pkg" "LUCI_VARIANT" "Luci应用变体: ${variants[*]}"
    fi
    
    # 网络工具变体
    if [[ "$original_pkg" == *dnsmasq* ]]; then
        variants=("$original_pkg" "dnsmasq" "dnsmasq-full")
        log_package_result "$original_pkg" "DNSMASQ_VARIANT" "DNS工具变体: ${variants[*]}"
    fi
    
    if [[ "$original_pkg" == *hostapd* ]]; then
        variants=("$original_pkg" "hostapd" "hostapd-common" "hostapd-utils")
        log_package_result "$original_pkg" "HOSTAPD_VARIANT" "无线AP变体: ${variants[*]}"
    fi
    
    if [[ "$original_pkg" == *wpad* ]]; then
        variants=("$original_pkg" "wpad" "wpad-basic" "wpad-openssl" "wpad-wolfssl")
        log_package_result "$original_pkg" "WPAD_VARIANT" "WPA工具变体: ${variants[*]}"
    fi
    
    # 系统工具变体
    case "$original_pkg" in
        "firewall") 
            variants=("$original_pkg" "firewall4")
            log_package_result "$original_pkg" "FIREWALL_VARIANT" "防火墙变体: ${variants[*]}"
            ;;
        "odhcpd") 
            variants=("$original_pkg" "odhcpd")
            log_package_result "$original_pkg" "ODHCPD_VARIANT" "DHCP服务变体: ${variants[*]}"
            ;;
        "block-mount") 
            variants=("$original_pkg" "block-mount")
            log_package_result "$original_pkg" "BLOCKMOUNT_VARIANT" "块挂载变体: ${variants[*]}"
            ;;
    esac
    
    # 检查所有变体
    for variant in "${variants[@]}"; do
        if echo "$available_packages" | grep -q "^$variant$"; then
            log_package_result "$original_pkg" "VARIANT_MATCH" "变体匹配: $variant"
            echo "$variant"
            return 0
        fi
    done
    
    # 如果都没有找到，尝试模糊匹配
    local fuzzy_match=$(echo "$available_packages" | grep -i "$original_pkg" | head -1)
    if [ -n "$fuzzy_match" ]; then
        log_package_result "$original_pkg" "FUZZY_MATCH" "模糊匹配: $fuzzy_match"
        echo "$fuzzy_match"
        return 0
    fi
    
    # 最后尝试去掉前缀后缀匹配
    local simplified=$(echo "$original_pkg" | sed 's/^kmod-//;s/^luci-//;s/^lib//;s/-full$//;s/-utils$//')
    local final_match=$(echo "$available_packages" | grep -i "$simplified" | head -1)
    if [ -n "$final_match" ]; then
        log_package_result "$original_pkg" "SIMPLIFIED_MATCH" "简化匹配: $final_match"
        echo "$final_match"
        return 0
    fi
    
    # 没有找到匹配
    log_package_result "$original_pkg" "NO_MATCH" "未找到任何匹配的包"
    return 1
}

# 智能修复配置文件
smart_fix_config() {
    local build_dir="$1"
    local config_file="$2"
    
    cd "$build_dir"
    
    log_step "智能包匹配"
    echo "构建目录: $build_dir"
    echo "配置文件: $config_file"
    
    if [ ! -f "$config_file" ]; then
        log_error "配置文件不存在: $config_file"
        return 1
    fi
    
    # 备份原配置
    cp "$config_file" "${config_file}.backup"
    log_info "已备份配置文件: ${config_file}.backup"
    
    # 获取可用包列表
    log_info "获取可用包列表..."
    local available_packages=$(get_available_packages "$build_dir")
    local available_count=$(echo "$available_packages" | wc -l)
    echo "可用包数量: $available_count"
    
    # 提取配置中的包
    local config_packages=$(grep "^CONFIG_PACKAGE_.*=y" "$config_file" | sed 's/CONFIG_PACKAGE_//;s/=y//')
    local total_packages=$(echo "$config_packages" | wc -l)
    
    log_info "配置中启用的包数量: $total_packages"
    
    local fixed_count=0
    local missing_count=0
    local missing_packages=()
    
    # 创建缺失包报告文件
    local missing_report="$build_dir/missing_packages.txt"
    echo "=== 缺失包报告 ===" > "$missing_report"
    echo "生成时间: $(date)" >> "$missing_report"
    echo "配置文件: $config_file" >> "$missing_report"
    echo "==========================================" >> "$missing_report"
    
    # 处理每个包
    while IFS= read -r original_pkg; do
        if [ -z "$original_pkg" ]; then
            continue
        fi
        
        local matched_pkg=$(smart_package_match "$original_pkg" "$available_packages")
        
        if [ -n "$matched_pkg" ] && [ "$matched_pkg" != "$original_pkg" ]; then
            # 替换包名
            sed -i "s/CONFIG_PACKAGE_${original_pkg}=y/CONFIG_PACKAGE_${matched_pkg}=y/" "$config_file"
            echo "✅ $original_pkg → $matched_pkg"
            fixed_count=$((fixed_count + 1))
            log_package_result "$original_pkg" "FIXED" "成功修复为: $matched_pkg"
        elif [ -n "$matched_pkg" ]; then
            echo "✅ $original_pkg (无需修改)"
            log_package_result "$original_pkg" "OK" "包名正确无需修改"
        else
            # 注释掉不存在的包
            sed -i "s/CONFIG_PACKAGE_${original_pkg}=y/# CONFIG_PACKAGE_${original_pkg} is not set/" "$config_file"
            echo "❌ $original_pkg (未找到匹配，已禁用)"
            missing_count=$((missing_count + 1))
            missing_packages+=("$original_pkg")
            
            # 记录到缺失包报告
            echo "❌ $original_pkg" >> "$missing_report"
            log_package_result "$original_pkg" "MISSING" "包不可用，已禁用"
            
            # 在控制台显示警告
            log_warning "包 '$original_pkg' 在当前版本中不可用，已自动禁用"
        fi
    done <<< "$config_packages"
    
    # 重新运行defconfig确保配置正确
    make -j1 defconfig >> "$LOG_FILE" 2>&1
    
    echo ""
    log_step "匹配结果"
    log_success "修复了 $fixed_count 个包名"
    
    if [ $missing_count -gt 0 ]; then
        log_warning "有 $missing_count 个包未找到匹配，已自动禁用"
        echo "==========================================" >> "$missing_report"
        echo "总计缺失包数量: $missing_count" >> "$missing_report"
        echo "这些包已在配置文件中禁用" >> "$missing_report"
        
        log_warning "缺失包详情已保存到: $missing_report"
        echo "=== 缺失包列表 ==="
        for pkg in "${missing_packages[@]}"; do
            echo "  ❌ $pkg"
        done
    fi
    
    # 检查关键包
    check_critical_packages "$build_dir"
    
    # 生成修复报告
    generate_fix_report "$build_dir" "$fixed_count" "$missing_count" "${missing_packages[@]}"
}

# 生成修复报告
generate_fix_report() {
    local build_dir="$1"
    local fixed_count="$2"
    local missing_count="$3"
    shift 3
    local missing_packages=("$@")
    
    local report_file="$build_dir/package_fix_report.txt"
    
    echo "=== 包修复报告 ===" > "$report_file"
    echo "生成时间: $(date)" >> "$report_file"
    echo "==========================================" >> "$report_file"
    echo "" >> "$report_file"
    
    echo "修复统计:" >> "$report_file"
    echo "✅ 成功修复包数量: $fixed_count" >> "$report_file"
    echo "❌ 缺失包数量: $missing_count" >> "$report_file"
    echo "" >> "$report_file"
    
    if [ $missing_count -gt 0 ]; then
        echo "缺失包列表:" >> "$report_file"
        for pkg in "${missing_packages[@]}"; do
            echo "❌ $pkg" >> "$report_file"
        done
        echo "" >> "$report_file"
        echo "注意: 这些包已在配置文件中自动禁用" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "详细日志请查看: $LOG_FILE" >> "$report_file"
    
    log_info "包修复报告已生成: $report_file"
}

# 检查关键包
check_critical_packages() {
    local build_dir="$1"
    cd "$build_dir"
    
    log_step "关键包检查"
    
    # 定义关键包（按优先级排序）
    local critical_packages=(
        "firewall4" "firewall" 
        "dnsmasq-full" "dnsmasq"
        "luci-base" "luci"
        "kmod-usb-storage"
        "block-mount"
        "kmod-fs-ext4"
        "kmod-fs-vfat"
    )
    
    local missing_critical=0
    local available_packages=$(get_available_packages "$build_dir")
    
    for pkg in "${critical_packages[@]}"; do
        if echo "$available_packages" | grep -q "^$pkg$"; then
            if grep -q "CONFIG_PACKAGE_${pkg}=y" .config; then
                echo "✅ 关键包: $pkg"
                log_package_result "$pkg" "CRITICAL_OK" "关键包已启用"
            else
                echo "❌ 关键包未启用: $pkg"
                # 自动启用关键包
                sed -i "/# CONFIG_PACKAGE_${pkg} is not set/d" .config
                echo "CONFIG_PACKAGE_${pkg}=y" >> .config
                echo "🔄 自动启用: $pkg"
                missing_critical=$((missing_critical + 1))
                log_package_result "$pkg" "CRITICAL_ENABLED" "关键包自动启用"
            fi
        else
            echo "⚠️  关键包不可用: $pkg"
            log_package_result "$pkg" "CRITICAL_MISSING" "关键包不可用"
        fi
    done
    
    if [ $missing_critical -eq 0 ]; then
        log_success "所有关键包都已正确配置"
    else
        log_warning "自动启用了 $missing_critical 个关键包"
    fi
    
    # 重新运行defconfig
    make -j1 defconfig >> "$LOG_FILE" 2>&1
}

# 生成最小可用配置
generate_minimal_config() {
    local build_dir="$1"
    local output_file="$2"
    
    cd "$build_dir"
    
    log_step "生成最小可用配置"
    
    local available_packages=$(get_available_packages "$build_dir")
    
    # 创建基础配置
    cat > "$output_file" << 'EOF'
# OpenWrt 最小可用配置
# 自动生成时间: $(date)

CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_IMAGES_PAD=y

# 基础系统
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_dnsmasq-full=y

# 必要工具
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget=y

# 内核模块
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_fdisk=y
EOF

    # 根据可用包动态添加
    for pkg in "htop" "tree" "file" "git" "rsync"; do
        if echo "$available_packages" | grep -q "^$pkg$"; then
            echo "CONFIG_PACKAGE_${pkg}=y" >> "$output_file"
        fi
    done
    
    log_success "已生成最小配置: $output_file"
}

# 显示使用说明
show_usage() {
    echo "OpenWrt 智能包匹配器"
    echo "用法: $0 <功能> [参数...]"
    echo ""
    echo "可用功能:"
    echo "  init_log           - 初始化日志 [构建目录]"
    echo "  smart_fix_config   - 智能修复配置 [构建目录] [配置文件]"
    echo "  check_critical     - 检查关键包 [构建目录]"
    echo "  generate_minimal   - 生成最小配置 [构建目录] [输出文件]"
    echo "  get_available      - 获取可用包列表 [构建目录]"
    echo ""
    echo "示例:"
    echo "  $0 init_log /mnt/openwrt-build"
    echo "  $0 smart_fix_config /mnt/openwrt-build .config"
    echo "  $0 generate_minimal /mnt/openwrt-build minimal.config"
}

# 主函数
main() {
    local command="$1"
    shift
    
    case "$command" in
        "init_log")
            init_log "$@"
            ;;
        "smart_fix_config")
            smart_fix_config "$@"
            ;;
        "check_critical")
            check_critical_packages "$@"
            ;;
        "generate_minimal")
            generate_minimal_config "$@"
            ;;
        "get_available")
            get_available_packages "$@"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi
    main "$@"
fi
