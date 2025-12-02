#!/bin/bash
# 测试工具链修复脚本

BUILD_DIR="/mnt/openwrt-build-ipk"

echo "=== 测试工具链 ==="

cd "$BUILD_DIR" 2>/dev/null || {
    echo "❌ 无法进入构建目录"
    exit 1
}

echo "1. 检查工具链目录..."
find staging_dir -name "toolchain-*" -type d 2>/dev/null | head -5

echo "2. 检查musl库文件..."
find staging_dir -name "*musl*" -type f 2>/dev/null | head -10

echo "3. 尝试修复musl库..."
TOOLCHAIN_DIR=$(find staging_dir -name "toolchain-*" -type d 2>/dev/null | head -1)
if [ -n "$TOOLCHAIN_DIR" ]; then
    echo "工具链目录: $TOOLCHAIN_DIR"
    LIB_DIR="$TOOLCHAIN_DIR/lib"
    mkdir -p "$LIB_DIR"
    
    # 创建musl库文件
    if [ ! -f "$LIB_DIR/ld-musl-x86_64.so.1" ]; then
        echo "创建musl库文件..."
        # 尝试查找现有的
        EXISTING=$(find . -name "ld-musl-*.so*" -type f 2>/dev/null | head -1)
        if [ -n "$EXISTING" ]; then
            cp "$EXISTING" "$LIB_DIR/"
            echo "✅ 复制现有文件"
        else
            # 创建符号链接
            LIBC_SO=$(find "$TOOLCHAIN_DIR" -name "libc.so" -o -name "libc.so.*" 2>/dev/null | head -1)
            if [ -n "$LIBC_SO" ]; then
                ln -sf "$LIBC_SO" "$LIB_DIR/ld-musl-x86_64.so.1"
                echo "✅ 创建符号链接"
            else
                # 创建空文件
                echo "#!/bin/bash" > "$LIB_DIR/ld-musl-x86_64.so.1"
                chmod +x "$LIB_DIR/ld-musl-x86_64.so.1"
                echo "⚠️ 创建空文件占位"
            fi
        fi
    fi
    
    echo "4. 检查修复结果..."
    ls -la "$LIB_DIR/" | grep -i musl
fi

echo "5. 测试编译简单包..."
if [ -d "feeds/luci/applications/luci-app-upnp" ]; then
    echo "尝试编译 luci-app-upnp..."
    make -j1 package/luci-app-upnp/compile 2>&1 | tail -100
else
    echo "luci-app-upnp 不存在"
fi
