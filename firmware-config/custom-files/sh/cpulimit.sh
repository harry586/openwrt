#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# cpulimit CPU限制配置脚本（限制vsftpd CPU使用率）
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

echo "开始配置cpulimit CPU限制..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/init.d"
    mkdir -p "${prefix}/usr/bin"
}

create_dirs "$INSTALL_DIR"

# ==================== 创建cpulimit配置文件 ====================
create_cpulimit_config() {
    local prefix="$1"
    cat > "${prefix}/etc/config/cpulimit" << 'EOF'
config cpulimit
    option enabled '1'
    option limit '70'
    option exename 'vsftpd'
    option pidfile '/var/run/vsftpd.pid'
EOF
}

# ==================== 创建cpulimit监控脚本 ====================
create_cpulimit_script() {
    local prefix="$1"
    cat > "${prefix}/usr/bin/cpulimit_monitor.sh" << 'EOF'
#!/bin/sh
# =============================================
# cpulimit 监控脚本 - 自动限制指定进程的CPU使用率
# =============================================

CONFIG_FILE="/etc/config/cpulimit"
CPULIMIT_BIN="/usr/bin/cpulimit"

# 读取配置文件
get_config() {
    local opt="$1"
    grep -E "^\\s*option\\s+${opt}\\s+" "$CONFIG_FILE" | sed -E "s/.*'([^']*)'.*/\\1/"
}

# 检查cpulimit是否安装
if [ ! -x "$CPULIMIT_BIN" ]; then
    echo "错误: cpulimit 未安装，请先安装: opkg install cpulimit"
    exit 1
fi

# 读取配置
ENABLED=$(get_config "enabled")
LIMIT=$(get_config "limit")
EXENAME=$(get_config "exename")
PIDFILE=$(get_config "pidfile")

# 检查是否启用
if [ "$ENABLED" != "1" ]; then
    echo "cpulimit 未启用"
    exit 0
fi

# 检查必要参数
if [ -z "$LIMIT" ] || [ -z "$EXENAME" ]; then
    echo "错误: 配置不完整，缺少 limit 或 exename"
    exit 1
fi

echo "启动 cpulimit 监控: 进程=$EXENAME, CPU限制=${LIMIT}%"

# 主循环：持续监控并限制进程
while true; do
    # 查找目标进程的PID
    PIDS=$(pgrep -x "$EXENAME" 2>/dev/null)
    
    if [ -n "$PIDS" ]; then
        for PID in $PIDS; do
            # 检查该进程是否已经被限制
            if ! $CPULIMIT_BIN -l "$LIMIT" -p "$PID" -q -z 2>/dev/null; then
                # 启动cpulimit限制该进程
                $CPULIMIT_BIN -l "$LIMIT" -p "$PID" -b 2>/dev/null
                echo "已限制进程 $EXENAME (PID: $PID) CPU使用率为 ${LIMIT}%"
            fi
        done
    fi
    
    # 等待5秒后再次检查
    sleep 5
done
EOF
    chmod +x "${prefix}/usr/bin/cpulimit_monitor.sh"
}

# ==================== 创建init.d启动脚本 ====================
create_init_script() {
    local prefix="$1"
    cat > "${prefix}/etc/init.d/cpulimit" << 'EOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1
PROG=/usr/bin/cpulimit_monitor.sh

start_service() {
    echo "启动 cpulimit 监控服务..."
    procd_open_instance
    procd_set_param command "$PROG"
    procd_set_param respawn
    procd_close_instance
}

stop_service() {
    echo "停止 cpulimit 监控服务..."
    # 杀死 cpulimit 监控脚本
    killall cpulimit_monitor.sh 2>/dev/null
    # 杀死所有 cpulimit 进程
    killall cpulimit 2>/dev/null
}

reload_service() {
    stop_service
    start_service
}
EOF
    chmod +x "${prefix}/etc/init.d/cpulimit"
}

# ==================== 创建luci界面配置文件（可选） ====================
create_luci_config() {
    local prefix="$1"
    # 创建luci配置目录
    mkdir -p "${prefix}/etc/config"
    # 配置已经在上面的 create_cpulimit_config 中创建
}

# ==================== 运行时安装 ====================
if [ "$RUNTIME_MODE" = "true" ]; then
    echo "运行时模式：安装 cpulimit 配置..."
    
    # 创建配置文件
    create_cpulimit_config ""
    create_cpulimit_script ""
    create_init_script ""
    
    # 检查是否安装了 cpulimit
    if ! command -v cpulimit >/dev/null 2>&1; then
        echo "警告: cpulimit 未安装，请运行以下命令安装:"
        echo "  opkg update && opkg install cpulimit"
    else
        # 启用并启动服务
        /etc/init.d/cpulimit enable 2>/dev/null
        /etc/init.d/cpulimit stop 2>/dev/null
        /etc/init.d/cpulimit start 2>/dev/null
        echo "✓ cpulimit 服务已启动"
    fi
    
    echo "✓ cpulimit 配置已应用"
    
# ==================== 编译集成模式 ====================
else
    echo "编译模式：集成 cpulimit 配置到固件..."
    
    create_cpulimit_config "files"
    create_cpulimit_script "files"
    create_init_script "files"
    
    echo "✓ cpulimit 配置已集成到固件"
    echo "  注意：编译固件时请确保包含 cpulimit 包"
    echo "  在 OpenWrt 配置中添加: cpulimit"
fi

echo ""
echo "=== cpulimit 配置完成 ==="
echo ""
echo "配置摘要:"
echo "  目标进程: vsftpd"
echo "  CPU限制: 70%"
echo "  配置文件: /etc/config/cpulimit"
echo "  监控脚本: /usr/bin/cpulimit_monitor.sh"
echo "  服务脚本: /etc/init.d/cpulimit"
echo ""
echo "常用命令:"
echo "  启动服务: /etc/init.d/cpulimit start"
echo "  停止服务: /etc/init.d/cpulimit stop"
echo "  重启服务: /etc/init.d/cpulimit restart"
echo "  查看状态: ps | grep cpulimit"
echo ""
echo "手动限制CPU命令:"
echo "  cpulimit -l 70 -p \$(pgrep vsftpd) -b"
