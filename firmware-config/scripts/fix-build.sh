#!/bin/bash
# OpenWrt编译智能修复脚本 v3.5（最终修复版）

# ========== 修复关键：安全的环境设置 ==========
# 不使用 set -e，改用智能错误处理
set -u  # 使用未定义变量时报错
set -o pipefail  # 管道中任意命令失败则整个管道失败

# ========== 自定义错误处理 ==========
handle_error() {
    echo "❌ 错误发生在第 $1 行: $2"
    echo "继续执行其他修复..."
    return 1  # 返回错误但不退出
}

# ========== 安全的命令执行 ==========
safe_run() {
    local cmd="$*"
    echo "执行: $cmd"
    
    if eval "$cmd"; then
        echo "✅ 成功"
        return 0
    else
        local exit_code=$?
        echo "⚠️ 失败 (退出码: $exit_code)"
        return $exit_code
    fi
}

# ========== 颜色定义（安全版）==========
# 先检查是否在终端中运行
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

# ========== 日志函数（安全版）==========
log_info() { echo -e "${BLUE}[INFO]${NC} $1" 2>/dev/null || echo "[INFO] $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" 2>/dev/null || echo "[SUCCESS] $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1" 2>/dev/null || echo "[WARNING] $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" 2>/dev/null || echo "[ERROR] $1"; }

# ========== 修复1：创建必需目录 ==========
fix_directories() {
    log_info "修复目录结构..."
    
    local dirs=(
        "firmware-config/scripts"
        "firmware-config/Toolchain"
        "firmware-config/config-backup"
        ".github/workflows"
        "scripts"
        "/tmp/build-artifacts"
    )
    
    for dir in "${dirs[@]}"; do
        if safe_run "mkdir -p '$dir'"; then
            log_success "目录创建/存在: $dir"
        else
            log_warn "目录创建失败: $dir (继续执行)"
        fi
    done
    
    return 0
}

# ========== 修复2：查找并修复主脚本 ==========
fix_main_script() {
    log_info "查找主构建脚本..."
    
    # 按优先级查找
    local search_paths=(
        "firmware-config/scripts/build_firmware_main.sh"
        "scripts/build_firmware_main.sh"
        "build_firmware_main.sh"
        ".github/scripts/build_firmware_main.sh"
    )
    
    local found_script=""
    for path in "${search_paths[@]}"; do
        if [ -f "$path" ]; then
            found_script="$path"
            log_success "找到主脚本: $found_script"
            break
        fi
    done
    
    if [ -z "$found_script" ]; then
        log_warn "未找到主脚本，尝试递归查找..."
        found_script=$(find . -name "build_firmware_main.sh" -type f 2>/dev/null | head -1)
        
        if [ -n "$found_script" ]; then
            log_success "递归找到主脚本: $found_script"
        else
            log_error "无法找到主构建脚本"
            return 1
        fi
    fi
    
    # 修复权限
    safe_run "chmod +x '$found_script'"
    
    # 简单语法检查（如果有bash）
    if command -v bash >/dev/null 2>&1; then
        if safe_run "bash -n '$found_script'"; then
            log_success "主脚本语法检查通过"
        else
            log_warn "主脚本语法检查失败（可能包含不兼容语法）"
        fi
    fi
    
    echo "MAIN_SCRIPT=$found_script" >> /tmp/fix_result.env
    return 0
}

# ========== 修复3：修复所有脚本权限 ==========
fix_permissions() {
    log_info "修复脚本权限..."
    
    local count=0
    # 限制深度，避免权限问题
    while IFS= read -r -d $'\0' file; do
        if safe_run "chmod +x '$file'"; then
            count=$((count + 1))
        fi
    done < <(find . -maxdepth 5 -name "*.sh" -type f -print0 2>/dev/null)
    
    log_success "修复了 $count 个脚本权限"
    return 0
}

# ========== 修复4：检查工作流文件 ==========
fix_workflow() {
    log_info "检查工作流文件..."
    
    local workflow_file=".github/workflows/firmware-build.yml"
    
    if [ -f "$workflow_file" ]; then
        log_success "工作流文件存在: $workflow_file"
        
        # 备份工作流文件
        safe_run "cp '$workflow_file' '$workflow_file.backup.$(date +%s)'"
        
        # 检查常见问题
        if grep -q "set -E" "$workflow_file"; then
            log_warn "工作流文件中发现 set -E（可能导致问题）"
        fi
        
        # 检查YAML语法
        if command -v yamllint >/dev/null 2>&1; then
            if safe_run "yamllint '$workflow_file'"; then
                log_success "工作流YAML语法检查通过"
            else
                log_warn "工作流YAML语法检查失败"
            fi
        fi
    else
        log_warn "工作流文件不存在: $workflow_file"
    fi
    
    return 0
}

# ========== 修复5：创建必需文件 ==========
create_essential_files() {
    log_info "创建必需文件..."
    
    # 创建错误分析脚本
    local error_script="firmware-config/scripts/error_analysis.sh"
    if [ ! -f "$error_script" ]; then
        safe_run "mkdir -p firmware-config/scripts"
        
        cat > "$error_script" << 'EOF'
#!/bin/bash
# 错误分析脚本
echo "=== 错误分析 ==="
echo "时间: $(date)"
echo "工作目录: $(pwd)"
echo "GitHub工作区: ${GITHUB_WORKSPACE:-未设置}"
echo ""
echo "=== 环境变量 ==="
env | grep -E "GITHUB|BUILD|TARGET|SELECTED" | sort || true
echo ""
echo "=== 磁盘空间 ==="
df -h 2>/dev/null || true
echo ""
echo "=== 内存使用 ==="
free -h 2>/dev/null || true
exit 0
EOF
        
        safe_run "chmod +x '$error_script'"
        log_success "创建错误分析脚本"
    fi
    
    # 创建工具链README
    local readme_file="firmware-config/Toolchain/README.md"
    if [ ! -f "$readme_file" ]; then
        safe_run "mkdir -p firmware-config/Toolchain"
        
        cat > "$readme_file" << 'EOF'
# 工具链目录
此目录用于保存编译工具链，加速后续构建。
EOF
        log_success "创建工具链README"
    fi
    
    return 0
}

# ========== 修复6：环境验证 ==========
validate_environment() {
    log_info "验证环境..."
    
    echo "=== 环境信息 ==="
    echo "当前目录: $(pwd)"
    echo "脚本路径: $(readlink -f "$0" 2>/dev/null || echo "$0")"
    echo "用户: $(whoami 2>/dev/null || echo '未知')"
    echo "主机名: $(hostname 2>/dev/null || echo '未知')"
    echo ""
    
    # 检查关键命令
    local required_commands=("bash" "find" "mkdir" "chmod" "cp")
    local missing_commands=0
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "命令可用: $cmd"
        else
            log_error "命令不可用: $cmd"
            missing_commands=$((missing_commands + 1))
        fi
    done
    
    if [ $missing_commands -gt 0 ]; then
        log_error "缺少 $missing_commands 个必要命令"
        return 1
    fi
    
    log_success "环境验证通过"
    return 0
}

# ========== 主修复函数 ==========
main() {
    echo "========================================"
    echo "🔧 OpenWrt构建修复脚本 v3.5"
    echo "========================================"
    echo "开始时间: $(date)"
    echo "工作目录: $(pwd)"
    echo ""
    
    # 验证环境
    if ! validate_environment; then
        log_error "环境验证失败，但继续尝试修复..."
    fi
    
    # 清理旧的结果文件
    rm -f /tmp/fix_result.env 2>/dev/null || true
    
    # 执行修复步骤
    local steps=(
        "fix_directories"
        "fix_main_script"
        "fix_permissions"
        "fix_workflow"
        "create_essential_files"
    )
    
    local success_count=0
    local total_steps=${#steps[@]}
    
    for step in "${steps[@]}"; do
        echo ""
        log_info "执行步骤: $step"
        
        if $step; then
            success_count=$((success_count + 1))
            log_success "步骤 $step 完成"
        else
            log_warn "步骤 $step 失败或部分失败"
        fi
    done
    
    echo ""
    echo "========================================"
    echo "📊 修复完成报告"
    echo "========================================"
    echo "总步骤数: $total_steps"
    echo "成功步骤: $success_count"
    echo ""
    
    if [ -f "/tmp/fix_result.env" ]; then
        echo "✅ 主脚本信息:"
        cat /tmp/fix_result.env
    fi
    
    echo ""
    if [ $success_count -eq $total_steps ]; then
        echo "🎉 所有修复步骤完成！"
        echo "🚀 现在可以重新运行构建工作流"
        return 0
    elif [ $success_count -ge $((total_steps / 2)) ]; then
        echo "⚠️ 部分修复完成 ($success_count/$total_steps)"
        echo "💡 建议检查失败步骤并重新运行"
        return 0
    else
        echo "❌ 修复完成度较低 ($success_count/$total_steps)"
        return 1
    fi
}

# ========== 脚本入口 ==========
# 确保脚本即使有错误也能运行到最后
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 设置最后的手段：即使脚本出错也不立即退出
    trap 'echo "脚本被中断或发生错误"; exit 1' INT TERM
    
    # 执行主函数
    if main; then
        exit 0
    else
        echo "❌ 修复脚本执行失败"
        exit 1
    fi
fi
