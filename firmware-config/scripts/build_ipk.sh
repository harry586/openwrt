#!/bin/bash
set -e

# 通用IPK编译脚本 - 支持全平台
PACKAGE_NAME="$1"
VERSION="$2"
EXTRA_DEPS="$3"
CLEAN_BUILD="$4"

BUILD_DIR="/mnt/openwrt-build-ipk"
LOG_FILE="$BUILD_DIR/build_ipk.log"

# 日志函数
log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1" | tee -a $LOG_FILE
}

# 错误处理函数
handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

# 初始化构建环境
init_build_env() {
    log "=== 初始化IPK编译环境 ==="
    
    # 清理旧目录（如果需要）
    if [ "$CLEAN_BUILD" = "true" ]; then
        log "🧹 清理旧构建目录..."
        sudo rm -rf $BUILD_DIR 2>/dev/null || true
    fi
    
    # 创建构建目录
    sudo mkdir -p $BUILD_DIR || handle_error "创建构建目录失败"
    sudo chown -R $USER:$USER $BUILD_DIR || handle_error "修改目录所有者失败"
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    # 安装依赖
    log "安装编译依赖..."
    sudo apt-get update || handle_error "apt-get update失败"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget libelf-dev ecj fastjar java-propose-classpath libpython3-dev python3 python3-pip python3-setuptools xsltproc zip subversion ninja-build automake autoconf libtool pkg-config help2man texinfo aria2 liblz4-dev zstd libcurl4-openssl-dev groff texlive texinfo cmake || handle_error "安装依赖包失败"
}

# 克隆源码
clone_source() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 克隆 $VERSION 源码 ==="
    
    if [ "$VERSION" = "23.05" ]; then
        REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        BRANCH="openwrt-23.05"
        FEEDS_BRANCH="openwrt-23.05"
    else
        REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        BRANCH="openwrt-21.02"
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    # 如果目录已存在且不是全新编译，则跳过克隆
    if [ ! -d ".git" ] || [ "$CLEAN_BUILD" = "true" ]; then
        git clone --depth 1 --branch "$BRANCH" "$REPO_URL" . || handle_error "克隆源码失败"
    else
        log "ℹ️ 使用现有源码目录"
    fi
    
    # 配置 feeds
    echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    log "✅ 源码准备完成: $VERSION"
}

# 创建最小化配置
create_minimal_config() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 创建最小化配置 ==="
    
    rm -f .config .config.old
    
    # 基础配置 - 使用通用的ramips/mt76x8平台
    echo "CONFIG_TARGET_ramips=y" > .config
    echo "CONFIG_TARGET_ramips_mt76x8=y" >> .config
    echo "CONFIG_TARGET_ramips_mt76x8_DEVICE_xiaomi_mi-router-4a-gigabit=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
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

    # 添加要编译的包
    echo "CONFIG_PACKAGE_${PACKAGE_NAME}=y" >> .config
    
    # 添加额外依赖
    if [ -n "$EXTRA_DEPS" ]; then
        IFS=',' read -ra DEPS <<< "$EXTRA_DEPS"
        for dep in "${DEPS[@]}"; do
            dep_clean=$(echo "$dep" | xargs)
            if [ -n "$dep_clean" ]; then
                echo "CONFIG_PACKAGE_${dep_clean}=y" >> .config
                log "✅ 添加依赖: $dep_clean"
            fi
        done
    fi
    
    make defconfig || handle_error "应用配置失败"
    log "✅ 最小化配置创建完成"
}

# 编译指定包
build_package() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 开始编译包: $PACKAGE_NAME ($VERSION) ==="
    
    # 下载依赖
    log "下载编译依赖..."
    make -j1 download || handle_error "下载依赖失败"
    
    # 编译指定包
    log "编译包: $PACKAGE_NAME"
    make -j$(nproc) package/${PACKAGE_NAME}/compile V=s 2>&1 | tee -a $LOG_FILE
    local build_exit_code=${PIPESTATUS[0]}
    
    if [ $build_exit_code -ne 0 ]; then
        log "⚠️ 编译过程有错误，但继续尝试提取IPK"
    fi
    
    # 查找生成的IPK文件
    log "=== 查找生成的IPK文件 ==="
    IPK_FOUND=0
    
    # 搜索所有可能的IPK文件路径
    SEARCH_PATHS=("bin/packages/*/*/${PACKAGE_NAME}*.ipk" "bin/targets/*/*/packages/${PACKAGE_NAME}*.ipk" "build_dir/target-*/*/ipkg-*/${PACKAGE_NAME}*.ipk")
    
    for search_path in "${SEARCH_PATHS[@]}"; do
        for ipk_file in $search_path; do
            if [ -f "$ipk_file" ]; then
                log "✅ 找到IPK文件: $ipk_file"
                mkdir -p $BUILD_DIR/ipk_output
                cp "$ipk_file" $BUILD_DIR/ipk_output/
                IPK_FOUND=1
            fi
        done
    done
    
    # 如果没找到，尝试深度搜索
    if [ $IPK_FOUND -eq 0 ]; then
        log "🔍 深度搜索IPK文件..."
        find $BUILD_DIR -name "*${PACKAGE_NAME}*.ipk" -type f | while read ipk_file; do
            log "✅ 找到IPK文件: $ipk_file"
            mkdir -p $BUILD_DIR/ipk_output
            cp "$ipk_file" $BUILD_DIR/ipk_output/
            IPK_FOUND=1
        done
    fi
    
    # 检查结果
    if [ $IPK_FOUND -eq 1 ]; then
        log "🎉 包 $PACKAGE_NAME 编译成功！"
        log "📦 生成的IPK文件:"
        ls -la $BUILD_DIR/ipk_output/
        
        # 创建文件列表
        find $BUILD_DIR/ipk_output -name "*.ipk" -type f > $BUILD_DIR/ipk_output/file_list.txt
    else
        log "❌ 未找到生成的IPK文件"
        log "💡 尝试编译整个包目录..."
        
        # 尝试编译整个包目录
        make -j$(nproc) package/compile V=s 2>&1 | tee -a $LOG_FILE
        
        # 再次搜索
        find $BUILD_DIR -name "*${PACKAGE_NAME}*.ipk" -type f | while read ipk_file; do
            log "✅ 找到IPK文件: $ipk_file"
            mkdir -p $BUILD_DIR/ipk_output
            cp "$ipk_file" $BUILD_DIR/ipk_output/
            IPK_FOUND=1
        done
        
        if [ $IPK_FOUND -eq 0 ]; then
            handle_error "IPK文件生成失败 - 请检查包名是否正确"
        fi
    fi
}

# 创建通用安装脚本
create_install_script() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 创建通用安装脚本 ==="
    
    # 创建安装脚本
    echo '#!/bin/bash' > $BUILD_DIR/ipk_output/install_package.sh
    echo '# 通用IPK包安装脚本' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '# 适用于全平台OpenWrt' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'set -e' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'PACKAGE_NAME="$1"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'if [ -z "$PACKAGE_NAME" ]; then' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    echo "用法: $0 <包名>"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    echo "示例: $0 luci-app-filetransfer"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    exit 1' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'fi' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'echo "=== OpenWrt IPK包安装脚本 ==="' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'echo "要安装的包: $PACKAGE_NAME"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '# 检查系统' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'if [ ! -f "/etc/openwrt_release" ]; then' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    echo "❌ 这不是OpenWrt系统"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    exit 1' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'fi' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '# 获取架构' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'ARCH=$(opkg print-architecture | awk '\''{print $2}'\'')' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'echo "系统架构: $ARCH"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '# 查找匹配的IPK文件' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'IPK_FILE=$(find . -name "*${PACKAGE_NAME}*.ipk" | head -1)' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'if [ -z "$IPK_FILE" ]; then' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    echo "❌ 未找到包 $PACKAGE_NAME 的IPK文件"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    echo "当前目录下的IPK文件:"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    find . -name "*.ipk" | while read file; do' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '        echo "  - $(basename "$file")"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    done' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    exit 1' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'fi' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'echo "找到IPK文件: $(basename "$IPK_FILE")"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '# 安装依赖（尝试自动解决）' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'echo "检查依赖..."' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'opkg update' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '# 尝试安装IPK（会自动解决依赖）' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'echo "安装包: $PACKAGE_NAME"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'if opkg install "$IPK_FILE"; then' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    echo "✅ $PACKAGE_NAME 安装成功！"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    # 检查是否真的安装成功' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    if opkg list-installed | grep -q "$PACKAGE_NAME"; then' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '        echo "🎉 包已成功安装到系统"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '        # 如果是Luci应用，提示重启服务' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '        if [[ "$PACKAGE_NAME" == luci-app-* ]]; then' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '            echo ""' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '            echo "💡 如果是Luci应用，请:"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '            echo "1. 刷新浏览器缓存"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '            echo "2. 在Luci界面中查看新功能"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '        fi' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    else' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '        echo "⚠️ 包可能未正确安装，请检查以上输出"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    fi' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'else' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    echo "❌ 安装失败，请检查依赖关系"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    echo "💡 可以尝试手动安装依赖后重试"' >> $BUILD_DIR/ipk_output/install_package.sh
    echo '    exit 1' >> $BUILD_DIR/ipk_output/install_package.sh
    echo 'fi' >> $BUILD_DIR/ipk_output/install_package.sh

    chmod +x $BUILD_DIR/ipk_output/install_package.sh
    
    # 创建使用说明
    echo '# IPK包使用说明' > $BUILD_DIR/ipk_output/README.md
    echo '' >> $BUILD_DIR/ipk_output/README.md
    echo '## 文件说明' >> $BUILD_DIR/ipk_output/README.md
    echo '- `*.ipk`: OpenWrt软件包文件' >> $BUILD_DIR/ipk_output/README.md
    echo '- `install_package.sh`: 自动安装脚本' >> $BUILD_DIR/ipk_output/README.md
    echo '- `file_list.txt`: 文件列表' >> $BUILD_DIR/ipk_output/README.md
    echo '' >> $BUILD_DIR/ipk_output/README.md
    echo '## 安装方法' >> $BUILD_DIR/ipk_output/README.md
    echo '' >> $BUILD_DIR/ipk_output/README.md
    echo '### 方法一：使用安装脚本（推荐）' >> $BUILD_DIR/ipk_output/README.md
    echo '```bash' >> $BUILD_DIR/ipk_output/README.md
    echo '# 上传整个ipk_output目录到路由器' >> $BUILD_DIR/ipk_output/README.md
    echo 'scp -r ipk_output root@192.168.1.1:/tmp/' >> $BUILD_DIR/ipk_output/README.md
    echo '' >> $BUILD_DIR/ipk_output/README.md
    echo '# 在路由器上执行' >> $BUILD_DIR/ipk_output/README.md
    echo 'ssh root@192.168.1.1' >> $BUILD_DIR/ipk_output/README.md
    echo 'cd /tmp/ipk_output' >> $BUILD_DIR/ipk_output/README.md
    echo './install_package.sh <包名>' >> $BUILD_DIR/ipk_output/README.md
    echo '```' >> $BUILD_DIR/ipk_output
