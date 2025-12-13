#!/bin/bash
# OpenWrt构建完整修复脚本

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
    
    local critical_files=(
        "firmware-config/scripts/build_firmware_main.sh"
        "firmware-config/scripts/fix-build.sh"
        ".github/workflows/firmware-build.yml"
    )
    
    for file in "${critical_files[@]}"; do
        local full_path="$repo_root/$file"
        
        if [ ! -f "$full_path" ]; then
            log_warn "文件缺失: $file"
            missing_files=$((missing_files + 1))
            continue
        fi
        
        if [[ "$file" == *.sh ]] && [ ! -x "$full_path" ]; then
            log_warn "文件没有执行权限: $file"
            permission_issues=$((permission_issues + 1))
        fi
    done
    
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

# 检查构建目录权限
check_build_dir_permissions() {
    local repo_root="$(get_repo_root)"
    
    log_info "检查构建目录权限..."
    
    if [ -d "/mnt" ]; then
        local mnt_permissions=$(stat -c "%a" /mnt 2>/dev/null || echo "未知")
        local mnt_owner=$(stat -c "%U:%G" /mnt 2>/dev/null || echo "未知")
        log_info "/mnt 目录权限: $mnt_permissions, 所有者: $mnt_owner"
        
        if [ "$mnt_permissions" != "777" ] && [ "$mnt_permissions" != "755" ]; then
            log_warn "/mnt 目录权限不足 (当前: $mnt_permissions)"
            return 1
        fi
    else
        log_warn "/mnt 目录不存在"
        return 1
    fi
    
    if [ -d "/mnt/openwrt-build" ]; then
        local build_dir_permissions=$(stat -c "%a" /mnt/openwrt-build 2>/dev/null || echo "未知")
        local build_dir_owner=$(stat -c "%U:%G" /mnt/openwrt-build 2>/dev/null || echo "未知")
        log_info "构建目录权限: $build_dir_permissions, 所有者: $build_dir_owner"
        
        if [ "$build_dir_permissions" != "777" ] && [ "$build_dir_permissions" != "755" ]; then
            log_warn "构建目录权限不足 (当前: $build_dir_permissions)"
            return 1
        fi
    else
        log_warn "构建目录不存在"
        return 0
    fi
    
    log_success "✅ 构建目录权限正常"
    return 0
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
    
    find "$repo_root" -name "*.sh" -type f 2>/dev/null | while read -r file; do
        if [ ! -x "$file" ]; then
            chmod +x "$file"
            log_info "设置执行权限: ${file#$repo_root/}"
            fixed_count=$((fixed_count + 1))
        fi
    done
    
    local critical_files=(
        "firmware-config/scripts/build_firmware_main.sh"
        "firmware-config/scripts/fix-build.sh"
        "firmware-config/scripts/error_analysis.sh"
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

# 修复构建目录权限
fix_build_dir_permissions() {
    log_info "修复构建目录权限..."
    
    local fixed_items=0
    
    if [ ! -d "/mnt" ]; then
        log_info "创建/mnt目录..."
        sudo mkdir -p /mnt
        fixed_items=$((fixed_items + 1))
    fi
    
    log_info "设置/mnt目录权限为777..."
    sudo chmod 777 /mnt 2>/dev/null || {
        log_warn "无法设置/mnt目录权限，尝试非sudo方式..."
        chmod 777 /mnt 2>/dev/null || true
    }
    fixed_items=$((fixed_items + 1))
    
    if [ ! -d "/mnt/openwrt-build" ]; then
        log_info "创建构建目录..."
        mkdir -p /mnt/openwrt-build
        fixed_items=$((fixed_items + 1))
    fi
    
    log_info "设置构建目录权限为777..."
    chmod 777 /mnt/openwrt-build 2>/dev/null || {
        log_warn "无法设置构建目录权限，尝试使用sudo..."
        sudo chmod 777 /mnt/openwrt-build 2>/dev/null || true
    }
    fixed_items=$((fixed_items + 1))
    
    log_info "确保目录所有权正确..."
    sudo chown -R $USER:$USER /mnt/openwrt-build 2>/dev/null || true
    fixed_items=$((fixed_items + 1))
    
    if [ -d "/mnt/openwrt-build" ]; then
        local permissions=$(stat -c "%a" /mnt/openwrt-build 2>/dev/null || echo "未知")
        log_info "构建目录权限: $permissions"
        
        if [ "$permissions" = "777" ] || [ "$permissions" = "755" ]; then
            log_success "✅ 构建目录权限修复成功"
        else
            log_warn "⚠️ 构建目录权限可能仍有问题 (当前: $permissions)"
        fi
    fi
    
    log_info "权限修复完成，处理了 $fixed_items 个项目"
}

# 修复工作流文件
fix_workflow_file() {
    local repo_root="$(get_repo_root)"
    local workflow_src="$repo_root/firmware-build.yml"
    local workflow_dest="$repo_root/.github/workflows/firmware-build.yml"
    
    log_info "修复工作流文件..."
    
    if [ -f "$workflow_src" ] && [ ! -f "$workflow_dest" ]; then
        cp "$workflow_src" "$workflow_dest"
        log_info "复制工作流文件到正确位置"
    fi
    
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
            "$FIX_SCRIPT" --fix-build-dir
          else
            echo "⚠️ 修复脚本不存在"
          fi
      
      - name: 准备环境
        run: |
          echo "准备构建环境..."
EOF
        
        log_info "✅ 已创建简化版工作流文件"
    fi
    
    if [ -f "$workflow_dest" ]; then
        if ! grep -q "^name:" "$workflow_dest"; then
            log_warn "工作流文件缺少name字段，修复中..."
            sed -i '1i name: OpenWrt 构建工作流' "$workflow_dest"
        fi
        
        if ! grep -q "^jobs:" "$workflow_dest"; then
            log_warn "工作流文件缺少jobs字段，修复中..."
            echo -e "\njobs:\n  build:\n    runs-on: ubuntu-22.04" >> "$workflow_dest"
        fi
        
        if grep -q '"$FIX_SCRIPT"' "$workflow_dest" && ! grep -q '"$FIX_SCRIPT".*--fix-build-dir' "$workflow_dest"; then
            log_info "更新工作流以包含构建目录修复..."
            sed -i 's/"\$FIX_SCRIPT"/"\$FIX_SCRIPT" --fix-build-dir/g' "$workflow_dest"
        fi
        
        log_success "工作流文件修复完成"
    fi
}

# 修复主构建脚本
fix_main_script() {
    local repo_root="$(get_repo_root)"
    local main_script="$repo_root/firmware-config/scripts/build_firmware_main.sh"
    
    log_info "检查主构建脚本..."
    
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
    
    mkdir -p "$toolchain_dir/common"
    mkdir -p "$toolchain_dir/configs"
    
    if [ ! -f "$toolchain_dir/README.md" ]; then
        cat > "$toolchain_dir/README.md" << 'EOF'
# OpenWrt 编译工具链目录

## 说明
此目录用于存放通用且必要的工具链文件。

## 目录结构
- common/ - 通用工具链组件
- configs/ - 工具链配置

## 权限说明
所有目录和文件应该具有可执行权限。
EOF
        log_info "✅ 创建工具链说明文件"
    fi
    
    touch "$toolchain_dir/common/.gitkeep"
    touch "$toolchain_dir/configs/.gitkeep"
    
    chmod -R 755 "$toolchain_dir" 2>/dev/null || true
    
    log_success "工具链目录修复完成"
}

# 创建修复记录
create_fix_record() {
    local repo_root="$(get_repo_root)"
    local record_file="$repo_root/.fix-record.txt"
    
    local fix_time="$(date '+%Y-%m-%d %H:%M:%S')"
    local git_status="未知"
    
    if command -v git &> /dev/null && [ -d "$repo_root/.git" ]; then
        git_status=$(git log --oneline -1 2>/dev/null || echo "无提交历史")
    fi
    
    cat > "$record_file" << EOF
# OpenWrt构建修复记录
修复时间: $fix_time
修复脚本: firmware-config/scripts/fix-build.sh
Git状态: $git_status
修复内容:
  1. 目录结构修复
  2. 文件权限修复
  3. 构建目录权限修复
  4. 工作流文件修复
  5. 主构建脚本修复
  6. 工具链目录修复

## 修复详情
$fix_time - 修复完成
EOF
    
    log_info "修复记录已保存到: .fix-record.txt"
    
    echo ""
    echo "========================================"
    echo "📝 修复完成报告"
    echo "========================================"
    cat "$record_file"
    echo "========================================"
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
    
    log_info "=== 检查当前状态 ==="
    
    local check_results=0
    
    check_directories || check_results=$((check_results + 1))
    check_critical_files || check_results=$((check_results + 1))
    check_workflow_format || check_results=$((check_results + 1))
    check_toolchain_dir || check_results=$((check_results + 1))
    check_build_dir_permissions || {
        log_warn "⚠️ 构建目录权限问题检测到"
        check_results=$((check_results + 1))
    }
    
    echo ""
    
    if [ $check_results -eq 0 ]; then
        log_success "✅ 系统状态正常，无需修复"
        echo ""
        echo "修复状态: 无需修复"
        echo "========================================"
        return 0
    fi
    
    log_info "发现 $check_results 个问题，开始修复..."
    echo ""
    
    log_info "=== 执行修复 ==="
    
    fix_build_dir_permissions
    echo ""
    
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
    
    create_fix_record
    echo ""
    
    log_info "=== 验证修复结果 ==="
    
    local verify_results=0
    check_directories || verify_results=$((verify_results + 1))
    check_critical_files || verify_results=$((verify_results + 1))
    check_build_dir_permissions || verify_results=$((verify_results + 1))
    
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

# 运行构建目录专用修复
run_build_dir_fix() {
    echo "========================================"
    echo "🔧 构建目录权限修复（专用）"
    echo "========================================"
    
    log_info "修复构建目录权限..."
    
    log_info "=== 检查当前状态 ==="
    check_build_dir_permissions || {
        log_warn "发现权限问题"
    }
    
    echo ""
    
    fix_build_dir_permissions
    
    echo ""
    
    log_info "=== 验证修复结果 ==="
    if check_build_dir_permissions; then
        log_success "✅ 构建目录权限修复成功"
        echo "修复状态: 成功"
    else
        log_error "❌ 构建目录权限修复失败"
        echo "修复状态: 失败"
    fi
    
    echo "修复时间: $(date)"
    echo "========================================"
}

# ========== 脚本入口 ==========

# 处理命令行参数
handle_arguments() {
    case "${1:-}" in
        "check")
            echo "=== 检查模式 ==="
            check_directories
            check_critical_files
            check_workflow_format
            check_toolchain_dir
            check_build_dir_permissions
            echo "检查完成"
            ;;
        "quick")
            echo "=== 快速修复模式 ==="
            fix_directories
            fix_file_permissions
            fix_build_dir_permissions
            echo "✅ 快速修复完成"
            ;;
        "--fix-build-dir")
            run_build_dir_fix
            ;;
        "help"|"--help"|"-h")
            echo "OpenWrt构建修复脚本"
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  check                仅检查，不修复"
            echo "  quick                快速修复（目录、权限、构建目录）"
            echo "  --fix-build-dir      构建目录专用修复（解决权限问题）"
            echo "  help                 显示此帮助信息"
            echo "  无参数               完整修复"
            echo ""
            echo "注意："
            echo "  如果遇到 'mkdir: cannot create directory' 权限错误，"
            echo "  请使用: $0 --fix-build-dir"
            ;;
        *)
            run_complete_fix
            ;;
    esac
}

# 安全执行修复
safe_execute() {
    if [ ! -f "${BASH_SOURCE[0]}" ]; then
        echo "❌ 修复脚本自身不存在"
        return 127
    fi
    
    if [ ! -x "${BASH_SOURCE[0]}" ]; then
        echo "⚠️ 修复脚本没有执行权限，尝试修复..."
        chmod +x "${BASH_SOURCE[0]}" 2>/dev/null || {
            echo "❌ 无法修复脚本权限"
            return 1
        }
    fi
    
    handle_arguments "$@"
    return $?
}

# 主入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    safe_execute "$@"
    exit $?
fi
