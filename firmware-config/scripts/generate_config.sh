#!/bin/bash

CONFIG_TYPE=$1
PLATFORM=$2
DEVICE_FULL_NAME=$3
EXTRA_PACKAGES=$4
BUILD_DIR=$5
CONFIG_DIR=$(dirname $(dirname $0))

echo "生成配置: 类型=$CONFIG_TYPE, 平台=$PLATFORM, 设备=$DEVICE_FULL_NAME"
echo "额外插件: $EXTRA_PACKAGES"

# 复制通用基础配置
cp $CONFIG_DIR/configs/base_universal.config $BUILD_DIR/.config

# 根据配置类型添加模块
case "$CONFIG_TYPE" in
    "minimal")
        echo "使用最小配置"
        ;;
    "normal")
        echo "使用正常配置，添加所有功能模块"
        cat $CONFIG_DIR/modules/storage.config >> $BUILD_DIR/.config
        cat $CONFIG_DIR/modules/network_extra.config >> $BUILD_DIR/.config
        cat $CONFIG_DIR/modules/services.config >> $BUILD_DIR/.config
        cat $CONFIG_DIR/modules/management.config >> $BUILD_DIR/.config
        ;;
    "custom")
        echo "使用自定义配置，只添加存储和网络模块"
        cat $CONFIG_DIR/modules/storage.config >> $BUILD_DIR/.config
        cat $CONFIG_DIR/modules/network_extra.config >> $BUILD_DIR/.config
        ;;
    *)
        echo "未知配置类型: $CONFIG_TYPE"
        exit 1
        ;;
esac

# 替换平台和设备变量
sed -i "s/\\\${PLATFORM}/${PLATFORM}/g" $BUILD_DIR/.config
sed -i "s/\\\${DEVICE_FULL_NAME}/${DEVICE_FULL_NAME}/g" $BUILD_DIR/.config

# 添加额外插件
if [ -n "$EXTRA_PACKAGES" ]; then
    echo "" >> $BUILD_DIR/.config
    echo "# ===== 用户自定义额外插件 =====" >> $BUILD_DIR/.config
    for pkg in $EXTRA_PACKAGES; do
        echo "添加插件: $pkg"
        echo "CONFIG_PACKAGE_${pkg}=y" >> $BUILD_DIR/.config
    done
fi

echo "配置生成完成"
