# arm_cortex-a7 musl 交叉编译器

## 基本信息
- 架构: arm_cortex-a7
- C库: musl
- GCC版本: 15.2.0
- Binutils版本: 2.45.1
- 编译器前缀: arm-openwrt-linux-musl-
- 构建时间: Wed Dec 17 13:18:51 UTC 2025

## 使用方法
```bash
# 设置环境变量
export STAGING_DIR="/tmp/compiler-build-arm_cortex-a7_musl_gcc-15.2.0_20251217_124848"
export PATH="$STAGING_DIR/bin:$PATH"

# 验证编译器
arm-openwrt-linux-musl-gcc --version
```
