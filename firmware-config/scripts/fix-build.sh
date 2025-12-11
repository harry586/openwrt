#!/bin/bash
# OpenWrt构建问题独立修复脚本 v4.0
# 完全独立，无需修改工作流文件
# 修复GitHub Actions中set -e导致提前退出的问题

# ========== 安全执行模式（避免提前退出）==========
# 不使用 set -e，改用函数返回值检查
set -u  # 使用未定义变量时报错
set -o pipefail  # 管道中任意命令失败则整个管道失败

# ========== 日志系统 ==========
LOG_FILE="/tmp/fix-build-$(date +%Y%m%d_%H%M%S).log"
exec 3>&1 4>&2  # 保存原始文件描述符
exec 1> >(tee -a "$LOG_FILE" >&3) 2> >(tee -a "$LOG_FILE" >&4)

echo "================================================"
echo "🔧 OpenWrt构建问题独立修复脚本 v4.0"
echo "================================================"
echo "开始时间: $(date)"
echo "日志文件: $LOG_FILE"
echo "================================================"
echo ""

# ========== 安全执行函数 ==========
run_cmd() {
    local cmd="$*"
    echo "▶ 执行: $cmd"
    
    # 执行命令，捕获退出状态但不退出
    if eval "$cmd"; then
        echo "✅ 成功: $cmd"
        return 0
    else
        local exit_code=$?
        echo "⚠️ 警告: $cmd (退出码: $exit_code)"
        return $exit_code
    fi
}

# ========== 检查环境 ==========
check_environment() {
    echo "📋 检查环境..."
    
    echo "当前目录: $(pwd)"
    echo "工作空间: ${GITHUB_WORKSPACE:-未设置}"
    echo "用户: $(whoami)"
    echo "主机名: $(hostname)"
    
    # 检查必要命令
    local commands=("bash" "find" "mkdir" "chmod" "cp" "ls")
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "✅ 命令可用: $cmd"
        else
            echo "❌ 命令缺失: $cmd"
            return 1
        fi
    done
    
    echo ""
    return 0
}

# ========== 修复1：创建必要目录 ==========
fix_directories() {
    echo "📁 修复1：创建必要目录..."
    
    local dirs=(
        "firmware-config"
        "firmware-config/scripts"
        "firmware-config/Toolchain"
        "firmware-config/config-backup"
        ".github"
        ".github/workflows"
        "scripts"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            run_cmd "mkdir -p '$dir'"
            echo "✅ 创建目录: $dir"
        else
            echo "✅ 目录已存在: $dir"
        fi
    done
    
    echo ""
    return 0
}

# ========== 修复2：查找并修复脚本 ==========
fix_scripts() {
    echo "🔧 修复2：查找并修复脚本..."
    
    # 查找主构建脚本
    local main_script=""
    local search_paths=(
        "build_firmware_main.sh"
        "scripts/build_firmware_main.sh"
        "firmware-config/scripts/build_firmware_main.sh"
        ".github/scripts/build_firmware_main.sh"
    )
    
    echo "查找主构建脚本..."
    for path in "${search_paths[@]}"; do
        if [ -f "$path" ]; then
            main_script="$path"
            echo "✅ 找到主脚本: $main_script"
            break
        fi
    done
    
    if [ -z "$main_script" ]; then
        echo "⚠️ 未找到主构建脚本，将尝试其他位置..."
        # 递归查找
        local found_script=$(find . -name "build_firmware_main.sh" -type f 2>/dev/null | head -1)
        if [ -n "$found_script" ]; then
            main_script="$found_script"
            echo "✅ 递归找到主脚本: $main_script"
        else
            echo "❌ 无法找到主构建脚本"
            return 1
        fi
    fi
    
    # 确保脚本有执行权限
    if [ -f "$main_script" ]; then
        if [ ! -x "$main_script" ]; then
            run_cmd "chmod +x '$main_script'"
            echo "✅ 添加执行权限: $main_script"
        fi
        echo "📊 主脚本信息: $(ls -l "$main_script")"
    fi
    
    echo ""
    return 0
}

# ========== 修复3：设置脚本权限 ==========
fix_permissions() {
    echo "🔑 修复3：设置脚本权限..."
    
    echo "设置.sh文件权限..."
    local count=0
    while IFS= read -r -d $'\0' script; do
        if [ ! -x "$script" ]; then
            run_cmd "chmod +x '$script'"
            count=$((count + 1))
        fi
    done < <(find . -name "*.sh" -type f -print0 2>/dev/null)
    
    echo "✅ 修复了 $count 个脚本权限"
    echo ""
    return 0
}

# ========== 修复4：检查工作流文件 ==========
fix_workflow() {
    echo "⚙️ 修复4：检查工作流文件..."
    
    local workflow_file=".github/workflows/firmware-build.yml"
    
    if [ -f "$workflow_file" ]; then
        echo "✅ 工作流文件存在: $workflow_file"
        echo "📊 文件大小: $(wc -l < "$workflow_file" 2>/dev/null || echo 0) 行"
        
        # 检查常见问题
        if grep -q "set -E" "$workflow_file"; then
            echo "⚠️ 检测到 set -E（可能导致问题）"
        fi
        
        # 备份工作流文件
        run_cmd "cp '$workflow_file' '$workflow_file.backup.$(date +%s)'"
    else
        echo "⚠️ 工作流文件不存在，将创建基础版本..."
        
        # 创建基础工作流文件
        run_cmd "mkdir -p .github/workflows"
        cat > "$workflow_file" << 'EOF'
name: OpenWrt Build Workflow
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: echo "构建开始"
EOF
        echo "✅ 创建基础工作流文件"
    fi
    
    echo ""
    return 0
}

# ========== 修复5：创建缺失脚本 ==========
create_missing_scripts() {
    echo "📝 修复5：创建缺失脚本..."
    
    # 确保错误分析脚本存在
    local error_script="firmware-config/scripts/error_analysis.sh"
    if [ ! -f "$error_script" ]; then
        echo "创建错误分析脚本..."
        mkdir -p firmware-config/scripts
        cat > "$error_script" << 'EOF'
#!/bin/bash
# 错误分析脚本
echo "=== 错误分析 ==="
echo "时间: $(date)"
echo "目录: $(pwd)"
echo ""
echo "=== 磁盘空间 ==="
df -h 2>/dev/null || echo "无法获取磁盘信息"
echo ""
echo "=== 内存使用 ==="
free -h 2>/dev/null || echo "无法获取内存信息"
echo ""
echo "=== 目录结构 ==="
find . -maxdepth 2 -type d 2>/dev/null | head -20
EOF
        run_cmd "chmod +x '$error_script'"
        echo "✅ 创建错误分析脚本"
    else
        echo "✅ 错误分析脚本已存在"
    fi
    
    echo ""
    return 0
}

# ========== 修复6：工具链目录初始化 ==========
init_toolchain() {
    echo "🛠️ 修复6：工具链目录初始化..."
    
    local toolchain_dir="firmware-config/Toolchain"
    
    if [ ! -d "$toolchain_dir" ]; then
        run_cmd "mkdir -p '$toolchain_dir'"
        echo "✅ 创建工具链目录"
    fi
    
    # 创建README
    if [ ! -f "$toolchain_dir/README.md" ]; then
        cat > "$toolchain_dir/README.md" << 'EOF'
# 工具链目录
此目录用于保存编译工具链
EOF
        echo "✅ 创建README文件"
    fi
    
    echo ""
    return 0
}

# ========== 修复7：检查仓库状态 ==========
check_repo() {
    echo "📦 修复7：检查仓库状态..."
    
    if [ -d ".git" ]; then
        echo "✅ Git仓库存在"
        echo "📊 当前分支: $(git branch --show-current 2>/dev/null || echo '未知')"
        echo "📊 最新提交: $(git log --oneline -1 2>/dev/null || echo '无提交')"
    else
        echo "⚠️ 当前不是Git仓库"
    fi
    
    echo ""
    return 0
}

# ========== 主修复流程 ==========
main() {
    echo "🚀 开始执行修复流程..."
    echo ""
    
    local success_count=0
    local total_steps=7
    
    # 步骤1：检查环境
    if check_environment; then
        success_count=$((success_count + 1))
    else
        echo "⚠️ 环境检查发现问题，但继续执行..."
    fi
    
    # 步骤2：修复目录
    if fix_directories; then
        success_count=$((success_count + 1))
    fi
    
    # 步骤3：修复脚本
    if fix_scripts; then
        success_count=$((success_count + 1))
    fi
    
    # 步骤4：修复权限
    if fix_permissions; then
        success_count=$((success_count + 1))
    fi
    
    # 步骤5：修复工作流
    if fix_workflow; then
        success_count=$((success_count + 1))
    fi
    
    # 步骤6：创建缺失脚本
    if create_missing_scripts; then
        success_count=$((success_count + 1))
    fi
    
    # 步骤7：初始化工具链
    if init_toolchain; then
        success_count=$((success_count + 1))
    fi
    
    # 步骤8：检查仓库
    if check_repo; then
        # 这个步骤不强制成功
        echo "✅ 仓库检查完成"
    fi
    
    echo ""
    echo "================================================"
    echo "📊 修复完成报告"
    echo "================================================"
    echo "总步骤数: $total_steps"
    echo "成功步骤: $success_count"
    echo "失败步骤: $((total_steps - success_count))"
    echo ""
    echo "📄 详细日志: $LOG_FILE"
    echo "🕒 修复时间: $(date)"
    echo ""
    
    if [ $success_count -eq $total_steps ]; then
        echo "🎉 所有修复步骤都成功完成！"
        echo "🚀 现在可以重新运行构建工作流"
        return 0
    elif [ $success_count -ge $((total_steps / 2)) ]; then
        echo "⚠️ 部分修复步骤完成"
        echo "💡 建议检查日志文件并重新运行工作流"
        return 0
    else
        echo "❌ 修复失败步骤过多"
        echo "🔍 请检查日志文件: $LOG_FILE"
        return 1
    fi
}

# ========== 执行入口 ==========
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "正在启动修复脚本..."
    echo ""
    
    # 执行主函数
    if main; then
        echo "✅ 修复脚本执行成功"
        exit 0
    else
        echo "❌ 修复脚本执行失败"
        exit 1
    fi
fi
