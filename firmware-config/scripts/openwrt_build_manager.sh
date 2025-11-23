#!/bin/bash

# OpenWrt 智能构建管理器 - 整合所有核心功能
# 功能：版本检测、设备检测、插件检查、配置管理、自定义文件集成

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
    echo "OpenWrt 智能构建管理器"
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

# 配置加载 - 更新版
config_load() {
    local config_type="$1"
    local platform="$2"
    local device_short_name="$3"
    local selected_branch="$4"
    local device_name="$5"
    local extra_packages="$6"
    local disabled_plugins="$7"
    
    log_info "=== 配置加载 ==="
    echo "配置类型: $config_type"
    echo "平台: $platform"
    echo "设备: $device_short_name"
    echo "分支: $selected_branch"
    
    export MAKE_JOBS=1
    
    # 选择基础配置文件
    local config_file="config-templates/base-template.config"
    
    echo "=== 使用基础模板配置 ==="
    if [ ! -f "$config_file" ]; then
        log_error "错误: 找不到基础配置文件 $config_file"
        return 1
    fi
    
    # 创建基础配置
    echo "=== 创建基础配置 ==="
    echo "# 设备基础配置" > .config
    echo "CONFIG_TARGET_${platform}=y" >> .config
    echo "CONFIG_TARGET_${platform}_generic=y" >> .config
    echo "CONFIG_TARGET_${platform}_generic_DEVICE_${device_short_name}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    echo "CONFIG_TARGET_IMAGES_PAD=y" >> .config
    
    # 追加模板配置
    echo "=== 追加模板配置 ==="
    cat "$config_file" >> .config
    
    # 初始化日志
    echo "=== 初始化构建日志 ==="
    ./smart_package_matcher.sh init_log "."
    
    # 运行智能包匹配
    echo "=== 运行智能包匹配 ==="
    if ! ./smart_package_matcher.sh smart_fix_config "." ".config"; then
        log_error "智能包匹配失败"
        return 1
    fi
    
    # 处理用户自定义包
    if [ -n "$extra_packages" ]; then
        echo "=== 添加额外插件 ==="
        for pkg in $extra_packages; do
            echo "添加插件: $pkg"
            # 使用智能匹配找到正确的包名
            local available_packages=$(./smart_package_matcher.sh get_available ".")
            local matched_pkg=$(./smart_package_matcher.sh smart_package_match "$pkg" "$available_packages")
            if [ -n "$matched_pkg" ]; then
                # 移除可能的旧配置
                sed -i "/# CONFIG_PACKAGE_${matched_pkg} is not set/d" .config
                echo "CONFIG_PACKAGE_${matched_pkg}=y" >> .config
                echo "✅ 添加: $pkg → $matched_pkg"
            else
                echo "❌ 无法找到包: $pkg"
                log_warning "无法找到用户请求的包: $pkg"
            fi
        done
    fi
    
    if [ -n "$disabled_plugins" ]; then
        echo "=== 禁用指定插件 ==="
        for pkg in $disabled_plugins; do
            echo "禁用插件: $pkg"
            sed -i "/CONFIG_PACKAGE_${pkg}=y/d" .config
            echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
            echo "✅ 已禁用: $pkg"
        done
    fi
    
    # 运行 defconfig
    echo "=== 运行 defconfig ==="
    make -j1 defconfig
    
    # 显示最终配置状态
    echo "=== 最终启用的luci插件 ==="
    grep "^CONFIG_PACKAGE_luci-app" .config | sed 's/CONFIG_PACKAGE_//' | sed 's/=y//' | sort | uniq || echo "无luci插件"
    
    log_success "配置加载完成"
}

# 包可用性检查 - 更新版
package_check() {
    local build_dir="${1:-.}"
    cd "$build_dir"
    
    log_info "=== 包可用性检查 ==="
    
    # 更新feeds
    echo "更新feeds..."
    ./scripts/feeds update -a > /dev/null 2>&1
    
    # 读取配置文件
    CONFIG_FILE=".config"
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "错误: 配置文件 $CONFIG_FILE 不存在"
        return 1
    fi
    
    # 提取所有启用的包
    PACKAGES=$(grep "^CONFIG_PACKAGE_" "$CONFIG_FILE" | grep "=y$" | sed 's/CONFIG_PACKAGE_//;s/=y//')
    
    echo "在 $CONFIG_FILE 中启用的包数量: $(echo "$PACKAGES" | wc -l)"
    
    # 检查每个包是否在feeds中
    MISSING_PACKAGES=()
    AVAILABLE_PACKAGES=()
    
    # 预加载feeds列表到内存
    local feeds_list=$(./scripts/feeds list 2>/dev/null)
    
    echo "=== 开始检查包可用性 ==="
    
    # 检查每个包
    for pkg in $PACKAGES; do
        if echo "$feeds_list" | grep -q "^$pkg"; then
            AVAILABLE_PACKAGES+=("$pkg")
            echo "✅ $pkg"
        else
            MISSING_PACKAGES+=("$pkg")
            echo "❌ $pkg (在feeds中未找到)"
            log_warning "包 '$pkg' 在feeds中不可用"
        fi
    done
    
    echo ""
    echo "=== 检查结果 ==="
    echo "可用的包数量: ${#AVAILABLE_PACKAGES[@]}"
    echo "缺失的包数量: ${#MISSING_PACKAGES[@]}"
    
    if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
        echo ""
        echo "=== 缺失的包 ==="
        for pkg in "${MISSING_PACKAGES[@]}"; do
            echo "  ❌ $pkg"
        done
        
        echo ""
        echo "=== 建议的解决方案 ==="
        echo "1. 运行智能包匹配: ./smart_package_matcher.sh smart_fix_config . .config"
        echo "2. 手动更新 feeds: ./scripts/feeds update -a && ./scripts/feeds install -a"
        echo "3. 使用 make menuconfig 查看可用的包"
        
        # 检查关键包是否缺失
        CRITICAL_PACKAGES=("firewall" "dnsmasq" "kmod-usb-storage" "block-mount" "luci-base")
        critical_missing=0
        
        for critical in "${CRITICAL_PACKAGES[@]}"; do
            for missing in "${MISSING_PACKAGES[@]}"; do
                if [ "$missing" = "$critical" ]; then
                    echo "❌ 关键包缺失: $critical"
                    critical_missing=1
                    log_error "关键包 '$critical' 缺失"
                fi
            done
        done
        
        if [ $critical_missing -eq 1 ]; then
            log_error "有关键包缺失，构建将停止"
            return 1
        else
            log_warning "有非关键包缺失，但构建可以继续"
            return 0
        fi
    else
        log_success "所有包都在feeds中可用"
        return 0
    fi
}

# 其他函数保持不变...
# [这里包含原来的 version_detect, device_detect, plugin_check, feeds_config, custom_integrate, error_analyze 等函数]

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
