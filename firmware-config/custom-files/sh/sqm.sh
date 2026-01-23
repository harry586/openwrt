#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# SQM QoS流量控制设置脚本
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

echo "开始配置SQM QoS流量控制..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/sqm"
}

create_dirs "$INSTALL_DIR"

# ==================== 配置SQM ====================
create_sqm_config() {
    local prefix="$1"
    cat > "${prefix}/etc/config/sqm" << 'EOF'
config queue 'eth1'
    option qdisc 'cake'
    option script 'piece_of_cake.qos'
    option debug_logging '0'
    option verbosity '2'
    option enabled '1'
    option interface 'eth0'
    option download '960000'
    option upload '96000'
    option linklayer 'ethernet'
    option overhead '0'
EOF
}

create_sqm_script() {
    local prefix="$1"
    cat > "${prefix}/etc/sqm/piece_of_cake.qos" << 'EOF'
#!/bin/sh

# SQM script for Piece of Cake QoS

. /usr/lib/sqm/functions.sh

[ -z "${SCRIPT}" ] && exit 1

if [ "$ACTION" = "stop" ]; then
    sqm_stop
    exit 0
fi

# Setup
sqm_start

# Default settings
UPLINK=${UPLINK:-96000}
DOWNLINK=${DOWNLINK:-960000}

# Apply CAKE qdisc
tc qdisc add dev $IFACE root handle 1: cake bandwidth ${UPLINK}kbit
tc qdisc add dev $IFACE ingress
tc filter add dev $IFACE parent ffff: protocol all prio 1 u32 match u32 0 0 flowid 1:1 action mirred egress redirect dev ifb4$IFACE
tc qdisc add dev ifb4$IFACE root handle 1: cake bandwidth ${DOWNLINK}kbit

echo "SQM Piece of Cake configured: UPLINK=${UPLINK}kbit, DOWNLINK=${DOWNLINK}kbit"
EOF
    chmod +x "${prefix}/etc/sqm/piece_of_cake.qos"
}

if [ "$RUNTIME_MODE" = "true" ]; then
    create_sqm_config ""
    create_sqm_script ""
    
    # 重启服务
    if [ -f /etc/init.d/sqm ]; then
        /etc/init.d/sqm restart 2>/dev/null || true
    fi
    echo "✓ SQM配置已应用"
else
    create_sqm_config "files"
    create_sqm_script "files"
    echo "✓ SQM配置已集成到固件"
fi

echo "SQM QoS流量控制设置完成！"
