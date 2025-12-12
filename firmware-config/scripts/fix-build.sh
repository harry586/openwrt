#!/bin/bash
# OpenWrt编译智能修复脚本 v3.0（完整步骤修复版）
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
SCRIPT_VERSION="3.1"
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
    
    # 修复缺失的步骤
    log_info "检查并修复工作流步骤..."
    
    # 读取工作流内容
    local workflow_content=$(cat "$workflow_file")
    
    # 检查是否包含错误检查步骤
    if ! echo "$workflow_content" | grep -q "前置错误检查"; then
        log_info "添加前置错误检查步骤..."
        
        # 在编译步骤前插入错误检查
        local temp_file="/tmp/workflow_fixed.yml"
        awk '
        /步骤28：编译固件/ {
            print "      # 步骤27.5：前置错误检查"
            print "      - name: \"🚨 27.5 前置错误检查\""
            print "        run: |"
            print "          MAIN_SCRIPT=\"${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}\""
            print "          if [ -x \"$MAIN_SCRIPT\" ]; then"
            print "            \"$MAIN_SCRIPT\" workflow_main step26_pre_build_error_check"
            print "          fi"
            print ""
        }
        { print }
        ' "$workflow_file" > "$temp_file"
        
        cp "$temp_file" "$workflow_file"
        rm -f "$temp_file"
        log_success "已添加前置错误检查步骤"
    fi
    
    # 检查是否包含USB步骤
    if ! echo "$workflow_content" | grep -q "USB驱动完整性检查"; then
        log_info "添加USB相关步骤..."
        
        # 创建完整的工作流修复版本
        cat > "/tmp/workflow_complete.yml" << 'EOF'
name: OpenWrt 智能固件构建工作流（完整版）

on:
  workflow_dispatch:
    inputs:
      device_name:
        description: "📱 设备名称 (如: ac42u, acrh17, r3g等)"
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
        description: |
          ⚙️ 配置模式选择
          
          🟣 基础模式 - 最小化配置，用于测试编译
          🟠 正常模式 - 完整功能配置
          
          🔧 USB 3.0加强：所有平台的关键USB驱动都已强制启用！
        required: true
        type: choice
        default: "normal"
        options:
          - "base"
          - "normal"
      extra_packages:
        description: |
          额外安装插件
          格式：用分号;分隔。启用插件：+插件名。禁用插件：-插件名。
        required: false
        type: string
        default: ""
      enable_cache:
        description: "⚡ 启用编译缓存 (加速编译过程)"
        required: false
        default: true
        type: boolean
      save_toolchain:
        description: "💾 保存通用工具链 (节省下次编译时间)"
        required: false
        default: false
        type: boolean

env:
  BUILD_DIR: "/mnt/openwrt-build"
  GIT_LFS_SKIP_SMUDGE: 1
  ENABLE_CACHE: "true"

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
          mkdir -p /tmp/source-upload /tmp/build-artifacts /tmp/fix-logs
          echo "工作空间: ${{ github.workspace }}"
          echo "当前目录: $(pwd)"
          ls -la
      
      # 🔥 步骤1：智能修复脚本（优先级最高）
      - name: "🔧 1. 智能修复脚本"
        id: smart_fix
        continue-on-error: true
        run: |
          echo "=== 智能修复脚本开始 ==="
          
          # 智能查找修复脚本
          find_fix_script() {
            local script_name="$1"
            local search_dirs="$2"
            
            IFS=':' read -ra dirs <<< "$search_dirs"
            for dir in "${dirs[@]}"; do
              if [ -d "$dir" ]; then
                local found=$(find "$dir" -name "$script_name" -type f 2>/dev/null | head -1)
                if [ -n "$found" ]; then
                  echo "$found"
                  return 0
                fi
              fi
            done
            return 1
          }
          
          # 查找修复脚本
          FIX_SCRIPT=""
          SEARCH_DIRS=".:scripts:firmware-config/scripts:.github/scripts:automation"
          
          for script_name in "fix-build.sh" "fix-build-issues.sh" "repair-build.sh"; do
            FIX_SCRIPT=$(find_fix_script "$script_name" "$SEARCH_DIRS")
            if [ -n "$FIX_SCRIPT" ]; then
              echo "✅ 找到修复脚本: $FIX_SCRIPT"
              break
            fi
          done
          
          if [ -z "$FIX_SCRIPT" ]; then
            echo "⚠️  未找到修复脚本，创建默认修复脚本..."
            cat > /tmp/default-fix.sh << 'EOF'
#!/bin/bash
echo "=== 默认修复脚本 ==="
echo "创建必要的目录结构..."
mkdir -p firmware-config/scripts
mkdir -p firmware-config/Toolchain
mkdir -p .github/workflows
echo "✅ 默认修复完成"
EOF
            chmod +x /tmp/default-fix.sh
            FIX_SCRIPT="/tmp/default-fix.sh"
            echo "fix_script_location=default" >> $GITHUB_OUTPUT
            echo "fix_script_found_in=created" >> $GITHUB_OUTPUT
          else
            echo "fix_script_location=$FIX_SCRIPT" >> $GITHUB_OUTPUT
            echo "fix_script_found_in=found" >> $GITHUB_OUTPUT
          fi
          
          # 运行修复脚本
          echo "🚀 运行修复脚本: $FIX_SCRIPT"
          chmod +x "$FIX_SCRIPT"
          
          LOG_FILE="/tmp/fix-script-output-$(date +%Y%m%d_%H%M%S).log"
          
          timeout 300 bash "$FIX_SCRIPT" 2>&1 | tee "$LOG_FILE"
          
          FIX_EXIT_CODE=${PIPESTATUS[0]}
          
          if [ $FIX_EXIT_CODE -eq 0 ]; then
            echo "✅ 修复脚本执行成功"
            echo "fix_script_status=success" >> $GITHUB_OUTPUT
          elif [ $FIX_EXIT_CODE -eq 124 ]; then
            echo "⏰ 修复脚本执行超时"
            echo "fix_script_status=timeout" >> $GITHUB_OUTPUT
          else
            echo "⚠️ 修复脚本执行有错误"
            echo "fix_script_status=error" >> $GITHUB_OUTPUT
          fi
          
          # 复制日志文件
          cp "$LOG_FILE" /tmp/fix-logs/ 2>/dev/null || true
      
      # 步骤2：智能查找主构建脚本
      - name: "🔍 2. 智能查找主构建脚本"
        id: find_main_script
        run: |
          echo "=== 智能查找主构建脚本 ==="
          
          cd "${{ github.workspace }}"
          
          # 智能查找主脚本
          find_main_script() {
            local possible_paths=(
              "firmware-config/scripts/build_firmware_main.sh"
              "scripts/build_firmware_main.sh" 
              "build_firmware_main.sh"
              ".github/scripts/build_firmware_main.sh"
            )
            
            for path in "${possible_paths[@]}"; do
              if [ -f "$path" ]; then
                echo "$path"
                return 0
              fi
            done
            
            # 递归查找
            local found=$(find . -name "build_firmware_main.sh" -type f 2>/dev/null | head -1)
            if [ -n "$found" ]; then
              echo "$found"
              return 0
            fi
            
            return 1
          }
          
          MAIN_SCRIPT=$(find_main_script)
          
          if [ -n "$MAIN_SCRIPT" ]; then
            echo "✅ 找到主构建脚本: $MAIN_SCRIPT"
            
            # 确保脚本可执行
            chmod +x "$MAIN_SCRIPT"
            
            # 计算仓库根目录
            REPO_ROOT=$(cd "$(dirname "$MAIN_SCRIPT")/../.." && pwd)
            
            echo "📊 脚本信息:"
            echo "  路径: $MAIN_SCRIPT"
            echo "  大小: $(ls -lh "$MAIN_SCRIPT" | awk '{print $5}')"
            echo "  权限: $(ls -la "$MAIN_SCRIPT" | awk '{print $1}')"
            echo "  仓库根目录: $REPO_ROOT"
            
            # 设置输出变量
            echo "MAIN_SCRIPT_PATH=$MAIN_SCRIPT" >> $GITHUB_OUTPUT
            echo "REPO_ROOT=$REPO_ROOT" >> $GITHUB_OUTPUT
            echo "script_found=true" >> $GITHUB_OUTPUT
          else
            echo "❌ 未找到主构建脚本"
            echo "当前目录内容:"
            find . -maxdepth 3 -type f -name "*.sh" | head -10
            
            echo "script_found=false" >> $GITHUB_OUTPUT
            exit 1
          fi
      
      # 步骤3：下载源代码（使用找到的脚本）
      - name: "📥 3. 下载源代码"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          echo "=== 下载源代码 ==="
          
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          WORKSPACE="${{ github.workspace }}"
          
          echo "使用主脚本: $MAIN_SCRIPT"
          echo "工作空间: $WORKSPACE"
          
          # 检查脚本是否存在且可执行
          if [ ! -f "$MAIN_SCRIPT" ]; then
            echo "❌ 主脚本不存在: $MAIN_SCRIPT"
            exit 1
          fi
          
          if [ ! -x "$MAIN_SCRIPT" ]; then
            echo "🔧 添加执行权限..."
            chmod +x "$MAIN_SCRIPT"
          fi
          
          # 执行下载步骤
          "$MAIN_SCRIPT" workflow_main step1_download_source "$WORKSPACE"
      
      # 步骤4：上传源代码压缩包
      - name: "📤 4. 上传源代码压缩包"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          echo "=== 上传源代码压缩包 ==="
          
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step2_upload_source
          else
            echo "⚠️  主脚本不可执行，跳过上传"
          fi
      
      - name: "📦 5. 上传源代码压缩包到Artifacts"
        uses: actions/upload-artifact@v4
        with:
          name: "source-code-${{ github.event.inputs.device_name }}-${{ github.run_id }}"
          path: /tmp/source-upload/
      
      # 步骤6：Git LFS配置
      - name: "🔧 6. Git LFS配置"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          echo "=== Git LFS配置 ==="
          
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step4_install_git_lfs
          else
            echo "⚠️  主脚本不可执行，使用原生命令"
            sudo apt-get update
            sudo apt-get install -y git-lfs
            git lfs install --force
          fi
      
      # 步骤7：大文件检查
      - name: "📊 7. 大文件检查"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step5_check_large_files
          fi
      
      # 步骤8：工具链目录检查
      - name: "🗂️ 8. 工具链目录检查"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step6_check_toolchain_dir
          fi
      
      # 步骤9：初始化工具链
      - name: "💾 9. 初始化工具链"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step7_init_toolchain_dir
          fi
      
      # 步骤10：设置环境
      - name: "🛠️ 10. 设置环境"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step8_setup_environment
          else
            echo "⚠️  主脚本不可执行，使用基础环境设置"
            sudo apt-get update
            sudo apt-get install -y build-essential ccache git
          fi
      
      # 步骤11：创建目录
      - name: "📁 11. 创建目录"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step9_create_build_dir
          fi
      
      # 步骤12：初始化构建环境
      - name: "🚀 12. 初始化构建环境"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step10_init_build_env \
              "${{ github.event.inputs.device_name }}" \
              "${{ github.event.inputs.version_selection }}" \
              "${{ github.event.inputs.config_mode }}" \
              "${{ github.event.inputs.extra_packages }}"
          else
            echo "❌ 主脚本不可执行，无法初始化构建环境"
            exit 1
          fi
      
      # 步骤13：显示配置
      - name: "⚡ 13. 显示配置"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step11_show_config
          fi
      
      # 步骤14：添加TurboACC支持
      - name: "🔌 14. 添加TurboACC支持"
        if: steps.find_main_script.outputs.script_found == 'true' && github.event.inputs.config_mode == 'normal'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step12_add_turboacc_support
          fi
      
      # 步骤15：配置Feeds
      - name: "📦 15. 配置Feeds"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step13_configure_feeds
          fi
      
      # 步骤16：安装TurboACC包
      - name: "🔧 16. 安装TurboACC包"
        if: steps.find_main_script.outputs.script_found == 'true' && env.SELECTED_BRANCH == 'openwrt-23.05' && github.event.inputs.config_mode == 'normal'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step14_install_turboacc_packages
          fi
      
      # 步骤17：空间检查
      - name: "💽 17. 空间检查"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step15_pre_build_space_check
          else
            echo "=== 基本空间检查 ==="
            df -h
            free -h
          fi
      
      # 步骤18：生成配置
      - name: "⚙️ 18. 生成配置"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step16_generate_config "${{ github.event.inputs.extra_packages }}"
          fi
      
      # 步骤19：验证USB配置
      - name: "🔍 19. 验证USB配置"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step17_verify_usb_config
          fi
      
      # 步骤20：USB驱动完整性检查
      - name: "🛡️ 20. USB驱动完整性检查"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step18_check_usb_drivers_integrity
          fi
      
      # 步骤21：应用配置并显示详情
      - name: "✅ 21. 应用配置并显示详情"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step19_apply_config
          fi
      
      # 步骤22：备份配置
      - name: "💾 22. 备份配置"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step20_backup_config
          fi
      
      # 步骤23：修复网络
      - name: "🌐 23. 修复网络"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step21_fix_network
          fi
      
      # 步骤24：加载工具链
      - name: "🔧 24. 加载工具链"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step22_load_toolchain
          fi
      
      # 步骤25：检查工具链状态
      - name: "📊 25. 检查工具链状态"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step23_check_toolchain_status
          fi
      
      # 步骤26：下载依赖包
      - name: "📥 26. 下载依赖包"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step24_download_dependencies
          fi
      
      # 步骤27：集成自定义文件
      - name: "🔌 27. 集成自定义文件"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step25_integrate_custom_files
          fi
      
      # 步骤28：前置错误检查
      - name: "🚨 28. 前置错误检查"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step26_pre_build_error_check
          fi
      
      # 步骤29：最终空间检查
      - name: "💽 29. 最终空间检查"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step27_final_space_check
          else
            echo "=== 最终空间检查 ==="
            df -h
            AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
            AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
            echo "可用空间: ${AVAILABLE_GB}G"
          fi
      
      # 步骤30：编译固件
      - name: "🔨 30. 编译固件"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step28_build_firmware
          else
            echo "❌ 主脚本不可执行，无法编译固件"
            exit 1
          fi
      
      # 步骤31：保存通用工具链
      - name: "💾 31. 保存通用工具链"
        if: steps.find_main_script.outputs.script_found == 'true' && github.event.inputs.save_toolchain == 'true' && success()
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step29_save_essential_toolchain
          fi
      
      # 步骤32：提交修复结果
      - name: "💾 32. 提交修复结果到仓库"
        if: steps.smart_fix.outputs.fix_script_status == 'success' && steps.find_main_script.outputs.script_found == 'true' && success()
        run: |
          echo "=== 提交修复结果 ==="
          
          cd "${{ github.workspace }}"
          
          # 检查是否有需要提交的更改
          echo "检查Git状态..."
          git status --porcelain | head -20
          
          CHANGED_FILES=$(git status --porcelain | grep -E "\.(sh|yml|md)$" | wc -l)
          
          if [ $CHANGED_FILES -gt 0 ]; then
            echo "📦 检测到 $CHANGED_FILES 个文件更改，准备提交..."
            
            # 配置Git
            git config --global user.name "GitHub Actions Bot"
            git config --global user.email "actions@github.com"
            
            # 添加更改
            git add -A
            
            # 创建提交信息
            COMMIT_MSG="fix: 自动修复更新 [$(date '+%Y-%m-%d %H:%M:%S')]
            
            修复内容:
            - 路径问题修复
            - 脚本权限修复
            - 配置文件优化
            修复脚本状态: ${{ steps.smart_fix.outputs.fix_script_status }}
            设备: ${{ github.event.inputs.device_name }}
            模式: ${{ github.event.inputs.config_mode }}"
            
            # 提交更改
            if git commit -m "$COMMIT_MSG"; then
              echo "✅ 更改已提交到本地仓库"
              
              # 尝试推送
              for i in {1..3}; do
                echo "推送尝试 #$i/3..."
                if git push; then
                  echo "✅ 修复结果已成功推送到远程仓库"
                  break
                else
                  echo "推送失败，等待10秒后重试..."
                  sleep 10
                fi
              done
            else
              echo "⚠️  提交失败，可能没有需要提交的更改"
            fi
          else
            echo "ℹ️  没有检测到文件更改，跳过提交"
          fi
      
      # 步骤33：错误分析（如果失败）
      - name: "⚠️ 33. 错误分析"
        if: failure()
        run: |
          echo "=== 编译失败分析 ==="
          
          # 智能查找错误分析脚本
          ERROR_SCRIPT=""
          
          for path in "firmware-config/scripts/error_analysis.sh" "scripts/error_analysis.sh" "error_analysis.sh"; do
            if [ -f "$path" ]; then
              ERROR_SCRIPT="$path"
              break
            fi
          done
          
          if [ -n "$ERROR_SCRIPT" ]; then
            echo "运行错误分析脚本: $ERROR_SCRIPT"
            chmod +x "$ERROR_SCRIPT"
            bash "$ERROR_SCRIPT"
          else
            echo "未找到错误分析脚本，执行基本分析..."
            echo "=== 基本错误分析 ==="
            echo "时间: $(date)"
            echo "工作空间: ${{ github.workspace }}"
            echo "构建目录: /mnt/openwrt-build"
            echo ""
            echo "=== 磁盘空间 ==="
            df -h
            echo ""
            echo "=== 内存使用 ==="
            free -h
          fi
      
      # 步骤34：编译后检查
      - name: "📊 34. 编译后检查"
        if: steps.find_main_script.outputs.script_found == 'true'
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step32_post_build_space_check
          fi
      
      # 步骤35：固件检查
      - name: "📦 35. 固件检查"
        if: steps.find_main_script.outputs.script_found == 'true' && success()
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step33_check_firmware_files
          fi
      
      # 步骤36：上传固件
      - name: "⬆️ 36. 上传固件"
        if: steps.find_main_script.outputs.script_found == 'true' && success()
        uses: actions/upload-artifact@v4
        with:
          name: "firmware-${{ github.event.inputs.device_name }}-${{ env.SELECTED_BRANCH || 'unknown' }}-${{ github.event.inputs.config_mode }}"
          path: /mnt/openwrt-build/bin/targets/
          retention-days: 30
      
      # 步骤37：上传日志
      - name: "⬆️ 37. 上传日志"
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: "build-log-${{ github.event.inputs.device_name }}-${{ github.run_id }}"
          path: /mnt/openwrt-build/build.log
          retention-days: 30
      
      # 步骤38：上传配置
      - name: "⬆️ 38. 上传配置"
        if: always() && steps.find_main_script.outputs.script_found == 'true'
        uses: actions/upload-artifact@v4
        with:
          name: "config-${{ github.event.inputs.device_name }}-${{ github.run_id }}"
          path: ${{ github.workspace }}/firmware-config/config-backup/
          retention-days: 30
      
      # 步骤39：上传修复脚本日志
      - name: "⬆️ 39. 上传修复脚本日志"
        if: always() && steps.smart_fix.outputs.fix_script_status != 'not_found'
        uses: actions/upload-artifact@v4
        with:
          name: "fix-script-logs-${{ github.event.inputs.device_name }}-${{ github.run_id }}"
          path: /tmp/fix-logs/
          retention-days: 30
      
      # 步骤40：清理目录
      - name: "🧹 40. 清理目录"
        if: always()
        run: |
          MAIN_SCRIPT="${{ steps.find_main_script.outputs.MAIN_SCRIPT_PATH }}"
          
          if [ -x "$MAIN_SCRIPT" ]; then
            "$MAIN_SCRIPT" workflow_main step37_cleanup
          else
            echo "=== 基本清理 ==="
            if [ -d "/mnt/openwrt-build" ]; then
              echo "清理构建目录..."
              sudo rm -rf /mnt/openwrt-build/* 2>/dev/null || true
            fi
          fi
      
      # 步骤41：最终构建总结
      - name: "📈 41. 最终构建总结"
        if: always()
        run: |
          echo "========================================"
          echo "🏁 最终构建总结"
          echo "========================================"
          echo ""
          
          echo "📊 构建状态: ${{ job.status }}"
          echo "📱 设备: ${{ github.event.inputs.device_name }}"
          echo "🔄 版本: ${{ github.event.inputs.version_selection }}"
          echo "⚙️ 配置模式: ${{ github.event.inputs.config_mode }}"
          
          if [ -n "${{ env.SELECTED_BRANCH }}" ]; then
            echo "🌿 分支: ${{ env.SELECTED_BRANCH }}"
          fi
          
          if [ -n "${{ env.TARGET }}" ]; then
            echo "🎯 目标平台: ${{ env.TARGET }}/${{ env.SUBTARGET }}"
          fi
          
          echo ""
          echo "🔧 修复脚本状态: ${{ steps.smart_fix.outputs.fix_script_status || '未运行' }}"
          echo "📝 主脚本状态: ${{ steps.find_main_script.outputs.script_found || '未找到' }}"
          
          if [ "${{ job.status }}" = "success" ]; then
            echo ""
            echo "✅ 构建成功！"
            echo "📥 构建产物已上传到Artifacts"
            echo ""
            echo "💾 工具链状态:"
            if [ "${{ github.event.inputs.enable_cache }}" = "true" ]; then
              echo "  ✅ 编译缓存已启用"
            fi
            
            if [ "${{ github.event.inputs.save_toolchain }}" = "true" ]; then
              echo "  ✅ 通用工具链已保存"
            fi
          else
            echo ""
            echo "❌ 构建失败"
            echo "🔍 请查看错误分析日志和构建日志"
          fi
          
          echo ""
          echo "========================================"
          echo "          🏁 构建流程全部完成          "
          echo "========================================"
EOF
        
        # 比较文件差异
        if ! diff -q "$workflow_file" "/tmp/workflow_complete.yml" > /dev/null; then
            cp "/tmp/workflow_complete.yml" "$workflow_file"
            log_success "工作流文件已修复为完整版"
            echo "workflow_fixed=true" >> /tmp/fix_results.log
        else
            log_info "工作流文件无需修复"
        fi
        
        rm -f "/tmp/workflow_complete.yml"
    else
        log_info "工作流文件已包含所有必要步骤"
    fi
    
    # 验证工作流语法
    log_info "验证工作流语法..."
    if command -v yamllint > /dev/null 2>&1; then
        yamllint "$workflow_file" && log_success "工作流语法验证通过" || log_warn "工作流语法验证有警告"
    else
        log_info "跳过yaml语法检查（yamllint未安装）"
    fi
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
    
    # 检查脚本是否包含所有必要函数
    local missing_functions=()
    
    # 检查的关键函数
    local required_functions=(
        "add_turboacc_support"
        "install_turboacc_packages"
        "verify_usb_config"
        "check_usb_drivers_integrity"
        "integrate_custom_files"
        "pre_build_error_check"
        "apply_config"
    )
    
    for func in "${required_functions[@]}"; do
        if ! grep -q "^$func()" "$main_script"; then
            missing_functions+=("$func")
        fi
    done
    
    if [ ${#missing_functions[@]} -gt 0 ]; then
        log_warn "缺失函数: ${missing_functions[*]}"
        log_info "从旧脚本复制缺失函数..."
        
        local old_script=$(smart_find "旧build_firmware_main.sh" 4)
        if [ -n "$old_script" ]; then
            # 备份原文件
            local backup="${main_script}.backup.$(date +%s)"
            cp "$main_script" "$backup"
            
            # 创建修复版
            local temp_file="/tmp/main_script_fixed.sh"
            
            # 从旧脚本提取缺失函数
            for func in "${missing_functions[@]}"; do
                log_info "提取函数: $func"
                
                # 使用awk提取函数
                awk -v func="$func" '
                $0 ~ "^" func "\(\)" {
                    print_line = 1
                    print $0
                    next
                }
                print_line == 1 {
                    print $0
                    if ($0 == "}") {
                        print_line = 0
                        print ""
                    }
                }
                ' "$old_script" >> "$temp_file"
            done
            
            # 将缺失函数添加到主脚本末尾（在最后一个函数之后）
            local last_function_line=$(grep -n "^}" "$main_script" | tail -1 | cut -d: -f1)
            
            if [ -n "$last_function_line" ]; then
                # 插入缺失函数
                head -n "$last_function_line" "$main_script" > "/tmp/main_part1.sh"
                tail -n +$((last_function_line + 1)) "$main_script" > "/tmp/main_part2.sh"
                
                cat "/tmp/main_part1.sh" "$temp_file" "/tmp/main_part2.sh" > "${main_script}.new"
                
                # 比较差异
                if ! diff -q "$main_script" "${main_script}.new" > /dev/null; then
                    mv "${main_script}.new" "$main_script"
                    chmod +x "$main_script"
                    log_success "主构建脚本已修复，添加了 ${#missing_functions[@]} 个缺失函数"
                    echo "main_script_fixed=true" >> /tmp/fix_results.log
                else
                    log_info "主构建脚本无需修复"
                    rm -f "${main_script}.new"
                fi
                
                rm -f "/tmp/main_part1.sh" "/tmp/main_part2.sh"
            fi
            
            rm -f "$temp_file"
        else
            log_error "未找到旧脚本，无法复制缺失函数"
        fi
    else
        log_success "主构建脚本已包含所有必要函数"
    fi
    
    # 确保脚本可执行
    chmod +x "$main_script"
}

# ========== 修复目录结构 ==========
fix_directory_structure() {
    log_info "3. 修复目录结构..."
    
    local dirs_created=0
    
    # 创建必要的目录
    for dir in "firmware-config/scripts" \
               "firmware-config/Toolchain" \
               "firmware-config/config-backup" \
               "firmware-config/custom-files" \
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
    
    scripts_created=0
    
    # 创建错误分析脚本（如果不存在）
    if [ ! -f "firmware-config/scripts/error_analysis.sh" ]; then
        mkdir -p firmware-config/scripts
        cat > firmware-config/scripts/error_analysis.sh << 'EOF'
#!/bin/bash
# 错误分析脚本 v2.0

echo "========================================"
echo "⚠️  错误分析报告"
echo "========================================"
echo ""

echo "📅 分析时间: $(date)"
echo "📁 当前目录: $(pwd)"
echo "🔧 构建目录: ${{ env.BUILD_DIR || '/mnt/openwrt-build' }}"
echo ""

echo "=== 系统信息 ==="
echo "主机名: $(hostname)"
echo "内核版本: $(uname -r)"
echo "系统架构: $(uname -m)"
echo ""

echo "=== 磁盘空间 ==="
df -h
echo ""

echo "=== 内存使用 ==="
free -h
echo ""

echo "=== CPU信息 ==="
echo "CPU核心数: $(nproc)"
echo "CPU负载: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

echo "=== 网络连接 ==="
echo "外部连通性测试..."
timeout 5 curl -s --connect-timeout 3 https://github.com > /dev/null && echo "✅ 外部网络连通" || echo "❌ 外部网络不通"
echo ""

echo "=== 构建目录状态 ==="
if [ -d "/mnt/openwrt-build" ]; then
    echo "构建目录存在"
    echo "目录大小: $(du -sh /mnt/openwrt-build 2>/dev/null | cut -f1 || echo '未知')"
    echo ""
    
    echo "=== 关键文件检查 ==="
    for file in "/mnt/openwrt-build/openwrt/.config" "/mnt/openwrt-build/openwrt/build.log" "/mnt/openwrt-build/openwrt/download.log"; do
        if [ -f "$file" ]; then
            echo "✅ $file 存在 ($(ls -lh "$file" | awk '{print $5}'))"
        else
            echo "❌ $file 不存在"
        fi
    done
else
    echo "❌ 构建目录不存在"
fi

echo ""
echo "=== 最后10行构建日志 ==="
if [ -f "/mnt/openwrt-build/openwrt/build.log" ]; then
    tail -20 "/mnt/openwrt-build/openwrt/build.log"
else
    echo "构建日志不存在"
fi

echo ""
echo "=== 常见错误模式 ==="
if [ -f "/mnt/openwrt-build/openwrt/build.log" ]; then
    echo "1. 内存不足错误:"
    grep -i "out of memory\|killed\|oom" "/mnt/openwrt-build/openwrt/build.log" | head -3 || echo "   未发现"
    echo ""
    echo "2. 编译错误:"
    grep -i "error:" "/mnt/openwrt-build/openwrt/build.log" | head -5 || echo "   未发现"
    echo ""
    echo "3. 文件缺失错误:"
    grep -i "no such file\|not found" "/mnt/openwrt-build/openwrt/build.log" | head -3 || echo "   未发现"
fi

echo ""
echo "========================================"
echo "💡 建议操作:"
echo "1. 检查磁盘空间是否充足"
echo "2. 查看完整的构建日志"
echo "3. 检查网络连接"
echo "4. 清理构建目录后重试"
echo "========================================"
EOF
        chmod +x firmware-config/scripts/error_analysis.sh
        scripts_created=$((scripts_created + 1))
        log_success "创建错误分析脚本"
    fi
    
    log_info "共创建了 $scripts_created 个缺失脚本"
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
    echo "   1. 工作流文件路径修复（包含所有步骤）"
    echo "   2. 主构建脚本路径修复（补充缺失函数）"
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
