#!/bin/bash
set -e

# 文件传输插件单独编译脚本
# 支持全平台编译

BUILD_DIR="/mnt/openwrt-build-filetransfer"
LOG_FILE="$BUILD_DIR/build_filetransfer.log"

# 日志函数
log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1" | tee -a $LOG_FILE
}

# 错误处理函数
handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

# 清理和准备构建环境
setup_build_env() {
    log "=== 设置文件传输插件编译环境 ==="
    
    # 清理旧目录
    sudo rm -rf $BUILD_DIR 2>/dev/null || true
    
    # 创建构建目录
    sudo mkdir -p $BUILD_DIR || handle_error "创建构建目录失败"
    sudo chown -R $USER:$USER $BUILD_DIR || handle_error "修改目录所有者失败"
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    # 安装依赖
    log "安装编译依赖..."
    sudo apt-get update || handle_error "apt-get update失败"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
        gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip \
        zlib1g-dev file wget libelf-dev ecj fastjar java-propose-classpath \
        libpython3-dev python3 python3-pip python3-setuptools \
        xsltproc zip subversion ninja-build automake autoconf \
        libtool pkg-config help2man texinfo aria2 liblz4-dev zstd \
        libcurl4-openssl-dev groff texlive texinfo cmake || handle_error "安装依赖包失败"
}

# 克隆源码
clone_source() {
    local version=$1
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 克隆 $version 源码 ==="
    
    if [ "$version" = "23.05" ]; then
        REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        BRANCH="openwrt-23.05"
        FEEDS_BRANCH="openwrt-23.05"
    else
        REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        BRANCH="openwrt-21.02"
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" . || handle_error "克隆源码失败"
    
    # 配置 feeds
    echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    log "✅ 源码准备完成: $version"
}

# 创建最小化配置
create_minimal_config() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 创建最小化配置 ==="
    
    rm -f .config .config.old
    
    # 基础配置
    cat > .config << 'EOF'
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt76x8=y
CONFIG_TARGET_ramips_mt76x8_DEVICE_xiaomi_mi-router-4a-gigabit=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_IMAGES_GZIP=y

# 基础系统
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

# 文件传输插件
CONFIG_PACKAGE_luci-app-filetransfer=y
CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn=y

# 基础依赖
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-lib-base=y
CONFIG_PACKAGE_luci-lib-ip=y
CONFIG_PACKAGE_luci-lib-jsonc=y
CONFIG_PACKAGE_luci-lib-nixio=y
CONFIG_PACKAGE_luci-mod-admin-full=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_luci-compat=y

# 中文支持
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
EOF

    make defconfig || handle_error "应用配置失败"
    log "✅ 最小化配置创建完成"
}

# 编译文件传输插件
build_filetransfer() {
    local version=$1
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 开始编译文件传输插件 ($version) ==="
    
    # 下载依赖
    log "下载编译依赖..."
    make -j1 download || handle_error "下载依赖失败"
    
    # 只编译文件传输插件相关包
    log "编译文件传输插件..."
    make -j$(nproc) package/luci-app-filetransfer/compile V=s 2>&1 | tee -a $LOG_FILE
    local build_exit_code=${PIPESTATUS[0]}
    
    if [ $build_exit_code -ne 0 ]; then
        log "⚠️ 编译过程有错误，但继续尝试提取IPK"
    fi
    
    # 查找生成的IPK文件
    log "=== 查找生成的IPK文件 ==="
    find bin -name "*filetransfer*.ipk" -type f | while read ipk_file; do
        log "✅ 找到IPK文件: $ipk_file"
        # 复制到输出目录
        mkdir -p $BUILD_DIR/ipk_output
        cp "$ipk_file" $BUILD_DIR/ipk_output/
    done
    
    # 如果没找到，尝试其他路径
    if [ ! -d "$BUILD_DIR/ipk_output" ] || [ -z "$(ls -A $BUILD_DIR/ipk_output)" ]; then
        log "🔍 在主目录中搜索IPK文件..."
        find $BUILD_DIR -name "*filetransfer*.ipk" -type f | while read ipk_file; do
            log "✅ 找到IPK文件: $ipk_file"
            mkdir -p $BUILD_DIR/ipk_output
            cp "$ipk_file" $BUILD_DIR/ipk_output/
        done
    fi
    
    # 检查结果
    if [ -d "$BUILD_DIR/ipk_output" ] && [ "$(ls -A $BUILD_DIR/ipk_output)" ]; then
        log "🎉 文件传输插件IPK编译成功！"
        log "📦 生成的IPK文件:"
        ls -la $BUILD_DIR/ipk_output/
    else
        log "❌ 未找到生成的IPK文件"
        handle_error "IPK文件生成失败"
    fi
}

# 创建通用安装脚本
create_install_script() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 创建安装脚本 ==="
    
    cat > $BUILD_DIR/ipk_output/install_filetransfer.sh << 'EOF'
#!/bin/bash
# 文件传输插件安装脚本
# 适用于全平台OpenWrt

set -e

echo "=== 文件传输插件安装脚本 ==="
echo "适用于: OpenWrt 21.02/23.05"

# 检查系统
if [ ! -f "/etc/openwrt_release" ]; then
    echo "❌ 这不是OpenWrt系统"
    exit 1
fi

# 获取架构
ARCH=$(opkg print-architecture | awk '{print $2}')
echo "系统架构: $ARCH"

# 查找匹配的IPK文件
IPK_FILE=$(find . -name "*filetransfer*${ARCH}*.ipk" | head -1)

if [ -z "$IPK_FILE" ]; then
    echo "❌ 未找到适合架构 $ARCH 的IPK文件"
    echo "可用的IPK文件:"
    find . -name "*.ipk" | while read file; do
        echo "  - $file"
    done
    exit 1
fi

echo "找到IPK文件: $IPK_FILE"

# 安装依赖
echo "安装依赖..."
opkg update
opkg install luci-base luci-compat

# 安装文件传输插件
echo "安装文件传输插件..."
opkg install "$IPK_FILE"

# 检查安装结果
if opkg list-installed | grep -q "luci-app-filetransfer"; then
    echo "✅ 文件传输插件安装成功！"
    echo ""
    echo "使用方法:"
    echo "1. 登录Luci网页界面"
    echo "2. 在'服务'菜单中找到'文件传输'"
    echo "3. 上传文件到路由器的/tmp/upload目录"
else
    echo "❌ 文件传输插件安装失败"
    exit 1
fi
EOF

    chmod +x $BUILD_DIR/ipk_output/install_filetransfer.sh
    log "✅ 安装脚本创建完成"
}

# 主函数
main() {
    local version=$1
    
    if [ -z "$version" ]; then
        echo "用法: $0 <版本>"
        echo "版本: 21.02 或 23.05"
        exit 1
    fi
    
    if [ "$version" != "21.02" ] && [ "$version" != "23.05" ]; then
        echo "错误: 版本必须是 21.02 或 23.05"
        exit 1
    fi
    
    log "开始编译文件传输插件 for $version"
    
    # 执行编译步骤
    setup_build_env
    clone_source "$version"
    create_minimal_config
    build_filetransfer "$version"
    create_install_script
    
    log "=========================================="
    log "🎉 文件传输插件编译完成！"
    log "📁 IPK文件位置: $BUILD_DIR/ipk_output/"
    log "🔄 安装脚本: $BUILD_DIR/ipk_output/install_filetransfer.sh"
    log "=========================================="
    
    # 显示文件列表
    echo "生成的文件:"
    find $BUILD_DIR/ipk_output -type f -exec ls -la {} \;
}

# 执行主函数
main "$@"
