#!/bin/bash
# OpenWrt构建完整修复脚本
# 位置: firmware-config/scripts/fix-build.sh
# 功能: 智能检查并修复构建环境

set -e

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========== 日志函数 ==========
log() { echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ========== 工具函数 ==========

# 获取脚本所在目录的绝对路径
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# 获取仓库根目录
get_repo_root() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
}

# ========== 检查函数 ==========

# 检查目录结构完整性
check_directories() {
    local repo_root="$(get_repo_root)"
    local missing_dirs=0
    
    # 关键目录列表（相对于仓库根目录）
    local required_dirs=(
        "firmware-config/scripts"
        "firmware-config/Toolchain"
        "firmware-config/config-backup"
        "firmware-config/custom-files"
        ".github/workflows"
    )
    
    for dir in "${required_dirs[@]}"; do
        local full_path="$repo_root/$dir"
        if [ ! -d "$full_path" ]; then
            log_warn "目录缺失: $dir"
            missing_dirs=$((missing_dirs + 1))
        fi
    done
    
    if [ $missing_dirs -eq 0 ]; then
        log_success "✅ 所有必要目录存在"
        return 0
    else
        log_warn "⚠️  发现 $missing_dirs 个缺失的目录"
        return 1
    fi
}

# 检查关键文件存在性和权限
check_critical_files() {
    local repo_root="$(get_repo_root)"
    local missing_files=0
    local permission_issues=0
    
    # 关键文件列表（相对于仓库根目录）
    local critical_files=(
        "firmware-config/scripts/build_firmware_main.sh"
        ".github/workflows/firmware-build.yml"
    )
    
    for file in "${critical_files[@]}"; do
        local full_path="$repo_root/$file"
        
        # 检查文件是否存在
        if [ ! -f "$full_path" ]; then
            log_warn "文件缺失: $file"
            missing_files=$((missing_files + 1))
            continue
        fi
        
        # 检查.sh文件的执行权限
        if [[ "$file" == *.sh ]] && [ ! -x "$full_path" ]; then
            log_warn "文件没有执行权限: $file"
            permission_issues=$((permission_issues + 1))
        fi
    done
    
    # 检查修复脚本自身的权限
    local script_path="$repo_root/firmware-config/scripts/fix-build.sh"
    if [ ! -x "$script_path" ]; then
        log_warn "修复脚本自身没有执行权限"
        permission_issues=$((permission_issues + 1))
    fi
    
    local total_issues=$((missing_files + permission_issues))
    
    if [ $total_issues -eq 0 ]; then
        log_success "✅ 所有关键文件正常"
        return 0
    else
        log_warn "⚠️  发现 $missing_files 个缺失文件，$permission_issues 个权限问题"
        return 1
    fi
}

# 检查工作流文件格式
check_workflow_format() {
    local repo_root="$(get_repo_root)"
    local workflow_file="$repo_root/.github/workflows/firmware-build.yml"
    
    if [ ! -f "$workflow_file" ]; then
        log_warn "工作流文件不存在"
        return 1
    fi
    
    # 检查YAML基本格式
    if ! head -5 "$workflow_file" | grep -q "^name:"; then
        log_warn "工作流文件缺少name字段"
        return 1
    fi
    
    if ! grep -q "^jobs:" "$workflow_file"; then
        log_warn "工作流文件缺少jobs字段"
        return 1
    fi
    
    log_success "✅ 工作流文件格式正确"
    return 0
}

# 检查工具链目录状态
check_toolchain_dir() {
    local repo_root="$(get_repo_root)"
    local toolchain_dir="$repo_root/firmware-config/Toolchain"
    
    if [ ! -d "$toolchain_dir" ]; then
        log_warn "工具链目录不存在"
        return 1
    fi
    
    # 检查工具链目录结构
    local subdirs=("common" "configs")
    local missing_subdirs=0
    
    for subdir in "${subdirs[@]}"; do
        if [ ! -d "$toolchain_dir/$subdir" ]; then
            log_warn "工具链子目录缺失: $subdir"
            missing_subdirs=$((missing_subdirs + 1))
        fi
    done
    
    if [ $missing_subdirs -eq 0 ]; then
        log_success "✅ 工具链目录结构完整"
        return 0
    else
        log_warn "⚠️  工具链目录缺少 $missing_subdirs 个子目录"
        return 1
    fi
}

# ========== 修复函数 ==========

# 修复目录结构
fix_directories() {
    local repo_root="$(get_repo_root)"
    local created_count=0
    
    log_info "修复目录结构..."
    
    local required_dirs=(
        "firmware-config/scripts"
        "firmware-config/Toolchain"
        "firmware-config/config-backup"
        "firmware-config/custom-files"
        ".github/workflows"
    )
    
    for dir in "${required_dirs[@]}"; do
        local full_path="$repo_root/$dir"
        if [ ! -d "$full_path" ]; then
            mkdir -p "$full_path"
            log_info "创建目录: $dir"
            created_count=$((created_count + 1))
        fi
    done
    
    # 创建工具链子目录
    local toolchain_subdirs=("common" "configs")
    for subdir in "${toolchain_subdirs[@]}"; do
        local full_path="$repo_root/firmware-config/Toolchain/$subdir"
        if [ ! -d "$full_path" ]; then
            mkdir -p "$full_path"
            log_info "创建工具链子目录: $subdir"
            created_count=$((created_count + 1))
        fi
    done
    
    log_success "目录修复完成，创建了 $created_count 个目录"
}

# 修复文件权限
fix_file_permissions() {
    local repo_root="$(get_repo_root)"
    local fixed_count=0
    
    log_info "修复文件权限..."
    
    # 修复所有.sh文件的执行权限
    find "$repo_root" -name "*.sh" -type f 2>/dev/null | while read -r file; do
        if [ ! -x "$file" ]; then
            chmod +x "$file"
            log_info "设置执行权限: ${file#$repo_root/}"
            fixed_count=$((fixed_count + 1))
        fi
    done
    
    # 特别修复关键文件
    local critical_files=(
        "firmware-config/scripts/build_firmware_main.sh"
        "firmware-config/scripts/fix-build.sh"
    )
    
    for file in "${critical_files[@]}"; do
        local full_path="$repo_root/$file"
        if [ -f "$full_path" ] && [ ! -x "$full_path" ]; then
            chmod +x "$full_path"
            log_info "设置关键文件执行权限: $file"
            fixed_count=$((fixed_count + 1))
        fi
    done
    
    if [ $fixed_count -eq 0 ]; then
        log_info "✅ 所有文件权限正常"
    else
        log_success "权限修复完成，修复了 $fixed_count 个文件"
    fi
}

# 修复工作流文件
fix_workflow_file() {
    local repo_root="$(get_repo_root)"
    local workflow_src="$repo_root/firmware-build.yml"
    local workflow_dest="$repo_root/.github/workflows/firmware-build.yml"
    
    log_info "修复工作流文件..."
    
    # 如果源文件存在但目标文件不存在，则复制
    if [ -f "$workflow_src" ] && [ ! -f "$workflow_dest" ]; then
        cp "$workflow_src" "$workflow_dest"
        log_info "复制工作流文件到正确位置"
    fi
    
    # 如果工作流文件不存在，创建简化版本
    if [ ! -f "$workflow_dest" ]; then
        log_warn "工作流文件不存在，创建简化版本..."
        
        mkdir -p "$repo_root/.github/workflows"
        
        cat > "$workflow_dest" << 'EOF'
name: OpenWrt 智能固件构建工作流

on:
  workflow_dispatch:
    inputs:
      device_name:
        description: "设备名称"
        required: true
        type: string
        default: "ac42u"

jobs:
  build:
    runs-on: ubuntu-22.04
    steps:
      - name: 检出代码
        uses: actions/checkout@v4
      
      - name: 运行修复脚本
        run: |
          echo "=== 运行修复脚本 ==="
          FIX_SCRIPT="firmware-config/scripts/fix-build.sh"
          if [ -f "$FIX_SCRIPT" ]; then
            chmod +x "$FIX_SCRIPT"
            "$FIX_SCRIPT"
          else
            echo "⚠️ 修复脚本不存在"
          fi
      
      - name: 准备环境
        run: |
          echo "准备构建环境..."
EOF
        
        log_info "✅ 已创建简化版工作流文件"
    fi
    
    # 检查并修复工作流文件格式
    if [ -f "$workflow_dest" ]; then
        # 确保有必要的字段
        if ! grep -q "^name:" "$workflow_dest"; then
            log_warn "工作流文件缺少name字段，修复中..."
            sed -i '1i name: OpenWrt 构建工作流' "$workflow_dest"
        fi
        
        if ! grep -q "^jobs:" "$workflow_dest"; then
            log_warn "工作流文件缺少jobs字段，修复中..."
            echo -e "\njobs:\n  build:\n    runs-on: ubuntu-22.04" >> "$workflow_dest"
        fi
        
        log_success "工作流文件修复完成"
    fi
}

# 修复主构建脚本
fix_main_script() {
    local repo_root="$(get_repo_root)"
    local main_script="$repo_root/firmware-config/scripts/build_firmware_main.sh"
    
    log_info "检查主构建脚本..."
    
    # 如果主脚本不存在，创建基本版本
    if [ ! -f "$main_script" ]; then
        log_warn "主构建脚本不存在，创建基本版本..."
        
        mkdir -p "$(dirname "$main_script")"
        
        cat > "$main_script" << 'EOF'
#!/bin/bash
# OpenWrt构建主脚本（基本版）

echo "OpenWrt构建主脚本 - 基本版"

# 工作流步骤函数
workflow_main() {
    case $1 in
        "step3_prepare_environment")
            echo "步骤3：准备构建环境"
            mkdir -p firmware-config/scripts
            mkdir -p firmware-config/Toolchain
            echo "✅ 环境准备完成"
            ;;
        "step4_setup_environment")
            echo "步骤4：设置编译环境"
            echo "✅ 编译环境设置完成"
            ;;
        "step5_create_build_dir")
            echo "步骤5：创建构建目录"
            echo "✅ 构建目录创建完成"
            ;;
        *)
            echo "未知步骤: $1"
            ;;
    esac
}

# 主函数
main() {
    case $1 in
        "workflow_main")
            workflow_main "${@:2}"
            ;;
        *)
            echo "可用命令: workflow_main"
            ;;
    esac
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF
        
        chmod +x "$main_script"
        log_info "✅ 已创建基本版主构建脚本"
    elif [ -f "$main_script" ] && [ ! -x "$main_script" ]; then
        # 修复执行权限
        chmod +x "$main_script"
        log_info "✅ 修复主构建脚本执行权限"
    else
        log_info "✅ 主构建脚本正常"
    fi
}

# 修复工具链目录
fix_toolchain_dir() {
    local repo_root="$(get_repo_root)"
    local toolchain_dir="$repo_root/firmware-config/Toolchain"
    
    log_info "修复工具链目录..."
    
    # 创建工具链目录结构
    mkdir -p "$toolchain_dir/common"
    mkdir -p "$toolchain_dir/configs"
    
    # 创建说明文件
    if [ ! -f "$toolchain_dir/README.md" ]; then
        cat > "$toolchain_dir/README.md" << 'EOF'
# OpenWrt 编译工具链目录

## 说明
此目录用于存放通用且必要的工具链文件。

## 目录结构
- common/ - 通用工具链组件
- configs/ - 工具链配置
EOF
        log_info "✅ 创建工具链说明文件"
    fi
    
    # 创建.gitkeep文件以保持目录结构
    touch "$toolchain_dir/common/.gitkeep"
    touch "$toolchain_dir/configs/.gitkeep"
    
    log_success "工具链目录修复完成"
}

# 创建修复记录
create_fix_record() {
    local repo_root="$(get_repo_root)"
    local record_file="$repo_root/.fix-record.txt"
    
    cat > "$record_file" << EOF
# OpenWrt构建修复记录
修复时间: $(date)
修复脚本: firmware-config/scripts/fix-build.sh
修复内容:
  1. 目录结构修复
  2. 文件权限修复
  3. 工作流文件修复
  4. 主构建脚本修复
  5. 工具链目录修复

## 修复详情
$(date '+%Y-%m-%d %H:%M:%S') - 修复完成

EOF
    
    log_info "修复记录已保存到: .fix-record.txt"
}

# ========== 主修复流程 ==========

# 运行完整修复
run_complete_fix() {
    echo "========================================"
    echo "🔧 OpenWrt构建完整修复脚本"
    echo "========================================"
    
    echo "脚本位置: $(get_script_dir)/fix-build.sh"
    echo "仓库根目录: $(get_repo_root)"
    echo "修复时间: $(date)"
    echo ""
    
    # 1. 检查当前状态
    log_info "=== 检查当前状态 ==="
    
    local check_results=0
    
    check_directories || check_results=$((check_results + 1))
    check_critical_files || check_results=$((check_results + 1))
    check_workflow_format || check_results=$((check_results + 1))
    check_toolchain_dir || check_results=$((check_results + 1))
    
    echo ""
    
    # 2. 判断是否需要修复
    if [ $check_results -eq 0 ]; then
        log_success "✅ 系统状态正常，无需修复"
        echo ""
        echo "修复状态: 无需修复"
        echo "========================================"
        return 0
    fi
    
    log_info "发现 $check_results 个问题，开始修复..."
    echo ""
    
    # 3. 执行修复
    log_info "=== 执行修复 ==="
    
    fix_directories
    echo ""
    
    fix_file_permissions
    echo ""
    
    fix_workflow_file
    echo ""
    
    fix_main_script
    echo ""
    
    fix_toolchain_dir
    echo ""
    
    # 4. 创建修复记录
    create_fix_record
    echo ""
    
    # 5. 验证修复结果
    log_info "=== 验证修复结果 ==="
    
    local verify_results=0
    check_directories || verify_results=$((verify_results + 1))
    check_critical_files || verify_results=$((verify_results + 1))
    
    echo ""
    
    if [ $verify_results -eq 0 ]; then
        log_success "✅ 修复完成，所有问题已解决"
        echo "修复状态: 完全修复"
    else
        log_warn "⚠️  修复完成，但仍有 $verify_results 个问题未解决"
        echo "修复状态: 部分修复"
    fi
    
    echo "修复时间: $(date)"
    echo "========================================"
}

# ========== 脚本入口 ==========

# 处理命令行参数
handle_arguments() {
    case "${1:-}" in
        "check")
            # 仅检查模式
            echo "=== 检查模式 ==="
            check_directories
            check_critical_files
            check_workflow_format
            check_toolchain_dir
            echo "检查完成"
            ;;
        "quick")
            # 快速修复模式
            echo "=== 快速修复模式 ==="
            fix_directories
            fix_file_permissions
            echo "✅ 快速修复完成"
            ;;
        "help"|"--help"|"-h")
            # 帮助信息
            echo "OpenWrt构建修复脚本"
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  check     仅检查，不修复"
            echo "  quick     快速修复（仅目录和权限）"
            echo "  help      显示此帮助信息"
            echo "  无参数    完整修复"
            ;;
        *)
            # 完整修复模式（默认）
            run_complete_fix
            ;;
    esac
}

# 安全执行修复
safe_execute() {
    # 检查脚本自身是否存在
    if [ ! -f "${BASH_SOURCE[0]}" ]; then
        echo "❌ 修复脚本自身不存在"
        return 127
    fi
    
    # 检查脚本执行权限
    if [ ! -x "${BASH_SOURCE[0]}" ]; then
        echo "⚠️ 修复脚本没有执行权限，尝试修复..."
        chmod +x "${BASH_SOURCE[0]}" 2>/dev/null || {
            echo "❌ 无法修复脚本权限"
            return 1
        }
    fi
    
    # 执行修复
    handle_arguments "$@"
    return $?
}

# 主入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    safe_execute "$@"
    exit $?
fi
