# 源码压缩包目录

## 说明
此目录用于存放源码压缩包文件，支持以下格式：
- ZIP (.zip)
- TAR.GZ (.tar.gz, .tgz)
- TAR.BZ2 (.tar.bz2)

## 使用方法
1. 将源码压缩包上传到此目录
2. 在 GitHub Actions 工作流中输入文件名
3. 支持多个文件，用顿号分隔

## 文件命名规范
建议使用包名作为文件名，例如：
- `luci-app-filetransfer.zip`
- `my-custom-package.tar.gz`

## 包结构要求
源码压缩包应包含完整的 OpenWrt 包结构，至少包含：
- `Makefile` - 包编译配置
- 源代码文件
- 其他必要的配置文件

## 示例结构
