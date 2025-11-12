#!/bin/bash

set -e

# 配置参数
DEVICE_NAME=${1:-ac42u}
BUILD_DIR="/mnt/openwrt-build"
CONFIG_DIR="./firmware-config"
CONFIG_FILE="$CONFIG_DIR/configs/${DEVICE_NAME}_config"

echo "=== 开始构建固件 ==="
echo "设备: $DEVICE_NAME"
echo "构建目录: $BUILD_DIR"
echo "配置目录: $CONFIG_DIR"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在!"
    echo "请先运行GitHub工作流生成配置，或检查设备名称是否正确。"
    exit 1
fi

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
    # 确保源码是最新的
    git pull
fi

# 更新安装feeds
echo "=== 更新安装feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

# 使用已有的配置文件
echo "=== 使用已有的配置文件 ==="
cp $CONFIG_FILE .config

# 下载软件包
echo "=== 下载软件包 ==="
make -j8 download V=s

# 编译固件
echo "=== 开始编译固件 ==="
make -j$(nproc) V=s 2>&1 | tee build.log

echo "=== 构建完成 ==="
echo "固件文件位置: $BUILD_DIR/bin/targets/"
