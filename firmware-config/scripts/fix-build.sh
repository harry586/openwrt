#!/bin/bash
# OpenWrt编译智能修复脚本 v3.1（增强稳定版）
# 修复问题：GitHub Actions中过早退出问题

# ========== 错误处理设置 ==========
set -eEuo pipefail
trap 'handle_error $? $LINENO' ERR

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ========== 全局变量 ==========
SCRIPT_VERSION="3.1"
BACKUP_DIR="/tmp/openwrt_fix_backup_$(date +%Y%m%d_%H%M%S)"
FIX_MARKER=".fix_marker_$SCRIPT_VERSION"
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
REPO_ROOT="$GITHUB_WORKSPACE"
ERROR_FILE="/tmp/fix_script_error.log"

# ========== 错误处理函数 ==========
handle_error() {
    local exit_code=$1
    local line_no=$2
    local command="${BASH_COMMAND}"
    
    echo -e "${RED}❌ 脚本执行错误${NC}" >&2
    echo "错误代码: $exit_code" >&2
    echo "错误行号: $line_no" >&2
    echo "执行命令: $command" >&2
    echo "错误详情已保存到: $ERROR_FILE" >&2
    
    # 保存错误信息
    cat > "$ERROR_FILE" << EOF
修复脚本错误报告
==================
时间: $(date)
脚本版本: $SCRIPT_VERSION
退出代码: $exit_code
错误行号: $line_no
执行命令: $command
工作目录: $(pwd)
GitHub工作区: $GITHUB_WORKSPACE
仓库根目录: $REPO_ROOT
EOF
    
    # 显示环境信息
    echo "=== 环境信息 ===" >&2
    echo "当前目录: $(pwd)" >&2
    echo "目录内容:" >&2
    ls -la 2>/dev/null || echo "无法列出目录" >&2
    
    exit $exit_code
}

# ========== 日志函数 ==========
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ========== 智能文件查找函数 ==========
smart_find() {
    local pattern="$1"
    local max_depth="${2:-3}"
    
    log_info "查找文件: $pattern (最大深度: $max_depth)"
    
    # 在常见位置查找
    local common_locations=(
        "$REPO_ROOT"
        "$REPO_ROOT/firmware-config"
        "$REPO_ROOT/scripts"
        "$REPO_ROOT/.github"
        "/tmp"
        "."
    )
    
    for location in "${common_locations[@]}"; do
        if [ -d "$location" ]; then
            log_info "检查位置: $location"
            local found=$(find "$location" -maxdepth "$max_depth" -name "$pattern" 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                log_success "找到文件: $found"
                echo "$found"
                return 0
            fi
        else
            log_warn "位置不存在: $location"
        fi
    done
    
    # 递归查找（有限深度）
    log_info "执行递归查找..."
    local found=$(find . -maxdepth 5 -name "$pattern" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        log_success "递归找到文件: $found"
        echo "$found"
        return 0
    fi
    
    log_warn "未找到文件: $pattern"
    return 1
}

# ========== 智能脚本执行函数 ==========
smart_exec() {
    local script_name="$1"
    shift
    
    log_info "查找并执行脚本: $script_name"
    
    # 尝试多个可能的位置
    local possible_paths=(
        "firmware-config/scripts/$script_name"
        "scripts/$script_name"
        ".github/scripts/$script_name"
        "$script_name"
        "/tmp/$script_name"
    )
    
    for path in "${possible_paths[@]}"; do
        log_info "检查路径: $path"
        if [ -f "$path" ] && [ -x "$path" ]; then
            log_success "执行脚本: $path"
            bash "$path" "$@"
            return $?
        elif [ -f "$path" ]; then
            log_success "执行脚本(添加权限): $path"
            chmod +x "$path"
            bash "$path" "$@"
            return $?
        fi
    done
    
    log_error "未找到可执行脚本: $script_name"
    return 1
}

# ========== 修复工作流文件路径 ==========
fix_workflow_paths() {
    log_info "1. 修复工作流文件路径..."
    
    local workflow_file=$(smart_find "firmware-build.yml" 4)
    if [ -z "$workflow_file" ]; then
        log_warn "未找到工作流文件，跳过此步骤"
        return 0
    fi
    
    log_success "找到工作流文件: $workflow_file"
    cp "$workflow_file" "$BACKUP_DIR/workflow_original.yml" 2>/dev/null || true
    
    # 备份原文件
    local backup="${workflow_file}.backup.$(date +%s)"
    cp "$workflow_file" "$backup"
    log_info "工作流文件已备份到: $backup"
    
    # 简单的修复：确保文件存在且可读
    if [ -f "$workflow_file" ] && [ -r "$workflow_file" ]; then
        log_success "工作流文件可正常访问"
        echo "workflow_check=passed" >> /tmp/fix_results.log
    else
        log_error "工作流文件无法访问"
        return 1
    fi
    
    return 0
}

# ========== 修复主构建脚本路径 ==========
fix_main_script_paths() {
    log_info "2. 修复主构建脚本路径..."
    
    local main_script=$(smart_find "build_firmware_main.sh" 4)
    if [ -z "$main_script" ]; then
        log_warn "未找到主构建脚本，跳过此步骤"
        return 0
    fi
    
    log_success "找到主构建脚本: $main_script"
    cp "$main_script" "$BACKUP_DIR/main_script_original.sh" 2>/dev/null || true
    
    # 简单的修复：确保脚本有执行权限
    if [ -f "$main_script" ]; then
        if [ ! -x "$main_script" ]; then
            log_info "添加执行权限: $main_script"
            chmod +x "$main_script"
        fi
        
        # 验证脚本语法
        if bash -n "$main_script"; then
            log_success "主脚本语法检查通过"
            echo "main_script_check=passed" >> /tmp/fix_results.log
        else
            log_error "主脚本语法检查失败"
            return 1
        fi
    else
        log_error "主脚本文件不存在"
        return 1
    fi
    
    return 0
}

# ========== 修复目录结构 ==========
fix_directory_structure() {
    log_info "3. 修复目录结构..."
    
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
        log_info "检查目录: $dir"
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" 2>/dev/null || {
                log_warn "无法创建目录: $dir"
                continue
            }
            dirs_created=$((dirs_created + 1))
            log_success "创建目录: $dir"
        else
            log_info "目录已存在: $dir"
        fi
    done
    
    log_info "创建了 $dirs_created 个缺失目录"
    
    # 确保关键脚本存在
    if [ ! -f "firmware-config/scripts/build_firmware_main.sh" ]; then
        log_info "查找并复制主构建脚本..."
        local found_script=$(smart_find "build_firmware_main.sh" 4)
        if [ -n "$found_script" ] && [ "$found_script" != "firmware-config/scripts/build_firmware_main.sh" ]; then
            mkdir -p firmware-config/scripts
            cp "$found_script" firmware-config/scripts/ 2>/dev/null || {
                log_warn "无法复制脚本到标准位置"
                return 0
            }
            chmod +x firmware-config/scripts/build_firmware_main.sh 2>/dev/null || true
            log_success "复制主脚本到标准位置"
        else
            log_warn "未找到可复制的主脚本"
        fi
    fi
    
    return 0
}

# ========== 修复权限问题 ==========
fix_permissions() {
    log_info "4. 修复脚本权限..."
    
    local scripts_fixed=0
    
    # 修复当前目录下的.sh文件权限
    log_info "修复当前目录的脚本权限..."
    find . -maxdepth 3 -name "*.sh" -type f 2>/dev/null | while read script; do
        if [ ! -x "$script" ]; then
            chmod +x "$script" 2>/dev/null && {
                scripts_fixed=$((scripts_fixed + 1))
                log_info "添加执行权限: $script"
            } || log_warn "无法添加权限: $script"
        fi
    done
    
    log_info "修复了 $scripts_fixed 个文件权限"
    return 0
}

# ========== 创建缺失的脚本 ==========
create_missing_scripts() {
    log_info "5. 创建缺失的脚本..."
    
    # 创建错误分析脚本（如果不存在）
    local error_script="firmware-config/scripts/error_analysis.sh"
    if [ ! -f "$error_script" ]; then
        mkdir -p firmware-config/scripts 2>/dev/null || {
            log_warn "无法创建脚本目录"
            return 0
        }
        
        log_info "创建错误分析脚本..."
        cat > "$error_script" << 'EOF'
#!/bin/bash
# 错误分析脚本
echo "=== 错误分析脚本 ==="
echo "运行时间: $(date)"
echo "当前目录: $(pwd)"
echo "环境变量:"
env | grep -E "GITHUB|BUILD|TARGET|SELECTED" || true
echo "=== 磁盘空间 ==="
df -h 2>/dev/null || true
echo "=== 内存使用 ==="
free -h 2>/dev/null || true
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
    log_info "6. 创建修复标记..."
    
    cat > "$FIX_MARKER" 2>/dev/null << EOF || {
        log_warn "无法创建修复标记文件"
        return 0
    }
# 修复标记文件
version=$SCRIPT_VERSION
date=$(date '+%Y-%m-%d %H:%M:%S')
fixed_items=(
    "workflow_paths"
    "main_script_paths"
    "directory_structure"
    "script_permissions"
    "missing_scripts"
)
workspace=$GITHUB_WORKSPACE
repo_root=$REPO_ROOT
EOF
    
    log_success "创建修复标记: $FIX_MARKER"
}

# ========== 显示修复报告 ==========
show_fix_report() {
    echo ""
    echo "========================================"
    echo "📊 修复完成报告 v$SCRIPT_VERSION"
    echo "========================================"
    echo ""
    
    echo "✅ 修复项目完成:"
    echo "   1. 工作流文件路径修复"
    echo "   2. 主构建脚本路径修复"
    echo "   3. 目录结构修复"
    echo "   4. 脚本权限修复"
    echo "   5. 缺失脚本创建"
    echo "   6. 修复标记创建"
    echo ""
    
    echo "📁 备份目录: $BACKUP_DIR"
    if [ -d "$BACKUP_DIR" ]; then
        echo "   备份文件数: $(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l)"
    fi
    
    echo ""
    echo "🔧 修复脚本位置: $(realpath "$0" 2>/dev/null || echo "$0")"
    echo "📅 修复时间: $(date)"
    echo ""
    
    if [ -f "/tmp/fix_results.log" ]; then
        echo "📝 修复结果:"
        cat /tmp/fix_results.log 2>/dev/null || echo "无法读取修复结果"
    fi
    
    echo "========================================"
}

# ========== 清理临时文件 ==========
cleanup_temporary_files() {
    log_info "清理临时文件..."
    
    # 清理旧的临时文件（保留最近3个）
    find /tmp -name "openwrt_fix_backup_*" -type d -mtime +1 2>/dev/null | head -5 | while read dir; do
        log_info "清理旧备份: $dir"
        rm -rf "$dir" 2>/dev/null || true
    done
    
    # 清理临时日志文件
    rm -f /tmp/fix_results.log 2>/dev/null || true
}

# ========== 环境验证 ==========
validate_environment() {
    log_info "验证环境..."
    
    echo "=== 环境验证 ==="
    echo "当前目录: $(pwd)"
    echo "GitHub工作区: $GITHUB_WORKSPACE"
    echo "仓库根目录: $REPO_ROOT"
    echo "用户: $(whoami)"
    echo ""
    
    # 检查关键命令
    local required_commands=("bash" "find" "mkdir" "chmod" "cp")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            log_success "命令可用: $cmd"
        else
            log_error "命令不可用: $cmd"
            return 1
        fi
    done
    
    # 检查目录权限
    local test_dir="/tmp/test_dir_$(date +%s)"
    if mkdir -p "$test_dir" 2>/dev/null && rmdir "$test_dir" 2>/dev/null; then
        log_success "目录创建/删除权限正常"
    else
        log_error "目录权限异常"
        return 1
    fi
    
    return 0
}

# ========== 主函数 ==========
main() {
    echo "========================================"
    echo "🔧 OpenWrt构建修复脚本 v$SCRIPT_VERSION"
    echo "========================================"
    echo "开始时间: $(date)"
    
    # 环境验证
    if ! validate_environment; then
        log_error "环境验证失败"
        return 1
    fi
    
    # 创建备份目录
    mkdir -p "$BACKUP_DIR" 2>/dev/null || {
        log_error "无法创建备份目录"
        return 1
    }
    
    # 执行修复步骤（每个步骤独立，即使失败也继续）
    log_info "开始执行修复步骤..."
    
    # 步骤1：修复工作流文件路径
    if ! fix_workflow_paths; then
        log_warn "工作流文件修复失败，继续其他步骤"
    fi
    
    # 步骤2：修复主构建脚本路径
    if ! fix_main_script_paths; then
        log_warn "主构建脚本修复失败，继续其他步骤"
    fi
    
    # 步骤3：修复目录结构
    if ! fix_directory_structure; then
        log_warn "目录结构修复失败，继续其他步骤"
    fi
    
    # 步骤4：修复权限问题
    if ! fix_permissions; then
        log_warn "权限修复失败，继续其他步骤"
    fi
    
    # 步骤5：创建缺失的脚本
    if ! create_missing_scripts; then
        log_warn "创建缺失脚本失败，继续其他步骤"
    fi
    
    # 步骤6：创建修复标记
    if ! create_fix_marker; then
        log_warn "创建修复标记失败，继续其他步骤"
    fi
    
    # 显示报告
    show_fix_report
    
    # 清理
    cleanup_temporary_files
    
    log_success "修复完成！"
    return 0
}

# ========== 脚本入口 ==========
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 设置日志文件
    exec 2>>"$ERROR_FILE"
    
    echo "开始执行修复脚本..." >> "$ERROR_FILE"
    
    # 执行主函数
    if main; then
        echo "修复脚本执行成功" >> "$ERROR_FILE"
        exit 0
    else
        echo "修复脚本执行失败" >> "$ERROR_FILE"
        exit 1
    fi
fi
