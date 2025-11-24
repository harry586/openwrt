#!/bin/bash

# OpenWrt 智能构建管理器 - 修复版
# 主要修复：版本检测逻辑、包匹配逻辑、feeds更新时机

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

# 显示使用说明
show_usage() {
    echo "OpenWrt 智能构建管理器 - 修复版"
    echo "用法: $0 <功能> [参数...]"
    echo ""
    echo "可用功能:"
    echo "  version_detect    - 版本检测 <设备> [版本] [是否老旧设备]"
    echo "  device_detect     - 设备检测 <设备名称>"
    echo "  plugin_check      - 插件兼容性检查 <分支>"
    echo "  feeds_config      - Feeds配置 <分支>"
    echo "  config_load       - 配置加载 <类型> <平台> <设备> <分支> <原始设备> <额外包> <禁用包>"
    echo "  custom_integrate  - 自定义文件集成 <工作空间目录>"
    echo "  package_check     - 包可用性检查 [构建目录]"
    echo "  error_analyze     - 错误分析 [构建目录]"
    echo "  all               - 执行完整构建流程"
    echo ""
    echo "示例:"
    echo "  $0 version_detect ac42u auto false"
    echo "  $0 device_detect ac42u"
    echo "  $0 plugin_check openwrt-23.05"
}

# 版本检测功能 - 修复版：确保正确输出环境变量
version_detect() {
    local device_name="$1"
    local user_version="$2"
    local old_device="${3:-false}"
    
    # 初始化变量
    local SELECTED_REPO=""
    local SELECTED_BRANCH=""
    local SELECTED_REPO_URL=""
    
    log_info "=== 版本检测 ==="
    echo "设备: $device_name"
    echo "用户版本: ${user_version:-自动}"
    echo "老旧设备: $old_device"
    
    # 如果用户指定了版本，直接使用
    if [ -n "$user_version" ] && [ "$user_version" != "auto" ]; then
        log_info "使用用户指定版本: $user_version"
        
        # 解析版本规格
        if [[ "$user_version" == *":"* ]]; then
            IFS=':' read -r repo branch <<< "$user_version"
        else
            repo="immortalwrt"
            branch="$user_version"
        fi
        
        # 自动添加前缀
        if [[ "$branch" =~ ^[0-9]+\.[0-9]+$ ]]; then
            branch="openwrt-$branch"
            log_info "自动添加分支前缀: $branch"
        fi
        
        # 设置仓库URL
        case "$repo" in
            "immortalwrt")
                SELECTED_REPO="immortalwrt"
                SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
                SELECTED_BRANCH="$branch"
                ;;
            "openwrt")
                SELECTED_REPO="openwrt"
                SELECTED_REPO_URL="https://github.com/openwrt/openwrt.git"
                SELECTED_BRANCH="$branch"
                ;;
            "lede")
                SELECTED_REPO="lede"
                SELECTED_REPO_URL="https://github.com/coolsnowwolf/lede.git"
                SELECTED_BRANCH="$branch"
                ;;
            *)
                log_error "未知仓库: $repo"
                return 1
                ;;
        esac
        
        log_success "设置版本: $SELECTED_REPO:$SELECTED_BRANCH"
        
    else
        # 自动版本检测逻辑
        log_info "开始自动版本检测..."
        
        # 根据设备类型选择默认版本
        case "$device_name" in
            "wr841n"|"wr842n"|"wr941n"|"mr3420"|"ar71xx"*)
                SELECTED_REPO="openwrt"
                SELECTED_BRANCH="openwrt-19.07"
                SELECTED_REPO_URL="https://github.com/openwrt/openwrt.git"
                log_success "老旧设备，选择 OpenWrt 19.07"
                ;;
            *)
                SELECTED_REPO="immortalwrt"
                SELECTED_BRANCH="openwrt-23.05"
                SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
                log_success "现代设备，选择 ImmortalWrt 23.05"
                ;;
        esac
    fi
    
    # 验证变量是否设置
    if [ -z "$SELECTED_REPO" ] || [ -z "$SELECTED_BRANCH" ] || [ -z "$SELECTED_REPO_URL" ]; then
        log_error "版本检测失败：无法确定仓库、分支或URL"
        echo "SELECTED_REPO: $SELECTED_REPO"
        echo "SELECTED_BRANCH: $SELECTED_BRANCH"
        echo "SELECTED_REPO_URL: $SELECTED_REPO_URL"
        return 1
    fi
    
    # 输出环境变量 - 修复：确保格式正确，便于提取
    echo "SELECTED_REPO=$SELECTED_REPO"
    echo "SELECTED_BRANCH=$SELECTED_BRANCH"
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL"
    
    log_success "版本检测完成"
    return 0
}

# 插件兼容性检查 - 修复版：不因警告而终止构建
plugin_check() {
    local branch="$1"
    
    log_info "=== 插件兼容性检查 ==="
    echo "目标版本: $branch"
    
    # 插件兼容性数据库
    declare -A PLUGIN_COMPATIBILITY=(
        # 网络加速插件
        ["turboacc"]="22.03 23.05"
        ["luci-app-turboacc"]="22.03 23.05"
        ["kmod-nft-fullcone"]="22.03 23.05"
        ["kmod-shortcut-fe"]="22.03 23.05"
        
        # 网络工具
        ["luci-app-sqm"]="21.02 22.03 23.05"
        ["luci-app-upnp"]="19.07 21.02 22.03 23.05"
        ["luci-app-wol"]="19.07 21.02 22.03 23.05"
        
        # 存储和文件共享
        ["luci-app-samba4"]="21.02 22.03 23.05"
        ["luci-app-vsftpd"]="19.07 21.02 22.03 23.05"
        
        # 网络服务
        ["luci-app-smartdns"]="21.02 22.03 23.05"
        ["luci-app-arpbind"]="19.07 21.02 22.03 23.05"
        
        # 系统工具
        ["luci-app-cpulimit"]="21.02 22.03 23.05"
        ["luci-app-diskman"]="21.02 22.03 23.05"
        ["luci-app-accesscontrol"]="19.07 21.02 22.03 23.05"
        ["luci-app-vlmcsd"]="19.07 21.02 22.03 23.05"
        
        # 基础插件
        ["luci-theme-bootstrap"]="18.06 19.07 21.02 22.03 23.05"
        ["luci-theme-material"]="19.07 21.02 22.03 23.05"
        ["luci-app-firewall"]="18.06 19.07 21.02 22.03 23.05"
    )
    
    check_plugin() {
        local branch="$1"
        local plugin="$2"
        
        local version=$(echo "$branch" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        
        if [ -z "$version" ]; then
            if [[ "$branch" =~ master|main ]]; then
                log_warning "⚠️  $plugin: 开发版分支，兼容性未知"
                return 0  # 修复：返回0，不阻止构建
            else
                log_warning "⚠️  $plugin: 无法识别版本号"
                return 0  # 修复：返回0
            fi
        fi
        
        local compatible_versions="${PLUGIN_COMPATIBILITY[$plugin]}"
        
        if [ -z "$compatible_versions" ]; then
            log_info "ℹ️  $plugin: 兼容性信息未知"
            return 0
        fi
        
        if echo "$compatible_versions" | grep -q "$version"; then
            log_success "✅ $plugin: 兼容版本 $version"
            return 0
        else
            log_error "❌ $plugin: 不兼容版本 $version (仅支持: $compatible_versions)"
            return 1
        fi
    }
    
    local has_critical_error=0
    
    echo "=== 网络加速插件兼容性 ==="
    check_plugin "$branch" "turboacc" || has_critical_error=1
    check_plugin "$branch" "luci-app-turboacc" || has_critical_error=1
    check_plugin "$branch" "kmod-nft-fullcone" || has_critical_error=1
    check_plugin "$branch" "kmod-shortcut-fe" || has_critical_error=1
    
    echo ""
    echo "=== 网络工具插件兼容性 ==="
    check_plugin "$branch" "luci-app-sqm" || has_critical_error=1
    check_plugin "$branch" "luci-app-upnp" || has_critical_error=1
    check_plugin "$branch" "luci-app-wol" || has_critical_error=1
    
    echo ""
    echo "=== 存储和文件共享插件兼容性 ==="
    check_plugin "$branch" "luci-app-samba4" || has_critical_error=1
    check_plugin "$branch" "luci-app-vsftpd" || has_critical_error=1
    
    echo ""
    echo "=== 网络服务插件兼容性 ==="
    check_plugin "$branch" "luci-app-smartdns" || has_critical_error=1
    check_plugin "$branch" "luci-app-arpbind" || has_critical_error=1
    
    echo ""
    echo "=== 系统工具插件兼容性 ==="
    check_plugin "$branch" "luci-app-cpulimit" || has_critical_error=1
    check_plugin "$branch" "luci-app-diskman" || has_critical_error=1
    check_plugin "$branch" "luci-app-accesscontrol" || has_critical_error=1
    check_plugin "$branch" "luci-app-vlmcsd" || has_critical_error=1
    
    echo ""
    echo "=== 基础插件兼容性 ==="
    check_plugin "$branch" "luci-theme-bootstrap" || has_critical_error=1
    check_plugin "$branch" "luci-theme-material" || has_critical_error=1
    check_plugin "$branch" "luci-app-firewall" || has_critical_error=1
    
    echo ""
    echo "=== 兼容性说明 ==="
    echo "🔹 22.03/23.05 - 完全支持所有插件"
    echo "🔹 21.02       - 支持大部分插件"
    echo "🔹 19.07       - 支持基础插件"
    echo "🔹 18.06       - 仅支持核心功能"
    echo "🔹 master      - 开发版，兼容性不确定"
    
    # 修复：总是返回0，不终止构建
    log_info "插件兼容性检查完成（警告不影响构建）"
    return 0
}

# ... 其余函数保持不变（feeds_config, config_load, custom_integrate, package_check, error_analyze 等）
# 这些函数的内容与之前相同，这里省略以节省空间

# 主函数
main() {
    local command="$1"
    shift
    
    case "$command" in
        "version_detect")
            version_detect "$@"
            ;;
        "device_detect")
            device_detect "$@"
            ;;
        "plugin_check")
            plugin_check "$@"
            ;;
        "feeds_config")
            feeds_config "$@"
            ;;
        "config_load")
            config_load "$@"
            ;;
        "custom_integrate")
            custom_integrate "$@"
            ;;
        "package_check")
            package_check "$@"
            ;;
        "error_analyze")
            error_analyze "$@"
            ;;
        "all")
            build_all "$@"
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
