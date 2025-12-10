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

# ========== 新增：前置错误检查函数 ==========
pre_build_error_check() {
    log "=== 前置错误检查 ==="
    
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    # 检查.config文件
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        exit 1
    fi
    
    # 检查关键目录
    local critical_dirs=("staging_dir" "build_dir" "dl" "feeds" "package")
    for dir in "${critical_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log "⚠️  警告: 目录 $dir 不存在"
        fi
    done
    
    # 检查工具链
    log "检查工具链状态..."
    if [ -d "staging_dir" ]; then
        local toolchain_dirs=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | wc -l)
        if [ $toolchain_dirs -eq 0 ]; then
            log "⚠️  警告: 构建目录中没有工具链，可能需要下载"
        else
            log "✅ 构建目录中有 $toolchain_dirs 个工具链"
            find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | while read dir; do
                log "  工具链: $(basename $dir) ($(du -sh "$dir" 2>/dev/null | cut -f1 || echo '未知大小'))"
            done
        fi
    else
        log "⚠️  警告: staging_dir 目录不存在"
    fi
    
    # 检查磁盘空间
    log "检查磁盘空间..."
    local available_space=$(df -m "$BUILD_DIR" | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024))
    log "可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 5 ]; then
        log "🚨 严重警告: 磁盘空间不足 (需要至少5G，当前${available_gb}G)"
    else
        log "✅ 磁盘空间充足"
    fi
    
    # 检查关键文件
    local critical_files=(".config" "Makefile" "rules.mk" "Config.in")
    for file in "${critical_files[@]}"; do
        if [ ! -f "$file" ]; then
            log "❌ 错误: 关键文件 $file 不存在"
            exit 1
        fi
    done
    
    log "✅ 前置错误检查完成"
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

# 新增：验证工具链完整性函数（修复版）
verify_toolchain_completeness() {
    local toolchain_dir=$1
    
    log "🔧 验证工具链完整性: $toolchain_dir"
    
    if [ ! -d "$toolchain_dir" ]; then
        log "❌ 工具链目录不存在: $toolchain_dir"
        return 1
    fi
    
    # 检查真正的编译器文件，而不是stamp文件
    log "查找真正的编译器文件..."
    local compilers=($(find "$toolchain_dir" -type f \( -name "*gcc*" -o -name "*g++*" \) ! -name "*.stamp*" ! -name ".gcc_*" 2>/dev/null | grep -v "stamp" | head -20))
    
    if [ ${#compilers[@]} -eq 0 ]; then
        log "⚠️  未找到编译器，尝试在其他位置查找..."
        # 尝试在bin目录查找
        if [ -d "$toolchain_dir/bin" ]; then
            compilers=($(find "$toolchain_dir/bin" -type f -name "*gcc*" 2>/dev/null))
        fi
        
        if [ ${#compilers[@]} -eq 0 ]; then
            log "❌ 未找到任何编译器文件，工具链不完整"
            return 1
        fi
    fi
    
    log "找到 ${#compilers[@]} 个编译器文件"
    
    # 只检查真正的可执行文件，跳过标记文件
    local valid_compilers=0
    for compiler in "${compilers[@]}"; do
        # 跳过非普通文件（如目录、符号链接等）
        if [ ! -f "$compiler" ]; then
            continue
        fi
        
        # 跳过stamp文件和标记文件
        if [[ "$compiler" == *".stamp"* ]] || [[ "$compiler" == *".gcc_"* ]] || [[ "$compiler" == *"/stamp/"* ]]; then
            continue
        fi
        
        # 检查文件大小，太小的文件可能是标记文件
        local file_size=$(stat -c%s "$compiler" 2>/dev/null || echo "0")
        if [ "$file_size" -lt 1000 ]; then
            log "跳过小文件（可能是标记文件）: $compiler ($file_size 字节)"
            continue
        fi
        
        log "检查编译器: $compiler ($(du -h "$compiler" 2>/dev/null | cut -f1))"
        
        # 如果是可执行文件，测试它
        if [ -x "$compiler" ]; then
            log "✅ 可执行: $compiler"
            valid_compilers=$((valid_compilers + 1))
        else
            # 尝试添加执行权限
            if chmod +x "$compiler" 2>/dev/null; then
                log "✅ 已添加执行权限: $compiler"
                valid_compilers=$((valid_compilers + 1))
            else
                log "⚠️  无法添加执行权限: $compiler"
            fi
        fi
    done
    
    if [ $valid_compilers -eq 0 ]; then
        log "❌ 没有找到有效的可执行编译器"
        return 1
    fi
    
    log "✅ 找到 $valid_compilers 个有效的编译器"
    
    # 检查bin目录是否存在
    if [ ! -d "$toolchain_dir/bin" ]; then
        log "⚠️  警告: bin目录不存在，但找到了编译器文件"
        # 列出工具链目录结构以便调试
        log "工具链目录结构:"
        find "$toolchain_dir" -maxdepth 2 -type d | head -10
    else
        log "✅ bin目录存在"
    fi
    
    log "✅ 工具链验证通过"
    return 0
}

# 新增：检查工具链完整性（公开函数）
check_toolchain_completeness() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 检查工具链完整性 ==="
    
    # 查找工具链目录
    local toolchain_dir=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
    
    if [ -z "$toolchain_dir" ]; then
        log "❌ 未找到工具链目录"
        return 1
    fi
    
    verify_toolchain_completeness "$toolchain_dir"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log "✅ 工具链完整性检查通过"
    else
        log "❌ 工具链完整性检查失败"
    fi
    
    return $result
}

# 新增：设置工具链环境函数
setup_toolchain_env() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 设置工具链环境 ==="
    
    # 查找工具链目录
    local toolchain_dir=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
    
    if [ -d "$toolchain_dir" ]; then
        log "✅ 找到工具链目录: $toolchain_dir"
        
        # 设置工具链环境变量
        export STAGING_DIR="$toolchain_dir"
        
        # 查找编译器路径
        local bin_dir="$toolchain_dir/bin"
        if [ -d "$bin_dir" ]; then
            export PATH="$bin_dir:$PATH"
            log "✅ 添加工具链到PATH: $bin_dir"
            
            # 检查编译器是否存在
            local target_compiler=""
            case "$TARGET" in
                "ipq40xx")
                    target_compiler="arm-openwrt-linux-muslgnueabi-gcc"
                    ;;
                "ramips")
                    if [ "$SUBTARGET" = "mt76x8" ]; then
                        target_compiler="mipsel-openwrt-linux-musl-gcc"
                    elif [ "$SUBTARGET" = "mt7621" ]; then
                        target_compiler="mipsel-openwrt-linux-musl-gcc"
                    fi
                    ;;
            esac
            
            if [ -n "$target_compiler" ] && [ -f "$bin_dir/$target_compiler" ]; then
                log "✅ 找到目标编译器: $bin_dir/$target_compiler"
                # 测试编译器
                if "$bin_dir/$target_compiler" --version >/dev/null 2>&1; then
                    log "✅ 编译器工作正常"
                else
                    log "❌ 编译器无法运行，检查权限"
                    chmod +x "$bin_dir/$target_compiler"
                fi
            else
                log "⚠️  未找到目标编译器: $target_compiler"
                # 显示可用的编译器
                find "$bin_dir" -name "*gcc*" 2>/dev/null | head -5
            fi
        fi
    else
        log "⚠️  未找到工具链目录，将自动下载"
    fi
}

# 新增：保存源代码信息函数
save_source_code_info() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 保存源代码信息 ==="
    
    # 创建源代码信息目录
    local source_info_dir="/tmp/build-artifacts/source-info"
    mkdir -p "$source_info_dir"
    
    # 保存构建环境信息
    cat > "$source_info_dir/build_env.txt" << EOF
构建环境信息
===========
构建时间: $(date)
设备: $DEVICE
版本: $SELECTED_BRANCH
目标平台: $TARGET/$SUBTARGET
配置模式: $CONFIG_MODE
构建目录: $BUILD_DIR
仓库根目录: $REPO_ROOT
EOF
    
    # 保存配置文件信息
    if [ -f ".config" ]; then
        cp ".config" "$source_info_dir/openwrt.config"
        log "✅ 配置文件已保存"
    fi
    
    # 保存feeds信息
    if [ -f "feeds.conf.default" ]; then
        cp "feeds.conf.default" "$source_info_dir/feeds.conf"
        log "✅ Feeds配置已保存"
    fi
    
    # 保存目录结构
    log "📁 保存目录结构信息..."
    find . -maxdepth 3 -type d | sort > "$source_info_dir/directory_structure.txt"
    
    # 保存关键文件列表
    log "📋 保存关键文件列表..."
    cat > "$source_info_dir/key_files.txt" << 'EOF'
关键文件列表
==========
.config - OpenWrt配置文件
feeds.conf.default - Feeds配置文件
Makefile - 主Makefile
rules.mk - 构建规则
Config.in - 配置菜单
feeds/ - Feeds目录
package/ - 包目录
target/ - 目标平台目录
toolchain/ - 工具链目录
EOF
    
    log "✅ 源代码信息保存完成: $source_info_dir"
}

save_env() {
    mkdir -p $BUILD_DIR
    echo "#!/bin/bash" > $ENV_FILE
    echo "export SELECTED_REPO_URL=\"$SELECTED_REPO_URL\"" >> $ENV_FILE
    echo "export SELECTED_BRANCH=\"$SELECTED_BRANCH\"" >> $ENV_FILE
    echo "export TARGET=\"$TARGET\"" >> $ENV_FILE
    echo "export SUBTARGET=\"$SUBTARGET\"" >> $ENV_FILE
    echo "export DEVICE=\"$DEVICE\"" >> $ENV_FILE
    echo "export CONFIG_MODE=\"$CONFIG_MODE\"" >> $ENV_FILE
    echo "export REPO_ROOT=\"$REPO_ROOT\"" >> $ENV_FILE
    chmod +x $ENV_FILE
}

load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
}

get_toolchain_path() {
    load_env
    # 确保Toolchain目录存在
    mkdir -p "$TOOLCHAIN_DIR/$SELECTED_BRANCH/$TARGET/$SUBTARGET"
    echo "$TOOLCHAIN_DIR/$SELECTED_BRANCH/$TARGET/$SUBTARGET"
}

get_common_toolchain_path() {
    # 确保common目录存在
    mkdir -p "$TOOLCHAIN_DIR/common"
    echo "$TOOLCHAIN_DIR/common"
}

check_large_files() {
    log "=== 检查大文件 ==="
    
    local repo_root="$(pwd)"
    
    # 检查是否有超过 90MB 的文件
    log "检查大于90MB的文件..."
    large_files=$(find . -type f -size +90M 2>/dev/null | grep -v ".git" || true)
    
    if [ -n "$large_files" ]; then
        log "⚠️  发现以下大文件（可能超过GitHub限制）:"
        echo "$large_files"
        log "💡 建议: 将这些文件添加到 .gitattributes 中使用 Git LFS 管理"
        
        # 检查工具链中的大文件
        if [ -d "firmware-config/Toolchain" ]; then
            log "检查工具链中的大文件..."
            find firmware-config/Toolchain -type f -size +50M 2>/dev/null | head -10 || true
        fi
    else
        log "✅ 未发现超过90MB的大文件"
    fi
}

init_toolchain_dir() {
    log "=== 初始化工具链目录 ==="
    mkdir -p "$TOOLCHAIN_DIR"
    log "✅ 工具链目录: $TOOLCHAIN_DIR"
    
    # 确保目录结构正确
    mkdir -p "$TOOLCHAIN_DIR/common"
    mkdir -p "$TOOLCHAIN_DIR/openwrt-21.02"
    mkdir -p "$TOOLCHAIN_DIR/openwrt-23.05"
    
    # 创建README文件（如果不存在）
    if [ ! -f "$TOOLCHAIN_DIR/README.md" ]; then
        cat > "$TOOLCHAIN_DIR/README.md" << EOF
# OpenWrt 编译工具链

## 目录结构
- \`common/\` - 通用工具链组件，包含基本的编译工具
- \`<版本>/<平台>/<子平台>/ - 版本特定的完整工具链

## 用途
1. **加速编译**：保存的工具链可以避免重复下载和编译
2. **离线编译**：在没有网络的环境下也可以进行编译
3. **版本管理**：不同版本和平台的工具链独立保存

## 使用方式
工具链会在编译时自动加载，无需手动操作

## 注意事项
- 工具链文件较大，已使用 Git LFS 管理大文件
- 不同版本的工具链不兼容，请勿混用
- 如果编译失败，可以尝试清理工具链重新下载

## 文件说明
- \`build.config\` - 编译时使用的配置文件备份
- \`bin/\` - 编译工具（gcc, g++, ld等）
- \`lib/\` - 库文件
- \`include/\` - 头文件

## Git LFS 管理
大文件（如编译器、库文件）已使用 Git LFS 管理，确保不会超过 GitHub 文件大小限制
EOF
        log "✅ 创建README.md文件"
    fi
}

# ========== 修复：加载工具链函数（增强版）==========
load_toolchain() {
    log "=== 加载工具链（增强版）==="
    
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "当前工作目录: $(pwd)"
    log "仓库根目录: $REPO_ROOT"
    log "工具链目录: $TOOLCHAIN_DIR"
    
    # 首先检查构建目录中是否已有工具链
    local existing_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
    if [ -n "$existing_toolchain" ]; then
        log "✅ 构建目录中已有工具链，跳过加载: $existing_toolchain"
        log "工具链大小: $(du -sh "$existing_toolchain" 2>/dev/null | cut -f1 || echo '未知')"
        return 0
    fi
    
    # 获取工具链路径
    local toolchain_path=$(get_toolchain_path)
    local common_path=$(get_common_toolchain_path)
    
    log "检查仓库工具链目录:"
    log "  版本特定路径: $toolchain_path"
    log "  通用工具链路径: $common_path"
    
    # 创建staging_dir目录（如果不存在）
    mkdir -p staging_dir
    
    local found_toolchain=0
    
    # 首先尝试从版本特定路径加载
    if [ -d "$toolchain_path" ] && [ -n "$(ls -A "$toolchain_path" 2>/dev/null)" ]; then
        log "🔍 从版本特定路径查找工具链: $toolchain_path"
        
        # 查找工具链目录（可能是直接复制过来的工具链目录）
        local toolchain_dirs=$(find "$toolchain_path" -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
        
        if [ -n "$toolchain_dirs" ]; then
            local toolchain_name=$(basename "$toolchain_dirs")
            log "📦 找到工具链目录: $toolchain_name"
            log "复制工具链到构建目录..."
            
            # 复制工具链到staging_dir
            cp -r "$toolchain_dirs" staging_dir/
            
            if [ -d "staging_dir/$toolchain_name" ]; then
                log "✅ 版本特定工具链加载成功"
                log "工具链路径: staging_dir/$toolchain_name"
                found_toolchain=1
            fi
        else
            # 如果没有找到toolchain-*目录，检查是否整个目录就是工具链
            log "未找到toolchain-*格式的目录，检查整个目录..."
            local dir_content=$(ls -A "$toolchain_path" 2>/dev/null | head -5)
            if [ -n "$dir_content" ]; then
                log "目录内容: $dir_content"
                
                # 检查是否有bin目录和编译器
                if [ -d "$toolchain_path/bin" ]; then
                    local compilers=$(find "$toolchain_path/bin" -name "*gcc*" 2>/dev/null | head -3)
                    if [ -n "$compilers" ]; then
                        log "🔧 找到编译器，创建工具链目录..."
                        mkdir -p staging_dir/toolchain-repo
                        cp -r "$toolchain_path/"* staging_dir/toolchain-repo/ 2>/dev/null || true
                        
                        # 重命名为标准格式
                        local new_name="toolchain-repo-$(date +%s)"
                        mv staging_dir/toolchain-repo staging_dir/"$new_name" 2>/dev/null || true
                        
                        if [ -d "staging_dir/$new_name" ]; then
                            log "✅ 工具链文件加载成功"
                            found_toolchain=1
                        fi
                    fi
                fi
            fi
        fi
    fi
    
    # 如果版本特定路径没有找到，尝试通用路径
    if [ $found_toolchain -eq 0 ] && [ -d "$common_path" ] && [ -n "$(ls -A "$common_path" 2>/dev/null)" ]; then
        log "🔍 从通用工具链路径查找: $common_path"
        
        # 检查是否有编译器
        if [ -d "$common_path/bin" ]; then
            local compilers=$(find "$common_path/bin" -name "*gcc*" 2>/dev/null | head -3)
            if [ -n "$compilers" ]; then
                log "🔧 找到通用编译器，创建工具链目录..."
                mkdir -p staging_dir/toolchain-common
                cp -r "$common_path/"* staging_dir/toolchain-common/ 2>/dev/null || true
                
                log "✅ 通用工具链加载成功"
                found_toolchain=1
            fi
        fi
    fi
    
    # 如果都没有找到工具链
    if [ $found_toolchain -eq 0 ]; then
        log "⚠️  仓库中未找到可用的工具链，将自动下载"
        log "工具链保存路径说明:"
        log "  版本特定路径: $toolchain_path"
        log "  通用路径: $common_path"
        
        # 显示工具链目录结构（用于调试）
        if [ -d "$TOOLCHAIN_DIR" ]; then
            log "当前工具链目录结构:"
            find "$TOOLCHAIN_DIR" -maxdepth 3 -type d 2>/dev/null | sort | head -20 || log "无法列出目录"
        fi
    else
        # 验证加载的工具链
        log "🔧 验证加载的工具链..."
        local loaded_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
        if [ -n "$loaded_toolchain" ]; then
            verify_toolchain_completeness "$loaded_toolchain" || log "⚠️ 工具链验证失败"
        fi
    fi
    
    log "✅ 工具链加载完成"
    log "构建目录状态:"
    if [ -d "staging_dir" ]; then
        find staging_dir -maxdepth 1 -type d 2>/dev/null | while read dir; do
            local dir_name=$(basename "$dir")
            if [ "$dir_name" != "staging_dir" ]; then
                log "  - $dir_name ($(du -sh "$dir" 2>/dev/null | cut -f1 || echo '未知'))"
            fi
        done
    fi
    
    return 0
}

save_toolchain() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 保存工具链到仓库 ==="
    
    # 初始化工具链目录
    init_toolchain_dir
    
    local toolchain_path=$(get_toolchain_path)
    local common_path=$(get_common_toolchain_path)
    
    log "🔍 工具链保存路径信息:"
    log "  目标工具链路径: $toolchain_path"
    log "  仓库根目录: $REPO_ROOT"
    log "  当前工作目录: $(pwd)"
    
    # 确保目标目录存在且有写权限
    mkdir -p "$toolchain_path"
    mkdir -p "$common_path"
    
    # 检查是否有工具链可以保存
    local staging_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
    
    if [ -z "$staging_toolchain" ]; then
        log "⚠️  未找到工具链，跳过保存"
        return 0
    fi
    
    log "找到工具链: $staging_toolchain"
    
    # 先清理目标目录
    log "清理目标目录..."
    rm -rf "$toolchain_path"/*
    rm -rf "$common_path"/*
    
    if [ -d "$staging_toolchain" ]; then
        log "保存版本特定工具链到: $toolchain_path"
        
        # 使用rsync保持文件属性和符号链接
        cd "$(dirname "$staging_toolchain")"
        local toolchain_name=$(basename "$staging_toolchain")
        
        # 创建工具链的压缩版本（用于快速传输）
        log "创建工具链..."
        if rsync -av "$toolchain_name/" "$toolchain_path/" --exclude="*.o" --exclude="*.a"; then
            log "✅ 版本特定工具链保存成功 (使用rsync复制)"
            
            # 记录工具链信息
            echo "# Toolchain saved on $(date)" > "$toolchain_path/toolchain.info"
            echo "Version: $SELECTED_BRANCH" >> "$toolchain_path/toolchain.info"
            echo "Target: $TARGET" >> "$toolchain_path/toolchain.info"
            echo "Subtarget: $SUBTARGET" >> "$toolchain_path/toolchain.info"
            echo "Device: $DEVICE" >> "$toolchain_path/toolchain.info"
            echo "Saved with Git LFS: true" >> "$toolchain_path/toolchain.info"
        else
            log "❌ rsync复制失败"
            return 1
        fi
    else
        log "❌ 工具链目录不存在: $staging_toolchain"
        return 1
    fi
    
    log "保存通用工具链到: $common_path"
    mkdir -p "$common_path/bin"
    
    # 复制常用工具
    local tools=("ar" "as" "gcc" "g++" "ld" "nm" "objcopy" "objdump" "ranlib" "strip")
    local copied_tools=0
    for tool in "${tools[@]}"; do
        if find "$staging_toolchain/bin" -name "*$tool*" -type f -exec cp -v {} "$common_path/bin/" \; 2>/dev/null; then
            copied_tools=$((copied_tools + 1))
        fi
    done
    
    log "复制了 $copied_tools 个通用工具"
    
    # 保存编译配置文件
    mkdir -p "$common_path/etc"
    if [ -f "$BUILD_DIR/openwrt/.config" ]; then
        cp "$BUILD_DIR/openwrt/.config" "$common_path/etc/build.config"
        log "✅ 保存构建配置文件"
    fi
    
    # 显示保存结果
    log "✅ 工具链保存完成"
    log "特定版本工具链: $toolchain_path"
    log "  文件数: $(find "$toolchain_path" -type f | wc -l)"
    log "  大小: $(du -sh "$toolchain_path" | cut -f1)"
    log "通用工具链: $common_path"
    log "  通用工具: $copied_tools 个"
    log "  大小: $(du -sh "$common_path" | cut -f1)"
    
    # 检查是否有大文件需要Git LFS管理
    log "🔍 检查大文件..."
    local large_files=$(find "$TOOLCHAIN_DIR" -type f -size +50M 2>/dev/null | wc -l)
    if [ $large_files -gt 0 ]; then
        log "⚠️  发现 $large_files 个大于50M的文件，建议使用Git LFS管理"
        find "$TOOLCHAIN_DIR" -type f -size +50M 2>/dev/null | head -5
    fi
    
    return 0
}

# ========== OpenWrt源码下载函数 ==========

# 下载OpenWrt源代码
download_openwrt_source() {
    log "=== 下载OpenWrt源代码 ==="
    
    cd "$BUILD_DIR"
    
    log "📥 下载OpenWrt $SELECTED_BRANCH 源代码..."
    
    # 根据分支选择下载对应的OpenWrt版本
    local openwrt_url=""
    case "$SELECTED_BRANCH" in
        "openwrt-23.05")
            openwrt_url="https://github.com/openwrt/openwrt.git"
            ;;
        "openwrt-21.02")
            openwrt_url="https://github.com/openwrt/openwrt.git"
            ;;
        *)
            openwrt_url="https://github.com/openwrt/openwrt.git"
            log "⚠️  使用默认的OpenWrt主分支"
            ;;
    esac
    
    log "🔗 下载地址: $openwrt_url"
    log "📂 目标目录: $BUILD_DIR"
    
    # 检查是否已经存在OpenWrt源码
    if [ -d "$BUILD_DIR/openwrt" ] && [ -f "$BUILD_DIR/openwrt/feeds.conf.default" ]; then
        log "✅ OpenWrt源码已存在，跳过下载"
        log "📊 源码目录信息:"
        log "  路径: $BUILD_DIR/openwrt"
        log "  大小: $(du -sh "$BUILD_DIR/openwrt" 2>/dev/null | cut -f1 || echo '未知')"
        return 0
    fi
    
    # 清理旧的源码目录
    if [ -d "$BUILD_DIR/openwrt" ]; then
        log "🧹 清理旧的源码目录..."
        rm -rf "$BUILD_DIR/openwrt"
    fi
    
    # 下载OpenWrt源码
    log "⏬ 正在下载OpenWrt源码..."
    git clone --depth 1 --branch "$SELECTED_BRANCH" "$openwrt_url" "$BUILD_DIR/openwrt"
    
    if [ ! -d "$BUILD_DIR/openwrt" ]; then
        log "❌ OpenWrt源码下载失败"
        exit 1
    fi
    
    log "✅ OpenWrt源码下载完成"
    log "📊 下载信息:"
    log "  版本: $SELECTED_BRANCH"
    log "  目录: $BUILD_DIR/openwrt"
    log "  大小: $(du -sh "$BUILD_DIR/openwrt" 2>/dev/null | cut -f1 || echo '未知')"
    
    # 显示源码目录结构
    log "📁 源码目录结构:"
    find "$BUILD_DIR/openwrt" -maxdepth 2 -type d | head -20
    
    log "=== OpenWrt源码下载完成 ==="
}

# ========== 构建环境初始化函数 ==========

# 初始化构建环境
initialize_build_env() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local extra_packages="${4:-}"
    
    log "=== 初始化构建环境 ==="
    
    log "📱 设备: $device_name"
    log "🔄 版本选择: $version_selection"
    log "⚙️ 配置模式: $config_mode"
    log "🔌 额外插件: $extra_packages"
    
    # 设置版本分支
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_BRANCH="openwrt-23.05"
    elif [ "$version_selection" = "21.02" ]; then
        SELECTED_BRANCH="openwrt-21.02"
    else
        SELECTED_BRANCH="$version_selection"
    fi
    
    log "✅ 版本分支: $SELECTED_BRANCH"
    
    # 设备到目标的映射（修复版）
    case "$device_name" in
        "ac42u")
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="asus_rt-ac42u"
            log "🔧 检测到高通IPQ40xx平台设备: $device_name (华硕RT-AC42U)"
            log "🔧 该设备支持USB 3.0，将启用所有USB 3.0相关驱动"
            ;;
        "acrh17")
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="asus_rt-acrh17"
            log "🔧 检测到高通IPQ40xx平台设备: $device_name (华硕RT-ACRH17)"
            log "🔧 该设备支持USB 3.0，将启用所有USB 3.0相关驱动"
            ;;
        "r3g")
            TARGET="ramips"
            SUBTARGET="mt7621"
            DEVICE="xiaomi_mi-router-3g"
            log "🔧 检测到雷凌MT7621平台设备: $device_name"
            ;;
        *)
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="$device_name"
            log "🔧 未知设备，使用默认平台: $TARGET/$SUBTARGET"
            ;;
    esac
    
    log "🎯 目标平台: $TARGET/$SUBTARGET (根据设备 $device_name 确定)"
    log "📱 设备: $DEVICE"
    
    # 配置模式
    CONFIG_MODE="$config_mode"
    log "⚙️ 配置模式: $CONFIG_MODE"
    
    # 从环境变量获取或设置默认值
    ENABLE_CACHE="${ENABLE_CACHE:-true}"
    COMMIT_TOOLCHAIN="${COMMIT_TOOLCHAIN:-true}"
    
    log "⚡ 启用缓存: $ENABLE_CACHE"
    log "💾 提交工具链: $COMMIT_TOOLCHAIN"
    
    # 下载OpenWrt源代码
    download_openwrt_source
    
    # 创建符号链接，确保构建系统能找到源码
    if [ -d "$BUILD_DIR/openwrt" ] && [ ! -L "$BUILD_DIR"/*.sh ]; then
        log "🔗 创建构建系统链接..."
        
        # 进入OpenWrt源码目录
        cd "$BUILD_DIR/openwrt"
        
        # 备份原始的feeds.conf.default
        if [ -f "feeds.conf.default" ]; then
            cp feeds.conf.default feeds.conf.default.backup
            log "📄 备份feeds.conf.default"
        fi
        
        # 回到构建目录
        cd "$BUILD_DIR"
    fi
    
    # 保存环境变量到文件
    log "📝 保存环境变量到: $ENV_FILE"
    cat > "$ENV_FILE" << EOF
# 构建环境变量
# 生成时间: $(date)
SELECTED_BRANCH="$SELECTED_BRANCH"
TARGET="$TARGET"
SUBTARGET="$SUBTARGET"
DEVICE="$DEVICE"
CONFIG_MODE="$CONFIG_MODE"
ENABLE_CACHE="$ENABLE_CACHE"
COMMIT_TOOLCHAIN="$COMMIT_TOOLCHAIN"
EXTRA_PACKAGES="$extra_packages"
BUILD_DIR="$BUILD_DIR"
REPO_ROOT="$REPO_ROOT"
TOOLCHAIN_DIR="$TOOLCHAIN_DIR"
EOF
    
    log "✅ 环境变量保存完成"
    log "📄 环境变量文件: $ENV_FILE"
    
    # 显示环境变量
    log "📋 当前环境变量:"
    log "  SELECTED_BRANCH: $SELECTED_BRANCH"
    log "  TARGET: $TARGET"
    log "  SUBTARGET: $SUBTARGET"
    log "  DEVICE: $DEVICE"
    log "  CONFIG_MODE: $CONFIG_MODE"
    log "  ENABLE_CACHE: $ENABLE_CACHE"
    log "  COMMIT_TOOLCHAIN: $COMMIT_TOOLCHAIN"
    log "  EXTRA_PACKAGES: $extra_packages"
    
    log "=== 构建环境初始化完成 ==="
}

# ========== 集成自定义文件（修复目录路径）==========

integrate_custom_files() {
    log "=== 集成自定义文件 ==="
    
    cd "$BUILD_DIR/openwrt"
    
    log "🔌 集成自定义文件..."
    
    # 检查是否有自定义文件目录
    local custom_files_dir="$REPO_ROOT/firmware-config/custom-files"
    
    if [ -d "$custom_files_dir" ]; then
        log "📁 找到自定义文件目录: $custom_files_dir"
        log "📊 目录内容:"
        find "$custom_files_dir" -type f | head -10 | while read file; do
            local size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "未知")
            log "  - $(basename "$file") ($size)"
        done
        
        # 创建files目录（如果不存在）
        mkdir -p files
        
        # 复制文件到构建目录
        log "📦 复制自定义文件..."
        cp -r "$custom_files_dir/"* files/ 2>/dev/null || true
        
        # 检查复制结果
        local copied_count=$(find files -type f 2>/dev/null | wc -l || echo "0")
        log "✅ 自定义文件复制完成，共复制 $copied_count 个文件"
        
        # 显示复制的文件
        log "📋 复制的文件:"
        find files -type f | head -5 | while read file; do
            log "  - $file"
        done
    else
        log "ℹ️  无自定义文件目录: $custom_files_dir 不存在"
        log "📁 检查路径: $REPO_ROOT"
        log "📁 当前工作目录: $(pwd)"
        log "📁 仓库根目录结构:"
        ls -la "$REPO_ROOT" || true
    fi
    
    log "=== 自定义文件集成完成 ==="
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
    
    cd "$BUILD_DIR/openwrt"
    
    if [ ! -d "staging_dir" ]; then
        log "❌ 构建目录中没有工具链，跳过保存"
        return 0
    fi
    
    # 查找工具链目录
    local toolchain_dirs=$(find "staging_dir" -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
    
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
    
    log "📁 检查构建目录: $BUILD_DIR"
    
    if [ -d "$BUILD_DIR" ]; then
        log "✅ 构建目录已存在，跳过创建"
        log "📊 目录信息:"
        log "  路径: $BUILD_DIR"
        log "  权限: $(ls -ld "$BUILD_DIR" | awk '{print $1}')"
        log "  所有者: $(ls -ld "$BUILD_DIR" | awk '{print $3":"$4}')"
    else
        log "📁 创建构建目录: $BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        
        # 只有在目录不存在时才设置权限
        if [ -d "$BUILD_DIR" ]; then
            log "✅ 构建目录创建成功"
        else
            log "❌ 构建目录创建失败"
            exit 1
        fi
    fi
    
    # 检查磁盘空间
    local available_space=$(df -h "$BUILD_DIR" | tail -1 | awk '{print $4}')
    log "💽 可用空间: $available_space"
    
    log "=== 构建目录创建完成 ==="
}

# ========== 原有函数（修复目录路径）==========

# 添加 TurboACC 支持
add_turboacc_support() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 添加 TurboACC 支持 ==="
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        log "🔧 为正常模式添加 TurboACC 支持"
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            log "🔧 为 23.05 添加 TurboACC 支持"
            echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
            log "✅ TurboACC feed 添加完成"
        else
            log "ℹ️  21.02 版本已内置 TurboACC，无需额外添加"
        fi
    else
        log "ℹ️  基础模式不添加 TurboACC 支持"
    fi
}

# 配置 Feeds
configure_feeds() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 配置Feeds ==="
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        FEEDS_BRANCH="openwrt-23.05"
    else
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ] && [ "$CONFIG_MODE" = "normal" ]; then
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
    fi
    
    log "=== 更新Feeds ==="
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    # 检查feeds安装结果
    local critical_feeds_dirs=("feeds/packages" "feeds/luci" "package/feeds")
    for dir in "${critical_feeds_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log "✅ Feed目录存在: $dir"
        else
            log "❌ Feed目录缺失: $dir"
        fi
    done
    
    log "✅ Feeds配置完成"
}

# 安装 TurboACC 包
install_turboacc_packages() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 安装 TurboACC 包 ==="
    
    ./scripts/feeds update turboacc || handle_error "更新turboacc feed失败"
    
    ./scripts/feeds install -p turboacc luci-app-turboacc || handle_error "安装luci-app-turboacc失败"
    ./scripts/feeds install -p turboacc kmod-shortcut-fe || handle_error "安装kmod-shortcut-fe失败"
    ./scripts/feeds install -p turboacc kmod-fast-classifier || handle_error "安装kmod-fast-classifier失败"
    
    log "✅ TurboACC 包安装完成"
}

# 编译前空间检查
pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    
    echo "当前目录: $(pwd)"
    echo "构建目录: $BUILD_DIR"
    
    # 详细磁盘信息
    echo "=== 磁盘使用情况 ==="
    df -h
    
    # 构建目录空间
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    # 检查/mnt可用空间
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    echo "/mnt 可用空间: ${available_gb}G"
    
    # 检查/可用空间
    local root_available_space=$(df / --output=avail | tail -1)
    local root_available_gb=$((root_available_space / 1024 / 1024))
    echo "/ 可用空间: ${root_available_gb}G"
    
    # 内存和交换空间
    echo "=== 内存使用情况 ==="
    free -h
    
    # CPU信息
    echo "=== CPU信息 ==="
    echo "CPU核心数: $(nproc)"
    
    # 编译所需空间估算
    local estimated_space=15  # 估计需要15GB
    if [ $available_gb -lt $estimated_space ]; then
        log "⚠️  警告: 可用空间(${available_gb}G)可能不足，建议至少${estimated_space}G"
    else
        log "✅ 磁盘空间充足: ${available_gb}G 可用"
    fi
    
    log "✅ 空间检查完成"
}

# 生成配置
generate_config() {
    local extra_packages=$1
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 智能配置生成系统（USB完全修复通用版）==="
    log "版本: $SELECTED_BRANCH"
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    
    rm -f .config .config.old
    
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
    echo "CONFIG_PACKAGE_busybox=y" >> .config
    echo "CONFIG_PACKAGE_base-files=y" >> .config
    echo "CONFIG_PACKAGE_dropbear=y" >> .config
    echo "CONFIG_PACKAGE_firewall=y" >> .config
    echo "CONFIG_PACKAGE_fstools=y" >> .config
    echo "CONFIG_PACKAGE_libc=y" >> .config
    echo "CONFIG_PACKAGE_libgcc=y" >> .config
    echo "CONFIG_PACKAGE_mtd=y" >> .config
    echo "CONFIG_PACKAGE_netifd=y" >> .config
    echo "CONFIG_PACKAGE_opkg=y" >> .config
    echo "CONFIG_PACKAGE_procd=y" >> .config
    echo "CONFIG_PACKAGE_ubox=y" >> .config
    echo "CONFIG_PACKAGE_ubus=y" >> .config
    echo "CONFIG_PACKAGE_ubusd=y" >> .config
    echo "CONFIG_PACKAGE_uci=y" >> .config
    echo "CONFIG_PACKAGE_uclient-fetch=y" >> .config
    echo "CONFIG_PACKAGE_usign=y" >> .config
    
    echo "# CONFIG_PACKAGE_dnsmasq is not set" >> .config
    echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcp=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dnssec=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_ipset=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_conntrack=y" >> .config
    
    echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
    echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
    echo "CONFIG_PACKAGE_ath10k-firmware-qca988x=y" >> .config
    echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y" >> .config
    
    echo "CONFIG_PACKAGE_iptables=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-conntrack-extra=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-ipopt=y" >> .config
    echo "CONFIG_PACKAGE_ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ipt-nat6=y" >> .config
    
    # 添加常用网络插件
    echo "CONFIG_PACKAGE_bridge=y" >> .config
    echo "CONFIG_PACKAGE_blockd=y" >> .config
    echo "# CONFIG_PACKAGE_busybox-selinux is not set" >> .config
    echo "# CONFIG_PACKAGE_attendedsysupgrade-common is not set" >> .config
    echo "# CONFIG_PACKAGE_auc is not set" >> .config
    
    log "=== 🚨 USB 完全修复通用配置 - 开始 ==="
    
    echo "# 🟢 USB 核心驱动 - 基础必须" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config
    
    echo "# 🟢 USB 主机控制器驱动 - 通用支持" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ehci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-uhci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
    
    echo "# 🟢 USB 3.0扩展主机控制器接口驱动 - 支持USB 3.0高速数据传输" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> .config
    
    echo "# 🟡 平台专用USB控制器驱动 - 根据平台启用" >> .config
    log "🔍 检测平台类型: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
    
    if [ "$TARGET" = "ipq40xx" ]; then
        log "🚨 关键修复：IPQ40xx 专用USB控制器驱动（高通平台，支持USB 3.0）"
        echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
        # 高通平台通常不需要MTK驱动，但保留以防万一
        echo "# CONFIG_PACKAGE_kmod-usb-xhci-mtk is not set" >> .config
        log "✅ 已启用所有高通IPQ40xx平台的USB驱动"
    fi
    
    if [ "$TARGET" = "ramips" ]; then
        if [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; then
            log "🚨 关键修复：MT76xx/雷凌 平台USB控制器驱动"
            echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
            # 雷凌平台通常不需要高通专用驱动
            echo "# CONFIG_PACKAGE_kmod-usb-dwc3-qcom is not set" >> .config
            echo "# CONFIG_PACKAGE_kmod-phy-qcom-dwc3 is not set" >> .config
            log "✅ 已启用雷凌MT76xx平台的USB驱动"
        fi
    fi
    
    echo "# 🟢 USB 存储驱动 - 核心功能" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
    
    echo "# 🟢 SCSI 支持 - 硬盘和U盘必需" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-core=y" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-generic=y" >> .config
    
    echo "# 🟢 文件系统支持 - 完整文件系统兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-exfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-autofs4=y" >> .config
    
    echo "# 🟢 USB大容量存储额外驱动" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本NTFS配置优化"
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs-3g is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs-3g-utils is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs3-mount is not set" >> .config
    else
        log "🔧 21.02版本NTFS配置"
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
        echo "CONFIG_PACKAGE_ntfs3-mount=y" >> .config
    fi
    
    echo "# 🟢 编码支持 - 多语言文件名兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp437=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-iso8859-1=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp936=y" >> .config
    
    echo "# 🟢 自动挂载工具 - 即插即用支持" >> .config
    echo "CONFIG_PACKAGE_block-mount=y" >> .config
    echo "CONFIG_PACKAGE_automount=y" >> .config
    
    echo "# 🟢 USB 工具和热插拔支持 - 设备管理" >> .config
    echo "CONFIG_PACKAGE_usbutils=y" >> .config
    echo "CONFIG_PACKAGE_lsusb=y" >> .config
    echo "CONFIG_PACKAGE_udev=y" >> .config
    
    echo "# 🟢 USB串口支持 - 扩展功能" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-serial=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-serial-ftdi=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-serial-pl2303=y" >> .config
    
    log "=== 🚨 USB 完全修复通用配置 - 完成 ==="
    
    echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y" >> .config
    
    if [ "$CONFIG_MODE" = "base" ]; then
        log "🔧 使用基础模式 (最小化，用于测试编译)"
        echo "# CONFIG_PACKAGE_luci-app-turboacc is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-shortcut-fe is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-fast-classifier is not set" >> .config
        echo "# CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn is not set" >> .config
    else
        log "🔧 使用正常模式 (完整功能)"
        
        NORMAL_PLUGINS=(
          "CONFIG_PACKAGE_luci-app-turboacc=y"
          "CONFIG_PACKAGE_kmod-shortcut-fe=y"
          "CONFIG_PACKAGE_kmod-fast-classifier=y"
          "CONFIG_PACKAGE_luci-app-upnp=y"
          "CONFIG_PACKAGE_miniupnpd=y"
          "CONFIG_PACKAGE_vsftpd=y"
          "CONFIG_PACKAGE_luci-app-vsftpd=y"
          "CONFIG_PACKAGE_luci-app-arpbind=y"
          "CONFIG_PACKAGE_luci-app-cpulimit=y"
          "CONFIG_PACKAGE_samba4-server=y"
          "CONFIG_PACKAGE_luci-app-samba4=y"
          "CONFIG_PACKAGE_luci-app-wechatpush=y"
          "CONFIG_PACKAGE_sqm-scripts=y"
          "CONFIG_PACKAGE_luci-app-sqm=y"
          "CONFIG_PACKAGE_luci-app-hd-idle=y"
          "CONFIG_PACKAGE_luci-app-diskman=y"
          "CONFIG_PACKAGE_luci-app-accesscontrol=y"
          "CONFIG_PACKAGE_vlmcsd=y"
          "CONFIG_PACKAGE_luci-app-vlmcsd=y"
          "CONFIG_PACKAGE_smartdns=y"
          "CONFIG_PACKAGE_luci-app-smartdns=y"
        )
        
        for plugin in "${NORMAL_PLUGINS[@]}"; do
            echo "$plugin" >> .config
        done
        
        if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
            echo "CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-vsftpd-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-arpbind-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-cpulimit-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-sqm-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-hd-idle-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-diskman-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-accesscontrol-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y" >> .config
        fi
    fi
    
    # 处理额外插件
    if [ -n "$extra_packages" ]; then
        log "🔧 处理额外安装插件: $extra_packages"
        IFS=';' read -ra EXTRA_PKGS <<< "$extra_packages"
        for pkg_cmd in "${EXTRA_PKGS[@]}"; do
            if [ -n "$pkg_cmd" ]; then
                pkg_cmd_clean=$(echo "$pkg_cmd" | xargs)
                if [[ "$pkg_cmd_clean" == +* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    log "启用插件: $pkg_name"
                    echo "CONFIG_PACKAGE_${pkg_name}=y" >> .config
                elif [[ "$pkg_cmd_clean" == -* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    log "禁用插件: $pkg_name"
                    echo "# CONFIG_PACKAGE_${pkg_name} is not set" >> .config
                else
                    log "启用插件: $pkg_cmd_clean"
                    echo "CONFIG_PACKAGE_${pkg_cmd_clean}=y" >> .config
                fi
            fi
        done
    fi
    
    log "✅ 智能配置生成完成"
}

# 验证 USB 配置
verify_usb_config() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 🚨 详细验证USB和存储配置 ==="
    
    echo "1. 🟢 USB核心模块:"
    grep "CONFIG_PACKAGE_kmod-usb-core" .config | grep "=y" && echo "✅ USB核心" || echo "❌ 缺少USB核心"
    
    echo "2. 🟢 USB控制器:"
    grep -E "CONFIG_PACKAGE_kmod-usb2|CONFIG_PACKAGE_kmod-usb3|CONFIG_PACKAGE_kmod-usb-ehci|CONFIG_PACKAGE_kmod-usb-ohci|CONFIG_PACKAGE_kmod-usb-xhci-hcd" .config | grep "=y" || echo "❌ 缺少USB控制器"
    
    echo "3. 🚨 USB 3.0关键驱动:"
    echo "  - kmod-usb-xhci-hcd:" $(grep "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - kmod-usb3:" $(grep "CONFIG_PACKAGE_kmod-usb3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - kmod-usb-dwc3:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    echo "4. 🚨 平台专用USB控制器:"
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "  🔧 检测到高通IPQ40xx平台，检查专用驱动:"
        echo "  - kmod-usb-dwc3-qcom:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
        echo "  - kmod-phy-qcom-dwc3:" $(grep "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    elif [ "$TARGET" = "ramips" ]; then
        echo "  🔧 检测到雷凌平台，检查专用驱动:"
        echo "  - kmod-usb-ohci-pci:" $(grep "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
        echo "  - kmod-usb2-pci:" $(grep "CONFIG_PACKAGE_kmod-usb2-pci=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    fi
    
    echo "5. 🟢 USB存储:"
    grep "CONFIG_PACKAGE_kmod-usb-storage" .config | grep "=y" && echo "✅ USB存储" || echo "❌ 缺少USB存储"
    
    echo "6. 🟢 SCSI支持:"
    grep -E "CONFIG_PACKAGE_kmod-scsi-core|CONFIG_PACKAGE_kmod-scsi-generic" .config | grep "=y" && echo "✅ SCSI支持" || echo "❌ 缺少SCSI支持"
    
    echo "7. 🟢 文件系统支持:"
    echo "  - NTFS3:" $(grep "CONFIG_PACKAGE_kmod-fs-ntfs3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - ext4:" $(grep "CONFIG_PACKAGE_kmod-fs-ext4=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - vfat:" $(grep "CONFIG_PACKAGE_kmod-fs-vfat=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    log "=== 🚨 USB配置验证完成 ==="
    
    # 输出总结
    log "📊 USB配置状态总结:"
    local usb_drivers=("kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-ehci" "kmod-usb-ohci" "kmod-usb-xhci-hcd" "kmod-usb-storage")
    local missing_count=0
    local enabled_count=0
    
    for driver in "${usb_drivers[@]}"; do
        if grep -q "CONFIG_PACKAGE_${driver}=y" .config; then
            log "  ✅ $driver: 已启用"
            enabled_count=$((enabled_count + 1))
        else
            log "  ❌ $driver: 未启用"
            missing_count=$((missing_count + 1))
        fi
    done
    
    log "📈 统计: $enabled_count 个已启用，$missing_count 个未启用"
    
    if [ $missing_count -gt 0 ]; then
        log "⚠️  警告: 有 $missing_count 个关键USB驱动未启用，可能会影响USB功能"
    else
        log "🎉 恭喜: 所有关键USB驱动都已启用"
    fi
}

# 检查 USB 驱动完整性
check_usb_drivers_integrity() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 🚨 USB驱动完整性检查 ==="
    
    local missing_drivers=()
    local required_drivers=(
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb3"
        "kmod-usb-xhci-hcd"
        "kmod-usb-storage"
        "kmod-scsi-core"
    )
    
    # 根据平台添加专用驱动
    if [ "$TARGET" = "ipq40xx" ]; then
        required_drivers+=("kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3")
    fi
    
    # 检查所有必需驱动
    for driver in "${required_drivers[@]}"; do
        if ! grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            log "❌ 缺失驱动: $driver"
            missing_drivers+=("$driver")
        else
            log "✅ 驱动存在: $driver"
        fi
    done
    
    # 如果有缺失驱动，尝试修复
    if [ ${#missing_drivers[@]} -gt 0 ]; then
        log "🚨 发现 ${#missing_drivers[@]} 个缺失的USB驱动"
        log "正在尝试修复..."
        
        for driver in "${missing_drivers[@]}"; do
            echo "CONFIG_PACKAGE_${driver}=y" >> .config
            log "✅ 已添加: $driver"
        done
        
        # 重新运行defconfig
        make defconfig
        log "✅ USB驱动修复完成"
    else
        log "🎉 所有必需USB驱动都已启用"
    fi
}

# 应用配置并分类显示插件
apply_config() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 应用配置并显示详情 ==="
    
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在，无法应用配置"
        return 1
    fi
    
    log "📋 配置详情:"
    log "配置文件大小: $(ls -lh .config | awk '{print $5}')"
    log "配置行数: $(wc -l < .config)"
    
    # 显示详细配置状态
    echo ""
    echo "=== 详细配置状态 ==="
    
    # 1. 关键USB配置状态
    echo "🔧 关键USB配置状态:"
    local critical_usb_drivers=(
        "kmod-usb-core" "kmod-usb2" "kmod-usb3" 
        "kmod-usb-ehci" "kmod-usb-ohci" "kmod-usb-xhci-hcd"
        "kmod-usb-storage" "kmod-usb-storage-uas" "kmod-usb-storage-extras"
        "kmod-scsi-core" "kmod-scsi-generic"
    )
    
    local missing_usb=0
    for driver in "${critical_usb_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "  ✅ $driver"
        else
            echo "  ❌ $driver - 缺失！"
            missing_usb=$((missing_usb + 1))
        fi
    done
    
    # 2. 平台专用驱动检查
    echo ""
    echo "🔧 平台专用USB驱动状态:"
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "  高通IPQ40xx平台专用驱动:"
        local qcom_drivers=("kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3-of-simple")
        for driver in "${qcom_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "    ✅ $driver"
            else
                echo "    ❌ $driver - 缺失！"
                missing_usb=$((missing_usb + 1))
            fi
        done
    elif [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; }; then
        echo "  雷凌MT76xx平台专用驱动:"
        local mtk_drivers=("kmod-usb-ohci-pci" "kmod-usb2-pci" "kmod-usb-xhci-mtk")
        for driver in "${mtk_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "    ✅ $driver"
            else
                echo "    ❌ $driver - 缺失！"
                missing_usb=$((missing_usb + 1))
            fi
        done
    fi
    
    # 3. 文件系统支持检查
    echo ""
    echo "🔧 文件系统支持状态:"
    local fs_drivers=("kmod-fs-ext4" "kmod-fs-vfat" "kmod-fs-exfat" "kmod-fs-ntfs3")
    for driver in "${fs_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "  ✅ $driver"
        else
            echo "  ❌ $driver - 缺失！"
        fi
    done
    
    # 4. 统计信息
    echo ""
    echo "📊 配置统计信息:"
    local enabled_count=$(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)
    local disabled_count=$(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)
    echo "  ✅ 已启用插件: $enabled_count 个"
    echo "  ❌ 已禁用插件: $disabled_count 个"
    
    # 5. 显示具体被禁用的插件（最多20个）
    if [ $disabled_count -gt 0 ]; then
        echo ""
        echo "📋 具体被禁用的插件:"
        local count=0
        grep "^# CONFIG_PACKAGE_.* is not set$" .config | while read line; do
            if [ $count -lt 20 ]; then
                local pkg_name=$(echo $line | sed 's/# CONFIG_PACKAGE_//;s/ is not set//')
                echo "  ❌ $pkg_name"
                count=$((count + 1))
            else
                local remaining=$((disabled_count - 20))
                echo "  ... 还有 $remaining 个被禁用的插件"
                break
            fi
        done
    fi
    
    # 6. 修复缺失的关键USB驱动
    if [ $missing_usb -gt 0 ]; then
        echo ""
        echo "🚨 修复缺失的关键USB驱动:"
        
        # 确保kmod-usb-xhci-hcd启用
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-hcd"
            sed -i 's/^# CONFIG_PACKAGE_kmod-usb-xhci-hcd is not set$/CONFIG_PACKAGE_kmod-usb-xhci-hcd=y/' .config
            if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
                echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
            fi
            echo "  ✅ 已修复 kmod-usb-xhci-hcd"
        fi
        
        # 确保kmod-usb-xhci-pci启用
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-pci=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-pci"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> .config
            echo "  ✅ 已修复 kmod-usb-xhci-pci"
        fi
        
        # 确保kmod-usb-xhci-plat-hcd启用
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-plat-hcd"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> .config
            echo "  ✅ 已修复 kmod-usb-xhci-plat-hcd"
        fi
        
        # 确保kmod-usb-ohci-pci启用
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-ohci-pci=y" .config; then
            echo "  修复: 启用 kmod-usb-ohci-pci"
            echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
            echo "  ✅ 已修复 kmod-usb-ohci-pci"
        fi
        
        # 确保kmod-usb-dwc3-of-simple启用（如果是高通平台）
        if [ "$TARGET" = "ipq40xx" ] && ! grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" .config; then
            echo "  修复: 启用 kmod-usb-dwc3-of-simple"
            echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
            echo "  ✅ 已修复 kmod-usb-dwc3-of-simple"
        fi
        
        # 确保kmod-usb-xhci-mtk启用（如果是雷凌平台）
        if [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; } && ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-mtk"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
            echo "  ✅ 已修复 kmod-usb-xhci-mtk"
        fi
    fi
    
    # 版本特定的配置修复
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本配置预处理"
        sed -i 's/CONFIG_PACKAGE_ntfs-3g=y/# CONFIG_PACKAGE_ntfs-3g is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs-3g-utils=y/# CONFIG_PACKAGE_ntfs-3g-utils is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs3-mount=y/# CONFIG_PACKAGE_ntfs3-mount is not set/g' .config
        log "✅ NTFS配置修复完成"
    fi
    
    log "🔄 运行 make defconfig..."
    make defconfig || handle_error "应用配置失败"
    
    log "🚨 强制启用关键USB驱动（防止defconfig删除）"
    # 确保 USB 3.0 关键驱动被启用
    echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
    
    # 根据平台启用专用驱动
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-xhci-mtk is not set" >> .config
    elif [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; }; then
        echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-dwc3-qcom is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-phy-qcom-dwc3 is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-dwc3-of-simple is not set" >> .config
    fi
    
    # 其他关键USB驱动
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
    
    # 运行defconfig后，再次检查并修复USB驱动
    check_usb_drivers_integrity
    
    # 最终检查
    echo ""
    echo "=== 最终配置检查 ==="
    local final_enabled=$(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)
    local final_disabled=$(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)
    echo "✅ 最终状态: 已启用 $final_enabled 个, 已禁用 $final_disabled 个"
    
    log "✅ 配置应用完成"
    log "最终配置文件: .config"
    log "最终配置大小: $(ls -lh .config | awk '{print $5}')"
}

# 修复网络环境
fix_network() {
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 修复网络环境 ==="
    
    # 设置git配置
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    git config --global core.compression 0
    git config --global core.looseCompression 0
    
    # 设置环境变量
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    export CURL_SSL_NO_VERIFY=1
    
    # 设置apt代理（如果有）
    if [ -n "$http_proxy" ]; then
        echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee /etc/apt/apt.conf.d/proxy.conf > /dev/null
    fi
    
    # 测试网络连接
    log "测试网络连接..."
    if curl -s --connect-timeout 10 https://github.com > /dev/null; then
        log "✅ 网络连接正常"
    else
        log "⚠️  网络连接可能有问题"
    fi
    
    log "✅ 网络环境修复完成"
}

# 下载依赖包
download_dependencies() {
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 下载依赖包 ==="
    
    # 检查依赖包目录
    if [ ! -d "dl" ]; then
        mkdir -p dl
        log "创建依赖包目录: dl"
    fi
    
    # 显示现有依赖包
    local existing_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log "现有依赖包数量: $existing_deps 个"
    
    # 下载依赖包
    log "开始下载依赖包..."
    make -j1 download V=s 2>&1 | tee download.log || handle_error "下载依赖包失败"
    
    # 检查下载结果
    local downloaded_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log "下载后依赖包数量: $downloaded_deps 个"
    
    if [ $downloaded_deps -gt $existing_deps ]; then
        log "✅ 成功下载了 $((downloaded_deps - existing_deps)) 个新依赖包"
    else
        log "ℹ️  没有下载新的依赖包"
    fi
    
    # 检查下载日志中的错误
    if grep -q "ERROR\|Failed\|404" download.log 2>/dev/null; then
        log "⚠️  下载过程中发现错误:"
        grep -E "ERROR|Failed|404" download.log | head -10
    fi
    
    log "✅ 依赖包下载完成"
}

# 构建固件
build_firmware() {
    local enable_cache=$1
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 编译固件 ==="
    
    # 设置工具链环境
    setup_toolchain_env
    
    # 编译前最终检查
    log "编译前最终检查..."
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        exit 1
    fi
    
    if [ ! -d "staging_dir" ]; then
        log "⚠️  警告: staging_dir 目录不存在"
    fi
    
    if [ ! -d "dl" ]; then
        log "⚠️  警告: dl 目录不存在"
    fi
    
    # 获取CPU核心数
    local cpu_cores=$(nproc)
    local make_jobs=$cpu_cores
    
    # 如果内存小于4GB，减少并行任务
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_mem -lt 4096 ]; then
        make_jobs=$((cpu_cores / 2))
        if [ $make_jobs -lt 1 ]; then
            make_jobs=1
        fi
        log "⚠️  内存较低(${total_mem}MB)，减少并行任务到 $make_jobs"
    fi
    
    # 开始编译
    if [ "$enable_cache" = "true" ]; then
        log "启用编译缓存，使用 $make_jobs 个并行任务"
        make -j$make_jobs V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    else
        log "普通编译模式，使用 $make_jobs 个并行任务"
        make -j$make_jobs V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    fi
    
    log "编译退出代码: $BUILD_EXIT_CODE"
    
    # 编译结果分析
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        log "✅ 固件编译成功"
        
        # 检查生成的固件
        if [ -d "bin/targets" ]; then
            local firmware_count=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
            log "✅ 生成固件文件: $firmware_count 个"
            
            # 显示固件文件
            find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | head -5 | while read file; do
                log "固件: $file ($(du -h "$file" | cut -f1))"
            done
        else
            log "❌ 固件目录不存在"
        fi
    else
        log "❌ 编译失败，退出代码: $BUILD_EXIT_CODE"
        
        # 分析失败原因
        if [ -f "build.log" ]; then
            log "=== 编译错误摘要 ==="
            
            # 查找常见错误
            local error_count=$(grep -c "Error [0-9]|error:" build.log)
            local warning_count=$(grep -c "Warning\|warning:" build.log)
            
            log "发现 $error_count 个错误，$warning_count 个警告"
            
            # 显示前10个错误
            if [ $error_count -gt 0 ]; then
                log "前10个错误:"
                grep -i "Error\|error:" build.log | head -10
            fi
            
            # 检查常见错误类型
            if grep -q "undefined reference" build.log; then
                log "⚠️  发现未定义引用错误"
            fi
            
            if grep -q "No such file" build.log; then
                log "⚠️  发现文件不存在错误"
            fi
            
            if grep -q "out of memory\|Killed process" build.log; then
                log "⚠️  可能是内存不足导致编译失败"
            fi
            
            # 特别检查编译器错误
            if grep -q "compiler.*not found" build.log; then
                log "🚨 发现编译器未找到错误"
                log "检查工具链路径..."
                if [ -d "staging_dir" ]; then
                    find staging_dir -name "*gcc*" 2>/dev/null | head -10
                fi
            fi
        fi
        
        exit $BUILD_EXIT_CODE
    fi
    
    log "✅ 固件编译完成"
}

# 编译后空间检查
post_build_space_check() {
    log "=== 编译后空间检查 ==="
    
    echo "=== 磁盘使用情况 ==="
    df -h
    
    # 构建目录空间
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    # 固件文件大小
    if [ -d "$BUILD_DIR/openwrt/bin/targets" ]; then
        local firmware_size=$(find "$BUILD_DIR/openwrt/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
        echo "固件文件总大小: $firmware_size"
    fi
    
    # 检查可用空间
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    log "/mnt 可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 5 ]; then
        log "⚠️  警告: 磁盘空间较低，建议清理"
    else
        log "✅ 磁盘空间充足"
    fi
    
    log "✅ 空间检查完成"
}

# 检查固件文件
check_firmware_files() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log "=== 固件文件检查 ==="
    
    if [ -d "bin/targets" ]; then
        log "✅ 固件目录存在"
        
        # 统计固件文件
        local firmware_files=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
        local all_files=$(find bin/targets -type f 2>/dev/null | wc -l)
        
        log "固件文件: $firmware_files 个"
        log "所有文件: $all_files 个"
        
        # 显示固件文件详情
        echo "=== 生成的固件文件 ==="
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec ls -lh {} \;
        
        # 检查文件大小
        local total_size=0
        while read size; do
            total_size=$((total_size + size))
        done < <(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec stat -c%s {} \; 2>/dev/null)
        
        if [ $total_size -gt 0 ]; then
            local total_size_mb=$((total_size / 1024 / 1024))
            log "固件总大小: ${total_size_mb}MB"
            
            # 检查固件大小是否合理
            if [ $total_size_mb -lt 5 ]; then
                log "⚠️  警告: 固件文件可能太小"
            elif [ $total_size_mb -gt 100 ]; then
                log "⚠️  警告: 固件文件可能太大"
            else
                log "✅ 固件大小正常"
            fi
        fi
        
        # 检查目标目录结构
        echo "=== 目标目录结构 ==="
        find bin/targets -maxdepth 3 -type d | sort
        
    else
        log "❌ 固件目录不存在"
        exit 1
    fi
}

# 清理目录
cleanup() {
    log "=== 清理构建目录 ==="
    
    if [ -d "$BUILD_DIR" ]; then
        log "检查是否有需要保留的文件..."
        
        # 如果.config文件存在，先备份
        if [ -f "$BUILD_DIR/openwrt/.config" ]; then
            log "备份配置文件..."
            mkdir -p /tmp/openwrt_backup
            local backup_file="/tmp/openwrt_backup/config_$(date +%Y%m%d_%H%M%S).config"
            cp "$BUILD_DIR/openwrt/.config" "$backup_file"
            log "✅ 配置文件备份到: $backup_file"
        fi
        
        # 如果build.log存在，备份
        if [ -f "$BUILD_DIR/openwrt/build.log" ]; then
            log "备份编译日志..."
            mkdir -p /tmp/openwrt_backup
            cp "$BUILD_DIR/openwrt/build.log" "/tmp/openwrt_backup/build_$(date +%Y%m%d_%H%M%S).log"
        fi
        
        # 清理构建目录
        log "清理构建目录: $BUILD_DIR"
        sudo rm -rf $BUILD_DIR || log "⚠️ 清理构建目录失败"
        log "✅ 构建目录已清理"
    else
        log "ℹ️  构建目录不存在，无需清理"
    fi
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

# 步骤4：安装Git LFS和配置
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
    log "📁 步骤9：检查构建目录"
    log "========================================"
    log ""
    
    create_build_dir
    
    log ""
    log "🎉 步骤9完成：构建目录检查完成"
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
    log "  配置模式: $CONFIG_MODE"
    
    # 设置GitHub环境变量
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
    echo "TARGET=$TARGET" >> $GITHUB_ENV
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
    echo "DEVICE=$DEVICE" >> $GITHUB_ENV
    echo "CONFIG_MODE=$CONFIG_MODE" >> $GITHUB_ENV
    
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
    log "  额外插件: $EXTRA_PACKAGES"
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
    if [ -f "$BUILD_DIR/openwrt/.config" ]; then
        log "✅ .config 文件存在"
        
        # 确保备份目录存在
        mkdir -p firmware-config/config-backup
        
        # 备份到仓库目录
        backup_file="firmware-config/config-backup/config_${DEVICE}_${SELECTED_BRANCH}_${CONFIG_MODE}_$(date +%Y%m%d_%H%M%S).config"
        
        cp "$BUILD_DIR/openwrt/.config" "$backup_file"
        log "✅ 配置文件备份到仓库目录: $backup_file"
        
        # 显示备份文件信息
        log "📊 备份文件信息:"
        log "  大小: $(ls -lh $backup_file | awk '{print $5}')"
        log "  行数: $(wc -l < $backup_file)"
        
        # 显示备份文件关键配置
        log "🔑 备份文件关键配置:"
        grep -E "^(CONFIG_TARGET|CONFIG_PACKAGE_kmod-usb)" "$backup_file" | head -10
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

# ========== 修复：检查工具链加载状态函数 ==========
workflow_step23_check_toolchain_status() {
    log "========================================"
    log "📊 步骤23：检查工具链加载状态"
    log "========================================"
    log ""
    
    cd $BUILD_DIR/openwrt
    
    log "🔍 详细检查构建目录工具链状态..."
    
    # 检查staging_dir是否存在
    if [ ! -d "staging_dir" ]; then
        log "❌ staging_dir 目录不存在，创建它..."
        mkdir -p staging_dir
    fi
    
    log "✅ staging_dir 目录存在"
    
    # 详细查找所有工具链相关目录
    log "📁 staging_dir 目录内容:"
    find staging_dir -maxdepth 2 -type d 2>/dev/null | sort | while read dir; do
        local dir_name=$(basename "$dir")
        if [[ "$dir_name" == toolchain* ]] || [[ "$dir" == *toolchain* ]]; then
            log "  🔍 工具链相关目录: $dir"
            log "    大小: $(du -sh "$dir" 2>/dev/null | cut -f1 || echo '未知')"
            
            # 检查编译器
            if [ -d "$dir/bin" ]; then
                local compiler_count=$(find "$dir/bin" -name "*gcc*" 2>/dev/null | wc -l)
                log "    编译器文件: $compiler_count 个"
                if [ $compiler_count -gt 0 ]; then
                    find "$dir/bin" -name "*gcc*" 2>/dev/null | head -3 | while read compiler; do
                        if [ -f "$compiler" ]; then
                            log "      - $(basename $compiler) ($(stat -c%s "$compiler" 2>/dev/null | numfmt --to=iec || echo '未知大小'))"
                        fi
                    done
                fi
            fi
        fi
    done
    
    # 查找所有工具链目录
    local toolchain_dirs=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null)
    local toolchain_count=$(echo "$toolchain_dirs" | wc -l)
    
    log "📊 找到 $toolchain_count 个工具链目录"
    
    if [ $toolchain_count -gt 0 ]; then
        log "🎉 工具链已成功加载到构建目录"
        echo "$toolchain_dirs" | while read dir; do
            log "  🔧 工具链: $(basename $dir)"
            log "    路径: $dir"
            log "    大小: $(du -sh "$dir" 2>/dev/null | cut -f1 || echo '未知')"
            
            # 详细检查编译器
            if [ -d "$dir/bin" ]; then
                log "    📁 bin目录内容:"
                ls -la "$dir/bin" 2>/dev/null | head -5 || log "      无法列出目录内容"
                
                # 测试编译器
                local compilers=$(find "$dir/bin" -name "*gcc*" -type f 2>/dev/null | head -2)
                for compiler in $compilers; do
                    if [ -x "$compiler" ]; then
                        log "    ✅ 编译器可执行: $(basename $compiler)"
                    else
                        log "    ⚠️  编译器不可执行，尝试添加权限: $(basename $compiler)"
                        chmod +x "$compiler" 2>/dev/null && log "      ✅ 权限添加成功" || log "      ❌ 权限添加失败"
                    fi
                done
            fi
        done
    else
        log "⚠️  构建目录中没有找到标准格式的工具链目录"
        
        # 检查是否有其他形式的工具链
        log "🔍 检查其他可能的工具链形式..."
        local other_dirs=$(find staging_dir -maxdepth 2 -type d -name "bin" 2>/dev/null | xargs -I {} dirname {})
        if [ -n "$other_dirs" ]; then
            log "找到可能的工具链位置:"
            echo "$other_dirs" | while read dir; do
                if [ -d "$dir/bin" ]; then
                    local gcc_count=$(find "$dir/bin" -name "*gcc*" 2>/dev/null | wc -l)
                    if [ $gcc_count -gt 0 ]; then
                        log "  📍 可能工具链: $dir"
                        log "    包含 $gcc_count 个编译器文件"
                        log "    大小: $(du -sh "$dir" 2>/dev/null | cut -f1 || echo '未知')"
                    fi
                fi
            done
        else
            log "❌ 构建目录中没有工具链，将自动下载"
        fi
    fi
    
    log ""
    log "🔧 验证工具链完整性..."
    check_toolchain_completeness || {
        log "⚠️  工具链完整性检查失败"
        log "💡 建议: 删除staging_dir目录重新下载工具链"
        log "命令: rm -rf staging_dir && make toolchain/install"
    }
    
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

# ========== 修复：工作流步骤26函数 ==========
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
