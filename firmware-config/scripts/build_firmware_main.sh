#!/bin/bash
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLCHAIN_DIR="$REPO_ROOT/firmware-config/Toolchain"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

# ========== 自动更新 Git 配置文件功能 ==========

# 自动更新 .gitattributes 文件
auto_update_gitattributes() {
    local repo_root="$1"
    local large_files="$2"
    
    log "=== 自动更新 .gitattributes 文件 ==="
    
    local gitattributes_file="$repo_root/.gitattributes"
    
    # 如果 .gitattributes 不存在，创建它
    if [ ! -f "$gitattributes_file" ]; then
        log "📄 创建 .gitattributes 文件"
        cat > "$gitattributes_file" << 'EOF'
# Git LFS 配置
# 管理工具链中的大文件

# Git LFS 全局配置
*.gz filter=lfs diff=lfs merge=lfs -text
*.xz filter=lfs diff=lfs merge=lfs -text
*.bz2 filter=lfs diff=lfs merge=lfs -text
*.zst filter=lfs diff=lfs merge=lfs -text

# 二进制文件
*.tar.gz filter=lfs diff=lfs merge=lfs -text
*.tar.xz filter=lfs diff=lfs merge=lfs -text
*.tar.bz2 filter=lfs diff=lfs merge=lfs -text
*.tar.zst filter=lfs diff=lfs merge=lfs -text

# 可执行文件
*.bin filter=lfs diff=lfs merge=lfs -text
*.so filter=lfs diff=lfs merge=lfs -text
*.so.* filter=lfs diff=lfs merge=lfs -text
EOF
    else
        log "📄 更新现有的 .gitattributes 文件"
        # 备份原始文件
        cp "$gitattributes_file" "$gitattributes_file.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 检查是否需要添加新规则
    local added_count=0
    local patterns=()
    
    # 分析大文件的扩展名和类型
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            local filename=$(basename "$file")
            local extension="${filename##*.}"
            
            # 确定文件类型并创建相应的模式
            case "$extension" in
                "bin")
                    patterns+=("*.bin")
                    ;;
                "img")
                    patterns+=("*.img")
                    ;;
                "so"|"so.*")
                    patterns+=("*.so" "*.so.*")
                    ;;
                "gz"|"xz"|"bz2"|"zst")
                    patterns+=("*.$extension")
                    ;;
                "tar")
                    # 处理tar文件
                    patterns+=("*.tar.*")
                    ;;
                *)
                    # 特殊文件处理（如编译器文件）
                    if [[ "$filename" == *cc1* ]]; then
                        patterns+=("*cc1*")
                    elif [[ "$filename" == *cc1plus* ]]; then
                        patterns+=("*cc1plus*")
                    elif [[ "$filename" == *lto1* ]]; then
                        patterns+=("*lto1*")
                    elif [[ "$filename" == *gcc* ]]; then
                        patterns+=("*gcc*")
                    elif [[ "$filename" == *g++* ]]; then
                        patterns+=("*g++*")
                    elif [[ "$filename" == *ld* ]]; then
                        patterns+=("*ld*")
                    elif [[ "$filename" == *ar* ]]; then
                        patterns+=("*ar*")
                    elif [[ "$filename" == *as* ]]; then
                        patterns+=("*as*")
                    fi
                    ;;
            esac
        fi
    done <<< "$large_files"
    
    # 去重
    local unique_patterns=($(printf "%s\n" "${patterns[@]}" | sort -u))
    
    log "🔍 找到 ${#unique_patterns[@]} 个唯一模式需要处理"
    
    # 添加新规则
    for pattern in "${unique_patterns[@]}"; do
        if ! grep -q "^$pattern filter=lfs diff=lfs merge=lfs -text" "$gitattributes_file"; then
            echo "$pattern filter=lfs diff=lfs merge=lfs -text" >> "$gitattributes_file"
            log "✅ 添加模式: $pattern"
            added_count=$((added_count + 1))
        else
            log "ℹ️  模式已存在: $pattern"
        fi
    done
    
    # 确保工具链目录被Git LFS管理
    if ! grep -q "^firmware-config/Toolchain/" "$gitattributes_file"; then
        echo "" >> "$gitattributes_file"
        echo "# 工具链目录" >> "$gitattributes_file"
        echo "firmware-config/Toolchain/** filter=lfs diff=lfs merge=lfs -text" >> "$gitattributes_file"
        log "✅ 添加工具链目录规则"
    fi
    
    log "📊 更新完成: 添加了 $added_count 个新规则"
    log "📄 文件位置: $gitattributes_file"
    
    # 修复：返回0而不是 $added_count，避免触发 set -e
    return 0
}

# 自动更新 .gitignore 文件
auto_update_gitignore() {
    local repo_root="$1"
    
    log "=== 自动更新 .gitignore 文件 ==="
    
    local gitignore_file="$repo_root/.gitignore"
    
    # 如果 .gitignore 不存在，创建它
    if [ ! -f "$gitignore_file" ]; then
        log "📄 创建 .gitignore 文件"
        cat > "$gitignore_file" << 'EOF'
# OpenWrt固件构建项目Git忽略文件

# ========== 编译输出目录 ==========
bin/
build/
tmp/
staging_dir/
build_dir/

# ========== 下载的源码包（可以重新下载） ==========
dl/
downloads/

# ========== Feeds目录（可以重新生成） ==========
feeds/

# ========== 日志文件 ==========
*.log
logs/
build.log
download.log
EOF
    else
        log "📄 更新现有的 .gitignore 文件"
        # 备份原始文件
        cp "$gitignore_file" "$gitignore_file.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    local added_count=0
    
    # 要添加的规则列表
    local rules_to_add=(
        "# ========== 构建产物目录 =========="
        "build-artifacts/"
        "/tmp/build-artifacts/"
        ""
        "# ========== 临时下载目录 =========="
        "openwrt-source/"
        "/tmp/openwrt-source/"
        ""
        "# ========== Git LFS 指针文件 =========="
        "*.lfs.*"
        ""
        "# ========== 本地配置文件 =========="
        ".env"
        ".env.local"
        "*.local"
        ""
        "# ========== 工具链临时文件 =========="
        "firmware-config/Toolchain/**/*.tmp"
        "firmware-config/Toolchain/**/*.temp"
        "firmware-config/Toolchain/**/.tmp_*"
        "firmware-config/Toolchain/**/.stamp_*"
    )
    
    # 添加缺失的规则
    for rule in "${rules_to_add[@]}"; do
        if [[ "$rule" == "#"* ]] || [[ -z "$rule" ]]; then
            # 注释或空行，直接检查
            if ! grep -q "^$rule$" "$gitignore_file" 2>/dev/null; then
                echo "$rule" >> "$gitignore_file"
                added_count=$((added_count + 1))
            fi
        else
            # 忽略规则，检查是否存在
            if ! grep -q "^$rule$" "$gitignore_file" 2>/dev/null; then
                echo "$rule" >> "$gitignore_file"
                added_count=$((added_count + 1))
                log "✅ 添加忽略规则: $rule"
            fi
        fi
    done
    
    log "📊 更新完成: 添加了 $added_count 个新规则"
    log "📄 文件位置: $gitignore_file"
    
    # 修复：返回0而不是 $added_count，避免触发 set -e
    return 0
}

# 智能管理大文件（整合功能）
smart_manage_large_files() {
    log "=== 🧠 智能管理大文件 ==="
    
    local repo_root="$(pwd)"
    
    # 检查大文件
    log "🔍 扫描大于90MB的文件..."
    local large_files=$(find . -type f -size +90M 2>/dev/null | grep -v ".git" | head -50 || true)
    
    if [ -n "$large_files" ]; then
        log "📊 发现大文件数量: $(echo "$large_files" | wc -l)"
        
        echo "=== 前10个大文件列表 ==="
        echo "$large_files" | head -10 | while read file; do
            local size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "未知")
            echo "  - $file ($size)"
        done
        
        # 自动更新 .gitattributes
        log "🔄 自动更新 .gitattributes..."
        auto_update_gitattributes "$repo_root" "$large_files"
        
        # 自动更新 .gitignore
        log "🔄 自动更新 .gitignore..."
        auto_update_gitignore "$repo_root"
        
        echo ""
        log "💡 建议操作:"
        log "1. 提交更新后的配置文件:"
        log "   git add .gitattributes .gitignore"
        log "   git commit -m 'chore: 自动更新Git配置文件以管理大文件'"
        
    else
        log "✅ 未发现超过90MB的大文件"
        
        # 即使没有大文件，也检查并更新 .gitignore
        log "🔍 检查 .gitignore 是否需要更新..."
        auto_update_gitignore "$repo_root"
    fi
    
    log "✅ 智能大文件管理完成"
}

# ========== 工具链相关函数 ==========

# 初始化工具链目录
init_toolchain_dir() {
    log "=== 初始化工具链目录 ==="
    
    log "📁 创建工具链目录: $TOOLCHAIN_DIR"
    mkdir -p "$TOOLCHAIN_DIR"
    
    if [ -d "$TOOLCHAIN_DIR" ]; then
        log "✅ 工具链目录创建成功"
        log "  路径: $TOOLCHAIN_DIR"
        log "  权限: $(ls -ld "$TOOLCHAIN_DIR" | awk '{print $1}')"
        
        # 创建 README 文件
        cat > "$TOOLCHAIN_DIR/README.md" << 'EOF'
# 工具链目录说明

此目录用于保存编译工具链，以加速后续构建过程。

## 目录结构
- Toolchain/
  - README.md (本文件)
  - toolchain-*.tar.gz (工具链压缩包)
  - toolchain_info.txt (工具链信息)

## 使用说明
1. 首次构建时会自动下载工具链
2. 构建完成后会自动保存工具链到此目录
3. 后续构建会优先从此目录加载工具链
4. 工具链会自动提交到Git LFS管理

## 注意事项
1. 工具链文件较大，使用Git LFS管理
2. 不同架构的设备需要不同的工具链
3. 工具链版本与OpenWrt版本相关
EOF
        log "📄 创建 README 文件"
    else
        log "❌ 工具链目录创建失败"
    fi
    
    log "=== 工具链目录初始化完成 ==="
}

# 保存工具链到仓库目录
save_toolchain() {
    log "=== 保存工具链到仓库目录 ==="
    
    if [ ! -d "$BUILD_DIR/staging_dir" ]; then
        log "❌ 构建目录中没有工具链，跳过保存"
        return 0
    fi
    
    # 查找工具链目录
    local toolchain_dirs=$(find "$BUILD_DIR/staging_dir" -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
    
    if [ -z "$toolchain_dirs" ]; then
        log "⚠️  未找到工具链目录，跳过保存"
        return 0
    fi
    
    local toolchain_dir="$toolchain_dirs"
    local toolchain_name=$(basename "$toolchain_dir")
    
    log "🔍 找到工具链: $toolchain_name"
    log "  路径: $toolchain_dir"
    log "  大小: $(du -sh "$toolchain_dir" 2>/dev/null | cut -f1 || echo '未知')"
    
    # 确保工具链目录存在
    mkdir -p "$TOOLCHAIN_DIR"
    
    # 保存工具链信息
    cat > "$TOOLCHAIN_DIR/toolchain_info.txt" << EOF
# 工具链信息
生成时间: $(date)
工具链名称: $toolchain_name
工具链路径: $toolchain_dir
目标平台: $TARGET/$SUBTARGET
设备: $DEVICE
OpenWrt版本: $SELECTED_BRANCH
配置模式: $CONFIG_MODE

# 文件列表
$(find "$toolchain_dir" -type f -name "*gcc*" 2>/dev/null | head -10)
EOF
    
    log "📄 保存工具链信息到: $TOOLCHAIN_DIR/toolchain_info.txt"
    
    # 复制工具链文件
    log "📦 复制工具链文件..."
    cp -r "$toolchain_dir" "$TOOLCHAIN_DIR/" 2>/dev/null || true
    
    # 检查复制结果
    local saved_count=$(find "$TOOLCHAIN_DIR" -type f 2>/dev/null | wc -l)
    log "📊 保存文件数量: $saved_count 个"
    
    if [ $saved_count -gt 0 ]; then
        log "✅ 工具链保存完成"
        log "  保存目录: $TOOLCHAIN_DIR"
        log "  总大小: $(du -sh "$TOOLCHAIN_DIR" 2>/dev/null | cut -f1 || echo '未知')"
    else
        log "⚠️  工具链保存失败，目录为空"
    fi
    
    log "=== 工具链保存完成 ==="
}

# 加载工具链
load_toolchain() {
    log "=== 加载工具链 ==="
    
    # 检查是否已经有工具链
    if [ -d "$BUILD_DIR/staging_dir/toolchain-"* ] 2>/dev/null; then
        log "✅ 构建目录中已存在工具链，跳过加载"
        return 0
    fi
    
    # 检查仓库中是否有保存的工具链
    if [ -d "$TOOLCHAIN_DIR" ] && [ -n "$(ls -A "$TOOLCHAIN_DIR" 2>/dev/null)" ]; then
        log "📁 仓库中有保存的工具链，尝试加载..."
        
        local toolchain_dirs=$(find "$TOOLCHAIN_DIR" -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
        
        if [ -n "$toolchain_dirs" ]; then
            local toolchain_name=$(basename "$toolchain_dirs")
            log "🔍 找到保存的工具链: $toolchain_name"
            
            # 确保构建目录存在
            mkdir -p "$BUILD_DIR/staging_dir"
            
            # 复制工具链到构建目录
            log "📦 复制工具链到构建目录..."
            cp -r "$toolchain_dirs" "$BUILD_DIR/staging_dir/" 2>/dev/null || true
            
            if [ -d "$BUILD_DIR/staging_dir/$toolchain_name" ]; then
                log "✅ 工具链加载成功"
                log "  工具链: $toolchain_name"
                log "  路径: $BUILD_DIR/staging_dir/$toolchain_name"
                log "  大小: $(du -sh "$BUILD_DIR/staging_dir/$toolchain_name" 2>/dev/null | cut -f1 || echo '未知')"
            else
                log "⚠️  工具链加载失败，将自动下载"
            fi
        else
            log "ℹ️  未找到可用的工具链目录，将自动下载"
        fi
    else
        log "ℹ️  仓库中没有保存的工具链，将自动下载"
    fi
    
    log "=== 工具链加载完成 ==="
}

# ========== 环境设置函数 ==========

# 设置编译环境
setup_environment() {
    log "=== 设置编译环境 ==="
    
    log "📦 安装必要软件包..."
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        ccache \
        ecj \
        fastjar \
        file \
        g++ \
        gawk \
        gettext \
        git \
        java-propose-classpath \
        libelf-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libssl-dev \
        python3 \
        python3-distutils \
        python3-setuptools \
        rsync \
        subversion \
        unzip \
        wget \
        xsltproc \
        zlib1g-dev \
        && log "✅ 软件包安装完成" || log "⚠️  软件包安装过程中有警告"
    
    log "🔧 创建构建目录..."
    mkdir -p "$BUILD_DIR"
    log "✅ 构建目录: $BUILD_DIR"
    
    log "⚡ 启用ccache..."
    export CCACHE_DIR="$BUILD_DIR/.ccache"
    mkdir -p "$CCACHE_DIR"
    ccache -M 5G
    log "✅ ccache配置完成"
    
    log "=== 编译环境设置完成 ==="
}

# 创建构建目录
create_build_dir() {
    log "=== 创建构建目录 ==="
    
    log "📁 创建构建目录: $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    
    # 设置权限
    chmod 755 "$BUILD_DIR"
    
    log "📊 目录信息:"
    log "  路径: $BUILD_DIR"
    log "  权限: $(ls -ld "$BUILD_DIR" | awk '{print $1}')"
    log "  所有者: $(ls -ld "$BUILD_DIR" | awk '{print $3}')"
    
    # 检查磁盘空间
    local available_space=$(df -h "$BUILD_DIR" | tail -1 | awk '{print $4}')
    log "💽 可用空间: $available_space"
    
    if [ -d "$BUILD_DIR" ]; then
        log "✅ 构建目录创建成功"
    else
        log "❌ 构建目录创建失败"
        exit 1
    fi
    
    log "=== 构建目录创建完成 ==="
}

# ========== 清理函数 ==========

# 清理目录
cleanup() {
    log "=== 清理目录 ==="
    
    log "🧹 清理临时文件..."
    
    # 清理临时目录
    local temp_dirs=(
        "/tmp/source-upload"
        "/tmp/exclude-list.txt"
        "/tmp/openwrt-source"
        "/tmp/build-artifacts"
    )
    
    for dir in "${temp_dirs[@]}"; do
        if [ -d "$dir" ] || [ -f "$dir" ]; then
            rm -rf "$dir" 2>/dev/null || true
            log "✅ 清理: $dir"
        fi
    done
    
    # 清理工作区临时文件（但保留关键文件）
    log "📁 检查工作区临时文件..."
    if [ -d "$REPO_ROOT" ]; then
        # 保留重要的构建文件
        find "$REPO_ROOT" -name "*.tmp" -o -name "*.temp" -o -name "*.bak" 2>/dev/null | head -5 | while read file; do
            rm -f "$file" 2>/dev/null || true
            log "  清理临时文件: $(basename "$file")"
        done
    fi
    
    # 检查磁盘空间
    log "💽 清理后磁盘空间:"
    df -h | grep -E "^/dev/|^Filesystem" | head -5
    
    log "✅ 目录清理完成"
    log "=== 清理完成 ==="
}

# ========== GitHub Actions 工作流步骤函数 ==========

# 步骤1：下载完整源代码
workflow_step1_download_source() {
    local workspace="$1"
    
    log "========================================"
    log "📥 步骤1：下载完整源代码（支持工具链提交）"
    log "========================================"
    log ""
    log "📊 仓库信息:"
    log "  工作区: $workspace"
    log ""
    
    # 清理工作区
    log "🧹 清理工作区..."
    cd "$workspace"
    ls -la
    log "移除工作区现有文件..."
    find . -maxdepth 1 ! -name '.' ! -name '..' -exec rm -rf {} + 2>/dev/null || true
    log "✅ 工作区清理完成"
    log ""
    
    # 克隆完整仓库
    log "📦 克隆完整仓库..."
    local repo_url="https://github.com/$GITHUB_REPOSITORY.git"
    log "命令: git clone --depth 1 $repo_url ."
    git clone --depth 1 "$repo_url" .
    
    if [ ! -d ".git" ]; then
        log "❌ 错误: 仓库克隆失败，.git目录不存在"
        log "当前目录内容:"
        ls -la
        exit 1
    fi
    
    log "✅ 完整仓库克隆完成"
    log "📊 仓库大小: $(du -sh . | cut -f1)"
    log "📁 Git信息:"
    git log --oneline -1
    log ""
    
    # 显示关键文件
    log "📄 关键文件检查:"
    if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
        log "✅ 主构建脚本: firmware-config/scripts/build_firmware_main.sh"
        log "  文件大小: $(ls -lh firmware-config/scripts/build_firmware_main.sh | awk '{print $5}')"
        log "  权限: $(ls -la firmware-config/scripts/build_firmware_main.sh | awk '{print $1}')"
    else
        log "❌ 错误: 主构建脚本不存在"
        log "当前目录结构:"
        find . -maxdepth 3 -type d | sort
        exit 1
    fi
    
    if [ -f "firmware-config/scripts/error_analysis.sh" ]; then
        log "✅ 错误分析脚本: firmware-config/scripts/error_analysis.sh"
    else
        log "⚠️  警告: 错误分析脚本不存在"
    fi
    
    log ""
    log "🔧 设置脚本执行权限..."
    find . -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
    log "✅ 脚本权限设置完成"
    
    log ""
    log "🎉 步骤1完成：源代码下载完成，准备进行构建"
    log "========================================"
}

# 步骤2：立即上传源代码（排除工具链目录）
workflow_step2_upload_source() {
    log "========================================"
    log "📤 步骤2：立即上传源代码（排除工具链目录）"
    log "========================================"
    log ""
    
    # 创建源代码压缩包（排除工具链目录）
    log "📦 创建源代码压缩包..."
    log "排除目录: firmware-config/Toolchain/"
    log "排除目录: .git/"
    
    mkdir -p /tmp/source-upload
    cd "$REPO_ROOT"
    
    # 创建排除列表
    echo "firmware-config/Toolchain" > /tmp/exclude-list.txt
    echo ".git" >> /tmp/exclude-list.txt
    
    # 创建压缩包
    tar --exclude-from=/tmp/exclude-list.txt -czf /tmp/source-upload/source-code.tar.gz .
    
    log "✅ 源代码压缩包创建完成"
    log "📊 压缩包大小: $(ls -lh /tmp/source-upload/source-code.tar.gz | awk '{print $5}')"
    log ""
    
    # 显示压缩包内容
    log "📁 压缩包内容预览:"
    tar -tzf /tmp/source-upload/source-code.tar.gz | head -20
    log ""
    
    log "🎉 步骤2完成：源代码准备上传"
    log "========================================"
}

# 步骤3：安装Git LFS和配置
workflow_step4_install_git_lfs() {
    log "========================================"
    log "🔧 步骤4：安装Git LFS和配置"
    log "========================================"
    log ""
    
    log "📦 安装Git LFS..."
    sudo apt-get update
    sudo apt-get install -y git-lfs
    
    log "🔧 配置Git..."
    git config --global user.name "GitHub Actions"
    git config --global user.email "actions@github.com"
    git config --global http.postBuffer 524288000
    
    log "⚡ 初始化Git LFS..."
    git lfs install --force
    
    log "📥 拉取Git LFS文件..."
    git lfs pull || log "⚠️  Git LFS拉取失败，继续构建..."
    
    log ""
    log "📊 Git LFS文件状态:"
    git lfs ls-files 2>/dev/null | head -10 || log "   无LFS文件或未跟踪"
    
    log ""
    log "🎉 步骤4完成：Git LFS安装和配置完成"
    log "========================================"
}

# 步骤5：检查大文件状态
workflow_step5_check_large_files() {
    log "========================================"
    log "📊 步骤5：检查大文件状态"
    log "========================================"
    log ""
    
    log "🔍 检查大文件..."
    smart_manage_large_files
    
    log ""
    log "🎉 步骤5完成：大文件检查完成"
    log "========================================"
}

# 步骤6：检查工具链目录状态
workflow_step6_check_toolchain_dir() {
    log "========================================"
    log "🗂️ 步骤6：检查工具链目录状态"
    log "========================================"
    log ""
    
    log "🔍 检查工具链目录: $TOOLCHAIN_DIR"
    
    if [ -d "$TOOLCHAIN_DIR" ]; then
        log "✅ 工具链目录存在"
        log ""
        log "📊 目录信息:"
        log "  路径: $TOOLCHAIN_DIR"
        log "  大小: $(du -sh "$TOOLCHAIN_DIR" 2>/dev/null | cut -f1 || echo '未知')"
        log ""
        log "📁 目录结构:"
        find "$TOOLCHAIN_DIR" -maxdepth 3 -type d 2>/dev/null | sort | head -20
        log ""
        
        # 统计文件数量
        file_count=$(find "$TOOLCHAIN_DIR" -type f 2>/dev/null | wc -l)
        log "📈 文件统计:"
        log "  文件总数: $file_count 个"
        
        if [ $file_count -gt 0 ]; then
            log "✅ 工具链目录非空"
            log ""
            log "🔑 关键文件列表:"
            find "$TOOLCHAIN_DIR" -type f \( -name "*gcc*" -o -name "*.info" \) 2>/dev/null | head -10
        else
            log "⚠️  工具链目录为空"
        fi
    else
        log "ℹ️  工具链目录不存在，将自动创建"
        mkdir -p "$TOOLCHAIN_DIR"
        log "✅ 工具链目录已创建: $TOOLCHAIN_DIR"
    fi
    
    log ""
    log "🎉 步骤6完成：工具链目录检查完成"
    log "========================================"
}

# 步骤7：初始化工具链目录
workflow_step7_init_toolchain_dir() {
    log "========================================"
    log "💾 步骤7：初始化工具链目录"
    log "========================================"
    log ""
    
    init_toolchain_dir
    
    log ""
    log "🎉 步骤7完成：工具链目录初始化完成"
    log "========================================"
}

# 步骤8：设置编译环境
workflow_step8_setup_environment() {
    log "========================================"
    log "🛠️ 步骤8：设置编译环境"
    log "========================================"
    log ""
    
    setup_environment
    
    log ""
    log "🎉 步骤8完成：编译环境设置完成"
    log "========================================"
}

# 步骤9：创建构建目录
workflow_step9_create_build_dir() {
    log "========================================"
    log "📁 步骤9：创建构建目录"
    log "========================================"
    log ""
    
    create_build_dir
    
    log ""
    log "🎉 步骤9完成：构建目录创建完成"
    log "========================================"
}

# 步骤10：初始化构建环境
workflow_step10_init_build_env() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local extra_packages="${4:-}"
    
    log "========================================"
    log "🚀 步骤10：初始化构建环境"
    log "========================================"
    log ""
    
    log "📱 设备: $device_name"
    log "🔄 版本: $version_selection"
    log "⚙️ 配置模式: $config_mode"
    log "🔌 额外插件: $extra_packages"
    log ""
    
    # 调用原有函数（这里假设已有此函数）
    initialize_build_env "$device_name" "$version_selection" "$config_mode"
    
    log ""
    log "📋 环境变量设置完成:"
    log "  构建目录: $BUILD_DIR"
    
    # 加载环境变量
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        log "✅ 环境变量文件加载成功"
    else
        log "❌ 环境变量文件不存在: $ENV_FILE"
        exit 1
    fi
    
    log "  分支: $SELECTED_BRANCH"
    log "  目标: $TARGET"
    log "  子目标: $SUBTARGET"
    log "  设备: $DEVICE"
    
    # 设置GitHub环境变量
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
    echo "TARGET=$TARGET" >> $GITHUB_ENV
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
    echo "DEVICE=$DEVICE" >> $GITHUB_ENV
    
    log ""
    log "🎉 步骤10完成：构建环境初始化完成"
    log "========================================"
}

# 步骤11：显示构建配置
workflow_step11_show_config() {
    log "========================================"
    log "⚡ 步骤11：显示构建配置"
    log "========================================"
    log ""
    
    log "📊 构建配置摘要:"
    log "  设备: $DEVICE"
    log "  版本: $SELECTED_BRANCH"
    log "  配置模式: $CONFIG_MODE"
    log "  目标平台: $TARGET/$SUBTARGET"
    log "  构建目录: $BUILD_DIR"
    log "  启用缓存: $ENABLE_CACHE"
    log "  提交工具链: $COMMIT_TOOLCHAIN"
    log ""
    
    log "🎉 步骤11完成：构建配置显示完成"
    log "========================================"
}

# 步骤12：添加TurboACC支持
workflow_step12_add_turboacc_support() {
    log "========================================"
    log "🔌 步骤12：添加TurboACC支持"
    log "========================================"
    log ""
    
    add_turboacc_support
    
    log ""
    log "🎉 步骤12完成：TurboACC支持添加完成"
    log "========================================"
}

# 步骤13：配置Feeds
workflow_step13_configure_feeds() {
    log "========================================"
    log "📦 步骤13：配置Feeds"
    log "========================================"
    log ""
    
    configure_feeds
    
    log ""
    log "🎉 步骤13完成：Feeds配置完成"
    log "========================================"
}

# 步骤14：安装TurboACC包
workflow_step14_install_turboacc_packages() {
    log "========================================"
    log "🔧 步骤14：安装TurboACC包"
    log "========================================"
    log ""
    
    install_turboacc_packages
    
    log ""
    log "🎉 步骤14完成：TurboACC包安装完成"
    log "========================================"
}

# 步骤15：编译前空间检查
workflow_step15_pre_build_space_check() {
    log "========================================"
    log "💽 步骤15：编译前空间检查"
    log "========================================"
    log ""
    
    pre_build_space_check
    
    log ""
    log "🎉 步骤15完成：空间检查完成"
    log "========================================"
}

# 步骤16：智能配置生成（USB完全修复加强版）
workflow_step16_generate_config() {
    local extra_packages="$1"
    
    log "========================================"
    log "⚙️ 步骤16：智能配置生成（USB完全修复加强版）"
    log "========================================"
    log ""
    log "🚨 USB 3.0加强：所有关键USB驱动强制启用"
    log ""
    
    generate_config "$extra_packages"
    
    log ""
    log "🎉 步骤16完成：智能配置生成完成"
    log "========================================"
}

# 步骤17：验证USB配置
workflow_step17_verify_usb_config() {
    log "========================================"
    log "🔍 步骤17：验证USB配置"
    log "========================================"
    log ""
    
    verify_usb_config
    
    log ""
    log "🎉 步骤17完成：USB配置验证完成"
    log "========================================"
}

# 步骤18：USB驱动完整性检查
workflow_step18_check_usb_drivers_integrity() {
    log "========================================"
    log "🛡️ 步骤18：USB驱动完整性检查"
    log "========================================"
    log ""
    
    check_usb_drivers_integrity
    
    log ""
    log "🎉 步骤18完成：USB驱动完整性检查完成"
    log "========================================"
}

# 步骤19：应用配置并显示详情
workflow_step19_apply_config() {
    log "========================================"
    log "✅ 步骤19：应用配置并显示详情"
    log "========================================"
    log ""
    
    apply_config
    
    log ""
    log "🎉 步骤19完成：配置应用完成"
    log "========================================"
}

# 步骤20：检查并备份配置文件
workflow_step20_backup_config() {
    log "========================================"
    log "💾 步骤20：检查并备份配置文件"
    log "========================================"
    log ""
    
    # 检查配置文件
    if [ -f "$BUILD_DIR/.config" ]; then
        log "✅ .config 文件存在"
        
        # 确保备份目录存在
        mkdir -p firmware-config/config-backup
        
        # 备份到仓库目录
        backup_file="firmware-config/config-backup/config_${DEVICE}_${SELECTED_BRANCH}_${CONFIG_MODE}_$(date +%Y%m%d_%H%M%S).config"
        
        cp "$BUILD_DIR/.config" "$backup_file"
        log "✅ 配置文件备份到仓库目录: $backup_file"
        
        # 显示备份文件信息
        log "📊 备份文件信息:"
        log "  大小: $(ls -lh $backup_file | awk '{print $5}')"
        log "  行数: $(wc -l < $backup_file)"
    else
        log "❌ .config 文件不存在"
        exit 1
    fi
    
    log ""
    log "🎉 步骤20完成：配置文件备份完成"
    log "========================================"
}

# 步骤21：修复网络环境
workflow_step21_fix_network() {
    log "========================================"
    log "🌐 步骤21：修复网络环境"
    log "========================================"
    log ""
    
    fix_network
    
    log ""
    log "🎉 步骤21完成：网络环境修复完成"
    log "========================================"
}

# 步骤22：加载工具链
workflow_step22_load_toolchain() {
    log "========================================"
    log "🔧 步骤22：加载工具链"
    log "========================================"
    log ""
    
    load_toolchain
    
    log ""
    log "🎉 步骤22完成：工具链加载完成"
    log "========================================"
}

# 步骤23：检查工具链加载状态
workflow_step23_check_toolchain_status() {
    log "========================================"
    log "📊 步骤23：检查工具链加载状态"
    log "========================================"
    log ""
    
    cd $BUILD_DIR
    
    log "🔍 检查构建目录工具链状态..."
    if [ -d "staging_dir" ]; then
        log "✅ staging_dir 目录存在"
        
        local toolchain_dirs=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | wc -l)
        log "📊 找到 $toolchain_dirs 个工具链目录"
        
        if [ $toolchain_dirs -gt 0 ]; then
            log "🎉 工具链已成功加载到构建目录"
            find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | while read dir; do
                log "  工具链: $(basename $dir)"
                log "    大小: $(du -sh "$dir" 2>/dev/null | cut -f1 || echo '未知')"
                
                # 检查编译器
                if [ -d "$dir/bin" ]; then
                    local compiler_count=$(find "$dir/bin" -name "*gcc*" 2>/dev/null | wc -l)
                    log "    编译器文件: $compiler_count 个"
                    if [ $compiler_count -gt 0 ]; then
                        find "$dir/bin" -name "*gcc*" 2>/dev/null | head -3 | while read compiler; do
                            log "      - $(basename $compiler)"
                        done
                    fi
                fi
            done
        else
            log "⚠️  构建目录中没有工具链，将自动下载"
        fi
    else
        log "❌ staging_dir 目录不存在，将自动创建并下载工具链"
    fi
    
    log ""
    log "🔧 验证工具链完整性..."
    # 这里调用原有的 check_toolchain_completeness 函数
    check_toolchain_completeness || log "⚠️  工具链完整性检查失败"
    
    log ""
    log "🎉 步骤23完成：工具链加载状态检查完成"
    log "========================================"
}

# 步骤24：下载依赖包
workflow_step24_download_dependencies() {
    log "========================================"
    log "📥 步骤24：下载依赖包"
    log "========================================"
    log ""
    
    download_dependencies
    
    log ""
    log "🎉 步骤24完成：依赖包下载完成"
    log "========================================"
}

# 步骤25：集成自定义文件
workflow_step25_integrate_custom_files() {
    log "========================================"
    log "🔌 步骤25：集成自定义文件"
    log "========================================"
    log ""
    
    integrate_custom_files
    
    log ""
    log "🎉 步骤25完成：自定义文件集成完成"
    log "========================================"
}

# 步骤26：前置错误检查
workflow_step26_pre_build_error_check() {
    log "========================================"
    log "🚨 步骤26：前置错误检查"
    log "========================================"
    log ""
    
    pre_build_error_check
    
    log ""
    log "🎉 步骤26完成：前置错误检查完成"
    log "========================================"
}

# 步骤27：编译固件前的空间检查
workflow_step27_final_space_check() {
    log "========================================"
    log "💽 步骤27：编译固件前的空间检查"
    log "========================================"
    log ""
    
    df -h
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log ""
    log "📊 空间检查结果:"
    log "  /mnt 可用空间: ${AVAILABLE_GB}G"
    
    # 检查编译所需空间
    if [ $AVAILABLE_GB -lt 10 ]; then
        log "❌ 错误: 编译前空间不足 (需要至少10G，当前${AVAILABLE_GB}G)"
        exit 1
    elif [ $AVAILABLE_GB -lt 20 ]; then
        log "⚠️  警告: 编译前空间较低 (建议至少20G，当前${AVAILABLE_GB}G)"
    else
        log "✅ 编译前空间充足"
    fi
    
    log ""
    log "🎉 步骤27完成：编译前空间检查完成"
    log "========================================"
}

# 步骤28：编译固件（启用缓存）
workflow_step28_build_firmware() {
    log "========================================"
    log "🔨 步骤28：编译固件（启用缓存）"
    log "========================================"
    log ""
    
    log "⚡ 启用编译缓存: $ENABLE_CACHE"
    log ""
    
    build_firmware "true"
    
    log ""
    log "🎉 步骤28完成：固件编译完成"
    log "========================================"
}

# 步骤29：保存工具链到仓库目录（自动执行）
workflow_step29_save_toolchain() {
    log "========================================"
    log "💾 步骤29：保存工具链到仓库目录（自动执行）"
    log "========================================"
    log ""
    
    log "📤 自动保存工具链..."
    save_toolchain
    
    log ""
    log "📊 保存结果:"
    if [ -d "firmware-config/Toolchain" ]; then
        log "✅ 工具链已保存到仓库目录"
        log "  目录大小: $(du -sh firmware-config/Toolchain 2>/dev/null | cut -f1 || echo '未知')"
        log "  目录结构:"
        find firmware-config/Toolchain -type d 2>/dev/null | head -10
    else
        log "❌ 工具链保存失败"
    fi
    
    log ""
    log "🎉 步骤29完成：工具链保存完成"
    log "========================================"
}

# 步骤30：提交工具链到仓库（自动执行）
workflow_step30_commit_toolchain() {
    log "========================================"
    log "📤 步骤30：提交工具链到仓库（自动执行）"
    log "========================================"
    log ""
    
    log "🔧 自动提交工具链到Git LFS..."
    
    # 检查当前目录是否是Git仓库
    if [ ! -d ".git" ]; then
        log "❌ 当前目录不是Git仓库，无法提交工具链"
        return 0
    fi
    
    # 检查是否有工具链文件
    if [ -d "firmware-config/Toolchain" ] && [ -n "$(ls -A firmware-config/Toolchain 2>/dev/null)" ]; then
        log "📦 有工具链文件需要提交"
        
        # 配置git用户
        git config --global user.name "GitHub Actions"
        git config --global user.email "actions@github.com"
        
        # 添加.gitattributes文件确保LFS配置
        log "🔧 确保.gitattributes文件存在并配置正确"
        if [ ! -f ".gitattributes" ]; then
            cat > .gitattributes << 'EOF'
# Git LFS 配置
firmware-config/Toolchain/** filter=lfs diff=lfs merge=lfs -text
*.tar.gz filter=lfs diff=lfs merge=lfs -text
*.tar.xz filter=lfs diff=lfs merge=lfs -text
*.bin filter=lfs diff=lfs merge=lfs -text
*.img filter=lfs diff=lfs merge=lfs -text
EOF
            log "✅ 创建.gitattributes文件"
        fi
        
        # 确保Git LFS已正确设置
        git lfs install --force
        
        # 添加所有工具链文件到LFS跟踪
        log "🔧 添加工具链文件到Git LFS跟踪..."
        git add .gitattributes
        git add firmware-config/Toolchain/
        
        # 检查是否有变更
        if git status --porcelain | grep -q "firmware-config/Toolchain" || git status --porcelain | grep -q ".gitattributes"; then
            log "📦 提交工具链文件..."
            
            # 使用单行提交消息
            COMMIT_MSG="chore: 自动更新工具链 [构建自动化] 版本: $SELECTED_BRANCH 目标: $TARGET/$SUBTARGET 设备: $DEVICE 模式: $CONFIG_MODE 时间: $(date '+%Y-%m-%d %H:%M:%S')"
            
            git commit -m "$COMMIT_MSG"
            
            log "🚀 推送工具链到远程仓库..."
            
            # 尝试推送
            for i in {1..3}; do
                log "尝试推送 #$i..."
                if git push; then
                    log "✅ 工具链已成功提交并推送到仓库"
                    break
                else
                    log "⚠️  推送失败，等待10秒后重试..."
                    sleep 10
                    if [ $i -eq 3 ]; then
                        log "❌ 推送失败3次，跳过工具链提交"
                    fi
                fi
            done
        else
            log "ℹ️  没有新的工具链文件需要提交"
        fi
    else
        log "ℹ️  没有工具链文件需要提交"
    fi
    
    log ""
    log "🎉 步骤30完成：工具链提交完成"
    log "========================================"
}

# 步骤31：错误分析（如果失败）
workflow_step31_error_analysis() {
    log "========================================"
    log "⚠️ 步骤31：错误分析（构建失败）"
    log "========================================"
    log ""
    
    # 使用完整路径调用错误分析脚本
    local error_analysis_script="$REPO_ROOT/firmware-config/scripts/error_analysis.sh"
    
    if [ -f "$error_analysis_script" ]; then
        log "📊 运行错误分析脚本..."
        cd "$REPO_ROOT"
        bash "$error_analysis_script"
    else
        log "❌ 错误分析脚本不存在: $error_analysis_script"
        log "📊 执行基本错误分析..."
        echo "=== 基本错误分析 ==="
        echo "分析时间: $(date)"
        echo "当前目录: $(pwd)"
        echo "构建目录: $BUILD_DIR"
        echo "设备: $DEVICE"
        echo "目标平台: $TARGET/$SUBTARGET"
        echo ""
        echo "=== 磁盘空间 ==="
        df -h
        echo ""
        echo "=== 构建目录状态 ==="
        ls -la "$BUILD_DIR/" 2>/dev/null | head -10 || echo "构建目录不存在"
    fi
    
    log ""
    log "🎉 步骤31完成：错误分析完成"
    log "========================================"
}

# 步骤32：编译后空间检查
workflow_step32_post_build_space_check() {
    log "========================================"
    log "📊 步骤32：编译后空间检查"
    log "========================================"
    log ""
    
    post_build_space_check
    
    log ""
    log "🎉 步骤32完成：编译后空间检查完成"
    log "========================================"
}

# 步骤33：固件文件检查
workflow_step33_check_firmware_files() {
    log "========================================"
    log "📦 步骤33：固件文件检查"
    log "========================================"
    log ""
    
    check_firmware_files
    
    log ""
    log "🎉 步骤33完成：固件文件检查完成"
    log "========================================"
}

# 步骤37：清理目录
workflow_step37_cleanup() {
    log "========================================"
    log "🧹 步骤37：清理目录"
    log "========================================"
    log ""
    
    cleanup
    
    log ""
    log "🎉 步骤37完成：目录清理完成"
    log "========================================"
}

# 步骤38：最终构建总结
workflow_step38_final_summary() {
    local build_status="$1"
    
    log "========================================"
    log "📈 步骤38：最终构建总结"
    log "========================================"
    log ""
    
    log "🎯 构建配置摘要:"
    log "  设备: $DEVICE"
    log "  版本: $SELECTED_BRANCH"
    log "  配置模式: $CONFIG_MODE"
    log "  目标平台: $TARGET/$SUBTARGET"
    log ""
    
    log "⚙️ 自动化功能状态:"
    log "  ✅ 自动下载源代码（支持工具链提交）"
    log "  ✅ 自动上传源代码压缩包（步骤3）"
    log "  ✅ 自动启用编译缓存 ($ENABLE_CACHE)"
    log "  ✅ 自动提交工具链到仓库 ($COMMIT_TOOLCHAIN)"
    log ""
    
    log "📦 构建产物:"
    log "  1. 源代码压缩包 (步骤3上传)"
    log "  2. 固件文件: firmware-$DEVICE-$SELECTED_BRANCH-$CONFIG_MODE"
    log "  3. 编译日志: build-log-$DEVICE-$SELECTED_BRANCH-$CONFIG_MODE"
    log "  4. 配置文件: config-$DEVICE-$SELECTED_BRANCH-$CONFIG_MODE"
    log ""
    
    log "📊 工具链状态:"
    if [ -d "firmware-config/Toolchain" ]; then
        toolchain_size=$(du -sh firmware-config/Toolchain 2>/dev/null | cut -f1 || echo "未知")
        log "  ✅ 工具链已保存 (大小: $toolchain_size)"
        log "  💡 下次构建将自动加载工具链，编译速度更快"
    else
        log "  ⚠️  工具链未保存"
    fi
    
    log ""
    log "📈 构建状态: $build_status"
    log ""
    
    if [ "$build_status" = "success" ]; then
        log "🎉 构建成功！"
        log "📥 所有构建产物已上传，可在Artifacts中下载"
        log "🚀 下次构建将使用已保存的工具链，编译速度更快"
    else
        log "❌ 构建失败"
        log "🔍 请查看错误分析日志和构建日志"
    fi
    
    log ""
    log "========================================"
    log "          🏁 构建流程全部完成          "
    log "========================================"
}

# ========== 主调度函数 ==========
workflow_main() {
    case $1 in
        "step1_download_source")
            workflow_step1_download_source "$2"
            ;;
        "step2_upload_source")
            workflow_step2_upload_source
            ;;
        "step4_install_git_lfs")
            workflow_step4_install_git_lfs
            ;;
        "step5_check_large_files")
            workflow_step5_check_large_files
            ;;
        "step6_check_toolchain_dir")
            workflow_step6_check_toolchain_dir
            ;;
        "step7_init_toolchain_dir")
            workflow_step7_init_toolchain_dir
            ;;
        "step8_setup_environment")
            workflow_step8_setup_environment
            ;;
        "step9_create_build_dir")
            workflow_step9_create_build_dir
            ;;
        "step10_init_build_env")
            workflow_step10_init_build_env "$2" "$3" "$4" "$5"
            ;;
        "step11_show_config")
            workflow_step11_show_config
            ;;
        "step12_add_turboacc_support")
            workflow_step12_add_turboacc_support
            ;;
        "step13_configure_feeds")
            workflow_step13_configure_feeds
            ;;
        "step14_install_turboacc_packages")
            workflow_step14_install_turboacc_packages
            ;;
        "step15_pre_build_space_check")
            workflow_step15_pre_build_space_check
            ;;
        "step16_generate_config")
            workflow_step16_generate_config "$2"
            ;;
        "step17_verify_usb_config")
            workflow_step17_verify_usb_config
            ;;
        "step18_check_usb_drivers_integrity")
            workflow_step18_check_usb_drivers_integrity
            ;;
        "step19_apply_config")
            workflow_step19_apply_config
            ;;
        "step20_backup_config")
            workflow_step20_backup_config
            ;;
        "step21_fix_network")
            workflow_step21_fix_network
            ;;
        "step22_load_toolchain")
            workflow_step22_load_toolchain
            ;;
        "step23_check_toolchain_status")
            workflow_step23_check_toolchain_status
            ;;
        "step24_download_dependencies")
            workflow_step24_download_dependencies
            ;;
        "step25_integrate_custom_files")
            workflow_step25_integrate_custom_files
            ;;
        "step26_pre_build_error_check")
            workflow_step26_pre_build_error_check
            ;;
        "step27_final_space_check")
            workflow_step27_final_space_check
            ;;
        "step28_build_firmware")
            workflow_step28_build_firmware
            ;;
        "step29_save_toolchain")
            workflow_step29_save_toolchain
            ;;
        "step30_commit_toolchain")
            workflow_step30_commit_toolchain
            ;;
        "step31_error_analysis")
            workflow_step31_error_analysis
            ;;
        "step32_post_build_space_check")
            workflow_step32_post_build_space_check
            ;;
        "step33_check_firmware_files")
            workflow_step33_check_firmware_files
            ;;
        "step37_cleanup")
            workflow_step37_cleanup
            ;;
        "step38_final_summary")
            workflow_step38_final_summary "$2"
            ;;
        # 工具函数
        "auto_update_gitattributes")
            auto_update_gitattributes "$2" "$3"
            ;;
        "auto_update_gitignore")
            auto_update_gitignore "$2"
            ;;
        "smart_manage_large_files")
            smart_manage_large_files
            ;;
        # 原有函数调用
        *)
            main "$@"
            ;;
    esac
}

# 原有主函数保持不变
main() {
    case $1 in
        "setup_environment")
            setup_environment
            ;;
        "create_build_dir")
            create_build_dir
            ;;
        "initialize_build_env")
            initialize_build_env "$2" "$3" "$4"
            ;;
        "add_turboacc_support")
            add_turboacc_support
            ;;
        "configure_feeds")
            configure_feeds
            ;;
        "install_turboacc_packages")
            install_turboacc_packages
            ;;
        "pre_build_space_check")
            pre_build_space_check
            ;;
        "generate_config")
            generate_config "$2"
            ;;
        "verify_usb_config")
            verify_usb_config
            ;;
        "check_usb_drivers_integrity")
            check_usb_drivers_integrity
            ;;
        "apply_config")
            apply_config
            ;;
        "fix_network")
            fix_network
            ;;
        "download_dependencies")
            download_dependencies
            ;;
        "load_toolchain")
            load_toolchain
            ;;
        "integrate_custom_files")
            integrate_custom_files
            ;;
        "pre_build_error_check")
            pre_build_error_check
            ;;
        "build_firmware")
            build_firmware "$2"
            ;;
        "save_toolchain")
            save_toolchain
            ;;
        "post_build_space_check")
            post_build_space_check
            ;;
        "check_firmware_files")
            check_firmware_files
            ;;
        "cleanup")
            cleanup
            ;;
        "init_toolchain_dir")
            init_toolchain_dir
            ;;
        "check_large_files")
            check_large_files
            ;;
        "check_toolchain_completeness")
            check_toolchain_completeness
            ;;
        "save_source_code_info")
            save_source_code_info
            ;;
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  原有命令:"
            echo "    setup_environment, create_build_dir, initialize_build_env"
            echo "    add_turboacc_support, configure_feeds, install_turboacc_packages"
            echo "    pre_build_space_check, generate_config, verify_usb_config, check_usb_drivers_integrity, apply_config"
            echo "    fix_network, download_dependencies, load_toolchain, integrate_custom_files"
            echo "    pre_build_error_check, build_firmware, save_toolchain, post_build_space_check"
            echo "    check_firmware_files, cleanup, init_toolchain_dir, check_large_files, check_toolchain_completeness"
            echo "    save_source_code_info"
            echo ""
            echo "  工作流步骤命令:"
            echo "    step1_download_source, step2_upload_source, step4_install_git_lfs, step5_check_large_files"
            echo "    step6_check_toolchain_dir, step7_init_toolchain_dir, step8_setup_environment, step9_create_build_dir"
            echo "    step10_init_build_env, step11_show_config, step12_add_turboacc_support, step13_configure_feeds"
            echo "    step14_install_turboacc_packages, step15_pre_build_space_check, step16_generate_config, step17_verify_usb_config"
            echo "    step18_check_usb_drivers_integrity, step19_apply_config, step20_backup_config, step21_fix_network"
            echo "    step22_load_toolchain, step23_check_toolchain_status, step24_download_dependencies, step25_integrate_custom_files"
            echo "    step26_pre_build_error_check, step27_final_space_check, step28_build_firmware, step29_save_toolchain"
            echo "    step30_commit_toolchain, step31_error_analysis, step32_post_build_space_check, step33_check_firmware_files"
            echo "    step37_cleanup, step38_final_summary"
            echo ""
            echo "  自动更新命令:"
            echo "    auto_update_gitattributes, auto_update_gitignore, smart_manage_large_files"
            exit 1
            ;;
    esac
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 如果第一个参数是"workflow_main"，则调用工作流主函数
    if [[ "$1" == "workflow_main" ]]; then
        workflow_main "${@:2}"
    else
        main "$@"
    fi
fi
