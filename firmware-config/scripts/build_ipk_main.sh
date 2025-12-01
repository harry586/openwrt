#!/bin/bash
# 注意：移除了 set -e，使用更健壮的错误处理

# 全局变量
BUILD_DIR="/mnt/openwrt-build-ipk"
ENV_FILE="$BUILD_DIR/build_env.sh"
LOG_FILE="$BUILD_DIR/build_ipk.log"
SOURCE_PKG_DIR="$BUILD_DIR/source_packages"
PACKAGES_BASE_DIR="firmware-config/packages"

# 颜色输出函数
color_green() {
    echo -e "\033[32m$1\033[0m"
}

color_red() {
    echo -e "\033[31m$1\033[0m"
}

color_yellow() {
    echo -e "\033[33m$1\033[0m"
}

color_blue() {
    echo -e "\033[34m$1\033[0m"
}

# 日志函数
log() {
    local message="【$(date '+%Y-%m-%d %H:%M:%S')】$1"
    echo "$message"
    if [ -f "$LOG_FILE" ]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

# 错误处理函数（不退出）
log_error() {
    log "❌ 错误: $1"
    return 1
}

# 警告处理函数
log_warning() {
    log "⚠️ 警告: $1"
    return 0
}

# 保存环境变量到文件
save_env() {
    mkdir -p "$BUILD_DIR" || return 1
    cat > "$ENV_FILE" << EOF
#!/bin/bash
export SELECTED_REPO_URL="$SELECTED_REPO_URL"
export SELECTED_BRANCH="$SELECTED_BRANCH"
export PACKAGE_NAMES="$PACKAGE_NAMES"
export EXTRA_DEPS="$EXTRA_DEPS"
export SOURCE_PACKAGES="$SOURCE_PACKAGES"
EOF
    if [ $? -ne 0 ]; then
        log_warning "写入环境变量文件失败"
        return 1
    fi
    chmod +x "$ENV_FILE" 2>/dev/null || log_warning "设置环境变量文件执行权限失败"
    return 0
}

# 加载环境变量
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE" 2>/dev/null || log_warning "加载环境变量失败"
    fi
}

# 字符串分割函数
split_string() {
    local input="$1"
    local delimiter="$2"
    
    if [ -z "$input" ]; then
        return
    fi
    
    # 使用 sed 和 tr 进行分割
    echo "$input" | tr "$delimiter" '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
}

# 检查包是否存在
check_package_exists() {
    local package="$1"
    local found=0
    
    # 检查可能的包路径
    local possible_paths=(
        "package/$package"
        "feeds/luci/$package" 
        "feeds/packages/$package"
        "feeds/routing/$package"
        "feeds/telephony/$package"
    )
    
    for path in "${possible_paths[@]}"; do
        if [ -d "$path" ]; then
            log "✅ 找到包: $path"
            found=1
            break
        fi
    done
    
    # 如果没找到，搜索所有feeds
    if [ $found -eq 0 ]; then
        local search_result=$(find feeds -name "$package" -type d 2>/dev/null | head -1)
        if [ -n "$search_result" ]; then
            log "✅ 找到包: $search_result"
            found=1
        fi
    fi
    
    return $found
}

# 从GitHub仓库下载自定义包
download_custom_package() {
    local package_name="$1"
    local repo_url="$2"
    
    log "=== 下载自定义包 ==="
    log "包名: $package_name"
    log "仓库: $repo_url"
    
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    # 提取仓库名
    local repo_name=$(basename "$repo_url" .git)
    local target_dir="package/$package_name"
    
    # 清理旧目录
    rm -rf "$target_dir" 2>/dev/null
    
    # 克隆仓库
    git clone --depth 1 "$repo_url" "$target_dir" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_warning "克隆自定义包失败"
        return 1
    fi
    
    # 检查是否有Makefile
    if [ ! -f "$target_dir/Makefile" ]; then
        log_warning "自定义包没有Makefile，尝试查找..."
        find "$target_dir" -name "Makefile" 2>/dev/null | head -1 | while read makefile; do
            local subdir=$(dirname "$makefile")
            if [ "$subdir" != "$target_dir" ]; then
                log "📁 移动包文件从 $subdir 到 $target_dir"
                mv "$subdir"/* "$target_dir"/ 2>/dev/null || true
            fi
        done
    fi
    
    if [ -f "$target_dir/Makefile" ]; then
        color_green "✅ 自定义包下载完成: $package_name"
        return 0
    else
        log_warning "自定义包没有有效的Makefile"
        return 1
    fi
}

# 步骤1: 设置编译环境
setup_environment() {
    # 在设置环境前先创建构建目录
    sudo mkdir -p "$BUILD_DIR" 2>/dev/null || { log_error "创建构建目录失败"; return 1; }
    sudo chown -R $USER:$USER "$BUILD_DIR" 2>/dev/null || { log_warning "修改目录所有者失败"; }
    sudo chmod -R 755 "$BUILD_DIR" 2>/dev/null || { log_warning "修改目录权限失败"; }
    
    # 创建日志文件
    touch "$LOG_FILE" 2>/dev/null
    sudo chown $USER:$USER "$LOG_FILE" 2>/dev/null || true
    
    log "=== 安装编译依赖包 ==="
    sudo apt-get update 2>/dev/null || { log_warning "apt-get update失败"; }
    
    # 修复：添加更多基础编译工具
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
        gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip \
        zlib1g-dev file wget libelf-dev ecj fastjar java-propose-classpath \
        libpython3-dev python3 python3-dev python3-pip python3-setuptools \
        python3-yaml xsltproc zip subversion ninja-build automake autoconf \
        libtool pkg-config help2man texinfo aria2 liblz4-dev zstd \
        libcurl4-openssl-dev groff texlive texinfo cmake \
        gperf libxml2-utils libtool-bin libglib2.0-dev libgmp3-dev \
        libmpc-dev libmpfr-dev qemu-utils upx-ucl libltdl-dev \
        ccache python3-pip python3-venv libsqlite3-dev libffi-dev \
        libreadline-dev libbz2-dev liblzma-dev tk-dev 2>/dev/null || { log_warning "安装依赖包失败"; }
        
    log "✅ 编译环境设置完成"
}

# 步骤2: 创建构建目录
create_build_dir() {
    log "=== 创建构建目录 ==="
    sudo chown -R $USER:$USER "$BUILD_DIR" 2>/dev/null || { log_warning "修改目录所有者失败"; }
    sudo chmod -R 755 "$BUILD_DIR" 2>/dev/null || { log_warning "修改目录权限失败"; }
    log "✅ 构建目录准备完成"
}

# 步骤3: 初始化构建环境
initialize_build_env() {
    local version_selection="$1"
    
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    # 版本选择 - 修复：使用 ImmortalWrt，包含更多包
    log "=== 版本选择 ==="
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-23.05"
    else
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-21.02"
    fi
    log "✅ 版本选择完成: $SELECTED_BRANCH"
    
    # 保存环境变量
    save_env || log_warning "保存环境变量失败"
    
    # 设置GitHub环境变量
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> "$GITHUB_ENV" 2>/dev/null || true
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> "$GITHUB_ENV" 2>/dev/null || true
    
    # 克隆源码 - 修复：增加重试和深度
    log "=== 克隆源码 ==="
    log "仓库: $SELECTED_REPO_URL"
    log "分支: $SELECTED_BRANCH"
    
    # 清理目录
    sudo rm -rf ./* ./.git* 2>/dev/null || true
    
    # 克隆源码，增加重试机制
    for i in {1..3}; do
        log "尝试第 $i 次克隆..."
        if git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" . 2>/dev/null; then
            log "✅ 源码克隆完成"
            break
        elif [ $i -eq 3 ]; then
            log_error "克隆源码失败，已尝试3次"
            return 1
        else
            sleep 10
        fi
    done
    
    log "✅ 源码克隆完成"
}

# 步骤4: 配置Feeds
configure_feeds() {
    load_env
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    log "=== 配置Feeds ==="
    
    # 更新和安装所有 feeds
    log "=== 更新Feeds ==="
    for i in {1..3}; do
        if ./scripts/feeds update -a 2>/dev/null; then
            log "✅ Feeds 更新成功"
            break
        elif [ $i -eq 3 ]; then
            log_warning "Feeds 更新有错误，但继续执行"
            break
        else
            log "第 $i 次Feeds更新失败，重试..."
            sleep 10
        fi
    done
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a 2>/dev/null || log_warning "安装feeds有错误，但继续执行"
    
    log "✅ Feeds配置完成"
}

# 步骤5: 下载自定义包
download_custom_packages() {
    local package_names="$1"
    
    if [ -z "$package_names" ]; then
        log "=== 没有自定义包需要下载 ==="
        return 0
    fi
    
    log "=== 下载自定义包 ==="
    
    # 定义已知的自定义包仓库
    declare -A custom_repos=(
        ["luci-app-filetransfer"]="https://github.com/f8q8/luci-app-filetransfer.git"
        ["luci-app-koolproxy"]="https://github.com/immortalwrt/luci-app-koolproxy.git"
        ["luci-app-unblockneteasemusic"]="https://github.com/immortalwrt/luci-app-unblockneteasemusic.git"
    )
    
    while IFS= read -r package; do
        local pkg_clean=$(echo "$package" | xargs)
        if [ -z "$pkg_clean" ]; then
            continue
        fi
        
        # 检查是否是自定义包
        if [ -n "${custom_repos[$pkg_clean]}" ]; then
            local repo_url="${custom_repos[$pkg_clean]}"
            log "🔗 发现自定义包: $pkg_clean -> $repo_url"
            
            if download_custom_package "$pkg_clean" "$repo_url"; then
                color_green "✅ 自定义包下载成功: $pkg_clean"
            else
                log_warning "自定义包下载失败，继续尝试从feeds编译"
            fi
        else
            # 检查包是否存在，如果不存在，提示用户
            if ! check_package_exists "$pkg_clean"; then
                color_yellow "🔍 包 $pkg_clean 不存在，您可能需要提供自定义仓库或源码包"
            fi
        fi
    done <<< "$(split_string "$package_names" "、")"
    
    log "✅ 自定义包下载完成"
}

# 步骤6: 处理源码压缩包
process_source_packages() {
    local source_packages_list="$1"
    local build_all_packages="$2"
    
    # 修复：处理空字符串的情况
    if [ -z "$source_packages_list" ] || [ "$source_packages_list" = '""' ] || [ "$source_packages_list" = "''" ]; then
        source_packages_list=""
    fi
    
    log "=== 处理源码压缩包 ==="
    log "指定压缩包: $source_packages_list"
    log "编译所有包: $build_all_packages"
    
    # 准备源码包目录
    mkdir -p "$SOURCE_PKG_DIR" 2>/dev/null
    mkdir -p "$SOURCE_PKG_DIR/luci" 2>/dev/null
    mkdir -p "$SOURCE_PKG_DIR/temp" 2>/dev/null
    
    # 检查packages目录是否存在
    if [ ! -d "$PACKAGES_BASE_DIR" ]; then
        log_warning "源码包目录不存在: $PACKAGES_BASE_DIR"
        SOURCE_PACKAGES=""
        save_env 2>/dev/null || true
        return 0
    fi
    
    # 获取所有支持的压缩包
    local all_compressed_files=$(find "$PACKAGES_BASE_DIR" -name "*.zip" -o -name "*.tar.gz" -o -name "*.tgz" -o -name "*.tar.bz2" 2>/dev/null)
    
    if [ -z "$all_compressed_files" ]; then
        log_warning "目录中没有找到任何支持的压缩包文件"
        SOURCE_PACKAGES=""
        save_env 2>/dev/null || true
        return 0
    fi
    
    # 显示所有可用压缩包
    log "📦 可用源码压缩包:"
    echo "$all_compressed_files" | while read file; do
        color_blue "  📦 $(basename "$file")"
    done
    
    # 决定要处理的文件列表
    local files_to_process=""
    
    if [ "$build_all_packages" = "true" ]; then
        log "🔧 选择编译所有压缩包"
        # 使用所有压缩包
        files_to_process=$(echo "$all_compressed_files" | xargs -I {} basename {} 2>/dev/null)
    elif [ -n "$source_packages_list" ]; then
        log "🔧 选择编译指定压缩包"
        # 使用指定的压缩包
        files_to_process="$source_packages_list"
    else
        log "🔧 没有选择任何压缩包"
        SOURCE_PACKAGES=""
        save_env 2>/dev/null || true
        return 0
    fi
    
    # 将文件列表转换为换行分隔
    local file_array=()
    while IFS= read -r file; do
        file_array+=("$file")
    done <<< "$(echo "$files_to_process" | tr '、' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')"
    
    # 如果选择了编译所有包，但用户也指定了文件，则优先使用指定的
    if [ "$build_all_packages" = "false" ] && [ ${#file_array[@]} -eq 0 ]; then
        log "🔧 没有指定要编译的压缩包"
        SOURCE_PACKAGES=""
        save_env 2>/dev/null || true
        return 0
    fi
    
    # 处理每个指定的源码压缩包
    local processed_count=0
    local error_count=0
    local processed_files=""
    
    log "开始处理 ${#file_array[@]} 个源码压缩包"
    
    for source_file in "${file_array[@]}"; do
        local source_file_clean=$(echo "$source_file" | xargs)
        if [ -z "$source_file_clean" ]; then
            continue
        fi
        
        # 检查文件是否存在
        local source_path="$PACKAGES_BASE_DIR/$source_file_clean"
        
        if [ ! -f "$source_path" ]; then
            color_red "❌ 源码压缩包不存在: $source_file_clean"
            ((error_count++)) || true
            continue
        fi
        
        log "处理源码包 [$((processed_count + error_count + 1))/${#file_array[@]}]: $source_file_clean"
        
        # 从文件名提取包名（去掉扩展名）
        local package_name=$(basename "$source_file_clean" | sed 's/\.\(zip\|tar\.gz\|tgz\|tar\.bz2\)$//')
        
        # 创建目标目录
        local target_dir="$SOURCE_PKG_DIR/luci/$package_name"
        rm -rf "$target_dir" 2>/dev/null
        mkdir -p "$target_dir" 2>/dev/null
        
        # 解压文件
        log "解压源码文件..."
        local extract_success=0
        if [[ "$source_file_clean" == *.zip ]]; then
            if unzip -q "$source_path" -d "$target_dir" 2>/dev/null; then
                extract_success=1
            else
                color_red "❌ 解压ZIP文件失败: $source_file_clean"
            fi
        elif [[ "$source_file_clean" == *.tar.gz ]] || [[ "$source_file_clean" == *.tgz ]]; then
            if tar -xzf "$source_path" -C "$target_dir" 2>/dev/null; then
                extract_success=1
            else
                color_red "❌ 解压TAR.GZ文件失败: $source_file_clean"
            fi
        elif [[ "$source_file_clean" == *.tar.bz2 ]]; then
            if tar -xjf "$source_path" -C "$target_dir" 2>/dev/null; then
                extract_success=1
            else
                color_red "❌ 解压TAR.BZ2文件失败: $source_file_clean"
            fi
        else
            color_red "❌ 不支持的压缩格式: $source_file_clean"
        fi
        
        if [ $extract_success -eq 0 ]; then
            ((error_count++)) || true
            continue
        fi
        
        # 修复包目录结构
        if ! fix_package_structure "$target_dir" "$package_name"; then
            color_red "❌ 修复包结构失败: $package_name"
            ((error_count++)) || true
            continue
        fi
        
        # 集成到构建系统
        if ! integrate_source_package "$target_dir" "$package_name"; then
            color_red "❌ 集成到构建系统失败: $package_name"
            ((error_count++)) || true
            continue
        fi
        
        color_green "✅ 源码包处理完成: $package_name"
        ((processed_count++)) || true
        
        # 添加到已处理文件列表
        if [ -n "$processed_files" ]; then
            processed_files="$processed_files、$source_file_clean"
        else
            processed_files="$source_file_clean"
        fi
        
    done
    
    # 保存处理后的文件列表到环境变量
    SOURCE_PACKAGES="$processed_files"
    save_env 2>/dev/null || log_warning "保存环境变量失败"
    
    log "=== 处理结果 ==="
    if [ $processed_count -gt 0 ]; then
        color_green "✅ 源码压缩包处理完成: 成功 $processed_count/${#file_array[@]} 个包"
        log "✅ 处理的压缩包: $SOURCE_PACKAGES"
    else
        if [ $error_count -gt 0 ]; then
            color_red "❌ 所有源码压缩包处理失败"
        else
            log "ℹ️ 没有处理任何源码压缩包"
        fi
    fi
}

# 修复包目录结构
fix_package_structure() {
    local target_dir="$1"
    local package_name="$2"
    
    log "修复包目录结构: $package_name"
    
    # 检查是否解压到了子目录
    local subdirs=($(find "$target_dir" -maxdepth 1 -type d 2>/dev/null | grep -v "^$target_dir$"))
    
    if [ ${#subdirs[@]} -eq 1 ] && [ -d "${subdirs[0]}" ]; then
        log "检测到子目录结构，移动文件..."
        local subdir="${subdirs[0]}"
        mv "$subdir"/* "$target_dir"/ 2>/dev/null || true
        rm -rf "$subdir" 2>/dev/null
    fi
    
    # 检查特殊的目录结构（如luci_opkg）
    if [ -d "$target_dir/luci_opkg" ]; then
        log "调整luci_opkg目录结构..."
        mv "$target_dir/luci_opkg"/* "$target_dir"/ 2>/dev/null || true
        rm -rf "$target_dir/luci_opkg" 2>/dev/null
    fi
    
    # 验证最终结构
    if ! validate_package_structure "$target_dir" "$package_name"; then
        return 1
    fi
    
    return 0
}

# 验证包结构
validate_package_structure() {
    local target_dir="$1"
    local package_name="$2"
    
    log "验证包结构: $package_name"
    
    # 检查必要文件
    if [ ! -f "$target_dir/Makefile" ]; then
        color_red "❌ 缺少关键文件: Makefile"
        
        # 尝试查找可能的Makefile
        local found_makefile=$(find "$target_dir" -name "Makefile" -type f 2>/dev/null | head -1)
        if [ -n "$found_makefile" ]; then
            color_yellow "💡 在其他位置找到Makefile: $found_makefile"
            local makefile_dir=$(dirname "$found_makefile")
            if [ "$makefile_dir" != "$target_dir" ]; then
                log "移动Makefile和相关文件..."
                mv "$makefile_dir"/* "$target_dir"/ 2>/dev/null || true
                rm -rf "$makefile_dir" 2>/dev/null
            fi
        else
            color_red "❌ 无法找到Makefile，包结构无效"
            return 1
        fi
    fi
    
    if [ ! -f "$target_dir/Makefile" ]; then
        color_red "❌ 最终检查：仍然缺少Makefile"
        return 1
    fi
    
    color_green "✅ 找到关键文件: Makefile"
    
    # 检查目录内容
    local file_count=$(find "$target_dir" -type f 2>/dev/null | wc -l)
    log "包包含 $file_count 个文件"
    
    # 显示关键文件
    find "$target_dir" -type f \( -name "*.mk" -o -name "*.lua" -o -name "*.htm" -o -name "*.js" -o -name "*.css" \) 2>/dev/null | head -10 | while read file; do
        color_blue "  📄 $(basename "$file")"
    done
    
    # 显示Makefile信息
    if [ -f "$target_dir/Makefile" ]; then
        log "Makefile信息:"
        grep -E "^(PKG_NAME|PKG_VERSION|PKG_RELEASE|PKG_LICENSE|Package|Build)" "$target_dir/Makefile" 2>/dev/null | head -5 | while read line; do
            color_yellow "  📝 $line"
        done
    fi
    
    return 0
}

# 集成源码包到构建系统
integrate_source_package() {
    local source_dir="$1"
    local package_name="$2"
    
    log "集成源码包到构建系统: $package_name"
    
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    # 复制包到package目录
    local build_pkg_dir="package/$package_name"
    rm -rf "$build_pkg_dir" 2>/dev/null
    mkdir -p "$build_pkg_dir" 2>/dev/null
    
    log "复制包文件到构建系统..."
    if ! cp -r "$source_dir"/* "$build_pkg_dir"/ 2>/dev/null; then
        color_red "❌ 复制包文件失败"
        return 1
    fi
    
    # 验证是否成功复制
    if [ ! -f "$build_pkg_dir/Makefile" ]; then
        color_red "❌ 复制后缺少Makefile"
        return 1
    fi
    
    color_green "✅ 源码包集成完成: $package_name"
    return 0
}

# 步骤7: 编译前空间检查
pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    df -h 2>/dev/null || true
    AVAILABLE_SPACE=$(df /mnt --output=avail 2>/dev/null | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024 2>/dev/null)) || AVAILABLE_GB=0
    log "/mnt 可用空间: ${AVAILABLE_GB}G"
    if [ $AVAILABLE_GB -lt 10 ]; then
        log "⚠️ 警告: 可用空间不足10G，编译可能失败"
    fi
}

# 步骤8: 生成IPK配置
generate_config() {
    local package_names="$1"
    local extra_deps="$2"
    load_env
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    log "=== 生成IPK配置 ==="
    log "输入框包名: $package_names"
    log "源码压缩包: $SOURCE_PACKAGES"
    log "版本: $SELECTED_BRANCH"
    log "额外依赖: $extra_deps"
    
    PACKAGE_NAMES="$package_names"
    EXTRA_DEPS="$extra_deps"
    save_env 2>/dev/null || log_warning "保存环境变量失败"
    
    rm -f .config .config.old 2>/dev/null
    
    # 创建基础配置 - 修复：使用更通用的配置
    cat > .config << 'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
CONFIG_TOOLCHAIN=y
CONFIG_TOOLCHAIN_BUILD=y
CONFIG_PACKAGE_busybox=y
CONFIG_PACKAGE_base-files=y
CONFIG_PACKAGE_dropbear=y
CONFIG_PACKAGE_firewall=y
CONFIG_PACKAGE_fstools=y
CONFIG_PACKAGE_libc=y
CONFIG_PACKAGE_libgcc=y
CONFIG_PACKAGE_mtd=y
CONFIG_PACKAGE_netifd=y
CONFIG_PACKAGE_opkg=y
CONFIG_PACKAGE_procd=y
CONFIG_PACKAGE_ubox=y
CONFIG_PACKAGE_ubus=y
CONFIG_PACKAGE_ubusd=y
CONFIG_PACKAGE_uci=y
CONFIG_PACKAGE_uclient-fetch=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-lib-base=y
CONFIG_PACKAGE_luci-lib-ip=y
CONFIG_PACKAGE_luci-lib-jsonc=y
CONFIG_PACKAGE_luci-lib-nixio=y
CONFIG_PACKAGE_luci-mod-admin-full=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
EOF
    
    if [ $? -ne 0 ]; then
        log_error "创建基础配置失败"
        return 1
    fi

    # 合并所有要编译的包
    local all_packages=""
    
    # 添加输入框包名
    if [ -n "$package_names" ]; then
        all_packages="$package_names"
    fi
    
    # 添加源码压缩包包名
    if [ -n "$SOURCE_PACKAGES" ]; then
        while IFS= read -r source_file; do
            local source_file_clean=$(echo "$source_file" | xargs)
            if [ -n "$source_file_clean" ]; then
                local package_name=$(basename "$source_file_clean" | sed 's/\.\(zip\|tar\.gz\|tgz\|tar\.bz2\)$//')
                if [ -n "$all_packages" ]; then
                    all_packages="$all_packages、$package_name"
                else
                    all_packages="$package_name"
                fi
            fi
        done <<< "$(split_string "$SOURCE_PACKAGES" "、")"
    fi
    
    if [ -z "$all_packages" ]; then
        log_error "没有指定要编译的包（输入框和源码压缩包都为空）"
        return 1
    fi
    
    # 添加要编译的包 - 支持多个包
    log "=== 添加目标包 ==="
    
    # 使用更安全的方法分割字符串
    while IFS= read -r package; do
        local pkg_clean=$(echo "$package" | xargs)
        if [ -n "$pkg_clean" ]; then
            echo "CONFIG_PACKAGE_${pkg_clean}=y" >> .config
            color_green "  ✅ 添加包: $pkg_clean"
        fi
    done <<< "$(split_string "$all_packages" "、")"
    
    # 添加额外依赖
    if [ -n "$EXTRA_DEPS" ]; then
        log "=== 添加额外依赖 ==="
        while IFS= read -r dep; do
            local dep_clean=$(echo "$dep" | xargs)
            if [ -n "$dep_clean" ]; then
                echo "CONFIG_PACKAGE_${dep_clean}=y" >> .config
                color_blue "  🔧 添加依赖: $dep_clean"
            fi
        done <<< "$(split_string "$EXTRA_DEPS" "、")"
    fi
    
    log "✅ IPK配置生成完成"
    log "最终要编译的包: $all_packages"
}

# 步骤9: 应用配置
apply_config() {
    load_env
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    log "=== 应用配置 ==="
    
    # 显示启用的包 - 使用绿色显示
    log "=== 已启用的包列表 ==="
    grep "^CONFIG_PACKAGE_.*=y$" .config 2>/dev/null | while read line; do
        local pkg_name=$(echo "$line" | sed 's/CONFIG_PACKAGE_\(.*\)=y/\1/')
        color_green "  ✅ $pkg_name"
    done
    
    # 合并所有包名用于验证
    local all_packages=""
    if [ -n "$PACKAGE_NAMES" ]; then
        all_packages="$PACKAGE_NAMES"
    fi
    if [ -n "$SOURCE_PACKAGES" ]; then
        while IFS= read -r source_file; do
            local source_file_clean=$(echo "$source_file" | xargs)
            if [ -n "$source_file_clean" ]; then
                local package_name=$(basename "$source_file_clean" | sed 's/\.\(zip\|tar\.gz\|tgz\|tar\.bz2\)$//')
                if [ -n "$all_packages" ]; then
                    all_packages="$all_packages、$package_name"
                else
                    all_packages="$package_name"
                fi
            fi
        done <<< "$(split_string "$SOURCE_PACKAGES" "、")"
    fi
    
    # 显示目标包状态
    while IFS= read -r package; do
        local pkg_clean=$(echo "$package" | xargs)
        if [ -n "$pkg_clean" ]; then
            if grep -q "CONFIG_PACKAGE_${pkg_clean}=y" .config 2>/dev/null; then
                color_green "✅ 目标包已启用: $pkg_clean"
            else
                color_red "❌ 目标包未启用: $pkg_clean"
                log_warning "目标包配置失败"
            fi
        fi
    done <<< "$(split_string "$all_packages" "、")"
    
    make defconfig 2>/dev/null || { log_warning "应用配置失败"; }
    
    log "✅ 配置应用完成"
}

# 步骤10: 修复网络环境
fix_network() {
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    log "=== 修复网络环境 ==="
    git config --global http.postBuffer 524288000 2>/dev/null || true
    git config --global http.lowSpeedLimit 0 2>/dev/null || true
    git config --global http.lowSpeedTime 999999 2>/dev/null || true
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    
    log "✅ 网络环境修复完成"
}

# 步骤11: 下载依赖包
download_dependencies() {
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    log "=== 下载依赖包 ==="
    # 修复：增加重试次数
    for i in {1..3}; do
        log "第 $i 次尝试下载依赖..."
        if make -j1 download DOWNLOAD_RETRIES=3 2>/dev/null; then
            log "✅ 依赖包下载完成"
            break
        elif [ $i -eq 3 ]; then
            log_warning "下载依赖包有错误，但继续编译过程"
            break
        else
            sleep 10
        fi
    done
}

# 步骤12: 编译IPK包
build_ipk() {
    local package_names="$1"
    local clean_build="$2"
    load_env
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    log "=== 编译IPK包 ==="
    log "输入框包名: $package_names"
    log "源码压缩包: $SOURCE_PACKAGES"
    log "清理编译: $clean_build"
    
    # 合并所有包名
    local all_packages=""
    if [ -n "$package_names" ]; then
        all_packages="$package_names"
    fi
    if [ -n "$SOURCE_PACKAGES" ]; then
        while IFS= read -r source_file; do
            local source_file_clean=$(echo "$source_file" | xargs)
            if [ -n "$source_file_clean" ]; then
                local package_name=$(basename "$source_file_clean" | sed 's/\.\(zip\|tar\.gz\|tgz\|tar\.bz2\)$//')
                if [ -n "$all_packages" ]; then
                    all_packages="$all_packages、$package_name"
                else
                    all_packages="$package_name"
                fi
            fi
        done <<< "$(split_string "$SOURCE_PACKAGES" "、")"
    fi
    
    if [ -z "$all_packages" ]; then
        log_error "没有指定要编译的包"
        return 1
    fi
    
    # 创建输出目录
    mkdir -p "$BUILD_DIR/ipk_output" 2>/dev/null
    
    # 编译每个包
    local package_count=0
    local success_count=0
    
    while IFS= read -r package; do
        local pkg_clean=$(echo "$package" | xargs)
        if [ -z "$pkg_clean" ]; then
            continue
        fi
        
        ((package_count++)) || true
        
        log "📦 编译包 [$package_count]: $pkg_clean"
        
        # 检查包是否存在（包括自定义包和源码包）
        local package_exists=0
        if [ -d "package/$pkg_clean" ] || check_package_exists "$pkg_clean"; then
            package_exists=1
        fi
        
        if [ $package_exists -eq 0 ]; then
            color_red "❌ 包 $pkg_clean 不存在，跳过"
            
            # 搜索类似的包
            log "🔍 搜索类似包..."
            find . -name "*${pkg_clean##*-}*" -type d 2>/dev/null | head -5 | while read similar; do
                color_yellow "  💡 类似包: $(basename "$similar")"
            done
            continue
        fi
        
        # 如果要求清理编译，先清理相关包
        if [ "$clean_build" = "true" ]; then
            log "🧹 清理包构建..."
            make package/${pkg_clean}/clean 2>/dev/null || log_warning "清理包 $pkg_clean 失败，继续编译"
        fi
        
        # 编译指定包
        log "开始编译包: $pkg_clean"
        if make -j$(nproc) package/${pkg_clean}/compile V=s 2>&1 | tee -a "$LOG_FILE"; then
            ((success_count++)) || true
        else
            log_warning "包 $pkg_clean 编译过程有错误"
        fi
        
        # 查找生成的IPK文件
        log "=== 查找包 $pkg_clean 的IPK文件 ==="
        local ipk_found=0
        
        # 搜索所有可能的IPK文件路径
        local search_paths=(
            "bin/packages/*/*/${pkg_clean}*.ipk"
            "bin/targets/*/*/packages/${pkg_clean}*.ipk"
        )
        
        for search_path in "${search_paths[@]}"; do
            for ipk_file in $search_path; do
                if [ -f "$ipk_file" ]; then
                    log "✅ 找到IPK文件: $ipk_file"
                    cp "$ipk_file" "$BUILD_DIR/ipk_output/" 2>/dev/null || true
                    ipk_found=1
                fi
            done
        done
        
        # 如果没找到，尝试深度搜索
        if [ $ipk_found -eq 0 ]; then
            log "🔍 深度搜索 $pkg_clean 的IPK文件..."
            find "$BUILD_DIR" -name "*${pkg_clean}*.ipk" -type f 2>/dev/null | while read ipk_file; do
                log "✅ 找到IPK文件: $ipk_file"
                cp "$ipk_file" "$BUILD_DIR/ipk_output/" 2>/dev/null || true
                ipk_found=1
            done
        fi
        
        if [ $ipk_found -eq 1 ]; then
            color_green "✅ 包 $pkg_clean 编译成功！"
        else
            color_red "❌ 未找到包 $pkg_clean 的IPK文件"
        fi
        
        log "---"
    done <<< "$(split_string "$all_packages" "、")"
    
    # 总结编译结果
    log "=== 编译总结 ==="
    if [ $success_count -gt 0 ]; then
        color_green "🎉 编译完成！成功生成 $success_count/$package_count 个IPK包"
        log "📦 生成的IPK文件:"
        ls -la "$BUILD_DIR/ipk_output/" 2>/dev/null || log "输出目录为空"
        
        # 创建文件列表
        find "$BUILD_DIR/ipk_output" -name "*.ipk" -type f 2>/dev/null > "$BUILD_DIR/ipk_output/file_list.txt" 2>/dev/null || true
    else
        color_red "❌ 所有包编译失败"
        log "💡 可能的原因:"
        log "1. 包名不正确"
        log "2. 包在选择的版本中不存在"
        log "3. 编译依赖缺失"
        log "4. 网络问题导致下载失败"
        
        # 显示可用的包
        log "🔍 可用的Luci应用包:"
        find feeds/luci -name "luci-app-*" -type d 2>/dev/null | head -10 | while read app; do
            color_yellow "  📦 $(basename "$app")"
        done
        
        log_error "IPK文件生成失败 - 请检查包名和编译日志"
        return 1
    fi
    
    log "✅ IPK包编译完成"
}

# 步骤13: 创建安装脚本
create_install_script() {
    load_env
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    log "=== 创建安装脚本 ==="
    
    # 创建安装脚本
    cat > "$BUILD_DIR/ipk_output/install_package.sh" << 'EOF'
#!/bin/bash
# 通用IPK包安装脚本
# 适用于全平台OpenWrt

show_help() {
    echo "用法: $0 [选项] [包名...]"
    echo ""
    echo "选项:"
    echo "  -a, --all     安装所有IPK包"
    echo "  -h, --help    显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -a                         # 安装所有IPK包"
    echo "  $0 luci-app-filetransfer      # 安装指定包"
    echo "  $0 pkg1 pkg2 pkg3             # 安装多个包"
}

install_all_packages() {
    echo "=== 安装所有IPK包 ==="
    
    # 查找所有IPK文件
    local ipk_files=$(find . -name "*.ipk" -type f 2>/dev/null)
    
    if [ -z "$ipk_files" ]; then
        echo "❌ 未找到任何IPK文件"
        return 1
    fi
    
    echo "找到以下IPK文件:"
    echo "$ipk_files" | while read file; do
        echo "  - $(basename "$file")"
    done
    
    # 安装依赖
    echo "检查依赖..."
    opkg update 2>/dev/null || echo "⚠️ 更新包列表失败"
    
    # 安装所有包
    for ipk_file in $ipk_files; do
        echo "安装: $(basename "$ipk_file")"
        if opkg install "$ipk_file" 2>/dev/null; then
            echo "✅ $(basename "$ipk_file") 安装成功"
        else
            echo "❌ $(basename "$ipk_file") 安装失败"
        fi
        echo ""
    done
    
    echo "🎉 所有包安装完成！"
}

install_specific_packages() {
    local packages=("$@")
    
    echo "=== 安装指定包 ==="
    echo "要安装的包: ${packages[*]}"
    
    # 检查系统
    if [ ! -f "/etc/openwrt_release" ]; then
        echo "❌ 这不是OpenWrt系统"
        return 1
    fi
    
    # 获取架构
    ARCH=$(opkg print-architecture 2>/dev/null | awk '{print $2}')
    echo "系统架构: $ARCH"
    
    # 安装依赖
    echo "检查依赖..."
    opkg update 2>/dev/null || echo "⚠️ 更新包列表失败"
    
    # 安装每个包
    for package_name in "${packages[@]}"; do
        echo "=== 安装包: $package_name ==="
        
        # 查找匹配的IPK文件
        IPK_FILE=$(find . -name "*${package_name}*.ipk" 2>/dev/null | head -1)
        
        if [ -z "$IPK_FILE" ]; then
            echo "❌ 未找到包 $package_name 的IPK文件"
            echo "当前目录下的IPK文件:"
            find . -name "*.ipk" 2>/dev/null | while read file; do
                echo "  - $(basename "$file")"
            done
            continue
        fi
        
        echo "找到IPK文件: $(basename "$IPK_FILE")"
        
        # 尝试安装IPK
        if opkg install "$IPK_FILE" 2>/dev/null; then
            echo "✅ $package_name 安装成功！"
            
            # 检查是否真的安装成功
            if opkg list-installed 2>/dev/null | grep -q "$package_name"; then
                echo "🎉 包已成功安装到系统"
                
                # 如果是Luci应用，提示重启服务
                if [[ "$package_name" == luci-app-* ]]; then
                    echo ""
                    echo "💡 如果是Luci应用，请:"
                    echo "1. 刷新浏览器缓存"
                    echo "2. 在Luci界面中查看新功能"
                fi
            else
                echo "⚠️ 包可能未正确安装，请检查以上输出"
            fi
        else
            echo "❌ $package_name 安装失败，请检查依赖关系"
            echo "💡 可以尝试手动安装依赖后重试"
        fi
        echo ""
    done
}

# 主逻辑
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -a|--all)
        install_all_packages
        ;;
    *)
        if [ $# -eq 0 ]; then
            show_help
            exit 1
        else
            install_specific_packages "$@"
        fi
        ;;
esac
EOF

    chmod +x "$BUILD_DIR/ipk_output/install_package.sh" 2>/dev/null || log_warning "设置安装脚本执行权限失败"
    
    # 创建使用说明
    cat > "$BUILD_DIR/ipk_output/README.md" << EOF
# IPK包使用说明

## 文件说明
- \`*.ipk\`: OpenWrt软件包文件
- \`install_package.sh\`: 自动安装脚本
- \`file_list.txt\`: 文件列表

## 安装方法

### 方法一：使用安装脚本（推荐）
\`\`\`bash
# 上传整个ipk_output目录到路由器
scp -r ipk_output root@192.168.1.1:/tmp/

# 在路由器上执行
ssh root@192.168.1.1
cd /tmp/ipk_output

# 安装所有包
./install_package.sh -a

# 或安装指定包
./install_package.sh luci-app-filetransfer
./install_package.sh pkg1 pkg2 pkg3
\`\`\`

### 方法二：手动安装
\`\`\`bash
# 上传IPK文件到路由器
scp *.ipk root@192.168.1.1:/tmp/

# 在路由器上安装
ssh root@192.168.1.1
cd /tmp
opkg update
opkg install *.ipk
\`\`\`

## 支持的平台
- 所有OpenWrt平台（全平台通用）
- OpenWrt 21.02 / 23.05
- ImmortalWrt

## 编译方式
本次编译使用了以下方式：
- 输入框包名: ${PACKAGE_NAMES:-无}
- 源码压缩包: ${SOURCE_PACKAGES:-无}

## 注意事项
1. 确保路由器有足够的空间
2. 安装前建议备份配置
3. 某些包可能需要特定依赖

## 多包编译说明
支持同时编译多个IPK包，包名之间用顿号分隔。

示例：
- \`luci-app-filetransfer\`
- \`luci-app-filetransfer、luci-app-turboacc、luci-app-upnp\`

## 源码压缩包编译
支持从源码压缩包编译，文件需放在 \`firmware-config/packages/\` 目录下。

支持的格式：
- ZIP (.zip)
- TAR.GZ (.tar.gz, .tgz)  
- TAR.BZ2 (.tar.bz2)

## 常见问题

### 1. 包不存在
如果提示包不存在，请检查：
- 包名是否正确
- 包在选择的版本中是否存在
- 源码压缩包文件名是否正确

### 2. 常用包名参考
- \`luci-app-adblock\` - 广告过滤
- \`luci-app-aria2\` - 下载工具
- \`luci-app-ddns\` - 动态DNS
- \`luci-app-firewall\` - 防火墙
- \`luci-app-samba\` - 文件共享
- \`luci-app-upnp\` - UPnP服务
- \`luci-app-wireguard\` - WireGuard VPN

## 额外依赖包说明
额外依赖包用于在编译时确保相关的依赖包也被编译。这在你编译的包依赖其他包时特别有用。

例如：
- \`luci-base、luci-compat\`: 确保Luci基础包被编译
- \`libustream-openssl\`: 确保SSL支持被编译
- 其他包特定的依赖

如果没有特殊需求，通常可以留空。
EOF

    log "✅ 安装脚本和说明文档创建完成"
}

# 步骤14: 清理目录
cleanup() {
    log "=== 清理构建目录 ==="
    # 只清理构建文件，保留输出
    cd "$BUILD_DIR" 2>/dev/null && sudo rm -rf build_dir staging_dir tmp .config* 2>/dev/null || true
    log "✅ 构建中间文件已清理"
}

# 主函数
main() {
    local command="$1"
    local arg1="$2"
    local arg2="$3"
    
    case "$command" in
        "setup_environment")
            setup_environment
            ;;
        "create_build_dir")
            create_build_dir
            ;;
        "initialize_build_env")
            initialize_build_env "$arg1"
            ;;
        "configure_feeds")
            configure_feeds
            ;;
        "download_custom_packages")
            download_custom_packages "$arg1"
            ;;
        "process_source_packages")
            process_source_packages "$arg1" "$arg2"
            ;;
        "pre_build_space_check")
            pre_build_space_check
            ;;
        "generate_config")
            generate_config "$arg1" "$arg2"
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
        "build_ipk")
            build_ipk "$arg1" "$arg2"
            ;;
        "create_install_script")
            create_install_script
            ;;
        "cleanup")
            cleanup
            ;;
        *)
            log "❌ 未知命令: $command"
            echo "可用命令:"
            echo "  setup_environment, create_build_dir, initialize_build_env"
            echo "  configure_feeds, download_custom_packages, process_source_packages"
            echo "  pre_build_space_check, generate_config, apply_config, fix_network"
            echo "  download_dependencies, build_ipk, create_install_script, cleanup"
            return 1
            ;;
    esac
    
    # 如果函数执行成功，返回0
    return 0
}

# 执行主函数
if [ $# -lt 1 ]; then
    echo "用法: $0 <命令> [参数...]"
    echo "可用命令:"
    echo "  setup_environment, create_build_dir, initialize_build_env"
    echo "  configure_feeds, download_custom_packages, process_source_packages"
    echo "  pre_build_space_check, generate_config, apply_config, fix_network"
    echo "  download_dependencies, build_ipk, create_install_script, cleanup"
    exit 1
fi

# 执行命令，并捕获退出状态
main "$@"
EXIT_STATUS=$?

# 如果执行成功，确保返回0
if [ $EXIT_STATUS -eq 0 ]; then
    exit 0
else
    # 如果执行失败，返回1
    exit 1
fi
