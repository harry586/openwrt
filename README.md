# 通用 OpenWrt 固件构建器
一个基于 GitHub Actions 的通用 OpenWrt 固件自动化构建系统，支持多种设备和自定义配置。
默认密码：password
## 📁 项目结构
  仓库根目录
```
仓库根目录/
├── .github/workflows/
│   ├── universal-build.yml             # 主构建工作流
│   └── update-configs-list.yml         # 自动更新配置文件列表
├── firmware-config/
│   ├── repositories.json               # 源码库配置
│   ├── configs-list.md                 # 配置文件列表文档
│   ├── configs/                        # 设备配置文件目录
│   │   ├── config_rt-ac42u             # ASUS RT-AC42U 配置
│   │   └── ...                         # 其他设备配置
│   └── custom-features/                # 自定义功能目录
│       ├── prebuilt-ipks/              # 预编译 IPK 包目录
│       │   └── xx.ipk                  # ✅ 您的现成IPK文件放这里
│       └── scripts/                    # 自定义脚本目录
│           ├── 01-system-optimization.sh  # 系统优化脚本
│           └── xx.sh                   # ✅ 您的自定义脚本放这里
└── README.md                           # 项目说明文档

仓库根目录/
├── .github/workflows/
│   └── firmware-build.yml
├── firmware-config/
│   ├── configs/
│   │   └── base_universal.config
│   ├── modules/
│   │   ├── storage.config
│   │   ├── network_extra.config
│   │   ├── services.config
│   │   └── management.config
│   └── scripts/
│       ├── generate_config.sh
│       └── error_analysis.sh
└── README.md

```
