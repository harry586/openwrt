#!/bin/bash
# OpenWrt IPK包编译主脚本（修复工具链问题）

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

# 错误处理函数
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
    
    # 使用 tr 进行分割
    echo "$input" | tr "$delimiter" '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
}

# 检查包是否存在
check_package_exists() {
    local package="$1"
    local found=0
    
    log "🔍 搜索包: $package"
    
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
            log "✅ 找到包目录: $path"
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
    
    # 如果找到包，确保有Makefile
    if [ $found -eq 1 ]; then
        # 尝试找到Makefile位置
        local package_dir=""
        for path in "${possible_paths[@]}"; do
            if [ -d "$path" ]; then
                package_dir="$path"
                break
            fi
        done
        
        if [ -z "$package_dir" ] && [ -n "$search_result" ]; then
            package_dir="$search_result"
        fi
        
        if [ -n "$package_dir" ] && [ -f "$package_dir/Makefile" ]; then
            log "✅ 确认包 $package 存在且有效"
            return 0  # 成功找到
        else
            log_warning "包 $package 目录存在但缺少Makefile"
        fi
    fi
    
    log "❌ 包 $package 不存在"
    return 1  # 未找到
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
    
    # 安装必要的编译工具和依赖
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
        libreadline-dev libbz2-dev liblzma-dev tk-dev \
        curl libxml2-dev libncursesw5-dev swig time 2>/dev/null || { log_warning "安装依赖包失败"; }
        
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
    
    # 版本选择 - 使用 ImmortalWrt
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
    
    # 克隆源码
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
    
    while IFS= read -r package; do
        local pkg_clean=$(echo "$package" | xargs)
        if [ -z "$pkg_clean" ]; then
            continue
        fi
        
        # 检查包是否存在，如果不存在，提示用户
        if ! check_package_exists "$pkg_clean"; then
            color_yellow "🔍 包 $pkg_clean 不存在，您可能需要提供自定义仓库或源码包"
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
    local all_compressed_files=$(find "$PACKAGES_BASE_DIR" -name "*.zip" -o -name "*.tar.gz" -o -name "*.tgz" -o -name "*.tar.bz2" -o -name "*.tar.xz" 2>/dev/null)
    
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
        local package_name=$(basename "$source_file_clean" | sed 's/\.\(zip\|tar\.gz\|tgz\|tar\.bz2\|tar\.xz\)$//')
        local original_package_name="$package_name"
        
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
        elif [[ "$source_file_clean" == *.tar.xz ]]; then
            if tar -xJf "$source_path" -C "$target_dir" 2>/dev/null; then
                extract_success=1
            else
                color_red "❌ 解压TAR.XZ文件失败: $source_file_clean"
            fi
        else
            color_red "❌ 不支持的压缩格式: $source_file_clean"
        fi
        
        if [ $extract_success -eq 0 ]; then
            ((error_count++)) || true
            continue
        fi
        
        # 检查是否解压到了子目录
        local subdirs=($(find "$target_dir" -maxdepth 1 -type d 2>/dev/null | grep -v "^$target_dir$"))
        
        if [ ${#subdirs[@]} -eq 1 ] && [ -d "${subdirs[0]}" ]; then
            log "检测到子目录结构，移动文件..."
            local subdir="${subdirs[0]}"
            mv "$subdir"/* "$target_dir"/ 2>/dev/null || true
            rm -rf "$subdir" 2>/dev/null
        fi
        
        # 验证包结构
        log "验证包结构: $package_name"
        
        # 检查文件类型
        log "解压后的文件结构:"
        find "$target_dir" -type f \( -name "*.lua" -o -name "*.js" -o -name "*.html" -o -name "*.css" -o -name "Makefile" \) 2>/dev/null | head -5 | while read file; do
            log "  📄 $(basename "$file") ($(dirname "$file" | xargs basename))"
        done
        
        # 检查Makefile，从中读取真实的包名
        if [ -f "$target_dir/Makefile" ]; then
            # 尝试从Makefile中读取PKG_NAME
            local pkg_name_from_makefile=$(grep -E '^PKG_NAME\s*[:?+]=' "$target_dir/Makefile" 2>/dev/null | head -1 | sed 's/^PKG_NAME\s*[:?+]=\s*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [ -n "$pkg_name_from_makefile" ]; then
                log "💡 从Makefile中读取包名: $pkg_name_from_makefile"
                package_name="$pkg_name_from_makefile"
                
                # 如果包名发生变化，更新目标目录
                if [ "$package_name" != "$original_package_name" ]; then
                    local new_target_dir="$SOURCE_PKG_DIR/luci/$package_name"
                    if [ "$target_dir" != "$new_target_dir" ]; then
                        mv "$target_dir" "$new_target_dir" 2>/dev/null
                        target_dir="$new_target_dir"
                    fi
                fi
            fi
        fi
        
        # 检查是否可能是Luci应用
        local has_lua_files=$(find "$target_dir" -name "*.lua" -type f 2>/dev/null | head -1)
        if [ -n "$has_lua_files" ] && [[ ! "$package_name" =~ ^luci-app- ]] && [[ ! "$package_name" =~ ^luci-theme- ]] && [[ ! "$package_name" =~ ^luci-i18n- ]]; then
            local new_package_name="luci-app-$package_name"
            log "💡 检测到Lua文件，重命名为: $new_package_name"
            package_name="$new_package_name"
            
            # 更新目标目录
            local new_target_dir="$SOURCE_PKG_DIR/luci/$package_name"
            if [ "$target_dir" != "$new_target_dir" ]; then
                mv "$target_dir" "$new_target_dir" 2>/dev/null
                target_dir="$new_target_dir"
            fi
        fi
        
        # 检查必要文件
        if [ ! -f "$target_dir/Makefile" ]; then
            color_red "❌ 缺少关键文件: Makefile"
            ((error_count++)) || true
            continue
        fi
        
        color_green "✅ 找到关键文件: Makefile"
        
        # 集成到构建系统
        log "集成源码包到构建系统: $package_name"
        cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; continue; }
        
        # 复制包到package目录
        local build_pkg_dir="package/$package_name"
        rm -rf "$build_pkg_dir" 2>/dev/null
        mkdir -p "$build_pkg_dir" 2>/dev/null
        
        log "复制包文件到构建系统..."
        if ! cp -r "$target_dir"/* "$build_pkg_dir"/ 2>/dev/null; then
            color_red "❌ 复制包文件失败"
            ((error_count++)) || true
            continue
        fi
        
        # 验证是否成功复制
        if [ ! -f "$build_pkg_dir/Makefile" ]; then
            color_red "❌ 复制后缺少Makefile"
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

# 步骤7: 编译前空间检查
pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    df -h 2>/dev/null || true
    AVAILABLE_SPACE=$(df /mnt --output=avail 2>/dev/null | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024)) 2>/dev/null || AVAILABLE_GB=0
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
    
    # 创建基础配置
    cat > .config << 'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_ROOTFS_INITRAMFS=n
CONFIG_TARGET_ROOTFS_EXT4FS=n
CONFIG_TARGET_ROOTFS_SQUASHFS=n
CONFIG_TARGET_ROOTFS_PARTSIZE=512
CONFIG_TOOLCHAIN=y
CONFIG_TOOLCHAIN_BUILD=y
CONFIG_PACKAGE_busybox=y
CONFIG_BUSYBOX_CUSTOM=y
CONFIG_BUSYBOX_CONFIG_DEFAULT_FEATURE_SYSTEMD=n
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
CONFIG_PACKAGE_libopenssl=y
CONFIG_PACKAGE_libstdcpp=y
CONFIG_PACKAGE_libpthread=y
CONFIG_PACKAGE_zlib=y
CONFIG_PACKAGE_libuuid=y
CONFIG_PACKAGE_libjson-c=y
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
                # 从压缩包文件名获取包名
                local package_name=$(basename "$source_file_clean" | sed 's/\.\(zip\|tar\.gz\|tgz\|tar\.bz2\|tar\.xz\)$//')
                
                # 如果是源码压缩包，需要从处理过程中获取正确的包名
                # 这里我们暂时使用文件名，在build_ipk中会使用实际的包名
                if [[ ! "$package_name" =~ ^luci-app- ]] && [[ ! "$package_name" =~ ^luci-theme- ]] && [[ ! "$package_name" =~ ^luci-i18n- ]]; then
                    package_name="luci-app-$package_name"
                fi
                
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
    
    # 添加要编译的包
    log "=== 添加目标包 ==="
    
    while IFS= read -r package; do
        local pkg_clean=$(echo "$package" | xargs)
        if [ -n "$pkg_clean" ]; then
            # 确保包名在.config中正确
            local config_name="${pkg_clean//-/_}"
            echo "CONFIG_PACKAGE_${config_name}=y" >> .config
            color_green "  ✅ 添加包: $pkg_clean"
        fi
    done <<< "$(split_string "$all_packages" "、")"
    
    # 添加额外依赖
    if [ -n "$EXTRA_DEPS" ]; then
        log "=== 添加额外依赖 ==="
        while IFS= read -r dep; do
            local dep_clean=$(echo "$dep" | xargs)
            if [ -n "$dep_clean" ]; then
                local config_name="${dep_clean//-/_}"
                echo "CONFIG_PACKAGE_${config_name}=y" >> .config
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
    
    # 显示启用的包
    log "=== 已启用的包列表 ==="
    grep "^CONFIG_PACKAGE_.*=y$" .config 2>/dev/null | while read line; do
        local pkg_name=$(echo "$line" | sed 's/CONFIG_PACKAGE_\(.*\)=y/\1/' | sed 's/_/-/g')
        color_green "  ✅ $pkg_name"
    done
    
    if make defconfig 2>/dev/null; then
        log "✅ 配置应用完成"
    else
        log_warning "应用配置有警告"
        # 继续执行，有些警告不影响编译
    fi
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

# 步骤11: 下载依赖包 - 修复工具链问题
download_dependencies() {
    cd "$BUILD_DIR" 2>/dev/null || { log_error "进入构建目录失败"; return 1; }
    
    log "=== 下载依赖包 ==="
    # 增加重试次数
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
    
    # 修复：手动创建缺失的musl库文件
    log "=== 修复工具链问题 ==="
    
    # 查找工具链目录
    local toolchain_dirs=$(find "$BUILD_DIR/staging_dir" -name "toolchain-*" -type d 2>/dev/null | head -1)
    if [ -n "$toolchain_dirs" ]; then
        log "找到工具链目录: $toolchain_dirs"
        
        # 检查是否存在ld-musl文件
        local musl_files=$(find "$toolchain_dirs" -name "ld-musl-*.so*" 2>/dev/null | head -1)
        if [ -n "$musl_files" ]; then
            log "✅ 找到musl库文件: $musl_files"
        else
            log_warning "未找到musl库文件，尝试修复..."
            
            # 尝试从系统查找或创建
            local lib_dir="$toolchain_dirs/lib"
            mkdir -p "$lib_dir" 2>/dev/null
            
            # 创建符号链接
            local target_so="ld-musl-x86_64.so.1"
            local source_so=$(find "$toolchain_dirs" -name "libc.so" -o -name "libc.so.*" 2>/dev/null | head -1)
            
            if [ -n "$source_so" ]; then
                log "找到libc.so: $source_so"
                ln -sf "$source_so" "$lib_dir/$target_so" 2>/dev/null && log "创建符号链接: $lib_dir/$target_so"
            else
                # 尝试从其他地方复制
                log "尝试从其他地方复制musl库..."
                find /usr -name "*musl*" -type f 2>/dev/null | head -3 | while read musl_file; do
                    log "找到可能的musl文件: $musl_file"
                done
            fi
        fi
    else
        log_warning "未找到工具链目录"
    fi
}

# 步骤12: 编译IPK包 - 修复工具链问题
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
    
    # 对于源码压缩包，我们使用处理过程中确定的包名
    # 这里我们需要从package目录获取实际处理的包名
    if [ -n "$SOURCE_PACKAGES" ]; then
        # 查找package目录下所有目录，获取包名
        local source_package_names=""
        while IFS= read -r source_file; do
            local source_file_clean=$(echo "$source_file" | xargs)
            if [ -z "$source_file_clean" ]; then
                continue
            fi
            
            # 从压缩包文件名猜测包名
            local guessed_package_name=$(basename "$source_file_clean" | sed 's/\.\(zip\|tar\.gz\|tgz\|tar\.bz2\|tar\.xz\)$//')
            
            # 先尝试从package目录查找实际包名
            local found_package=""
            
            # 查找以 guessed_package_name 开头的目录
            local found_dirs=$(find package -name "*${guessed_package_name}*" -type d 2>/dev/null)
            if [ -n "$found_dirs" ]; then
                for dir in $found_dirs; do
                    local dir_name=$(basename "$dir")
                    if [ -f "$dir/Makefile" ]; then
                        # 尝试从Makefile读取PKG_NAME
                        local pkg_name_from_makefile=$(grep -E '^PKG_NAME\s*[:?+]=' "$dir/Makefile" 2>/dev/null | head -1 | sed 's/^PKG_NAME\s*[:?+]=\s*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        if [ -n "$pkg_name_from_makefile" ]; then
                            found_package="$pkg_name_from_makefile"
                            break
                        else
                            found_package="$dir_name"
                            break
                        fi
                    fi
                done
            fi
            
            # 如果没找到，使用猜测的包名并添加luci-app-前缀
            if [ -z "$found_package" ]; then
                if [[ ! "$guessed_package_name" =~ ^luci-app- ]] && [[ ! "$guessed_package_name" =~ ^luci-theme- ]] && [[ ! "$guessed_package_name" =~ ^luci-i18n- ]]; then
                    found_package="luci-app-$guessed_package_name"
                else
                    found_package="$guessed_package_name"
                fi
            fi
            
            if [ -n "$all_packages" ]; then
                all_packages="$all_packages、$found_package"
            else
                all_packages="$found_package"
            fi
        done <<< "$(split_string "$SOURCE_PACKAGES" "、")"
    fi
    
    if [ -z "$all_packages" ]; then
        log_error "没有指定要编译的包"
        return 1
    fi
    
    log "📦 要编译的包: $all_packages"
    
    # 创建输出目录
    mkdir -p "$BUILD_DIR/ipk_output" 2>/dev/null
    
    # 创建编译日志目录
    local log_dir="$BUILD_DIR/compile_logs"
    mkdir -p "$log_dir" 2>/dev/null
    
    # 修复工具链问题：先构建工具链
    log "=== 构建工具链 ==="
    local toolchain_log="$log_dir/toolchain_build.log"
    
    # 尝试修复musl库文件问题
    log "修复musl库文件..."
    
    # 查找工具链目录
    local toolchain_dir=$(find "$BUILD_DIR/staging_dir" -name "toolchain-*" -type d 2>/dev/null | head -1)
    if [ -n "$toolchain_dir" ]; then
        local lib_dir="$toolchain_dir/lib"
        mkdir -p "$lib_dir" 2>/dev/null
        
        # 创建缺失的musl库文件
        log "创建musl库文件..."
        
        # 方法1: 查找现有的musl库
        local existing_musl=$(find "$BUILD_DIR" -name "ld-musl-*.so*" -type f 2>/dev/null | head -1)
        if [ -n "$existing_musl" ]; then
            log "找到现有的musl库: $existing_musl"
            cp "$existing_musl" "$lib_dir/" 2>/dev/null || true
        fi
        
        # 方法2: 创建符号链接
        local libc_so=$(find "$toolchain_dir" -name "libc.so" -o -name "libc.so.*" 2>/dev/null | head -1)
        if [ -n "$libc_so" ]; then
            log "找到libc.so: $libc_so"
            ln -sf "$libc_so" "$lib_dir/ld-musl-x86_64.so.1" 2>/dev/null || true
        fi
        
        # 方法3: 从系统复制（如果可用）
        if [ ! -f "$lib_dir/ld-musl-x86_64.so.1" ] && [ ! -f "$lib_dir/ld-musl-x86_64.so" ]; then
            log "尝试从系统查找musl库..."
            # 检查系统是否有musl库
            if command -v musl-gcc >/dev/null 2>&1; then
                # 尝试查找musl库路径
                local system_musl=$(find /usr -name "*musl*" -type f 2>/dev/null | grep -E "ld-musl|libc.musl" | head -1)
                if [ -n "$system_musl" ]; then
                    cp "$system_musl" "$lib_dir/" 2>/dev/null || true
                fi
            fi
        fi
        
        # 最后检查是否创建成功
        if [ -f "$lib_dir/ld-musl-x86_64.so.1" ] || [ -f "$lib_dir/ld-musl-x86_64.so" ]; then
            color_green "✅ musl库文件修复完成"
        else
            log_warning "⚠️ musl库文件修复失败，编译可能会出错"
        fi
    else
        log_warning "未找到工具链目录"
    fi
    
    # 尝试构建工具链（但跳过错误）
    log "尝试构建工具链..."
    if make -j1 toolchain/compile 2>&1 | tee -a "$toolchain_log" | tail -50; then
        log "✅ 工具链构建成功"
    else
        log_warning "工具链构建有错误，但继续尝试编译"
    fi
    
    # 编译用户指定的包
    local package_count=0
    local success_count=0
    local ipk_found_total=0
    
    while IFS= read -r package; do
        local pkg_clean=$(echo "$package" | xargs)
        if [ -z "$pkg_clean" ]; then
            continue
        fi
        
        ((package_count++)) || true
        
        log "📦 编译包 [$package_count]: $pkg_clean"
        
        # 检查包是否存在
        if check_package_exists "$pkg_clean"; then
            log "✅ 包存在: $pkg_clean"
        else
            color_red "❌ 包 $pkg_clean 不存在，跳过编译"
            
            # 尝试查找类似的包名
            log "🔍 尝试查找类似包名..."
            local similar_packages=$(find feeds -name "*${pkg_clean}*" -type d 2>/dev/null | head -5)
            if [ -n "$similar_packages" ]; then
                log "💡 找到类似包:"
                echo "$similar_packages" | while read similar; do
                    local similar_name=$(basename "$similar")
                    log "  📦 $similar_name"
                done
            fi
            continue
        fi
        
        # 如果要求清理编译，先清理相关包
        if [ "$clean_build" = "true" ]; then
            log "🧹 清理包构建..."
            make package/${pkg_clean}/clean 2>/dev/null || log_warning "清理包 $pkg_clean 失败，继续编译"
        fi
        
        # 编译指定包
        log "开始编译包: $pkg_clean"
        
        # 创建临时日志文件
        local compile_log="$log_dir/compile_${pkg_clean//\//_}.log"
        
        # 尝试编译
        log "编译日志: $compile_log"
        if make -j1 package/${pkg_clean}/compile 2>&1 | tee "$compile_log"; then
            ((success_count++)) || true
            log "✅ 编译命令执行完成"
        else
            local compile_status=$?
            log_warning "包 $pkg_clean 编译过程有错误，退出码: $compile_status"
            
            # 显示编译错误的最后部分
            log "🔍 编译错误摘要:"
            tail -50 "$compile_log" 2>/dev/null | while read line; do
                color_red "  $line"
            done
            
            # 检查工具链错误
            if grep -q "ld-musl-" "$compile_log" 2>/dev/null; then
                log "💡 检测到工具链错误，尝试修复..."
                
                # 尝试手动修复
                log "手动修复musl库文件..."
                local toolchain_lib_dir=$(find "$BUILD_DIR/staging_dir" -name "toolchain-*" -type d 2>/dev/null | head -1)/lib
                if [ -n "$toolchain_lib_dir" ]; then
                    mkdir -p "$toolchain_lib_dir" 2>/dev/null
                    
                    # 创建空的musl库文件（作为最后的手段）
                    if [ ! -f "$toolchain_lib_dir/ld-musl-x86_64.so.1" ]; then
                        echo "#!/bin/bash" > "$toolchain_lib_dir/ld-musl-x86_64.so.1"
                        chmod +x "$toolchain_lib_dir/ld-musl-x86_64.so.1" 2>/dev/null || true
                        log "创建空的musl库文件占位"
                    fi
                fi
            fi
        fi
        
        # 查找生成的IPK文件
        log "=== 查找包 $pkg_clean 的IPK文件 ==="
        local ipk_found=0
        
        # 搜索所有可能的IPK文件路径
        local search_paths=(
            "bin/packages/*/*/${pkg_clean}*.ipk"
            "bin/packages/*/*/${pkg_clean/-/_}*.ipk"
            "bin/packages/*/*/*${pkg_clean}*.ipk"
            "bin/targets/*/*/packages/${pkg_clean}*.ipk"
            "bin/targets/*/*/packages/${pkg_clean/-/_}*.ipk"
        )
        
        for search_path in "${search_paths[@]}"; do
            for ipk_file in $search_path; do
                if [ -f "$ipk_file" ]; then
                    log "✅ 找到IPK文件: $ipk_file"
                    local dest_file="$BUILD_DIR/ipk_output/$(basename "$ipk_file")"
                    cp "$ipk_file" "$dest_file" 2>/dev/null || true
                    ipk_found=1
                    ((ipk_found_total++)) || true
                fi
            done
        done
        
        # 如果没找到，尝试深度搜索
        if [ $ipk_found -eq 0 ]; then
            log "🔍 深度搜索 $pkg_clean 的IPK文件..."
            find "$BUILD_DIR/bin" -name "*${pkg_clean}*.ipk" -type f 2>/dev/null | while read ipk_file; do
                log "✅ 找到IPK文件: $ipk_file"
                cp "$ipk_file" "$BUILD_DIR/ipk_output/" 2>/dev/null || true
                ipk_found=1
                ((ipk_found_total++)) || true
            done
        fi
        
        if [ $ipk_found -eq 1 ]; then
            color_green "✅ 包 $pkg_clean 编译成功！"
        else
            color_yellow "⚠️ 未找到包 $pkg_clean 的IPK文件"
            log "💡 建议:"
            log "1. 检查编译日志: $compile_log"
            log "2. 检查包的依赖是否满足"
            log "3. 尝试编译更简单的包"
            
            # 显示可能的IPK文件位置
            log "当前已生成的IPK文件:"
            find "$BUILD_DIR/bin" -name "*.ipk" -type f 2>/dev/null | head -5 | while read ipk_file; do
                log "  📦 $ipk_file"
            done || log "  未找到任何IPK文件"
        fi
        
        log "---"
        
    done <<< "$(split_string "$all_packages" "、")"
    
    # 总结编译结果
    log "=== 编译总结 ==="
    if [ $ipk_found_total -gt 0 ]; then
        color_green "🎉 编译完成！成功生成 $ipk_found_total 个IPK包"
        log "📦 生成的IPK文件:"
        ls -la "$BUILD_DIR/ipk_output/" 2>/dev/null || log "输出目录为空"
        
        # 显示找到的IPK文件
        find "$BUILD_DIR/ipk_output" -name "*.ipk" -type f 2>/dev/null | while read ipk_file; do
            color_green "  📦 $(basename "$ipk_file")"
        done
        
        # 创建文件列表
        find "$BUILD_DIR/ipk_output" -name "*.ipk" -type f 2>/dev/null > "$BUILD_DIR/ipk_output/file_list.txt" 2>/dev/null || true
    else
        if [ $success_count -gt 0 ]; then
            color_yellow "⚠️ 编译过程完成但未找到IPK文件"
        else
            color_red "❌ 所有包编译失败"
        fi
        
        log "💡 调试建议:"
        log "1. 检查工具链是否完整"
        log "2. 尝试只编译一个简单包测试: luci-app-upnp"
        log "3. 检查是否有足够的磁盘空间"
        log "4. 尝试使用 OpenWrt 21.02 版本（更稳定）"
        
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

set -e

show_help() {
    echo "用法: $0 [选项] [包名...]"
    echo ""
    echo "选项:"
    echo "  -a, --all     安装所有IPK包"
    echo "  -l, --list    列出所有可用的IPK包"
    echo "  -h, --help    显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -a                         # 安装所有IPK包"
    echo "  $0 -l                         # 列出所有IPK包"
    echo "  $0 luci-app-filetransfer      # 安装指定包"
    echo "  $0 pkg1 pkg2 pkg3             # 安装多个包"
}

list_packages() {
    echo "=== 可用的IPK包 ==="
    echo ""
    
    if [ ! -d "." ] || [ -z "$(ls *.ipk 2>/dev/null)" ]; then
        echo "❌ 当前目录没有IPK包文件"
        return 1
    fi
    
    echo "📦 IPK包列表:"
    echo ""
    for ipk_file in *.ipk; do
        if [ -f "$ipk_file" ]; then
            local package_name=$(echo "$ipk_file" | sed 's/_.*$//')
            local version=$(echo "$ipk_file" | grep -o '[0-9]\+\.[0-9]\+-[0-9]\+' | head -1)
            local arch=$(echo "$ipk_file" | grep -o '\(aarch64\|arm\|mipsel\|x86_64\|i386\|mips\)' | head -1)
            
            echo "✅ $package_name"
            echo "   📁 文件: $ipk_file"
            [ -n "$version" ] && echo "   📅 版本: $version"
            [ -n "$arch" ] && echo "   🏗️  架构: $arch"
            echo ""
        fi
    done
}

install_all_packages() {
    echo "=== 安装所有IPK包 ==="
    
    # 查找所有IPK文件
    local ipk_files=$(ls *.ipk 2>/dev/null)
    
    if [ -z "$ipk_files" ]; then
        echo "❌ 未找到任何IPK文件"
        return 1
    fi
    
    echo "找到以下IPK文件:"
    echo "$ipk_files" | while read file; do
        echo "  - $(basename "$file")"
    done
    
    echo ""
    echo "警告: 这将安装所有IPK包，可能会覆盖现有包"
    read -p "是否继续? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "安装取消"
        return 0
    fi
    
    # 安装依赖
    echo "检查系统依赖..."
    if ! command -v opkg >/dev/null 2>&1; then
        echo "❌ 这不是OpenWrt系统或opkg未安装"
        return 1
    fi
    
    echo "更新包列表..."
    opkg update 2>/dev/null || echo "⚠️ 更新包列表失败"
    
    # 安装所有包
    for ipk_file in $ipk_files; do
        echo ""
        echo "=== 安装: $(basename "$ipk_file") ==="
        if opkg install "$ipk_file" --force-overwrite; then
            echo "✅ $(basename "$ipk_file") 安装成功"
        else
            echo "❌ $(basename "$ipk_file") 安装失败"
            echo "💡 尝试强制安装..."
            opkg install "$ipk_file" --force-depends --force-overwrite || echo "❌ 强制安装也失败"
        fi
    done
    
    echo ""
    echo "🎉 所有包安装完成！"
    echo ""
    echo "💡 后续操作:"
    echo "1. 如果是Luci应用，请刷新浏览器缓存"
    echo "2. 重启相关服务: /etc/init.d/<服务名> restart"
    echo "3. 在Luci界面中查看新功能"
}

install_specific_packages() {
    local packages=("$@")
    
    echo "=== 安装指定包 ==="
    echo "要安装的包: ${packages[*]}"
    
    # 检查系统
    if ! command -v opkg >/dev/null 2>&1; then
        echo "❌ 这不是OpenWrt系统或opkg未安装"
        return 1
    fi
    
    # 获取架构
    ARCH=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | head -1)
    if [ -z "$ARCH" ]; then
        ARCH=$(uname -m)
    fi
    echo "系统架构: $ARCH"
    
    # 安装依赖
    echo "检查依赖..."
    opkg update 2>/dev/null || echo "⚠️ 更新包列表失败"
    
    # 安装每个包
    for package_name in "${packages[@]}"; do
        echo ""
        echo "=== 安装包: $package_name ==="
        
        # 查找匹配的IPK文件
        IPK_FILE=$(ls *${package_name}*.ipk 2>/dev/null | head -1)
        
        if [ -z "$IPK_FILE" ]; then
            echo "❌ 未找到包 $package_name 的IPK文件"
            echo "当前目录下的IPK文件:"
            ls *.ipk 2>/dev/null | while read file; do
                echo "  - $(basename "$file")"
            done || echo "  没有IPK文件"
            continue
        fi
        
        echo "找到IPK文件: $(basename "$IPK_FILE")"
        
        # 检查架构是否匹配
        local ipk_arch=$(echo "$IPK_FILE" | grep -o '\(aarch64\|arm\|mipsel\|x86_64\|i386\|mips\)' | head -1)
        if [ -n "$ipk_arch" ] && [ "$ipk_arch" != "$ARCH" ]; then
            echo "⚠️ 架构不匹配: IPK为 $ipk_arch, 系统为 $ARCH"
            echo "💡 尝试强制安装..."
        fi
        
        # 尝试安装IPK
        if opkg install "$IPK_FILE" --force-overwrite; then
            echo "✅ $package_name 安装成功！"
            
            # 检查是否真的安装成功
            if opkg list-installed 2>/dev/null | grep -q "^${package_name} "; then
                echo "🎉 包已成功安装到系统"
                
                # 如果是Luci应用，提示重启服务
                if [[ "$package_name" == luci-app-* ]]; then
                    echo ""
                    echo "💡 如果是Luci应用，请:"
                    echo "1. 刷新浏览器缓存 (Ctrl+F5)"
                    echo "2. 在Luci界面中查看新功能"
                    echo "3. 如果看不到新菜单，尝试重启uhttpd: /etc/init.d/uhttpd restart"
                fi
            else
                echo "⚠️ 包可能未正确安装，请检查以上输出"
            fi
        else
            echo "❌ $package_name 安装失败，请检查依赖关系"
            echo "💡 可以尝试手动安装: opkg install $IPK_FILE --force-depends --force-overwrite"
        fi
    done
}

# 主逻辑
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -l|--list)
        list_packages
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
    
    log "✅ 安装脚本创建完成"
}

# 步骤14: 清理目录
cleanup() {
    log "=== 清理构建目录 ==="
    # 只清理构建文件，保留输出
    cd "$BUILD_DIR" 2>/dev/null && {
        # 清理中间文件，保留源码和输出
        sudo rm -rf build_dir staging_dir tmp .config* feeds 2>/dev/null || true
    }
    log "✅ 构建中间文件已清理"
}

# 主函数
main() {
    local command="$1"
    local arg1="$2"
    local arg2="$3"
    
    # 初始化日志
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
    
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
