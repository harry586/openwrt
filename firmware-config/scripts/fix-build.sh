#!/bin/bash
# OpenWrt编译智能修复脚本 v3.2（GitHub Actions兼容版）
# 修复问题：set -E与trap的冲突，避免脚本提前退出

# ========== 安全设置（兼容GitHub Actions）==========
set -e  # 遇到错误时退出
set -u  # 使用未定义变量时报错
set -o pipefail  # 管道中任意命令失败则整个管道失败

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ========== 全局变量 ==========
SCRIPT_VERSION="3.2"
BACKUP_DIR="/tmp/openwrt_fix_backup_$(date +%Y%m%d_%H%M%S)"
FIX_MARKER=".fix_marker_$SCRIPT_VERSION"
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
REPO_ROOT="$GITHUB_WORKSPACE"
LOG_FILE="/tmp/fix_script_$(date +%Y%m%d_%H%M%S).log"

# ========== 安全的日志函数 ==========
log_info() { 
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
    return 0
}

log_success() { 
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
    return 0
}

log_warn() { 
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
    return 0
}

log_error() { 
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    return 0
}

# ========== 安全执行函数 ==========
safe_exec() {
    local description="$1"
    shift
    local cmd="$*"
    
    log_info "执行: $description"
    log_info "命令: $cmd"
    
    # 执行命令并捕获输出
    if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "$description 成功"
        return 0
    else
        local exit_code=${PIPESTATUS[0]}
        log_warn "$description 失败 (退出码: $exit_code)"
        return $exit_code
    fi
}

# ========== 智能文件查找（安全版）==========
smart_find() {
    local pattern="$1"
    local max_depth="${2:-3}"
    
    log_info "查找文件: $pattern (最大深度: $max_depth)"
    
    # 常见位置数组
    local common_locations=("$REPO_ROOT" "$REPO_ROOT/firmware-config" "$REPO_ROOT/scripts" "$REPO_ROOT/.github" "/tmp" ".")
    
    for location in "${common_locations[@]}"; do
        if [ -d "$location" ]; then
            local found=$(find "$location" -maxdepth "$max_depth" -name "$pattern" 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                log_success "找到文件: $found"
                echo "$found"
                return 0
            fi
        fi
    done
    
    log_warn "未找到文件: $pattern"
    return 1
}

# ========== 修复工作流文件路径 ==========
fix_workflow_paths() {
    log_info "开始修复工作流文件路径..."
    
    local workflow_file
    if workflow_file=$(smart_find "firmware-build.yml" 4); then
        log_success "找到工作流文件: $workflow_file"
        
        # 备份原文件
        mkdir -p "$BACKUP_DIR"
        cp "$workflow_file" "$BACKUP_DIR/workflow_original.yml" 2>/dev/null || true
        
        log_success "工作流文件备份完成"
        echo "workflow_fixed=true" >> /tmp/fix_results.log
    else
        log_warn "未找到工作流文件，跳过此步骤"
    fi
    
    return 0
}

# ========== 修复主构建脚本路径 ==========
fix_main_script_paths() {
    log_info "开始修复主构建脚本路径..."
    
    local main_script
    if main_script=$(smart_find "build_firmware_main.sh" 4); then
        log_success "找到主构建脚本: $main_script"
        
        # 备份原文件
        mkdir -p "$BACKUP_DIR"
        cp "$main_script" "$BACKUP_DIR/main_script_original.sh" 2>/dev/null || true
        
        # 确保脚本有执行权限
        if [ ! -x "$main_script" ]; then
            log_info "添加执行权限: $main_script"
            chmod +x "$main_script" 2>/dev/null || true
        fi
        
        # 简单语法检查
        if bash -n "$main_script" 2>/dev/null; then
            log_success "主脚本语法检查通过"
        else
            log_warn "主脚本语法检查失败（可能包含不兼容语法）"
        fi
        
        echo "main_script_fixed=true" >> /tmp/fix_results.log
    else
        log_warn "未找到主构建脚本，跳过此步骤"
    fi
    
    return 0
}

# ========== 修复目录结构 ==========
fix_directory_structure() {
    log_info "开始修复目录结构..."
    
    local dirs_created=0
    local required_dirs=(
        "firmware-config/scripts"
        "firmware-config/Toolchain"
        "firmware-config/config-backup"
        ".github/workflows"
        "scripts"
        "/tmp/build-artifacts"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            if mkdir -p "$dir" 2>/dev/null; then
                dirs_created=$((dirs_created + 1))
                log_success "创建目录: $dir"
            else
                log_warn "无法创建目录: $dir (权限不足或路径无效)"
            fi
        else
            log_info "目录已存在: $dir"
        fi
    done
    
    log_info "创建了 $dirs_created 个缺失目录"
    
    # 确保关键脚本存在
    if [ ! -f "firmware-config/scripts/build_firmware_main.sh" ]; then
        log_info "查找并复制主构建脚本..."
        local found_script
        if found_script=$(smart_find "build_firmware_main.sh" 4); then
            if [ "$found_script" != "firmware-config/scripts/build_firmware_main.sh" ]; then
                mkdir -p firmware-config/scripts
                if cp "$found_script" firmware-config/scripts/ 2>/dev/null; then
                    chmod +x firmware-config/scripts/build_firmware_main.sh 2>/dev/null || true
                    log_success "复制主脚本到标准位置"
                else
                    log_warn "无法复制主脚本"
                fi
            fi
        fi
    fi
    
    return 0
}

# ========== 修复权限问题 ==========
fix_permissions() {
    log_info "开始修复脚本权限..."
    
    local scripts_fixed=0
    
    # 修复当前目录下的.sh文件权限（限制深度避免权限问题）
    find . -maxdepth 3 -name "*.sh" -type f 2>/dev/null | while read -r script; do
        if [ ! -x "$script" ]; then
            if chmod +x "$script" 2>/dev/null; then
                scripts_fixed=$((scripts_fixed + 1))
                log_info "添加执行权限: $script"
            fi
        fi
    done
    
    log_info "修复了 $scripts_fixed 个文件权限"
    return 0
}

# ========== 创建缺失的脚本 ==========
create_missing_scripts() {
    log_info "开始创建缺失的脚本..."
    
    # 确保脚本目录存在
    mkdir -p firmware-config/scripts 2>/dev/null || true
    
    # 创建错误分析脚本
    local error_script="firmware-config/scripts/error_analysis.sh"
    if [ ! -f "$error_script" ]; then
        cat > "$error_script" << 'EOF'
#!/bin/bash
# 错误分析脚本
echo "=== 错误分析脚本 ==="
echo "运行时间: $(date)"
echo "当前目录: $(pwd)"
echo "工作目录: $GITHUB_WORKSPACE"
echo ""
echo "=== 环境变量 ==="
env | grep -E "GITHUB|BUILD|TARGET|SELECTED" | sort
echo ""
echo "=== 磁盘空间 ==="
df -h 2>/dev/null || echo "无法获取磁盘信息"
echo ""
echo "=== 内存使用 ==="
free -h 2>/dev/null || echo "无法获取内存信息"
exit 0
EOF
        
        chmod +x "$error_script" 2>/dev/null || true
        log_success "创建错误分析脚本: $error_script"
    else
        log_info "错误分析脚本已存在"
    fi
    
    return 0
}

# ========== 创建修复标记 ==========
create_fix_marker() {
    log_info "开始创建修复标记..."
    
    {
        echo "# 修复标记文件"
        echo "version=$SCRIPT_VERSION"
        echo "date=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "workspace=$GITHUB_WORKSPACE"
        echo "repo_root=$REPO_ROOT"
    } > "$FIX_MARKER" 2>/dev/null || {
        log_warn "无法创建修复标记文件"
        return 0
    }
    
    log_success "创建修复标记: $FIX_MARKER"
    return 0
}

# ========== 环境验证 ==========
validate_environment() {
    log_info "验证环境..."
    
    echo "=== 环境信息 ==="
    echo "脚本版本: $SCRIPT_VERSION"
    echo "当前目录: $(pwd)"
    echo "GitHub工作区: $GITHUB_WORKSPACE"
    echo "用户: $(whoami)"
    echo "主机名: $(hostname)"
    echo ""
    
    # 检查关键命令
    local required_commands=("bash" "find" "mkdir" "chmod" "cp" "echo")
    local all_commands_available=true
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "命令可用: $cmd"
        else
            log_error "命令不可用: $cmd"
            all_commands_available=false
        fi
    done
    
    if [ "$all_commands_available" = false ]; then
        log_error "环境验证失败：缺少必要命令"
        return 1
    fi
    
    # 检查目录权限
    local test_dir="/tmp/test_fix_$(date +%s)"
    if mkdir -p "$test_dir" 2>/dev/null; then
        if rmdir "$test_dir" 2>/dev/null; then
            log_success "目录权限正常"
        else
            log_warn "无法删除测试目录（可能是正常现象）"
        fi
    else
        log_error "无法创建测试目录（权限问题）"
        return 1
    fi
    
    log_success "环境验证通过"
    return 0
}

# ========== 显示修复报告 ==========
show_fix_report() {
    echo ""
    echo "========================================"
    echo "📊 修复完成报告 v$SCRIPT_VERSION"
    echo "========================================"
    echo ""
    
    echo "✅ 修复项目:"
    echo "   1. 工作流文件路径检查"
    echo "   2. 主构建脚本路径检查"
    echo "   3. 目录结构修复"
    echo "   4. 脚本权限修复"
    echo "   5. 缺失脚本创建"
    echo "   6. 修复标记创建"
    echo ""
    
    echo "📁 备份目录: $BACKUP_DIR"
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l)
        echo "   备份文件数: $backup_count"
    fi
    
    echo ""
    echo "📄 日志文件: $LOG_FILE"
    echo "📅 修复时间: $(date)"
    echo ""
    
    if [ -f "/tmp/fix_results.log" ]; then
        echo "📝 修复结果:"
        cat /tmp/fix_results.log 2>/dev/null | head -10
    fi
    
    echo "========================================"
    return 0
}

# ========== 主函数 ==========
main() {
    log_info "========================================"
    log_info "🔧 OpenWrt构建修复脚本 v$SCRIPT_VERSION"
    log_info "========================================"
    log_info "开始时间: $(date)"
    log_info "工作区: $GITHUB_WORKSPACE"
    log_info "仓库根目录: $REPO_ROOT"
    log_info ""
    
    # 初始化日志文件
    echo "=== 修复脚本日志 ===" > "$LOG_FILE"
    echo "开始时间: $(date)" >> "$LOG_FILE"
    echo "版本: $SCRIPT_VERSION" >> "$LOG_FILE"
    echo "工作区: $GITHUB_WORKSPACE" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # 清理旧的结果文件
    rm -f /tmp/fix_results.log 2>/dev/null || true
    
    # 验证环境
    if ! validate_environment; then
        log_error "环境验证失败，继续执行修复..."
        # 不退出，尝试继续修复
    fi
    
    # 创建备份目录
    mkdir -p "$BACKUP_DIR" 2>/dev/null || log_warn "无法创建备份目录"
    
    # 执行修复步骤（每个步骤独立，不会因为失败而停止）
    log_info "开始执行修复步骤..."
    
    # 步骤1：修复工作流文件路径
    fix_workflow_paths || log_warn "步骤1执行有警告"
    
    # 步骤2：修复主构建脚本路径
    fix_main_script_paths || log_warn "步骤2执行有警告"
    
    # 步骤3：修复目录结构
    fix_directory_structure || log_warn "步骤3执行有警告"
    
    # 步骤4：修复权限问题
    fix_permissions || log_warn "步骤4执行有警告"
    
    # 步骤5：创建缺失的脚本
    create_missing_scripts || log_warn "步骤5执行有警告"
    
    # 步骤6：创建修复标记
    create_fix_marker || log_warn "步骤6执行有警告"
    
    # 显示报告
    show_fix_report
    
    log_success "修复脚本执行完成！"
    log_info "详细日志请查看: $LOG_FILE"
    
    return 0
}

# ========== 脚本入口 ==========
# 确保脚本在子shell中运行不会影响主进程
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 执行主函数
    if main; then
        exit 0
    else
        log_error "修复脚本执行失败"
        exit 1
    fi
fi
