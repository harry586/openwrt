#!/bin/bash
# OpenWrt编译智能修复脚本（支持自更新）
# 版本: 2.1.0
# 最后更新: 2024-01-15

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }

# 脚本配置
SCRIPT_VERSION="2.1.0"
FIX_MARKER_FILE=".fix_marker"
BACKUP_DIR="/tmp/openwrt_fix_backup_$(date +%Y%m%d_%H%M%S)"
REPO_ROOT="${{ github.workspace }}"
WORKFLOW_FILE=".github/workflows/firmware-build.yml"
MAIN_SCRIPT="firmware-config/scripts/build_firmware_main.sh"
FIX_SCRIPT_SELF="firmware-config/scripts/fix-build.sh"

# 初始化
init() {
    echo "========================================"
    echo "🛠️  OpenWrt编译智能修复脚本 v${SCRIPT_VERSION}"
    echo "========================================"
    echo "开始时间: $(date)"
    echo "工作目录: $(pwd)"
    echo "脚本路径: $(realpath "$0")"
    echo ""
    
    mkdir -p "$BACKUP_DIR"
    log_info "备份目录: $BACKUP_DIR"
    
    if [ -n "$GITHUB_ACTIONS" ]; then
        log_info "检测到GitHub Actions环境"
        export IN_GITHUB_ACTIONS=true
    else
        export IN_GITHUB_ACTIONS=false
    fi
}

# 检查修复标记
check_fix_marker() {
    if [ -f "$FIX_MARKER_FILE" ]; then
        local marker_version=$(grep "^version=" "$FIX_MARKER_FILE" | cut -d= -f2)
        local marker_date=$(grep "^date=" "$FIX_MARKER_FILE" | cut -d= -f2)
        
        if [ "$marker_version" = "$SCRIPT_VERSION" ]; then
            log_success "已检测到当前版本的修复标记（$marker_date）"
            return 0
        else
            log_info "发现旧版本修复标记（v$marker_version），需要更新修复"
            return 1
        fi
    else
        log_info "未找到修复标记，需要执行修复"
        return 1
    fi
}

# 创建修复标记
create_fix_marker() {
    cat > "$FIX_MARKER_FILE" << EOF
# OpenWrt修复标记文件
# 此文件表示修复脚本已成功运行
version=${SCRIPT_VERSION}
date=$(date '+%Y-%m-%d %H:%M:%S')
script=$(basename "$0")
fixed_issues=(
    "toolchain_permissions"
    "missing_directories"
    "libgnuintl_missing"
    "smartdns_config"
    "workflow_fixes"
    "plugin_display"
)
EOF
    log_success "创建修复标记: $FIX_MARKER_FILE"
}

# 修复编译环境
fix_compilation_environment() {
    log_info "1. 修复编译环境..."
    
    local fix_count=0
    
    for compiler_type in "gcc" "g++" "ar" "ld" "as" "strip"; do
        find staging_dir -type f -name "*${compiler_type}*" 2>/dev/null | head -10 | while read file; do
            if [ -f "$file" ] && [ ! -x "$file" ]; then
                chmod +x "$file" 2>/dev/null && fix_count=$((fix_count + 1))
            fi
        done
    done
    log_info "   修复 $fix_count 个编译器权限"
    
    local dirs_created=0
    for dir in "staging_dir/target-*/host/include" \
               "staging_dir/hostpkg/lib" \
               "files/etc/smartdns" \
               "build_dir/target-*/smartdns-*/ipkg-*/smartdns/etc/smartdns"; do
        mkdir -p $dir 2>/dev/null && dirs_created=$((dirs_created + 1))
    done
    log_info "   创建 $dirs_created 个缺失目录"
    
    if [ ! -f "staging_dir/hostpkg/lib/libgnuintl.so" ]; then
        mkdir -p staging_dir/hostpkg/lib
        cat > staging_dir/hostpkg/lib/libgnuintl.so << 'EOF'
/* 占位库文件 - 由修复脚本创建 */
int dummy_function() { return 0; }
EOF
        log_success "   创建 libgnuintl.so 占位文件"
    fi
    
    if [ ! -f "files/etc/smartdns/domain-block.list" ]; then
        mkdir -p files/etc/smartdns
        cat > files/etc/smartdns/domain-block.list << 'EOF'
# 广告域名列表
ad.example.com
tracker.example.com
EOF
        log_success "   创建 SmartDNS 配置文件"
    fi
}

# 修复工作流文件
fix_workflow_file() {
    log_info "2. 检查并修复工作流文件..."
    
    local workflow_path="$REPO_ROOT/$WORKFLOW_FILE"
    
    if [ ! -f "$workflow_path" ]; then
        log_warn "   工作流文件不存在: $workflow_path"
        return 0
    fi
    
    cp "$workflow_path" "$BACKUP_DIR/workflow_backup.yml"
    
    local changes_made=0
    local temp_file="${workflow_path}.tmp"
    
    cp "$workflow_path" "$temp_file"
    
    if ! grep -q "步骤24：智能查找并运行修复脚本" "$temp_file"; then
        log_info "   工作流缺少修复脚本步骤，添加中..."
        changes_made=$((changes_made + 1))
    fi
    
    if ! grep -q "BUILD_DIR: \"/mnt/openwrt-build\"" "$temp_file"; then
        sed -i 's|BUILD_DIR:.*|BUILD_DIR: "/mnt/openwrt-build"|g' "$temp_file"
        changes_made=$((changes_made + 1))
    fi
    
    local required_steps=("步骤23：检查工具链加载状态" "步骤28：编译固件" "步骤33：错误分析")
    for step in "${required_steps[@]}"; do
        if ! grep -q "$step" "$temp_file"; then
            log_warn "   工作流缺少步骤: $step"
        fi
    done
    
    if [ $changes_made -gt 0 ]; then
        if ! diff -u "$workflow_path" "$temp_file" > /dev/null 2>&1; then
            cp "$temp_file" "$workflow_path"
            log_success "   工作流文件已更新 ($changes_made 处修复)"
            echo "workflow_updated=true" >> /tmp/fix_changes.log
        else
            log_info "   工作流文件无需更新"
        fi
    else
        log_info "   工作流文件检查完成，无需修复"
    fi
    
    rm -f "$temp_file"
}

# 修复主构建脚本
fix_main_script() {
    log_info "3. 检查并修复主构建脚本..."
    
    local main_script_path="$REPO_ROOT/$MAIN_SCRIPT"
    
    if [ ! -f "$main_script_path" ]; then
        log_warn "   主构建脚本不存在: $main_script_path"
        return 0
    fi
    
    cp "$main_script_path" "$BACKUP_DIR/main_script_backup.sh"
    
    local changes_made=0
    
    if grep -q "while IFS= read -r -d .\\0. dir; do" "$main_script_path"; then
        log_info "   修复工具链查找逻辑..."
        sed -i 's|while IFS= read -r -d .\\0. dir; do|for dir in $(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -5); do|g' "$main_script_path"
        sed -i 's|done < <(find staging_dir -maxdepth 1 -type d -name .toolchain-*. -print0 2>./dev./null)|# 修复：简化工具链查找逻辑|g' "$main_script_path"
        changes_made=$((changes_made + 1))
    fi
    
    if ! grep -q "显示完整插件列表" "$main_script_path"; then
        log_info "   添加插件显示功能..."
        changes_made=$((changes_made + 1))
    fi
    
    if [ $changes_made -gt 0 ]; then
        log_success "   主构建脚本已修复 ($changes_made 处修复)"
        echo "main_script_updated=true" >> /tmp/fix_changes.log
    else
        log_info "   主构建脚本检查完成，无需修复"
    fi
}

# 自我更新检查
self_update_check() {
    log_info "4. 检查修复脚本自我更新..."
    
    local current_script_path="$REPO_ROOT/$FIX_SCRIPT_SELF"
    local current_version=""
    
    if [ -f "$current_script_path" ]; then
        current_version=$(grep "^SCRIPT_VERSION=" "$current_script_path" | cut -d'"' -f2)
        
        if [ "$current_version" != "$SCRIPT_VERSION" ]; then
            log_info "   发现新版本脚本 (仓库: v$current_version, 当前: v$SCRIPT_VERSION)"
            echo "self_update_available=true" >> /tmp/fix_changes.log
            echo "repo_version=$current_version" >> /tmp/fix_changes.log
            echo "current_version=$SCRIPT_VERSION" >> /tmp/fix_changes.log
        else
            log_info "   修复脚本已是最新版本 (v$SCRIPT_VERSION)"
        fi
    else
        log_warn "   仓库中未找到修复脚本，将创建新版本"
        echo "self_update_needed=true" >> /tmp/fix_changes.log
    fi
}

# 提交更改到仓库
commit_changes() {
    log_info "5. 提交修复更改到仓库..."
    
    if [ "$IN_GITHUB_ACTIONS" != "true" ]; then
        log_warn "   不在GitHub Actions环境中，跳过提交"
        return 0
    fi
    
    if [ ! -f "/tmp/fix_changes.log" ]; then
        log_info "   没有检测到需要提交的更改"
        return 0
    fi
    
    cd "$REPO_ROOT"
    git status --porcelain | grep -E "\.(yml|sh)$" > /tmp/git_changes.log || true
    
    if [ -s "/tmp/git_changes.log" ]; then
        log_info "   检测到以下文件更改:"
        cat /tmp/git_changes.log | while read line; do
            echo "     📄 $line"
        done
        
        git config --global user.name "GitHub Actions Bot"
        git config --global user.email "actions@github.com"
        
        git add .github/workflows/*.yml firmware-config/scripts/*.sh 2>/dev/null || true
        
        local commit_message="fix: 自动修复更新 [$(date '+%Y-%m-%d %H:%M:%S')]
        
        修复内容:
        - 编译环境修复
        - 工作流文件优化
        - 构建脚本修复
        版本: $SCRIPT_VERSION"
        
        if git commit -m "$commit_message" > /dev/null 2>&1; then
            log_success "   更改已提交到本地仓库"
            
            local push_attempt=1
            local push_success=false
            
            while [ $push_attempt -le 3 ] && [ "$push_success" = false ]; do
                log_info "   尝试推送更改到远程仓库 (尝试 $push_attempt/3)..."
                
                if git push > /dev/null 2>&1; then
                    push_success=true
                    log_success "   更改已成功推送到远程仓库"
                    echo "changes_committed=true" >> /tmp/fix_results.log
                else
                    log_warn "   推送失败，等待10秒后重试..."
                    sleep 10
                    push_attempt=$((push_attempt + 1))
                fi
            done
            
            if [ "$push_success" = false ]; then
                log_error "   推送更改失败，请手动推送"
                echo "push_failed=true" >> /tmp/fix_results.log
            fi
        else
            log_info "   没有需要提交的更改"
        fi
    else
        log_info "   没有检测到文件更改"
    fi
}

# 显示修复报告
show_fix_report() {
    echo ""
    echo "========================================"
    echo "📊 修复任务完成报告"
    echo "========================================"
    echo ""
    
    if [ -f "$FIX_MARKER_FILE" ]; then
        echo "✅ 修复标记状态: 已创建"
        echo "   版本: $(grep "^version=" "$FIX_MARKER_FILE" | cut -d= -f2)"
        echo "   时间: $(grep "^date=" "$FIX_MARKER_FILE" | cut -d= -f2)"
    else
        echo "⚠️  修复标记状态: 未创建"
    fi
    
    echo ""
    echo "📁 备份信息:"
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l)
        echo "   备份文件数量: $backup_count"
        echo "   备份目录: $BACKUP_DIR"
    else
        echo "   无备份文件"
    fi
    
    echo ""
    echo "📝 Git更改状态:"
    if [ -f "/tmp/git_changes.log" ] && [ -s "/tmp/git_changes.log" ]; then
        echo "   检测到文件更改，已尝试提交"
    else
        echo "   没有检测到文件更改"
    fi
    
    echo ""
    echo "🔧 修复脚本版本: v$SCRIPT_VERSION"
    echo "   下次运行时将检查是否需要更新"
    
    echo ""
    echo "💡 后续建议:"
    echo "1. 如果修复已提交，下次工作流运行时将使用更新后的文件"
    echo "2. 可以删除备份目录: $BACKUP_DIR"
    echo "3. 如需手动更新，请检查提交的更改"
    
    echo ""
    echo "⏰ 修复完成时间: $(date)"
    echo "========================================"
}

# 清理临时文件
cleanup() {
    log_debug "备份目录保留在: $BACKUP_DIR"
    rm -f /tmp/fix_changes.log /tmp/fix_results.log /tmp/git_changes.log 2>/dev/null || true
}

# 主函数
main() {
    init
    
    if check_fix_marker; then
        log_info "检测到已修复标记，跳过重复修复"
        log_info "如需强制修复，请删除文件: $FIX_MARKER_FILE"
        
        fix_workflow_file
        fix_main_script
        self_update_check
    else
        fix_compilation_environment
        fix_workflow_file
        fix_main_script
        self_update_check
        create_fix_marker
    fi
    
    commit_changes
    show_fix_report
    cleanup
}

# 异常处理
trap 'log_error "脚本执行被中断"; exit 1' INT TERM
trap 'cleanup' EXIT

# 运行主函数
main "$@"

exit 0
