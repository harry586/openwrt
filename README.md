# 通用 OpenWrt 固件构建器
一个基于 GitHub Actions 的通用 OpenWrt 固件自动化构建系统，支持多种设备和自定义配置。
默认密码：空
## 📁 项目结构

```
./
├── firmware-config/
│   ├── config/
│   │   ├── devices/
│   │   │   ├── ath79.config
│   │   │   ├── ipq40xx.config
│   │   │   ├── mediatek.config
│   │   │   ├── netgear_wndr3800.config
│   │   │   └── ramips.config
│   │   ├── version-specific/
│   │   │   ├── 21.02.config
│   │   │   └── 23.05.config
│   │   ├── base.config
│   │   ├── normal.config
│   │   └── usb-generic.config
│   ├── custom-files/
│   │   ├── sh/
│   │   │   ├── OverlayBackup.sh
│   │   │   ├── basic.sh
│   │   │   ├── dhcp.sh
│   │   │   ├── disk.sh
│   │   │   ├── ext4.sh
│   │   │   ├── network.sh
│   │   │   ├── samba.sh
│   │   │   ├── smartdns.sh
│   │   │   ├── sqm.sh
│   │   │   ├── vsftpd.sh
│   │   │   └── wechatpush.sh
│   │   ├── luci-app-opkg-other_1.0_all.ipk
│   │   └── 注意，自定义文件名要求（纯英文），方便复制、运行
│   └── scripts/
│       ├── build_firmware_main.sh
│       └── custom-files-install.sh
├── README.md
├── build-config.conf
├── fix.txt
└── support.sh

7 directories, 29 files
```

> 最后更新时间: 2026-02-22 07:21:07

注意，自定义文件名是英文的，方便复制、运行

```
