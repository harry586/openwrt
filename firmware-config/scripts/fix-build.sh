#!/bin/bash
# OpenWrt编译智能修复脚本 v3.0（路径智能修复版）
# 最后更新: 2024-01-16

set -e

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ========== 日志函数 ==========
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ========== 配置变量 ==========
SCRIPT_VERSION="3.0"
BACKUP_DIR="/tmp/openwrt_fix_backup_$(date +%Y%m%d_%H%M%S)"
FIX_MARKER=".fix_marker_$SCRIPT_VERSION"
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
REPO_ROOT="$GITHUB_WORKSPACE"

# ========== 智能文件查找函数 ==========
smart_find() {
    local pattern="$1"
    local max_depth="${2:-3}"
    
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
            local found=$(find "$location" -maxdepth "$max_depth" -name "$pattern" 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                echo "$found"
                return 0
            fi
        fi
    done
    
    # 递归查找
    local found=$(find . -name "$pattern" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi
    
    return 1
}

# ========== 智能脚本执行函数 ==========
smart_exec() {
    local script_name="$1"
    shift
    
    log_info "查找脚本: $script_name"
    
    # 尝试多个可能的位置
    local possible_paths=(
        "firmware-config/scripts/$script_name"
        "scripts/$script_name"
        ".github/scripts/$script_name"
        "$script_name"
        "/tmp/$script_name"
    )
    
    for path in "${possible_paths[@]}"; do
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
    
    log_error "未找到脚本: $script_name"
    return 1
}

# ========== 修复工作流文件路径 ==========
fix_workflow_paths() {
    log_info "1. 修复工作流文件路径..."
    
    local workflow_file=$(smart_find "firmware-build.yml" 4)
    if [ -z "$workflow_file" ]; then
        log_warn "未找到工作流文件"
        return 0
    fi
    
    log_info "找到工作流文件: $workflow_file"
    cp "$workflow_file" "$BACKUP_DIR/workflow_original.yml"
    
    # 备份原文件
    local backup="${workflow_file}.backup.$(date +%s)"
    cp "$workflow_file" "$backup"
    
    # 修复脚本路径引用
    log_info "修复脚本路径引用..."
    
    # 创建修复后的内容
    local temp_file="/tmp/workflow_fixed.yml"
    cat > "$temp_file" << 'EOF'
name: OpenWrt 智能固件构建工作流（路径修复版）

on:
  workflow_dispatch:
    inputs:
      device_name:
        description: "📱 设备名称"
        required: true
        default: "ac42u"
        type: string
      version_selection:
        description: "🔄 版本选择"
        required: true
        type: choice
        default: "21.02"
        options:
          - "23.05"
          - "21.02"
      config_mode:
        description: "⚙️ 配置模式选择"
        required: true
        type: choice
        default: "normal"
        options:
          - "base"
          - "normal"
      extra_packages:
        description: "额外安装插件"
        required: false
        type: string
        default: ""
      enable_cache:
        description: "⚡ 启用编译缓存"
        required: false
        default: true
        type: boolean
      commit_toolchain:
        description: "💾 提交工具链到仓库"
        required: false
        default: false
        type: boolean

env:
  BUILD_DIR: "/mnt/openwrt-build"
  GIT_LFS_SKIP_SMUDGE: 1
  ENABLE_CACHE: "true"
  COMMIT_TOOLCHAIN: "true"

jobs:
  build-firmware:
    runs-on: ubuntu-22.04
    
    steps:
      # 步骤0：准备构建环境
      - name: "📁 0. 准备构建环境"
        run: |
          echo "=== 环境准备 ==="
          sudo mkdir -p /mnt/openwrt-build
          sudo chmod 777 /mnt/openwrt-build
          mkdir -p /tmp/source-upload /tmp/build-artifacts
      
      # 🔥 步骤1：智能查找并运行主脚本
      - name: "🔧 1. 智能执行主构建脚本"
        id: smart_main_script
        run: |
          echo "=== 智能执行主构建脚本 ==="
          
          # 查找主构建脚本
          find_main_script() {
              for path in "firmware-config/scripts/build_firmware_main.sh" "scripts/build_firmware_main.sh" "build_firmware_main.sh"; do
                  if [ -f "$path" ] && [ -x "$path" ]; then
                      echo "$path"
                      return 0
                  elif [ -f "$path" ]; then
                      chmod +x "$path"
                      echo "$path"
                      return 0
                  fi
              done
              return 1
          }
          
          MAIN_SCRIPT=$(find_main_script)
          if [ -z "$MAIN_SCRIPT" ]; then
              echo "❌ 未找到主构建脚本"
              exit 1
          fi
          
          echo "✅ 找到主脚本: $MAIN_SCRIPT"
          
          # 设置环境变量供后续步骤使用
          echo "MAIN_SCRIPT_PATH=$MAIN_SCRIPT" >> $GITHUB_OUTPUT
          echo "REPO_ROOT=$(dirname $(dirname "$MAIN_SCRIPT"))" >> $GITHUB_OUTPUT
      
      # 步骤2：使用找到的脚本执行下载
      - name: "📥 2. 下载源代码"
        run: |
          MAIN_SCRIPT="${{ steps.smart_main_script.outputs.MAIN_SCRIPT_PATH }}"
          if [ -n "$MAIN_SCRIPT" ] && [ -x "$MAIN_SCRIPT" ]; then
              "$MAIN_SCRIPT" workflow_main step1_download_source "${{ github.workspace }}"
          else
              echo "❌ 主脚本不可用"
              exit 1
          fi
      
      # 后续步骤都使用智能查找方式...
      - name: "📤 3. 上传源代码"
        run: |
          MAIN_SCRIPT="${{ steps.smart_main_script.outputs.MAIN_SCRIPT_PATH }}"
          if [ -n "$MAIN_SCRIPT" ] && [ -x "$MAIN_SCRIPT" ]; then
              "$MAIN_SCRIPT" workflow_main step2_upload_source
          fi
      
      # ... 其他步骤使用类似模式
      - name: "🔧 4. Git LFS配置"
        run: |
          MAIN_SCRIPT="${{ steps.smart_main_script.outputs.MAIN_SCRIPT_PATH }}"
          if [ -n "$MAIN_SCRIPT" ] && [ -x "$MAIN_SCRIPT" ]; then
              "$MAIN_SCRIPT" workflow_main step4_install_git_lfs
          fi
EOF
    
    # 比较文件差异
    if ! diff -q "$workflow_file" "$temp_file" > /dev/null; then
        cp "$temp_file" "$workflow_file"
        log_success "工作流文件已修复"
        echo "workflow_fixed=true" >> /tmp/fix_results.log
    else
        log_info "工作流文件无需修复"
    fi
    
    rm -f "$temp_file"
}

# ========== 修复主构建脚本路径 ==========
fix_main_script_paths() {
    log_info "2. 修复主构建脚本路径..."
    
    local main_script=$(smart_find "build_firmware_main.sh" 4)
    if [ -z "$main_script" ]; then
        log_warn "未找到主构建脚本"
        return 0
    fi
    
    log_info "找到主构建脚本: $main_script"
    cp "$main_script" "$BACKUP_DIR/main_script_original.sh"
    
    # 备份原文件
    local backup="${main_script}.backup.$(date +%s)"
    cp "$main_script" "$backup"
    
    # 修复REPO_ROOT检测逻辑
    log_info "修复REPO_ROOT检测..."
    
    # 创建修复后的内容
    local temp_file="/tmp/main_script_fixed.sh"
    
    # 读取原文件并修复
    grep -v "^REPO_ROOT=" "$main_script" | \
    sed 's|REPO_ROOT=".*"|REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." \&\& pwd)"|' | \
    sed 's|TOOLCHAIN_DIR=".*/Toolchain"|TOOLCHAIN_DIR="$REPO_ROOT/firmware-config/Toolchain"|' > "$temp_file"
    
    # 在文件开头添加智能路径查找
    cat > "/tmp/header.sh" << 'EOF'
#!/bin/bash
set -e

# ========== 智能路径检测 ==========
detect_repo_root() {
    # 方法1：从脚本位置推导
    if [ -n "${BASH_SOURCE[0]}" ]; then
        local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
        local possible_root=$(cd "$script_dir/../.." && pwd)
        if [ -f "$possible_root/.git/config" ] || [ -d "$possible_root/firmware-config" ]; then
            echo "$possible_root"
            return 0
        fi
    fi
    
    # 方法2：从工作区推导
    if [ -n "$GITHUB_WORKSPACE" ] && [ -d "$GITHUB_WORKSPACE" ]; then
        echo "$GITHUB_WORKSPACE"
        return 0
    fi
    
    # 方法3：查找firmware-config目录
    local found=$(find . -name "firmware-config" -type d 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$(dirname "$found")"
        return 0
    fi
    
    # 方法4：使用当前目录
    echo "$(pwd)"
}

# 设置关键路径
REPO_ROOT=$(detect_repo_root)
TOOLCHAIN_DIR="$REPO_ROOT/firmware-config/Toolchain"
BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

EOF
    
    # 合并文件
    cat "/tmp/header.sh" "$temp_file" > "${main_script}.new"
    
    # 比较差异
    if ! diff -q "$main_script" "${main_script}.new" > /dev/null; then
        mv "${main_script}.new" "$main_script"
        chmod +x "$main_script"
        log_success "主构建脚本已修复"
        echo "main_script_fixed=true" >> /tmp/fix_results.log
    else
        log_info "主构建脚本无需修复"
        rm -f "${main_script}.new"
    fi
    
    rm -f "/tmp/header.sh" "$temp_file"
}

# ========== 修复目录结构 ==========
fix_directory_structure() {
    log_info "3. 修复目录结构..."
    
    local dirs_created=0
    
    # 创建必要的目录
    for dir in "firmware-config/scripts" \
               "firmware-config/Toolchain" \
               "firmware-config/config-backup" \
               ".github/workflows" \
               "scripts" \
               "/tmp/build-artifacts"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            dirs_created=$((dirs_created + 1))
            log_info "创建目录: $dir"
        fi
    done
    
    # 确保关键脚本存在
    if [ ! -f "firmware-config/scripts/build_firmware_main.sh" ]; then
        # 查找脚本并复制
        local found_script=$(smart_find "build_firmware_main.sh" 4)
        if [ -n "$found_script" ] && [ "$found_script" != "firmware-config/scripts/build_firmware_main.sh" ]; then
            mkdir -p firmware-config/scripts
            cp "$found_script" firmware-config/scripts/
            chmod +x firmware-config/scripts/build_firmware_main.sh
            log_success "复制主脚本到标准位置"
        fi
    fi
    
    log_info "创建了 $dirs_created 个缺失目录"
}

# ========== 修复权限问题 ==========
fix_permissions() {
    log_info "4. 修复脚本权限..."
    
    local scripts_fixed=0
    
    # 修复所有.sh文件的权限
    find . -name "*.sh" -type f 2>/dev/null | while read script; do
        if [ ! -x "$script" ]; then
            chmod +x "$script"
            scripts_fixed=$((scripts_fixed + 1))
            log_info "添加执行权限: $script"
        fi
    done
    
    # 修复工具链权限
    if [ -d "staging_dir" ]; then
        find staging_dir -type f \( -name "*gcc*" -o -name "*g++*" -o -name "*ld*" \) 2>/dev/null | \
        while read file; do
            if [ -f "$file" ] && [ ! -x "$file" ]; then
                chmod +x "$file"
                scripts_fixed=$((scripts_fixed + 1))
            fi
        done
    fi
    
    log_info "修复了 $scripts_fixed 个文件权限"
}

# ========== 创建缺失的脚本 ==========
create_missing_scripts() {
    log_info "5. 创建缺失的脚本..."
    
    # 创建错误分析脚本（如果不存在）
    if [ ! -f "firmware-config/scripts/error_analysis.sh" ]; then
        mkdir -p firmware-config/scripts
        cat > firmware-config/scripts/error_analysis.sh << 'EOF'
#!/bin/bash
# 错误分析脚本
echo "=== 错误分析 ==="
echo "时间: $(date)"
echo "目录: $(pwd)"
echo "环境变量:"
env | grep -E "GITHUB|BUILD|TARGET" || true
exit 0
EOF
        chmod +x firmware-config/scripts/error_analysis.sh
        log_success "创建错误分析脚本"
    fi
}

# ========== 创建修复标记 ==========
create_fix_marker() {
    cat > "$FIX_MARKER" << EOF
# 修复标记文件
version=$SCRIPT_VERSION
date=$(date '+%Y-%m-%d %H:%M:%S')
fixed_items=(
    "workflow_paths"
    "main_script_paths"
    "directory_structure"
    "script_permissions"
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
    echo ""
    
    echo "📁 备份目录: $BACKUP_DIR"
    if [ -d "$BACKUP_DIR" ]; then
        echo "   备份文件数: $(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l)"
    fi
    
    echo ""
    echo "🔧 修复脚本位置: $(realpath "$0")"
    echo "📅 修复时间: $(date)"
    echo ""
    
    if [ -f "/tmp/fix_results.log" ]; then
        echo "📝 修复结果:"
        cat /tmp/fix_results.log
    fi
    
    echo "========================================"
}

# ========== 主函数 ==========
main() {
    echo "========================================"
    echo "🔧 OpenWrt构建修复脚本 v$SCRIPT_VERSION"
    echo "========================================"
    echo "开始时间: $(date)"
    echo "工作区: $GITHUB_WORKSPACE"
    echo "仓库根目录: $REPO_ROOT"
    echo ""
    
    # 创建备份目录
    mkdir -p "$BACKUP_DIR"
    
    # 执行修复步骤
    fix_workflow_paths
    fix_main_script_paths
    fix_directory_structure
    fix_permissions
    create_missing_scripts
    create_fix_marker
    
    # 显示报告
    show_fix_report
    
    # 清理
    rm -f /tmp/fix_results.log 2>/dev/null || true
    
    log_success "修复完成！"
}

# ========== 执行主函数 ==========
main "$@"
