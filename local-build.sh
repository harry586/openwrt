#!/bin/bash

set -e

# 配置参数
DEVICE_NAME=${1:-ac42u}
BUILD_DIR="/mnt/openwrt-build"
CONFIG_DIR="./firmware-config"

echo "=== 开始构建固件 ==="
echo "设备: $DEVICE_NAME"
echo "构建目录: $BUILD_DIR"
echo "配置目录: $CONFIG_DIR"

# 检查磁盘空间
echo "=== 检查磁盘空间 ==="
df -h
if [ ! -d "/mnt" ]; then
    echo "错误: /mnt 目录不存在!"
    exit 1
fi

AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
echo "/mnt 可用空间: ${AVAILABLE_GB}G"

if [ $AVAILABLE_GB -lt 50 ]; then
    echo "错误: /mnt 空间不足50G，当前只有 ${AVAILABLE_GB}G"
    exit 1
fi

echo "空间检查通过"

# 安装编译环境
echo "=== 安装编译环境 ==="
sudo apt-get update
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get -y install build-essential asciidoc binutils bzip2 gawk gettext git libncurses5-dev libz-dev patch python3 unzip zlib1g-dev libc6-dev-i386 subversion flex uglifyjs git-core gcc-multilib p7zip p7zip-full msmtp libssl-dev texinfo libglib2.0-dev xmlto qemu-utils upx libelf-dev autoconf automake libtool autopoint device-tree-compiler g++-multilib curl lib32gcc-s1 libc6-dev-x32 linux-libc-dev

# 创建构建目录
echo "=== 创建构建目录 ==="
sudo mkdir -p $BUILD_DIR
sudo chown -R $USER:$USER $BUILD_DIR

# 克隆源码
echo "=== 克隆源码 ==="
cd $BUILD_DIR
if [ ! -d ".git" ]; then
    git clone https://github.com/immortalwrt/immortalwrt.git .
    git checkout openwrt-21.02
else
    echo "源码已存在，跳过克隆"
fi

# 更新安装feeds
echo "=== 更新安装feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

# 生成设备配置
echo "=== 生成设备配置 ==="
case "$DEVICE_NAME" in
    "ac42u")
        PLATFORM="ipq40xx"
        DEVICE_FULL_NAME="asus_rt-ac42u"
        ;;
    *)
        echo "未知设备: $DEVICE_NAME"
        exit 1
        ;;
esac

echo "为设备 $DEVICE_NAME 生成配置，平台: $PLATFORM"

# 生成基础配置
echo "CONFIG_TARGET_${PLATFORM}=y" > .config
echo "CONFIG_TARGET_${PLATFORM}_generic=y" >> .config
echo "CONFIG_TARGET_${PLATFORM}_generic_DEVICE_${DEVICE_FULL_NAME}=y" >> .config
echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
echo "CONFIG_PACKAGE_luci=y" >> .config
echo "CONFIG_PACKAGE_luci-base=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_luci-theme-bootstrap=y" >> .config
echo "# CONFIG_PACKAGE_luci-app-accesscontrol is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-ddns is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-bandwidthd is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-wol is not set" >> .config

# 复制配置到配置目录
mkdir -p $CONFIG_DIR/configs/
cp .config $CONFIG_DIR/configs/${DEVICE_NAME}_config

# 下载软件包
echo "=== 下载软件包 ==="
make -j8 download V=s

# 编译固件
echo "=== 开始编译固件 ==="
make -j$(nproc) V=s 2>&1 | tee build.log

echo "=== 构建完成 ==="
