#!/bin/bash
# 权限修复脚本 - 一次性修复仓库文件权限

echo "========================================"
echo "🔧 OpenWrt构建权限修复脚本"
echo "========================================"

echo "修复时间: $(date)"
echo ""

# 1. 修复所有脚本权限
echo "1. 修复所有脚本权限..."
find . -name "*.sh" -type f -exec chmod +x {} \;

# 2. 修复主脚本权限
echo "2. 修复主脚本权限..."
if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    chmod +x firmware-config/scripts/build_firmware_main.sh
    echo "✅ 主脚本权限已修复"
else
    echo "⚠️ 主脚本不存在"
fi

# 3. 修复修复脚本权限
echo "3. 修复修复脚本权限..."
if [ -f "fix-build.sh" ]; then
    chmod +x fix-build.sh
    echo "✅ 修复脚本权限已修复"
else
    echo "⚠️ 修复脚本不存在"
fi

# 4. 设置Git文件权限
echo "4. 设置Git文件权限..."
git update-index --chmod=+x firmware-config/scripts/build_firmware_main.sh 2>/dev/null || true
git update-index --chmod=+x fix-build.sh 2>/dev/null || true

# 5. 创建.gitattributes文件
echo "5. 创建.gitattributes文件..."
cat > .gitattributes << 'EOF'
# 设置.sh文件为可执行
*.sh text eol=lf

# 特定文件设置权限
firmware-config/scripts/build_firmware_main.sh text eol=lf
fix-build.sh text eol=lf
EOF

echo ""
echo "✅ 权限修复完成"
echo ""
echo "请执行以下操作提交更改:"
echo "1. git add ."
echo "2. git commit -m '修复脚本权限问题'"
echo "3. git push"
echo ""
echo "========================================"
