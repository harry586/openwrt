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

# OpenWrt 固件构建配置说明

## 配置类型说明

### minimal (最小配置)
- **基础系统** + **必要驱动** + **基本网络功能**
- 文件系统很小，适合存储空间有限的设备
- 只包含最必要的包：`dnsmasq`, `firewall`, `luci-base`

### normal (正常配置)  
- **minimal** + **Web管理界面** + **常用功能**
- 包含完整的LUCI Web界面
- 包含IPv6支持、PPPoE等常用网络协议
- 适合大多数用户使用

### custom (自定义配置)
- **以normal为模板** + **用户自定义插件管理**
- 允许用户通过"增加插件"和"禁用插件"完全自定义
- 显示常用插件列表供参考
- 适合高级用户，知道具体需要哪些功能

## 插件管理

### 仅 custom 类型可用
- 增加插件: 输入要安装的包名，用空格分隔
- 禁用插件: 输入要禁用的包名，用空格分隔

### 常用插件示例
- 网络服务: `adblock wireguard openvpn-openssl ddns-scripts`
- 文件共享: `vsftpd samba4-server`
- 系统工具: `htop tmux screen`
- 网络工具: `iperf3 tcpdump nmap`

## 错误处理

### 常见错误及解决方案

1. **package/install Error 255**
   - 原因: 软件包依赖问题或编译冲突
   - 解决: 清理编译环境，单线程重新编译

2. **文件缺失错误**
   - 原因: 源码下载不完整
   - 解决: 重新下载源码和feeds

3. **管道错误 (Broken pipe)**
   - 原因: 并行编译的正常现象
   - 解决: 无需处理，不影响最终结果
