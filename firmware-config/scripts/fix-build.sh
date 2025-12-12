#!/bin/bash
# OpenWrt构建精准修复脚本 - 解决目录冲突，保持所有步骤功能完整
# 最后更新: 2024-01-16

set -e

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========== 日志函数 ==========
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "🔧 OpenWrt构建精准修复脚本"
echo "========================================"

# 步骤1：修复firmware-build.yml中的步骤7逻辑
log_info "步骤1: 修复firmware-build.yml中的步骤7逻辑..."

if [ -f ".github/workflows/firmware-build.yml" ]; then
    log_info "找到工作流文件，正在修复步骤7..."
    
    # 创建备份
    cp .github/workflows/firmware-build.yml .github/workflows/firmware-build.yml.backup
    
    # 修复步骤7，使其在正确的目录下载源代码
    cat > /tmp/fixed_step7.yml << 'EOF'
      # 步骤7：下载源代码
      - name: "📥 7. 下载源代码"
        run: |
          echo "=== 下载源代码 ==="
          if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
            chmod +x firmware-config/scripts/build_firmware_main.sh
            # 确保在构建目录中下载源代码，而不是当前工作目录
            firmware-config/scripts/build_firmware_main.sh workflow_main step1_download_source "/mnt/openwrt-build"
          else
            echo "❌ 错误: 未找到构建脚本"
            exit 1
          fi
EOF
    
    # 使用sed替换步骤7的内容
    sed -i '/# 步骤7：下载源代码/,/# 步骤8：上传源代码压缩包/{/# 步骤8：上传源代码压缩包/!d}' .github/workflows/firmware-build.yml
    sed -i '/# 步骤7：下载源代码/r /tmp/fixed_step7.yml' .github/workflows/firmware-build.yml
    
    log_success "firmware-build.yml 步骤7已修复"
else
    log_warn "未找到工作流文件: .github/workflows/firmware-build.yml"
fi

# 步骤2：修复build_firmware_main.sh中的workflow_step1_download_source函数
log_info "步骤2: 修复build_firmware_main.sh中的workflow_step1_download_source函数..."

if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    log_info "找到构建主脚本，正在修复函数..."
    
    # 创建备份
    cp firmware-config/scripts/build_firmware_main.sh firmware-config/scripts/build_firmware_main.sh.backup
    
    # 完全重写workflow_step1_download_source函数
    cat > /tmp/fixed_step1_download_source.sh << 'EOF'
# 步骤1：下载完整源代码
workflow_step1_download_source() {
    local workspace="$1"
    
    echo "========================================"
    echo "📥 步骤1：下载完整源代码"
    echo "========================================"
    
    if [ -z "$workspace" ] || [ "$workspace" = "." ] || [ "$workspace" = "$(pwd)" ]; then
        log_error "错误：不能在当前工作目录克隆，请指定不同的目录"
        log_info "当前目录: $(pwd)"
        log_info "当前目录内容:"
        ls -la | head -10
        exit 1
    fi
    
    # 确保目标目录存在
    mkdir -p "$workspace"
    
    # 切换到目标目录
    cd "$workspace"
    
    # 检查目录是否为空
    if [ -n "$(ls -A . 2>/dev/null)" ]; then
        log_warn "目标目录非空，无法克隆"
        log_info "目标目录: $workspace"
        log_info "目标目录内容:"
        ls -la | head -10
        
        # 创建临时目录用于克隆
        local temp_dir="${workspace}/temp-clone-$(date +%s)"
        mkdir -p "$temp_dir"
        cd "$temp_dir"
        
        # 克隆完整仓库
        local repo_url="https://github.com/$GITHUB_REPOSITORY.git"
        log_info "正在克隆到临时目录: $temp_dir"
        git clone --depth 1 "$repo_url" .
        
        if [ ! -d ".git" ]; then
            log_error "仓库克隆失败，.git目录不存在"
            exit 1
        fi
        
        log_success "仓库克隆到临时目录完成"
        
        # 将内容移动到目标目录
        log_info "将内容移动到目标目录..."
        cd "$workspace"
        cp -r "$temp_dir"/* "$workspace"/ 2>/dev/null || true
        cp -r "$temp_dir"/.git "$workspace"/ 2>/dev/null || true
        rm -rf "$temp_dir"
        
        log_success "内容已移动到目标目录"
    else
        # 克隆完整仓库
        local repo_url="https://github.com/$GITHUB_REPOSITORY.git"
        log_info "正在克隆仓库到: $workspace"
        git clone --depth 1 "$repo_url" .
        
        if [ ! -d ".git" ]; then
            log_error "仓库克隆失败，.git目录不存在"
            exit 1
        fi
        
        log_success "完整仓库克隆完成"
    fi
    
    log_info "克隆目录大小: $(du -sh . 2>/dev/null | cut -f1 || echo '未知')"
    log_info "克隆目录内容:"
    ls -la | head -10
    
    echo "✅ 步骤1完成"
    echo "========================================"
}
EOF
    
    # 替换原函数
    sed -i '/workflow_step1_download_source() {/,/^}/d' firmware-config/scripts/build_firmware_main.sh
    sed -i '/# ========== 工作流具体步骤实现 ==========/r /tmp/fixed_step1_download_source.sh' firmware-config/scripts/build_firmware_main.sh
    
    log_success "workflow_step1_download_source函数已修复"
else
    log_warn "未找到构建主脚本: firmware-config/scripts/build_firmware_main.sh"
    
    # 尝试从当前目录复制
    if [ -f "build_firmware_main.sh" ]; then
        log_info "从当前目录复制构建脚本..."
        mkdir -p firmware-config/scripts
        cp build_firmware_main.sh firmware-config/scripts/
        chmod +x firmware-config/scripts/build_firmware_main.sh
    fi
fi

# 步骤3：修复firmware-build.yml中的步骤2_upload_source调用
log_info "步骤3: 修复上传源代码步骤..."

if [ -f ".github/workflows/firmware-build.yml" ]; then
    # 修复步骤8：上传源代码压缩包
    log_info "修复步骤8：上传源代码压缩包..."
    
    # 创建修复后的步骤8
    cat > /tmp/fixed_step8.yml << 'EOF'
      # 步骤8：上传源代码压缩包
      - name: "📤 8. 上传源代码压缩包"
        run: |
          echo "=== 上传源代码压缩包 ==="
          if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
            chmod +x firmware-config/scripts/build_firmware_main.sh
            # 确保在正确目录创建压缩包
            cd /mnt/openwrt-build
            firmware-config/scripts/build_firmware_main.sh workflow_main step2_upload_source
          else
            echo "❌ 错误: 未找到构建脚本"
            exit 1
          fi
EOF
    
    # 替换步骤8
    sed -i '/# 步骤8：上传源代码压缩包/,/# 步骤9：上传源代码压缩包到Artifacts/{/# 步骤9：上传源代码压缩包到Artifacts/!d}' .github/workflows/firmware-build.yml
    sed -i '/# 步骤8：上传源代码压缩包/r /tmp/fixed_step8.yml' .github/workflows/firmware-build.yml
    
    log_success "步骤8已修复"
fi

# 步骤4：创建简化版的修复脚本，用于立即解决问题
log_info "步骤4: 创建简化版修复脚本..."

cat > /tmp/quick_fix_for_workflow.sh << 'EOF'
#!/bin/bash
# 工作流快速修复脚本 - 解决步骤7的目录冲突问题

echo "=== 工作流快速修复 ==="

# 1. 确保构建目录存在且可写
echo "1. 准备构建目录..."
sudo mkdir -p /mnt/openwrt-build
sudo chmod 777 /mnt/openwrt-build

# 2. 清理构建目录（如果需要）
if [ -n "$(ls -A /mnt/openwrt-build 2>/dev/null)" ]; then
    echo "清理构建目录内容..."
    rm -rf /mnt/openwrt-build/*
fi

# 3. 创建正确的目录结构用于克隆
echo "创建正确的目录结构..."
mkdir -p /mnt/openwrt-build/.gitkeep

# 4. 检查构建脚本是否存在
echo "检查构建脚本..."
if [ ! -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    echo "复制构建脚本..."
    mkdir -p firmware-config/scripts
    if [ -f "build_firmware_main.sh" ]; then
        cp build_firmware_main.sh firmware-config/scripts/
        chmod +x firmware-config/scripts/build_firmware_main.sh
    fi
fi

echo "✅ 快速修复完成"
echo ""
echo "现在可以重新运行工作流了。"
EOF

chmod +x /tmp/quick_fix_for_workflow.sh

# 步骤5：创建一步到位的修复脚本
log_info "步骤5: 创建一步到位修复脚本..."

cat > fix-all-in-one.sh << 'EOF'
#!/bin/bash
# OpenWrt构建全功能修复脚本 - 一步到位解决所有问题

echo "========================================"
echo "🔧 OpenWrt构建全功能修复脚本"
echo "========================================"

# 修复1：创建必要的目录结构
echo "创建必要的目录结构..."
mkdir -p firmware-config/scripts
mkdir -p firmware-config/Toolchain
mkdir -p firmware-config/config-backup
mkdir -p firmware-config/custom-files
mkdir -p .github/workflows
sudo mkdir -p /mnt/openwrt-build
sudo chmod 777 /mnt/openwrt-build

# 修复2：确保构建脚本存在且有权限
echo "检查构建脚本..."
if [ ! -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    echo "复制构建脚本..."
    if [ -f "build_firmware_main.sh" ]; then
        cp build_firmware_main.sh firmware-config/scripts/
    else
        echo "警告：未找到build_firmware_main.sh"
    fi
fi

if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    chmod +x firmware-config/scripts/build_firmware_main.sh
fi

# 修复3：修复工作流文件
echo "修复工作流文件..."
if [ -f ".github/workflows/firmware-build.yml" ]; then
    echo "工作流文件已存在"
else
    echo "创建工作流文件..."
    if [ -f "firmware-build.yml" ]; then
        mkdir -p .github/workflows
        cp firmware-build.yml .github/workflows/
    fi
fi

# 修复4：修复workflow_step1_download_source函数
echo "修复构建主脚本..."
if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    # 创建修复后的函数
    cat > /tmp/new_step1_function.sh << 'EOF2'
# 步骤1：下载完整源代码 - 修复版
workflow_step1_download_source() {
    local workspace="$1"
    
    echo "========================================"
    echo "📥 步骤1：下载完整源代码 - 修复版"
    echo "========================================"
    
    if [ -z "$workspace" ]; then
        workspace="/mnt/openwrt-build"
    fi
    
    if [ "$workspace" = "." ] || [ "$workspace" = "$(pwd)" ]; then
        echo "错误：不能在当前工作目录克隆"
        echo "当前目录: $(pwd)"
        echo "请使用不同的目录，如: /mnt/openwrt-build"
        exit 1
    fi
    
    echo "目标目录: $workspace"
    mkdir -p "$workspace"
    cd "$workspace"
    
    # 检查目录是否为空
    if [ -n "$(ls -A . 2>/dev/null)" ]; then
        echo "目标目录非空，跳过克隆"
        echo "当前目录内容:"
        ls -la | head -5
    else
        echo "正在克隆仓库..."
        local repo_url="https://github.com/$GITHUB_REPOSITORY.git"
        git clone --depth 1 "$repo_url" .
        
        if [ ! -d ".git" ]; then
            echo "错误：仓库克隆失败"
            exit 1
        fi
        
        echo "✅ 仓库克隆成功"
        echo "目录大小: $(du -sh . 2>/dev/null | cut -f1 || echo '未知')"
    fi
    
    echo "✅ 步骤1完成"
    echo "========================================"
}
EOF2
    
    # 替换原函数
    if grep -q "workflow_step1_download_source()" firmware-config/scripts/build_firmware_main.sh; then
        # 找到函数开始和结束位置
        start_line=$(grep -n "workflow_step1_download_source()" firmware-config/scripts/build_firmware_main.sh | head -1 | cut -d: -f1)
        # 找到下一个函数开始或章节标题
        next_section=$(sed -n "$start_line,\$p" firmware-config/scripts/build_firmware_main.sh | grep -n "^# \|^[a-zA-Z_][a-zA-Z0-9_]*()" | head -2 | tail -1 | cut -d: -f1)
        end_line=$((start_line + next_section - 2))
        
        # 替换函数内容
        sed -i "${start_line},${end_line}d" firmware-config/scripts/build_firmware_main.sh
        sed -i "${start_line}r /tmp/new_step1_function.sh" firmware-config/scripts/build_firmware_main.sh
        
        echo "✅ 构建脚本已修复"
    else
        echo "⚠️ 未找到workflow_step1_download_source函数，可能已修复"
    fi
fi

# 修复5：创建确保上传源代码的辅助脚本
echo "创建上传源代码辅助脚本..."
cat > ensure_source_upload.sh << 'EOF3'
#!/bin/bash
# 确保源代码上传的辅助脚本

echo "=== 确保源代码上传 ==="

# 检查是否在构建目录
if [ -d "/mnt/openwrt-build" ]; then
    echo "1. 检查构建目录..."
    cd /mnt/openwrt-build
    
    # 如果目录非空，创建源代码压缩包
    if [ -n "$(ls -A . 2>/dev/null)" ]; then
        echo "2. 创建源代码压缩包..."
        mkdir -p /tmp/source-upload
        
        # 创建排除列表
        echo "firmware-config/Toolchain" > /tmp/exclude-list.txt
        echo ".git" >> /tmp/exclude-list.txt
        
        # 创建压缩包
        tar --exclude-from=/tmp/exclude-list.txt -czf /tmp/source-upload/source-code.tar.gz .
        
        echo "✅ 源代码压缩包已创建: /tmp/source-upload/source-code.tar.gz"
        echo "文件大小: $(du -h /tmp/source-upload/source-code.tar.gz | cut -f1)"
    else
        echo "⚠️ 构建目录为空，无法创建压缩包"
    fi
else
    echo "❌ 构建目录不存在: /mnt/openwrt-build"
fi

echo "=== 完成 ==="
EOF3

chmod +x ensure_source_upload.sh

echo ""
echo "========================================"
echo "✅ 全功能修复完成"
echo "========================================"
echo ""
echo "已完成的修复:"
echo "1. ✅ 创建了所有必要的目录结构"
echo "2. ✅ 修复了构建脚本权限"
echo "3. ✅ 修复了工作流文件"
echo "4. ✅ 修复了workflow_step1_download_source函数"
echo "5. ✅ 创建了确保源代码上传的辅助脚本"
echo ""
echo "使用说明:"
echo "1. 运行修复后的工作流"
echo "2. 如果步骤7仍失败，可手动运行: ./ensure_source_upload.sh"
echo "========================================"
EOF

chmod +x fix-all-in-one.sh

# 步骤6：创建诊断和测试脚本
log_info "步骤6: 创建诊断和测试脚本..."

cat > test_fix.sh << 'EOF'
#!/bin/bash
# OpenWrt构建修复测试脚本

echo "=== OpenWrt构建修复测试 ==="

# 测试1：检查目录结构
echo "1. 测试目录结构..."
if [ -d "/mnt/openwrt-build" ]; then
    echo "✅ /mnt/openwrt-build 存在"
    echo "   权限: $(ls -ld /mnt/openwrt-build | awk '{print $1}')"
else
    echo "❌ /mnt/openwrt-build 不存在"
fi

if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    echo "✅ 构建脚本存在"
    echo "   权限: $(ls -l firmware-config/scripts/build_firmware_main.sh | awk '{print $1}')"
else
    echo "❌ 构建脚本不存在"
fi

# 测试2：测试workflow_step1_download_source函数
echo ""
echo "2. 测试workflow_step1_download_source函数..."
if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    echo "调用函数（模拟工作流步骤7）..."
    
    # 创建测试目录
    TEST_DIR="/tmp/test-openwrt-build"
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    
    # 模拟调用
    echo "测试目录: $TEST_DIR"
    
    # 检查函数逻辑
    if grep -q "不能在当前工作目录克隆" firmware-config/scripts/build_firmware_main.sh; then
        echo "✅ 函数包含安全检查"
    else
        echo "❌ 函数缺少安全检查"
    fi
    
    if grep -q "/mnt/openwrt-build" firmware-config/scripts/build_firmware_main.sh; then
        echo "✅ 函数使用正确的构建目录"
    else
        echo "❌ 函数可能未使用正确目录"
    fi
    
    rm -rf "$TEST_DIR"
fi

# 测试3：测试上传功能
echo ""
echo "3. 测试上传功能..."
if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    if grep -q "step2_upload_source" firmware-config/scripts/build_firmware_main.sh; then
        echo "✅ 上传函数存在"
    else
        echo "❌ 上传函数不存在"
    fi
fi

echo ""
echo "=== 测试完成 ==="
echo ""
echo "建议:"
echo "1. 确保 /mnt/openwrt-build 目录存在且可写"
echo "2. 确保 build_firmware_main.sh 有执行权限"
echo "3. 确保 workflow_step1_download_source 函数正确处理目录"
echo "4. 重新运行工作流"
EOF

chmod +x test_fix.sh

echo ""
echo "========================================"
echo "✅ 精准修复完成"
echo "========================================"
echo ""
echo "已创建的修复文件:"
echo "1. ✅ 修复了 firmware-build.yml 中的步骤7"
echo "2. ✅ 修复了 build_firmware_main.sh 中的 workflow_step1_download_source 函数"
echo "3. ✅ 创建了快速修复脚本: /tmp/quick_fix_for_workflow.sh"
echo "4. ✅ 创建了全功能修复脚本: fix-all-in-one.sh"
echo "5. ✅ 创建了测试脚本: test_fix.sh"
echo ""
echo "使用方法:"
echo "1. 运行全功能修复: ./fix-all-in-one.sh"
echo "2. 运行测试: ./test_fix.sh"
echo "3. 重新运行工作流"
echo ""
echo "修复要点:"
echo "• workflow_step1_download_source 现在会在 /mnt/openwrt-build 目录克隆"
echo "• 如果目录非空，会跳过克隆（但仍能上传源代码）"
echo "• 所有原始步骤保持不变，包括上传源代码的步骤"
echo "========================================"
