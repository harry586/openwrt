#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 微信推送设置脚本
# =============================================

# 检测运行环境
if [ -f "/etc/openwrt_release" ] || [ -d "/etc/config" ]; then
    echo "检测到在路由器环境运行，执行运行时安装..."
    RUNTIME_MODE="true"
    INSTALL_DIR="/"
else
    echo "检测到在编译环境运行，集成到固件..."
    RUNTIME_MODE="false"
    INSTALL_DIR="files/"
fi

echo "开始配置微信推送设置..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/usr/share/wechatpush/api"
}

create_dirs "$INSTALL_DIR"

# ==================== 配置微信推送 ====================
create_wechat_config() {
    local prefix="$1"
    cat > "${prefix}/etc/config/wechatpush" << 'EOF'
config wechatpush 'config'
    option sleeptime '60'
    option debuglevel '1'
    option up_timeout '2'
    option down_timeout '10'
    option timeout_retry_count '2'
    option thread_num '3'
    option enable '1'
    option jsonpath '/usr/share/wechatpush/api/wxpusher.json'
    option wxpusher_apptoken 'AT_06eMwByPyGf7eVZFDG4b5IhQKsTZYRuQ'
    option wxpusher_uids 'UID_32a65DkPE8HVU1dHFslNNt6lCrNZ'
    list cpu_notification 'temp'
    option temperature_threshold '80'
    list login_notification 'ssh_login_failed'
    option login_max_num '3'
    option crontab_mode '1'
    list crontab_regular_time '8'
    list send_notification 'router_status'
    list send_notification 'router_temp'
    list send_notification 'client_list'
    option wxpusher_topicIds '74675'
EOF
}

create_wxpusher_json() {
    local prefix="$1"
    cat > "${prefix}/usr/share/wechatpush/api/wxpusher.json" << 'EOF'
{
    "appToken": "AT_06eMwByPyGf7eVZFDG4b5IhQKsTZYRuQ",
    "content": "路由器状态通知",
    "summary": "OpenWrt路由器",
    "contentType": 1,
    "topicIds": [74675],
    "uids": ["UID_32a65DkPE8HVU1dHFslNNt6lCrNZ"],
    "url": ""
}
EOF
}

if [ "$RUNTIME_MODE" = "true" ]; then
    create_wechat_config ""
    create_wxpusher_json ""
    
    # 重启服务
    if [ -f /etc/init.d/wechatpush ]; then
        /etc/init.d/wechatpush restart 2>/dev/null || true
    fi
    echo "✓ 微信推送配置已应用"
else
    create_wechat_config "files"
    create_wxpusher_json "files"
    echo "✓ 微信推送配置已集成到固件"
fi

echo "微信推送设置完成！"
