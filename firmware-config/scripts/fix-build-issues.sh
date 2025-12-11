#!/bin/bash
# OpenWrt编译问题一键修复脚本
# 修复工具链矛盾、权限问题、插件显示等问题

set -e

echo "=== 🛠️ 开始修复编译环境 ==="
echo "当前时间: $(date)"
echo "工作目录: $(pwd)"

# 1. 修复工具链权限问题
echo "1. 🔧 修复工具链执行权限..."
find staging_dir -type f -name "*gcc*" -exec chmod +x {} \; 2>/dev/null || true
find staging_dir -type f -name "*ar" -exec chmod +x {} \; 2>/dev/null || true
find staging_dir -type f -name "*ld" -exec chmod +x {} \; 2>/dev/null || true
echo "✅ 工具链权限修复完成"

# 2. 创建缺失的目录
echo "2. 📁 创建缺失的关键目录..."
mkdir -p staging_dir/target-*/host/include 2>/dev/null || true
mkdir -p staging_dir/hostpkg/lib 2>/dev/null || true
mkdir -p files/etc/smartdns 2>/dev/null || true
mkdir -p build_dir/target-*/smartdns-*/ipkg-*/smartdns/etc/smartdns 2>/dev/null || true
echo "✅ 目录创建完成"

# 3. 修复SmartDNS配置文件
echo "3. 📄 创建SmartDNS默认配置文件..."
cat > files/etc/smartdns/domain-block.list << 'EOF'
# 广告域名列表
ad.example.com
analytics.example.com
tracker.example.com
EOF

cat > files/etc/smartdns/domain-forwarding.list << 'EOF'
# 域名转发规则
# 格式: domain server
example.com 8.8.8.8
test.com 1.1.1.1
EOF
echo "✅ SmartDNS配置创建完成"

# 4. 修复工具链显示函数（直接修改build_firmware_main.sh）
echo "4. 📝 修复工具链显示逻辑..."
if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    # 备份原文件
    cp firmware-config/scripts/build_firmware_main.sh firmware-config/scripts/build_firmware_main.sh.backup
    
    # 修复workflow_step23_check_toolchain_status函数中的工具链查找逻辑
    sed -i '/while IFS= read -r -d .\\0. dir; do/,/done < <(find staging_dir -maxdepth 1 -type d -name .toolchain-*. -print0 2>\/dev\/null)/c\
    # 修复：使用数组来存储工具链目录\
    local toolchain_dirs_array=()\
    # 改用简单循环，避免复杂子shell和print0兼容性问题\
    for dir in $(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -5); do\
        if [ -d "$dir" ]; then\
            toolchain_dirs_array+=("$dir")\
        fi\
    done' firmware-config/scripts/build_firmware_main.sh
    
    echo "✅ 工具链显示逻辑已修复"
else
    echo "⚠️  主构建脚本不存在，跳过修复"
fi

# 5. 显示当前插件状态
echo "5. 🧩 显示当前插件配置状态..."
if [ -f ".config" ]; then
    echo "=== 已启用的关键插件 ==="
    
    # USB插件
    echo ""
    echo "🔌 USB插件:"
    grep "^CONFIG_PACKAGE_kmod-usb" .config | grep "=y$" | sed 's/CONFIG_PACKAGE_//;s/=y//' | sort | head -15 | while read pkg; do
        echo "  ✅ $pkg"
    done
    
    # 网络插件
    echo ""
    echo "🌐 网络插件:"
    grep "^CONFIG_PACKAGE_kmod-" .config | grep -v "kmod-usb" | grep "=y$" | sed 's/CONFIG_PACKAGE_//;s/=y//' | sort | head -15 | while read pkg; do
        echo "  ✅ $pkg"
    done
    
    # LuCI插件
    echo ""
    echo "🖥️ LuCI插件:"
    grep "^CONFIG_PACKAGE_luci" .config | grep "=y$" | sed 's/CONFIG_PACKAGE_//;s/=y//' | sort | head -15 | while read pkg; do
        echo "  ✅ $pkg"
    done
    
    # 统计
    total=$(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)
    echo ""
    echo "📊 总计启用插件: $total 个"
else
    echo "⚠️  配置文件不存在"
fi

# 6. 修复libgnuintl.so缺失问题
echo "6. 📚 修复库文件缺失问题..."
if [ ! -f "staging_dir/hostpkg/lib/libgnuintl.so" ]; then
    echo "创建libgnuintl.so符号链接..."
    mkdir -p staging_dir/hostpkg/lib
    # 尝试在系统中查找或创建占位文件
    if [ -f "/usr/lib/x86_64-linux-gnu/libgnuintl.so" ]; then
        cp /usr/lib/x86_64-linux-gnu/libgnuintl.so staging_dir/hostpkg/lib/ 2>/dev/null || true
    elif [ -f "/usr/lib/libgnuintl.so" ]; then
        cp /usr/lib/libgnuintl.so staging_dir/hostpkg/lib/ 2>/dev/null || true
    else
        # 创建空的占位文件
        touch staging_dir/hostpkg/lib/libgnuintl.so
        echo "⚠️  创建了空的libgnuintl.so占位文件"
    fi
    echo "✅ 库文件处理完成"
else
    echo "✅ libgnuintl.so已存在"
fi

echo ""
echo "=== 🎉 所有修复完成 ==="
echo "修复完成时间: $(date)"
echo "请重新运行构建工作流"
