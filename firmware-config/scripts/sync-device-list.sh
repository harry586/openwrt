#!/bin/bash
# firmware-config/scripts/sync-device-list.sh
# 自动同步 support.sh 中的设备列表到 workflow.yml

echo "🔄 开始自动同步设备列表..."

SUPPORT_FILE="firmware-config/support.sh"
WORKFLOW_FILE=".github/workflows/firmware-build.yml"

# 检查文件是否存在
if [ ! -f "$SUPPORT_FILE" ]; then
    echo "❌ 错误: 未找到 $SUPPORT_FILE"
    exit 1
fi

if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "❌ 错误: 未找到 $WORKFLOW_FILE"
    exit 1
fi

# 备份原始文件
BACKUP_FILE="${WORKFLOW_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$WORKFLOW_FILE" "$BACKUP_FILE"
echo "💾 创建备份: $BACKUP_FILE"

# 读取 support.sh 中的设备列表
echo "📖 读取 $SUPPORT_FILE..."
source "$SUPPORT_FILE"

if ! command -v get_all_devices >/dev/null 2>&1; then
    echo "❌ 错误: support.sh 中没有 get_all_devices 函数"
    exit 1
fi

DEVICES=$(get_all_devices)
echo "📱 支持的设备: $DEVICES"

# 转换为数组
IFS=' ' read -ra DEVICE_ARRAY <<< "$DEVICES"

# 生成 options 部分
echo "📝 生成设备选项..."
DEVICE_OPTIONS=""
for device in "${DEVICE_ARRAY[@]}"; do
    DEVICE_OPTIONS="${DEVICE_OPTIONS}\n          - \"${device}\""
done

# 使用 Python 更可靠地处理 YAML
echo "🔄 更新 $WORKFLOW_FILE..."
python3 << EOF
import re
import sys

with open("$WORKFLOW_FILE", 'r') as f:
    content = f.read()

# 构建新的设备选项部分
new_options = '''        options:${DEVICE_OPTIONS}'''

# 使用正则表达式替换 device_name 部分
pattern = r'(device_name:\s*\n\s*description:[^\n]*\n\s*required:[^\n]*\n\s*type:[^\n]*\n\s*default:[^\n]*\n\s*options:\s*\n)(?:\s*-\s*"[^"]*"\n)*'
replacement = r'\1' + new_options + '\n'

updated_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

# 如果正则替换失败，使用更直接的方法
if updated_content == content:
    print("⚠️ 正则替换失败，使用字符串替换方法...")
    # 找到 device_name 部分
    lines = content.split('\n')
    in_device_block = False
    in_options = False
    options_replaced = False
    result_lines = []
    
    for i, line in enumerate(lines):
        if 'device_name:' in line:
            in_device_block = True
            result_lines.append(line)
        elif in_device_block and 'options:' in line:
            in_options = True
            result_lines.append(line)
            # 添加新的设备选项
            for option_line in new_options.split('\n'):
                if option_line.strip():
                    result_lines.append(option_line)
            options_replaced = True
        elif in_options and line.strip().startswith('- "'):
            # 跳过旧的设备选项
            continue
        elif in_device_block and not line.startswith(' ') and line.strip() and not line.strip().startswith('#'):
            # 退出 device_name 块
            in_device_block = False
            in_options = False
            result_lines.append(line)
        else:
            result_lines.append(line)
    
    updated_content = '\n'.join(result_lines)
    
    if not options_replaced:
        print("❌ 无法找到 options 部分进行替换")
        sys.exit(1)

with open("$WORKFLOW_FILE", 'w') as f:
    f.write(updated_content)

print("✅ 文件更新成功")
EOF

if [ $? -eq 0 ]; then
    echo "✅ 同步成功！"
    echo "📋 更新后的设备选项:"
    for device in "${DEVICE_ARRAY[@]}"; do
        echo "          - \"$device\""
    done
    echo ""
    echo "📊 同步统计:"
    echo "  - 支持设备数量: ${#DEVICE_ARRAY[@]} 个"
    echo "  - 备份文件: $(basename $BACKUP_FILE)"
    echo ""
    echo "💡 请提交更新后的 workflow.yml 文件"
else
    echo "❌ 同步失败，恢复备份..."
    cp "$BACKUP_FILE" "$WORKFLOW_FILE"
    exit 1
fi
