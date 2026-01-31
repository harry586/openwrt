#!/bin/bash
# firmware-config/scripts/sync-device-list.sh
# 自动同步 support.sh 中的设备列表到 workflow.yml（无临时文件版本）

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

# 读取 support.sh 中的设备列表
echo "📖 读取 $SUPPORT_FILE..."
# 使用source的替代方法避免污染当前shell
{
    # 读取并定义函数
    get_all_devices() {
        grep -A 10 "get_all_devices()" "$SUPPORT_FILE" | 
        grep "echo \"" | 
        sed 's/echo "\(.*\)"/\1/'
    }
    
    # 获取设备列表
    DEVICES=$(get_all_devices)
    if [ -z "$DEVICES" ]; then
        # 备用方法：直接提取函数内容
        DEVICES=$(awk '/get_all_devices\(\)/,/^}/' "$SUPPORT_FILE" | 
                 grep 'echo "' | 
                 head -1 | 
                 sed 's/.*echo "\(.*\)".*/\1/')
    fi
} 2>/dev/null

if [ -z "$DEVICES" ]; then
    echo "❌ 错误: 无法从 support.sh 中读取设备列表"
    exit 1
fi

echo "📱 支持的设备: $DEVICES"

# 转换为数组
IFS=' ' read -ra DEVICE_ARRAY <<< "$DEVICES"

# 构建sed命令的模式空间内容
echo "🔄 构建设备选项..."
SED_COMMAND="/device_name:/,/^[[:space:]]*[^[:space:]#-]/ {"

# 添加options行的处理
SED_COMMAND+="
    /options:/ {
        :start_options
        n
        /^[[:space:]]*- \"/ {
            b start_options
        }
        :insert_options
    }
"

# 为每个设备添加插入命令
for device in "${DEVICE_ARRAY[@]}"; do
    SED_COMMAND+="
        i\\
          - \"$device\"
    "
done

SED_COMMAND+="
        b insert_options
    }
}"

# 使用awk直接处理，不生成中间文件
echo "✏️ 直接更新 $WORKFLOW_FILE..."
{
    awk -v devices="${DEVICE_ARRAY[*]}" '
    BEGIN {
        split(devices, device_list, " ")
        device_count = length(device_list)
    }
    
    /device_name:/ {
        in_device_block = 1
        print $0
        next
    }
    
    in_device_block && /options:/ {
        print $0
        in_options = 1
        for (i = 1; i <= device_count; i++) {
            printf "          - \"%s\"\n", device_list[i]
        }
        next
    }
    
    in_options && /^[[:space:]]*- "/ {
        # 跳过旧的设备行
        next
    }
    
    in_device_block && !/^[[:space:]]/ && $0 !~ /^[[:space:]]*#/ && NF > 0 {
        # 退出device_name块
        in_device_block = 0
        in_options = 0
        print $0
        next
    }
    
    {
        print $0
    }
    ' "$WORKFLOW_FILE" > "${WORKFLOW_FILE}.new"
    
    # 直接替换原文件
    if [ -s "${WORKFLOW_FILE}.new" ]; then
        mv "${WORKFLOW_FILE}.new" "$WORKFLOW_FILE"
        echo "✅ 文件更新成功"
    else
        echo "❌ 生成的文件为空，保持原文件不变"
        rm -f "${WORKFLOW_FILE}.new"
        exit 1
    fi
}

echo "✅ 同步成功！"
echo "📋 更新后的设备选项:"
for device in "${DEVICE_ARRAY[@]}"; do
    echo "          - \"$device\""
done
echo ""
echo "📊 同步统计:"
echo "  - 支持设备数量: ${#DEVICE_ARRAY[@]} 个"
echo "  - 更新方式: 直接内存处理+原子替换"
echo ""

# 验证同步是否成功（直接内存比较）
echo "🔍 验证同步结果..."
{
    # 从workflow.yml中读取实际的设备列表
    WORKFLOW_DEVICES=$(awk '
    /device_name:/ { in_block=1 }
    in_block && /options:/ { in_options=1; next }
    in_options && /^[[:space:]]*- "/ {
        match($0, /- "([^"]+)"/, arr)
        if (arr[1]) devices = devices " " arr[1]
        next
    }
    in_block && !/^[[:space:]]/ && $0 !~ /^[[:space:]]*#/ && NF > 0 {
        exit
    }
    END {
        sub(/^ /, "", devices)
        print devices
    }
    ' "$WORKFLOW_FILE")
}

# 标准化比较
SUPPORT_SORTED=$(echo "$DEVICES" | tr ' ' '\n' | sort | xargs)
WORKFLOW_SORTED=$(echo "$WORKFLOW_DEVICES" | tr ' ' '\n' | sort | xargs)

if [ "$SUPPORT_SORTED" = "$WORKFLOW_SORTED" ]; then
    echo "🎉 验证通过：设备列表完全同步！"
else
    echo "❌ 同步验证失败"
    echo "  support.sh: $SUPPORT_SORTED"
    echo "  workflow.yml: $WORKFLOW_SORTED"
    echo ""
    
    # 计算差异但不生成文件
    echo "📊 差异分析:"
    echo "  只在 support.sh 中:"
    for device in $DEVICES; do
        if ! echo " $WORKFLOW_DEVICES " | grep -q " $device "; then
            echo "    - $device"
        fi
    done
    
    echo ""
    echo "  只在 workflow.yml 中:"
    for device in $WORKFLOW_DEVICES; do
        if ! echo " $DEVICES " | grep -q " $device "; then
            echo "    - $device"
        fi
    done
    exit 1
fi

echo "💡 请提交更新后的 workflow.yml 文件"
