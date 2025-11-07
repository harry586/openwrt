# 通用 OpenWrt 固件构建器

一个基于 GitHub Actions 的通用 OpenWrt 固件自动化构建系统，支持多种设备和自定义配置。

## 📁 项目结构

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

## 🚀 快速开始

### 1. 构建现有设备固件

1. 进入 **Actions** 标签页
2. 选择 **"通用固件构建器 - 增强版"** 工作流
3. 点击 **"Run workflow"** 按钮
4. 填写构建参数：
   - **设备名称**: 输入设备标识（如：`rt-ac42u`）
   - **源码库**: 选择源码来源（immortalwrt/openwrt/lede）
   - **源码分支**: 选择分支（推荐使用 `auto` 自动选择）
   - **语言包**: 选择系统语言（中文/英文/全部）
   - **插件预设**: 选择插件组合（最小化/标准/完整/自定义）
   - **优化策略**: 选择编译优化方式（平衡/速度/稳定）

### 2. 添加新设备支持

要添加新设备，有两种方式：

#### 方式一：自动创建模板
1. 在构建时输入新的设备名称
2. 系统会自动创建配置文件模板
3. 根据实际设备修改生成的目标配置

#### 方式二：手动创建配置文件
在 `firmware-config/configs/` 目录下创建 `config_设备名称` 文件，参考现有配置。

## ⚙️ 配置说明

### 设备配置文件

设备配置文件位于 `firmware-config/configs/` 目录，命名格式为 `config_设备名称`。

配置文件包含：
- 目标设备架构配置
- 内核和根文件系统分区大小
- 基础软件包选择
- 网络和硬件驱动配置
- 排除不需要的应用程序

### 自定义功能

#### 自定义脚本
将您的脚本放入 `firmware-config/custom-features/scripts/` 目录，系统会自动执行：
- 系统优化配置
- 内存释放脚本（每天凌晨3点自动运行）
- 时区和语言设置
- 其他自定义功能

#### 预编译 IPK 包
将现成的 IPK 包放入 `firmware-config/custom-features/prebuilt-ipks/` 目录，系统会自动包含到固件中。

### 源码库配置

`firmware-config/repositories.json` 文件定义了可用的源码库：

```json
{
  "repositories": {
    "immortalwrt": {
      "url": "https://github.com/immortalwrt/immortalwrt",
      "recommended_branch": "openwrt-22.03"
    },
    "openwrt": {
      "url": "https://git.openwrt.org/openwrt/openwrt.git", 
      "recommended_branch": "openwrt-22.03"
    },
    "lede": {
      "url": "https://github.com/coolsnowwolf/lede",
      "recommended_branch": "master"
    }
  }
}
