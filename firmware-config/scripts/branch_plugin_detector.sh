#!/bin/bash

# OpenWrt 分支插件检测器 - 工作流专用版
# 修复版：确保插件列表文件正确保存和统计

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# 验证分支并检测插件
validate_branch() {
    local repo_url="$1"
    local branch="$2"
    local output_file="${3:-verified_plugins.txt}"
    
    echo "== 开始分支验证和插件检测 =="
    echo "仓库: $repo_url"
    echo "分支: $branch"
    echo "输出文件: $output_file"
    
    # 获取当前工作目录（BUILD_DIR）
    local current_dir=$(pwd)
    log_info "当前工作目录: $current_dir"
    
    # 严格验证分支是否存在
    log_info "验证分支是否存在..."
    if ! git ls-remote --heads "$repo_url" "$branch" | grep -q "$branch"; then
        log_error "错误: 分支 $branch 不存在"
        echo ""
        echo "可用的分支:"
        git ls-remote --heads "$repo_url" | sed 's?.*refs/heads/??' | head -10
        return 1
    fi
    
    log_success "分支 $branch 存在"
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    log_info "创建临时目录: $temp_dir"
    
    # 克隆分支
    log_info "克隆分支 $branch ..."
    if ! git clone --depth 1 --branch "$branch" "$repo_url" "$temp_dir" 2>&1; then
        log_error "分支克隆失败"
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_success "分支克隆成功"
    
    # 进入目录并检测插件
    cd "$temp_dir"
    
    # 配置feeds
    log_info "配置feeds..."
    detect_feeds_branch "$branch"
    
    # 更新feeds
    log_info "更新feeds..."
    if ! ./scripts/feeds update -a > ./feeds_update.log 2>&1; then
        log_warning "Feeds 更新有警告，继续检测..."
        cat ./feeds_update.log | tail -5
    fi
    
    # 生成插件列表到临时文件
    local temp_output="/tmp/temp_plugins_$$.txt"
    generate_plugin_list "$temp_output"
    
    # 返回原始目录并复制文件
    cd "$current_dir"
    
    # 复制插件列表到最终位置
    if [ -f "$temp_output" ]; then
        cp "$temp_output" "$output_file"
        log_success "插件列表已保存到: $output_file"
        
        # 验证文件内容
        if [ -f "$output_file" ]; then
            local total_plugins=$(count_plugins "$output_file")
            log_info "验证: 输出文件包含 $total_plugins 个插件"
            
            # 显示文件信息
            echo "=== 文件信息 ==="
            echo "文件大小: $(wc -l < "$output_file") 行"
            echo "文件路径: $(pwd)/$output_file"
            
        else
            log_error "错误: 输出文件未创建: $output_file"
            rm -rf "$temp_dir"
            rm -f "$temp_output"
            return 1
        fi
    else
        log_error "错误: 临时插件列表文件未创建"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
    rm -f "$temp_output"
    
    log_success "插件检测完成"
    return 0
}

# 统计插件数量
count_plugins() {
    local file="$1"
    # 计算以 "- \`" 开头的行数
    grep -c "^- \`" "$file" 2>/dev/null || echo "0"
}

# 检测feeds分支
detect_feeds_branch() {
    local branch="$1"
    local feeds_branch="$branch"
    
    case "$branch" in
        *23.05*) feeds_branch="openwrt-23.05" ;;
        *22.03*) feeds_branch="openwrt-22.03" ;;
        *21.02*) feeds_branch="openwrt-21.02" ;;
        *19.07*) feeds_branch="openwrt-19.07" ;;
        *) feeds_branch="master" ;;
    esac
    
    log_info "使用 feeds 分支: $feeds_branch"
    
    cat > feeds.conf.default << EOF
src-git packages https://github.com/immortalwrt/packages.git;$feeds_branch
src-git luci https://github.com/immortalwrt/luci.git;$feeds_branch
src-git routing https://github.com/openwrt/routing.git;$feeds_branch
src-git telephony https://github.com/openwrt/telephony.git;$feeds_branch
EOF
}

# 生成插件列表
generate_plugin_list() {
    local output_file="$1"
    
    log_info "生成插件列表到: $output_file"
    
    # 创建输出文件
    {
    echo "=================================================="
    echo "          OpenWrt 分支插件验证列表"
    echo "=================================================="
    echo ""
    echo "📅 生成时间: $(date)"
    echo "📦 仓库: $repo_url"
    echo "🌿 分支: $branch"
    echo ""
    echo "📖 使用说明:"
    echo "此文件包含在分支 $branch 中验证存在的所有插件。"
    echo "请只使用此列表中的插件名称，确保构建成功。"
    echo ""
    } > "$output_file"
    
    # 检测 Luci 插件
    {
    echo "## 🎯 Luci 界面插件 (Web管理界面)"
    echo ""
    } >> "$output_file"
    
    local luci_plugins=$(./scripts/feeds list -r luci 2>/dev/null | grep "luci-app" | cut -d' ' -f1 | sort | uniq || true)
    if [ -n "$luci_plugins" ]; then
        for plugin in $luci_plugins; do
            echo "- \`$plugin\`" >> "$output_file"
        done
        echo "" >> "$output_file"
        echo "> 💡 提示: Luci 插件提供 Web 管理界面" >> "$output_file"
    else
        echo "# 未找到 Luci 插件" >> "$output_file"
    fi
    echo "" >> "$output_file"
    
    # 检测内核模块
    {
    echo "## 🔧 内核模块插件 (硬件驱动)"
    echo ""
    } >> "$output_file"
    
    local kmod_plugins=$(./scripts/feeds list -r packages 2>/dev/null | grep "kmod-" | head -50 | cut -d' ' -f1 | sort | uniq || true)
    if [ -n "$kmod_plugins" ]; then
        for plugin in $kmod_plugins; do
            echo "- \`$plugin\`" >> "$output_file"
        done
    else
        echo "# 未找到内核模块插件" >> "$output_file"
    fi
    echo "" >> "$output_file"
    
    # 检测常用插件
    {
    echo "## 🌐 常用功能插件"
    echo ""
    } >> "$output_file"
    
    local common_keywords="turboacc upnp sqm ddns adblock smartdns wireguard shadowsocks v2ray trojan openvpn samba vsftpd transmission aria2"
    local common_plugins=""
    
    for keyword in $common_keywords; do
        local found_plugins=$(./scripts/feeds list -r packages 2>/dev/null | grep -i "$keyword" | cut -d' ' -f1 | head -10 || true)
        common_plugins="$common_plugins $found_plugins"
    done
    
    common_plugins=$(echo "$common_plugins" | tr ' ' '\n' | sort -u)
    
    if [ -n "$common_plugins" ]; then
        for plugin in $common_plugins; do
            echo "- \`$plugin\`" >> "$output_file"
        done
    else
        echo "# 未找到常用插件" >> "$output_file"
    fi
    echo "" >> "$output_file"
    
    # 统计信息
    local total_plugins=$(count_plugins "$output_file")
    {
    echo "## 📊 统计信息"
    echo ""
    echo "- 总插件数量: $total_plugins"
    echo "- 验证状态: ✅ 成功"
    echo "- 检测完成时间: $(date)"
    echo ""
    echo "=================================================="
    echo "                   验证完成"
    echo "=================================================="
    } >> "$output_file"
    
    log_info "检测到 $total_plugins 个插件"
}

# 主函数
main() {
    case "$1" in
        "validate_branch")
            if [ $# -lt 3 ]; then
                log_error "参数不足"
                echo "用法: $0 validate_branch <仓库URL> <分支> [输出文件]"
                exit 1
            fi
            validate_branch "$2" "$3" "$4"
            ;;
        *)
            echo "OpenWrt 分支插件检测器 - 工作流专用版"
            echo ""
            echo "用法: $0 validate_branch <仓库URL> <分支> [输出文件]"
            echo ""
            echo "示例:"
            echo "  $0 validate_branch https://github.com/immortalwrt/immortalwrt.git openwrt-23.05"
            echo ""
            exit 1
            ;;
    esac
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
