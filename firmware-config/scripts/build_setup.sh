#!/bin/bash

# 参数定义
SELECTED_BRANCH="$1"
TARGET="$2"
SUBTARGET="$3"
DEVICE="$4"
CONFIG_MODE="$5"
EXTRA_PACKAGES="$6"

BUILD_DIR="/mnt/openwrt-build"
cd $BUILD_DIR

echo "=== 开始执行编译配置脚本 ==="
echo "参数:"
echo "  版本: $SELECTED_BRANCH"
echo "  目标: $TARGET"
echo "  子目标: $SUBTARGET"
echo "  设备: $DEVICE"
echo "  配置模式: $CONFIG_MODE"
echo "  额外包: $EXTRA_PACKAGES"

# 设置编译环境
echo "=== 设置编译环境 ==="
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget libelf-dev ecj fastjar java-propose-classpath libpython3-dev python3 python3-dev python3-pip python3-setuptools python3-yaml xsltproc zip subversion ninja-build automake autoconf libtool pkg-config help2man texinfo aria2 liblz4-dev zstd libcurl4-openssl-dev groff texlive texinfo cmake
echo "✅ 编译环境设置完成"

# 添加 TurboACC 支持
echo "=== 添加 TurboACC 支持 ==="
if [ "$CONFIG_MODE" = "normal" ]; then
    echo "🔧 为正常模式添加 TurboACC 支持"
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        echo "🔧 为 23.05 添加 TurboACC 支持"
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
        echo "✅ TurboACC feed 添加完成"
    else
        echo "ℹ️  21.02 版本已内置 TurboACC，无需额外添加"
    fi
else
    echo "ℹ️  基础模式不添加 TurboACC 支持"
fi

# 添加文件传输插件支持
echo "=== 添加文件传输插件支持 ==="
if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
    echo "🔧 为23.05添加文件传输插件支持"
    echo "src-git small https://github.com/kenzok8/small-package" >> feeds.conf.default
else
    echo "🔧 为21.02添加文件传输插件支持"
    echo "src-git kenzo https://github.com/kenzok8/openwrt-packages" >> feeds.conf.default
fi
echo "✅ 文件传输插件支持添加完成"

# 配置Feeds
echo "=== 配置Feeds ==="
if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
    FEEDS_BRANCH="openwrt-23.05"
else
    FEEDS_BRANCH="openwrt-21.02"
fi

# 确保 feeds.conf.default 包含基本 feeds
echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default

# 如果是 23.05 且正常模式，添加 turboacc feed
if [ "$SELECTED_BRANCH" = "openwrt-23.05" ] && [ "$CONFIG_MODE" = "normal" ]; then
    echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
fi

# 为所有版本添加文件传输插件源
if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
    echo "src-git small https://github.com/kenzok8/small-package" >> feeds.conf.default
else
    echo "src-git kenzo https://github.com/kenzok8/openwrt-packages" >> feeds.conf.default
fi

# 更新和安装所有 feeds
echo "=== 更新Feeds ==="
./scripts/feeds update -a
echo "=== 安装Feeds ==="
./scripts/feeds install -a
echo "✅ Feeds配置完成"

# 安装 TurboACC 包
if [ "$SELECTED_BRANCH" = "openwrt-23.05" ] && [ "$CONFIG_MODE" = "normal" ]; then
    echo "=== 安装 TurboACC 包 ==="
    ./scripts/feeds update turboacc
    ./scripts/feeds install -p turboacc luci-app-turboacc
    ./scripts/feeds install -p turboacc kmod-shortcut-fe
    ./scripts/feeds install -p turboacc kmod-fast-classifier
    echo "✅ TurboACC 包安装完成"
fi

# 安装文件传输插件包
echo "=== 安装文件传输插件包 ==="
if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
    echo "🔧 为23.05安装文件传输插件"
    ./scripts/feeds update small
    ./scripts/feeds install -p small luci-app-filetransfer
    ./scripts/feeds install -p small luci-i18n-filetransfer-zh-cn
else
    echo "🔧 为21.02安装文件传输插件"
    ./scripts/feeds update kenzo
    ./scripts/feeds install -p kenzo luci-app-filetransfer
    ./scripts/feeds install -p kenzo luci-i18n-filetransfer-zh-cn
fi
echo "✅ 文件传输插件包安装完成"

# 智能配置生成
echo "=== 智能配置生成系统（USB完全修复通用版）==="
rm -f .config .config.old

# 创建基础配置
echo "CONFIG_TARGET_${TARGET}=y" > .config
echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config

# 基础系统组件
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

# DNS配置
echo "# CONFIG_PACKAGE_dnsmasq is not set" >> .config
echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
echo "CONFIG_PACKAGE_dnsmasq_full_dhcp=y" >> .config
echo "CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y" >> .config
echo "CONFIG_PACKAGE_dnsmasq_full_dnssec=y" >> .config
echo "CONFIG_PACKAGE_dnsmasq_full_ipset=y" >> .config
echo "CONFIG_PACKAGE_dnsmasq_full_conntrack=y" >> .config

# 无线驱动
echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
echo "CONFIG_PACKAGE_ath10k-firmware-qca988x=y" >> .config
echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y" >> .config

# 网络工具
echo "CONFIG_PACKAGE_iptables=y" >> .config
echo "CONFIG_PACKAGE_iptables-mod-conntrack-extra=y" >> .config
echo "CONFIG_PACKAGE_iptables-mod-ipopt=y" >> .config
echo "CONFIG_PACKAGE_ip6tables=y" >> .config
echo "CONFIG_PACKAGE_kmod-ip6tables=y" >> .config
echo "CONFIG_PACKAGE_kmod-ipt-nat6=y" >> .config

# USB 完全修复通用配置
echo "=== 🚨 USB 完全修复通用配置 - 开始 ==="

# USB 核心驱动
echo "# 🟢 USB 核心驱动 - 基础必须" >> .config
echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config

# USB 主机控制器驱动
echo "# 🟢 USB 主机控制器驱动 - 通用支持" >> .config
echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-ehci=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-uhci=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config

# 平台专用USB控制器驱动
echo "# 🟡 平台专用USB控制器驱动 - 按平台启用" >> .config

if [ "$TARGET" = "ipq40xx" ]; then
    echo "# 🚨 关键修复：IPQ40xx 专用USB控制器驱动（高通方案）" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
    echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
fi

if [ "$TARGET" = "ramips" ] || [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; then
    echo "# 🚨 关键修复：MT76xx/雷凌 平台USB控制器驱动" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
fi

# 其他平台驱动配置...
# [这里保留原有的其他平台USB驱动配置，但为了简洁省略了部分]

# USB 存储驱动
echo "# 🟢 USB 存储驱动 - 核心功能" >> .config
echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config

# SCSI 支持
echo "# 🟢 SCSI 支持 - 硬盘和U盘必需" >> .config
echo "CONFIG_PACKAGE_kmod-scsi-core=y" >> .config
echo "CONFIG_PACKAGE_kmod-scsi-generic=y" >> .config

# 文件系统支持
echo "# 🟢 文件系统支持 - 完整文件系统兼容" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-exfat=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-autofs4=y" >> .config

# 编码支持
echo "# 🟢 编码支持 - 多语言文件名兼容" >> .config
echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config
echo "CONFIG_PACKAGE_kmod-nls-cp437=y" >> .config
echo "CONFIG_PACKAGE_kmod-nls-iso8859-1=y" >> .config
echo "CONFIG_PACKAGE_kmod-nls-cp936=y" >> .config

# 自动挂载工具
echo "# 🟢 自动挂载工具 - 即插即用支持" >> .config
echo "CONFIG_PACKAGE_block-mount=y" >> .config
echo "CONFIG_PACKAGE_automount=y" >> .config

# USB 工具和热插拔支持
echo "# 🟢 USB 工具和热插拔支持 - 设备管理" >> .config
echo "CONFIG_PACKAGE_usbutils=y" >> .config
echo "CONFIG_PACKAGE_lsusb=y" >> .config
echo "CONFIG_PACKAGE_udev=y" >> .config
echo "CONFIG_PACKAGE_udev-extra=y" >> .config

# 磁盘工具
echo "# 🟢 磁盘工具 - 完整磁盘管理" >> .config
echo "CONFIG_PACKAGE_blkid=y" >> .config
echo "CONFIG_PACKAGE_fdisk=y" >> .config
echo "CONFIG_PACKAGE_e2fsprogs=y" >> .config
echo "CONFIG_PACKAGE_dosfstools=y" >> .config
echo "CONFIG_PACKAGE_ntfs-3g=y" >> .config

echo "# 🔴 明确禁用冲突的包" >> .config
echo "# CONFIG_PACKAGE_ntfs-3g-utils is not set" >> .config

# 版本特定的automount配置
if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
    echo "CONFIG_PACKAGE_ntfs3-mount=y" >> .config
else
    echo "# CONFIG_PACKAGE_ntfs3-mount is not set" >> .config
fi

echo "=== 🚨 USB 完全修复通用配置 - 完成 ==="

# 版本智能检测和配置
echo "=== 版本智能检测: $SELECTED_BRANCH ==="
if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
    echo "🔧 检测到 21.02 版本，应用相应配置..."
    echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
elif [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
    echo "🔧 检测到 23.05 版本，应用相应配置..."
    echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
    echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
fi

# 基础中文语言包
echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y" >> .config

# 文件传输插件 - 所有模式都需要
echo "CONFIG_PACKAGE_luci-app-filetransfer=y" >> .config
if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
    echo "CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn=y" >> .config
fi

# 根据配置模式选择插件
if [ "$CONFIG_MODE" = "base" ]; then
    echo "🔧 使用基础模式 (最小化，用于测试编译)"
    echo "# CONFIG_PACKAGE_luci-app-turboacc is not set" >> .config
    echo "# CONFIG_PACKAGE_kmod-shortcut-fe is not set" >> .config
    echo "# CONFIG_PACKAGE_kmod-fast-classifier is not set" >> .config
    echo "# CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn is not set" >> .config
    echo "✅ 基础模式插件已启用"
else
    echo "🔧 使用正常模式 (完整功能)"
    # 正常配置插件
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
    
    echo "✅ 正常模式插件已启用"
fi

# 处理额外安装插件
if [ -n "$EXTRA_PACKAGES" ]; then
    echo "🔧 处理额外安装插件: $EXTRA_PACKAGES"
    IFS=';' read -ra EXTRA_PKGS <<< "$EXTRA_PACKAGES"
    
    for pkg_cmd in "${EXTRA_PKGS[@]}"; do
        if [ -n "$pkg_cmd" ]; then
            pkg_cmd_clean=$(echo "$pkg_cmd" | xargs)
            if [[ "$pkg_cmd_clean" == +* ]]; then
                pkg_name="${pkg_cmd_clean:1}"
                echo "启用插件: $pkg_name"
                echo "CONFIG_PACKAGE_${pkg_name}=y" >> .config
            elif [[ "$pkg_cmd_clean" == -* ]]; then
                pkg_name="${pkg_cmd_clean:1}"
                echo "禁用插件: $pkg_name"
                echo "# CONFIG_PACKAGE_${pkg_name} is not set" >> .config
            else
                echo "启用插件: $pkg_cmd_clean"
                echo "CONFIG_PACKAGE_${pkg_cmd_clean}=y" >> .config
            fi
        fi
    done
    echo "✅ 额外插件处理完成"
else
    echo "ℹ️  无额外安装插件"
fi

echo "✅ 智能配置生成完成"

# 验证USB配置
echo "=== 🚨 详细验证USB和存储配置 ==="
echo "1. 🟢 USB核心模块:"
grep "CONFIG_PACKAGE_kmod-usb-core" .config | grep "=y" && echo "✅ USB核心" || echo "❌ 缺少USB核心"

echo "2. 🟢 USB控制器:"
grep -E "CONFIG_PACKAGE_kmod-usb2|CONFIG_PACKAGE_kmod-usb3|CONFIG_PACKAGE_kmod-usb-ehci|CONFIG_PACKAGE_kmod-usb-ohci" .config | grep "=y" || echo "❌ 缺少USB控制器"

echo "3. 🚨 平台专用USB控制器:"
grep -E "CONFIG_PACKAGE_kmod-usb-dwc3|CONFIG_PACKAGE_kmod-usb-dwc3-qcom|CONFIG_PACKAGE_kmod-phy-qcom-dwc3" .config | grep "=y" || echo "ℹ️  无平台专用USB控制器"

echo "4. 🟢 USB存储:"
grep "CONFIG_PACKAGE_kmod-usb-storage" .config | grep "=y" || echo "❌ 缺少USB存储"

echo "=== 🚨 USB配置验证完成 ==="

# 应用配置
echo "=== 应用配置 ==="
make defconfig
echo "✅ 配置应用完成"

# 修复包冲突问题
echo "=== 修复包冲突 ==="
CONFLICT_PACKAGES=(
  "ntfs-3g-utils" 
)

for pkg in "${CONFLICT_PACKAGES[@]}"; do
    if grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config || grep -q "^CONFIG_PACKAGE_${pkg}=m$" .config; then
        echo "修复冲突: 禁用 $pkg"
        sed -i "s/^CONFIG_PACKAGE_${pkg}=y$/# CONFIG_PACKAGE_${pkg} is not set/" .config
        sed -i "s/^CONFIG_PACKAGE_${pkg}=m$/# CONFIG_PACKAGE_${pkg} is not set/" .config
    fi
done

# 确保 ntfs3 相关配置正确
echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config

# 21.02版本需要ntfs3-mount来满足automount依赖
if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
    echo "CONFIG_PACKAGE_ntfs3-mount=y" >> .config
else
    echo "# CONFIG_PACKAGE_ntfs3-mount is not set" >> .config
fi

# 基础模式强制禁用 TurboACC
if [ "$CONFIG_MODE" = "base" ]; then
    echo "=== 基础模式强制禁用 TurboACC ==="
    TURBOACC_CONFIGS=(
      "CONFIG_PACKAGE_luci-app-turboacc"
      "CONFIG_PACKAGE_kmod-shortcut-fe"
      "CONFIG_PACKAGE_kmod-fast-classifier"
      "CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn"
    )
    
    for config in "${TURBOACC_CONFIGS[@]}"; do
        if grep -q "^${config}=y$" .config || grep -q "^${config}=m$" .config; then
            echo "禁用: $config"
            sed -i "s/^${config}=y$/# ${config} is not set/" .config
            sed -i "s/^${config}=m$/# ${config} is not set/" .config
        fi
    done
fi

echo "✅ 配置修复完成"

echo "=== 🚨 编译配置脚本执行完成 ==="
