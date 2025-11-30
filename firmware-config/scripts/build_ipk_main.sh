#!/bin/bash
set -e

# 全局变量
BUILD_DIR="/mnt/openwrt-build-ipk"
ENV_FILE="$BUILD_DIR/build_env.sh"
LOG_FILE="$BUILD_DIR/build_ipk.log"

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
handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

# 保存环境变量到文件
save_env() {
    mkdir -p "$BUILD_DIR"
    echo "#!/bin/bash" > "$ENV_FILE"
    echo "export SELECTED_REPO_URL=\"$SELECTED_REPO_URL\"" >> "$ENV_FILE"
    echo "export SELECTED_BRANCH=\"$SELECTED_BRANCH\"" >> "$ENV_FILE"
    echo "export PACKAGE_NAMES=\"$PACKAGE_NAMES\"" >> "$ENV_FILE"
    echo "export EXTRA_DEPS=\"$EXTRA_DEPS\"" >> "$ENV_FILE"
    chmod +x "$ENV_FILE"
}

# 加载环境变量
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
}

# 字符串分割函数
split_string() {
    local input="$1"
    local delimiter="$2"
    echo "$input" | sed "s/$delimiter/\n/g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
}

# 步骤1: 设置编译环境
setup_environment() {
    # 在设置环境前先创建构建目录
    sudo mkdir -p "$BUILD_DIR" || handle_error "创建构建目录失败"
    sudo chown -R $USER:$USER "$BUILD_DIR" || handle_error "修改目录所有者失败"
    sudo chmod -R 755 "$BUILD_DIR" || handle_error "修改目录权限失败"
    
    # 创建日志文件
    touch "$LOG_FILE"
    sudo chown $USER:$USER "$LOG_FILE"
    
    log "=== 安装编译依赖包 ==="
    sudo apt-get update || handle_error "apt-get update失败"
    
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
        ccache python3-pip python3-venv || handle_error "安装依赖包失败"
        
    log "✅ 编译环境设置完成"
}

# 步骤2: 创建构建目录
create_build_dir() {
    log "=== 创建构建目录 ==="
    sudo chown -R $USER:$USER "$BUILD_DIR" || handle_error "修改目录所有者失败"
    sudo chmod -R 755 "$BUILD_DIR" || handle_error "修改目录权限失败"
    log "✅ 构建目录准备完成"
}

# 步骤3: 初始化构建环境
initialize_build_env() {
    local version_selection="$1"
    
    cd "$BUILD_DIR" || handle_error "进入构建目录失败"
    
    # 版本选择 - 修复：使用更稳定的分支
    log "=== 版本选择 ==="
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_REPO_URL="https://github.com/openwrt/openwrt.git"
        SELECTED_BRANCH="v23.05.2"
    else
        SELECTED_REPO_URL="https://github.com/openwrt/openwrt.git"
        SELECTED_BRANCH="v21.02.7"
    fi
    log "✅ 版本选择完成: $SELECTED_BRANCH"
    
    # 保存环境变量
    save_env
    
    # 设置GitHub环境变量
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> "$GITHUB_ENV"
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> "$GITHUB_ENV"
    
    # 克隆源码 - 修复：增加重试和深度
    log "=== 克隆源码 ==="
    log "仓库: $SELECTED_REPO_URL"
    log "分支: $SELECTED_BRANCH"
    
    # 清理目录
    sudo rm -rf ./* ./.git* 2>/dev/null || true
    
    # 克隆源码，增加重试机制
    for i in {1..3}; do
        log "尝试第 $i 次克隆..."
        if git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" .; then
            log "✅ 源码克隆完成"
            break
        elif [ $i -eq 3 ]; then
            handle_error "克隆源码失败，已尝试3次"
        else
            sleep 10
        fi
    done
    
    log "✅ 源码克隆完成"
}

# 步骤4: 配置Feeds
configure_feeds() {
    load_env
    cd "$BUILD_DIR" || handle_error "进入构建目录失败"
    
    log "=== 配置Feeds ==="
    
    # 更新和安装所有 feeds
    log "=== 更新Feeds ==="
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    log "✅ Feeds配置完成"
}

# 步骤5: 编译前空间检查
pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    df -h
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log "/mnt 可用空间: ${AVAILABLE_GB}G"
    if [ $AVAILABLE_GB -lt 10 ]; then
        log "⚠️ 警告: 可用空间不足10G，编译可能失败"
    fi
}

# 步骤6: 生成IPK配置
generate_config() {
    local package_names="$1"
    local extra_deps="$2"
    load_env
    cd "$BUILD_DIR" || handle_error "进入构建目录失败"
    
    log "=== 生成IPK配置 ==="
    log "包名: $package_names"
    log "版本: $SELECTED_BRANCH"
    log "额外依赖: $extra_deps"
    
    PACKAGE_NAMES="$package_names"
    EXTRA_DEPS="$extra_deps"
    save_env
    
    rm -f .config .config.old
    
    # 创建基础配置 - 修复：简化配置，只包含必要内容
    echo "CONFIG_TARGET_x86=y" > .config
    echo "CONFIG_TARGET_x86_64=y" >> .config
    echo "CONFIG_TARGET_x86_64_DEVICE_generic=y" >> .config
    
    # 基础工具链
    echo "CONFIG_TOOLCHAIN=y" >> .config
    echo "CONFIG_TOOLCHAIN_BUILD=y" >> .config
    
    # 基础系统
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
    
    # Luci基础
    echo "CONFIG_PACKAGE_luci=y" >> .config
    echo "CONFIG_PACKAGE_luci-base=y" >> .config
    echo "CONFIG_PACKAGE_luci-lib-base=y" >> .config
    echo "CONFIG_PACKAGE_luci-lib-ip=y" >> .config
    echo "CONFIG_PACKAGE_luci-lib-jsonc=y" >> .config
    echo "CONFIG_PACKAGE_luci-lib-nixio=y" >> .config
    echo "CONFIG_PACKAGE_luci-mod-admin-full=y" >> .config
    echo "CONFIG_PACKAGE_luci-theme-bootstrap=y" >> .config
    echo "CONFIG_PACKAGE_luci-compat=y" >> .config
    
    # 中文支持
    echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config

    # 添加要编译的包 - 支持多个包
    log "=== 添加目标包 ==="
    IFS=$'\n' read -d '' -ra PACKAGE_ARRAY <<< "$(split_string "$package_names" "、")"
    for package in "${PACKAGE_ARRAY[@]}"; do
        local pkg_clean=$(echo "$package" | xargs)
        if [ -n "$pkg_clean" ]; then
            echo "CONFIG_PACKAGE_${pkg_clean}=y" >> .config
            color_green "  ✅ 添加包: $pkg_clean"
        fi
    done
    
    # 添加额外依赖
    if [ -n "$EXTRA_DEPS" ]; then
        log "=== 添加额外依赖 ==="
        IFS=$'\n' read -d '' -ra DEPS_ARRAY <<< "$(split_string "$EXTRA_DEPS" "、")"
        for dep in "${DEPS_ARRAY[@]}"; do
            local dep_clean=$(echo "$dep" | xargs)
            if [ -n "$dep_clean" ]; then
                echo "CONFIG_PACKAGE_${dep_clean}=y" >> .config
                color_blue "  🔧 添加依赖: $dep_clean"
            fi
        done
    fi
    
    log "✅ IPK配置生成完成"
}

# 步骤7: 应用配置
apply_config() {
    load_env
    cd "$BUILD_DIR" || handle_error "进入构建目录失败"
    
    log "=== 应用配置 ==="
    
    # 显示启用的包 - 使用绿色显示
    log "=== 已启用的包列表 ==="
    grep "^CONFIG_PACKAGE_.*=y$" .config | while read line; do
        local pkg_name=$(echo "$line" | sed 's/CONFIG_PACKAGE_\(.*\)=y/\1/')
        color_green "  ✅ $pkg_name"
    done
    
    # 显示目标包状态
    IFS=$'\n' read -d '' -ra PACKAGE_ARRAY <<< "$(split_string "$PACKAGE_NAMES" "、")"
    for package in "${PACKAGE_ARRAY[@]}"; do
        local pkg_clean=$(echo "$package" | xargs)
        if grep -q "CONFIG_PACKAGE_${pkg_clean}=y" .config; then
            color_green "✅ 目标包已启用: $pkg_clean"
        else
            color_red "❌ 目标包未启用: $pkg_clean"
            handle_error "目标包配置失败"
        fi
    done
    
    make defconfig || handle_error "应用配置失败"
    
    log "✅ 配置应用完成"
}

# 步骤8: 修复网络环境
fix_network() {
    cd "$BUILD_DIR" || handle_error "进入构建目录失败"
    
    log "=== 修复网络环境 ==="
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    
    # 修复：设置下载重试
    echo "RETRIES=5" >> $BUILD_DIR/include/download.mk
    echo "DOWNLOAD_RETRIES=5" >> $BUILD_DIR/include/download.mk
    
    log "✅ 网络环境修复完成"
}

# 步骤9: 下载依赖包
download_dependencies() {
    cd "$BUILD_DIR" || handle_error "进入构建目录失败"
    
    log "=== 下载依赖包 ==="
    # 修复：增加重试次数
    for i in {1..3}; do
        log "第 $i 次尝试下载依赖..."
        if make -j1 download DOWNLOAD_RETRIES=3; then
            log "✅ 依赖包下载完成"
            break
        elif [ $i -eq 3 ]; then
            log "⚠️ 下载依赖包有错误，但继续编译过程"
            break
        else
            sleep 10
        fi
    done
}

# 步骤10: 编译IPK包
build_ipk() {
    local package_names="$1"
    local clean_build="$2"
    load_env
    cd "$BUILD_DIR" || handle_error "进入构建目录失败"
    
    log "=== 编译IPK包 ==="
    log "包名: $package_names"
    log "清理编译: $clean_build"
    
    # 解析包名数组
    IFS=$'\n' read -d '' -ra PACKAGE_ARRAY <<< "$(split_string "$package_names" "、")"
    
    # 如果要求清理编译，先清理相关包
    if [ "$clean_build" = "true" ]; then
        log "🧹 清理包构建..."
        for package in "${PACKAGE_ARRAY[@]}"; do
            local pkg_clean=$(echo "$package" | xargs)
            make package/${pkg_clean}/clean 2>/dev/null || log "⚠️ 清理包 $pkg_clean 失败，继续编译"
        done
    fi
    
    # 修复：先编译工具链和必要组件
    log "🔧 编译工具链和基础组件..."
    if ! make -j$(nproc) tools/compile toolchain/compile V=s 2>&1 | tee -a "$LOG_FILE"; then
        log "⚠️ 工具链编译有错误，但继续尝试编译目标包"
    fi
    
    # 创建输出目录
    mkdir -p "$BUILD_DIR/ipk_output"
    
    # 编译每个包
    local total_packages=${#PACKAGE_ARRAY[@]}
    local success_count=0
    local fail_count=0
    
    for ((i=0; i<${#PACKAGE_ARRAY[@]}; i++)); do
        local package="${PACKAGE_ARRAY[$i]}"
        local pkg_clean=$(echo "$package" | xargs)
        
        log "📦 编译包 [$((i+1))/$total_packages]: $pkg_clean"
        
        local build_exit_code=0
        if ! make -j$(nproc) package/${pkg_clean}/compile V=s 2>&1 | tee -a "$LOG_FILE"; then
            build_exit_code=${PIPESTATUS[0]}
            log "⚠️ 包 $pkg_clean 编译过程有错误"
            ((fail_count++))
        else
            ((success_count++))
        fi
        
        # 查找生成的IPK文件
        log "=== 查找包 $pkg_clean 的IPK文件 ==="
        local ipk_found=0
        
        # 搜索所有可能的IPK文件路径
        local search_paths=(
            "bin/packages/*/*/${pkg_clean}*.ipk"
            "bin/targets/*/*/packages/${pkg_clean}*.ipk"
            "build_dir/*/ipkg-*/${pkg_clean}*.ipk"
        )
        
        for search_path in "${search_paths[@]}"; do
            for ipk_file in $search_path; do
                if [ -f "$ipk_file" ]; then
                    log "✅ 找到IPK文件: $ipk_file"
                    cp "$ipk_file" "$BUILD_DIR/ipk_output/"
                    ipk_found=1
                fi
            done
        done
        
        # 如果没找到，尝试深度搜索
        if [ $ipk_found -eq 0 ]; then
            log "🔍 深度搜索 $pkg_clean 的IPK文件..."
            find "$BUILD_DIR" -name "*${pkg_clean}*.ipk" -type f 2>/dev/null | while read ipk_file; do
                log "✅ 找到IPK文件: $ipk_file"
                cp "$ipk_file" "$BUILD_DIR/ipk_output/"
                ipk_found=1
            done
        fi
        
        if [ $ipk_found -eq 1 ]; then
            color_green "✅ 包 $pkg_clean 编译成功！"
        else
            color_red "❌ 未找到包 $pkg_clean 的IPK文件"
        fi
        
        log "---"
    done
    
    # 总结编译结果
    log "=== 编译总结 ==="
    color_green "✅ 成功编译: $success_count/$total_packages 个包"
    if [ $fail_count -gt 0 ]; then
        color_red "❌ 编译失败: $fail_count/$total_packages 个包"
    fi
    
    # 检查最终输出
    if [ $success_count -gt 0 ]; then
        color_green "🎉 编译完成！成功生成 $success_count 个IPK包"
        log "📦 生成的IPK文件:"
        ls -la "$BUILD_DIR/ipk_output/" 2>/dev/null || log "输出目录为空"
        
        # 创建文件列表
        find "$BUILD_DIR/ipk_output" -name "*.ipk" -type f > "$BUILD_DIR/ipk_output/file_list.txt" 2>/dev/null || true
    else
        color_red "❌ 所有包编译失败"
        log "💡 调试信息:"
        log "构建目录内容:"
        ls -la "$BUILD_DIR/bin/" 2>/dev/null || log "bin目录不存在"
        handle_error "所有IPK文件生成失败 - 请检查包名是否正确或查看完整日志"
    fi
    
    log "✅ IPK包编译完成"
}

# 步骤11: 创建安装脚本
create_install_script() {
    load_env
    cd "$BUILD_DIR" || handle_error "进入构建目录失败"
    
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
    local ipk_files=$(find . -name "*.ipk" -type f)
    
    if [ -z "$ipk_files" ]; then
        echo "❌ 未找到任何IPK文件"
        exit 1
    fi
    
    echo "找到以下IPK文件:"
    echo "$ipk_files" | while read file; do
        echo "  - $(basename "$file")"
    done
    
    # 安装依赖
    echo "检查依赖..."
    opkg update
    
    # 安装所有包
    for ipk_file in $ipk_files; do
        echo "安装: $(basename "$ipk_file")"
        if opkg install "$ipk_file"; then
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
        exit 1
    fi
    
    # 获取架构
    ARCH=$(opkg print-architecture | awk '{print $2}')
    echo "系统架构: $ARCH"
    
    # 安装依赖
    echo "检查依赖..."
    opkg update
    
    # 安装每个包
    for package_name in "${packages[@]}"; do
        echo "=== 安装包: $package_name ==="
        
        # 查找匹配的IPK文件
        IPK_FILE=$(find . -name "*${package_name}*.ipk" | head -1)
        
        if [ -z "$IPK_FILE" ]; then
            echo "❌ 未找到包 $package_name 的IPK文件"
            echo "当前目录下的IPK文件:"
            find . -name "*.ipk" | while read file; do
                echo "  - $(basename "$file")"
            done
            continue
        fi
        
        echo "找到IPK文件: $(basename "$IPK_FILE")"
        
        # 尝试安装IPK
        if opkg install "$IPK_FILE"; then
            echo "✅ $package_name 安装成功！"
            
            # 检查是否真的安装成功
            if opkg list-installed | grep -q "$package_name"; then
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

    chmod +x "$BUILD_DIR/ipk_output/install_package.sh"
    
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

## 注意事项
1. 确保路由器有足够的空间
2. 安装前建议备份配置
3. 某些包可能需要特定依赖

## 多包编译说明
支持同时编译多个IPK包，包名之间用顿号分隔。

示例：
- \`luci-app-filetransfer\`
- \`luci-app-filetransfer、luci-app-turboacc、luci-app-upnp\`

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

# 步骤12: 清理目录
cleanup() {
    log "=== 清理构建目录 ==="
    # 只清理构建文件，保留输出
    cd "$BUILD_DIR" && sudo rm -rf build_dir staging_dir tmp .config* 2>/dev/null || true
    log "✅ 构建中间文件已清理"
}

# 主函数
main() {
    case $1 in
        "setup_environment")
            setup_environment
            ;;
        "create_build_dir")
            create_build_dir
            ;;
        "initialize_build_env")
            initialize_build_env "$2"
            ;;
        "configure_feeds")
            configure_feeds
            ;;
        "pre_build_space_check")
            pre_build_space_check
            ;;
        "generate_config")
            generate_config "$2" "$3"
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
            build_ipk "$2" "$3"
            ;;
        "create_install_script")
            create_install_script
            ;;
        "cleanup")
            cleanup
            ;;
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  setup_environment, create_build_dir, initialize_build_env"
            echo "  configure_feeds, pre_build_space_check, generate_config"
            echo "  apply_config, fix_network, download_dependencies, build_ipk"
            echo "  create_install_script, cleanup"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
