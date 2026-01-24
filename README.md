# 通用 OpenWrt 固件构建器
一个基于 GitHub Actions 的通用 OpenWrt 固件自动化构建系统，支持多种设备和自定义配置。
默认密码：空
## 📁 项目结构

```

仓库根目录/
├── .github/  #github隐藏目录
│   └── workflows/  #工作流目录
│        └── firmware-build.yml  #构建-工作流文件
├── firmware-config/  #构建相关目录
│   ├── scripts/
│   │   └── build_firmware_main.sh
│   └── custom-files/ # 自定义文件夹
│        ├── *.ipk    # 自定义IPK包（英文）
│        └── *.sh     # 自定义脚本（英文）
└── README.md			#说明文档

```
