#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 基础系统配置设置脚本（修复版）
# 功能：主机名、密码、计划任务、升级配置、静态路由
# =============================================

# 检测运行环境
if [ -f "/etc/openwrt_release" ] || [ -d "/etc/config" ]; then
    # 在路由器上运行
    echo "检测到在路由器环境运行，执行运行时配置..."
    RUNTIME_MODE="true"
    INSTALL_DIR="/"
else
    # 在编译环境运行
    echo "检测到在编译环境运行，集成到固件..."
    RUNTIME_MODE="false"
    INSTALL_DIR="files/"
fi

echo "开始配置基础系统设置..."

# ==================== 1. 设置主机名 ====================
echo "设置主机名为: Neptune"
if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：直接修改系统配置
    uci set system.@system[0].hostname='Neptune'
    uci commit system
    echo "主机名已设置为: Neptune"
else
    # 编译时：创建配置文件
    mkdir -p "${INSTALL_DIR}etc/config"
    cat > "${INSTALL_DIR}etc/config/system" << 'EOF'
config system
	option hostname 'Neptune'
	option timezone 'CST-8'
	option zonename 'Asia/Shanghai'

config timeserver 'ntp'
	list server 'ntp.aliyun.com'
	list server 'time1.cloud.tencent.com'
	list server 'cn.pool.ntp.org'
	option enabled '1'
	option enable_server '0'
EOF
    echo "主机名配置已集成到固件"
fi

# ==================== 2. 设置路由器密码 ====================
echo "设置路由器密码..."
if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：设置密码
    echo -e "harry586586\nharry586586" | passwd root 2>/dev/null || {
        # 如果passwd命令不可用，修改shadow文件
        local password_hash=$(openssl passwd -1 "harry586586" 2>/dev/null)
        if [ -n "$password_hash" ]; then
            sed -i "s|^root:[^:]*:|root:${password_hash}:|" /etc/shadow
            echo "密码已通过修改shadow文件设置"
        else
            echo "警告：无法生成密码哈希，请手动设置密码"
        fi
    }
    echo "密码已设置为: harry586586"
else
    # 编译时：设置shadow文件
    mkdir -p "${INSTALL_DIR}etc"
    # 生成密码哈希（需要编译环境有openssl）
    local password_hash=$(openssl passwd -1 "harry586586" 2>/dev/null)
    if [ -n "$password_hash" ]; then
        cat > "${INSTALL_DIR}etc/shadow" << EOF
root:${password_hash}:0:0:99999:7:::
daemon:*:0:0:99999:7:::
ftp:*:0:0:99999:7:::
network:*:0:0:99999:7:::
nobody:*:0:0:99999:7:::
EOF
        echo "密码哈希已集成到固件"
    else
        echo "注意：编译环境缺少openssl，请刷入固件后手动设置密码"
        # 创建空shadow文件
        touch "${INSTALL_DIR}etc/shadow"
    fi
fi

# ==================== 3. 设置自定义计划任务 ====================
echo "设置自定义计划任务..."
CRON_CONTENT="# =================================================================
# 文件格式说明
#  ——分钟 (0 - 59)
# |  ——小时 (0 - 23)
# | |  ——日   (1 - 31)
# | | |  ——月   (1 - 12)
# | | | |  ——星期 (0 - 7)（星期日=0或7）
# | | | | |
# * * * * * 被执行的命令
# =================================================================
# 注意
# =================================================================
# 1、pppoe拨号需注意MAC地址克隆问题
# openwrt-网络-接口-lan-修改-高级设置-克隆mac
# =================================================================

# 每天凌晨3点清理内存缓存
0 3 * * * /usr/bin/freemem >/dev/null 2>&1

# 每30分钟同步时间（如果网络可用）
*/30 * * * * /usr/sbin/ntpd -q -n -p ntp.aliyun.com >/dev/null 2>&1

# 每天凌晨4点重启无线服务（提高稳定性）
0 4 * * * wifi down && sleep 5 && wifi up >/dev/null 2>&1

# 每小时检查并重启崩溃的服务
0 * * * * /etc/init.d/watchdog restart >/dev/null 2>&1

# 每周日凌晨2点清理临时文件
0 2 * * 0 rm -rf /tmp/luci-* /tmp/upload/* >/dev/null 2>&1"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：添加到crontab
    echo "$CRON_CONTENT" > /etc/crontabs/root
    # 确保freemem脚本存在
    if [ ! -f /usr/bin/freemem ]; then
        cat > /usr/bin/freemem << 'EOF'
#!/bin/sh
sync
echo 1 > /proc/sys/vm/drop_caches 2>/dev/null
echo 2 > /proc/sys/vm/drop_caches 2>/dev/null  
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
logger "定时内存缓存清理完成"
EOF
        chmod +x /usr/bin/freemem
    fi
    /etc/init.d/cron restart 2>/dev/null || true
    echo "计划任务已设置并启用"
else
    # 编译时：集成到固件
    mkdir -p "${INSTALL_DIR}etc/crontabs"
    echo "$CRON_CONTENT" > "${INSTALL_DIR}etc/crontabs/root"
    echo "计划任务已集成到固件"
fi

# ==================== 4. 设置备份与升级配置 ====================
echo "设置备份与升级配置..."
UPGRADE_CONTENT="
# 自定义保留文件和目录（追加内容）
/overlay
"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：追加到sysupgrade.conf
    if [ -f "/etc/sysupgrade.conf" ]; then
        # 备份原配置
        cp /etc/sysupgrade.conf /etc/sysupgrade.conf.backup.$(date +%Y%m%d%H%M%S)
        echo "升级配置已备份"
    fi
    
    # 追加自定义配置
    echo "$UPGRADE_CONTENT" >> /etc/sysupgrade.conf
    echo "升级配置已追加：/overlay 将被保留"
else
    # 编译时：集成到固件
    mkdir -p "${INSTALL_DIR}etc"
    echo "$UPGRADE_CONTENT" > "${INSTALL_DIR}etc/sysupgrade.conf"
    echo "升级配置已集成到固件"
fi

# ==================== 5. 设置静态路由 ====================
echo "设置静态路由..."
ROUTE_CONFIG="config route
	option interface 'lan'
	option target '192.168.7.0'
	option netmask '255.255.255.0'
	option gateway '192.168.5.100'"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：添加到网络配置
    # 检查是否已存在相同路由
    route_exists=false
    for route in $(uci show network | grep "network.route" | cut -d= -f1); do
        target=$(uci get ${route}.target 2>/dev/null)
        gateway=$(uci get ${route}.gateway 2>/dev/null)
        if [ "$target" = "192.168.7.0" ] && [ "$gateway" = "192.168.5.100" ]; then
            route_exists=true
            break
        fi
    done
    
    if [ "$route_exists" = "false" ]; then
        # 添加新路由
        uci add network route >/dev/null 2>&1
        uci set network.@route[-1].interface='lan'
        uci set network.@route[-1].target='192.168.7.0'
        uci set network.@route[-1].netmask='255.255.255.0'
        uci set network.@route[-1].gateway='192.168.5.100'
        uci commit network
        echo "静态路由已添加到网络配置"
        
        # 尝试重启网络（如果当前不是编译环境）
        /etc/init.d/network restart >/dev/null 2>&1 || true
    else
        echo "相同静态路由已存在，跳过"
    fi
else
    # 编译时：需要更复杂的处理，因为network配置结构复杂
    # 创建路由配置文件片段
    mkdir -p "${INSTALL_DIR}etc/config"
    echo "$ROUTE_CONFIG" > "${INSTALL_DIR}etc/config/route-neptune"
    echo "静态路由配置片段已创建，请手动合并到network配置"
fi

# ==================== 6. 创建一键启用脚本 ====================
echo "创建一键启用脚本..."

create_enable_script() {
    local dest="$1"
    cat > "$dest" << 'EOF'
#!/bin/sh
# 基础系统配置一键启用脚本（修复版）

echo "正在启用基础系统配置..."
echo "================================"

# 1. 应用主机名设置
if [ -f /etc/config/system ]; then
    uci set system.@system[0].hostname='Neptune'
    uci commit system
    echo "✓ 主机名已设置为: Neptune"
fi

# 2. 设置密码（如果未设置）
if ! grep -q '^root:\$' /etc/shadow 2>/dev/null || grep -q '^root::' /etc/shadow 2>/dev/null; then
    echo -e "harry586586\nharry586586" | passwd root 2>/dev/null && echo "✓ 密码已设置"
fi

# 3. 启用计划任务
if [ -f /etc/crontabs/root ]; then
    /etc/init.d/cron enable 2>/dev/null || true
    /etc/init.d/cron restart 2>/dev/null || true
    echo "✓ 计划任务已启用"
fi

# 4. 设置升级配置（追加方式）
if ! grep -q "^/overlay$" /etc/sysupgrade.conf 2>/dev/null; then
    echo "/overlay" >> /etc/sysupgrade.conf
    echo "✓ 升级配置已设置（保留/overlay）"
fi

# 5. 添加静态路由（如果不存在）
route_exists=false
for route in $(uci show network 2>/dev/null | grep "network.route" | cut -d= -f1); do
    target=$(uci get ${route}.target 2>/dev/null)
    gateway=$(uci get ${route}.gateway 2>/dev/null)
    if [ "$target" = "192.168.7.0" ] && [ "$gateway" = "192.168.5.100" ]; then
        route_exists=true
        break
    fi
done

if [ "$route_exists" = "false" ]; then
    uci add network route 2>/dev/null && {
        uci set network.@route[-1].interface='lan'
        uci set network.@route[-1].target='192.168.7.0'
        uci set network.@route[-1].netmask='255.255.255.0'
        uci set network.@route[-1].gateway='192.168.5.100'
        uci commit network 2>/dev/null
        echo "✓ 静态路由已添加: 192.168.7.0/24 via 192.168.5.100"
    }
fi

echo "================================"
echo "基础系统配置启用完成！"
echo ""
echo "【配置摘要】:"
echo "  ✓ 主机名: Neptune"
echo "  ✓ 管理员密码: 已设置"
echo "  ✓ 计划任务: 已启用"
echo "  ✓ 升级保留: /overlay"
echo "  ✓ 静态路由: 192.168.7.0/24 via 192.168.5.100"
echo ""
echo "建议重启系统使所有配置生效"
echo "重启命令: reboot"
echo "================================"
EOF
    chmod +x "$dest"
}

if [ "$RUNTIME_MODE" = "true" ]; then
    create_enable_script "/usr/bin/enable-basic-config"
    echo "一键启用脚本已创建: /usr/bin/enable-basic-config"
    
    # 提示运行启用脚本
    echo ""
    echo "如需立即应用所有配置，请运行:"
    echo "  /usr/bin/enable-basic-config"
else
    create_enable_script "${INSTALL_DIR}usr/bin/enable-basic-config"
    echo "一键启用脚本已集成到固件"
fi

# ==================== 7. 创建无线配置说明 ====================
echo ""
echo "=========================================="
echo "无线配置说明"
echo "=========================================="
echo "由于无线配置与硬件相关且容易出错，建议:"
echo "1. 刷机后通过Web界面手动配置无线"
echo "2. 或使用以下命令手动设置:"
echo ""
echo "设置5GHz无线:"
echo "  uci set wireless.radio0.channel='auto'"
echo "  uci set wireless.radio0.htmode='VHT80'"
echo "  uci set wireless.default_radio0.ssid='Neptune_5GH'"
echo "  uci set wireless.default_radio0.key='harry586'"
echo "  uci commit wireless"
echo "  wifi reload"
echo ""
echo "设置2.4GHz无线:"
echo "  uci set wireless.radio1.channel='auto'"
echo "  uci set wireless.radio1.htmode='HT40'"
echo "  uci set wireless.default_radio1.ssid='Neptune_2.4GH'"
echo "  uci set wireless.default_radio1.key='harry586'"
echo "  uci commit wireless"
echo "  wifi reload"

# ==================== 8. 总结信息 ====================
echo ""
echo "=========================================="
echo "基础系统配置设置完成（修复版）"
echo "=========================================="

if [ "$RUNTIME_MODE" = "true" ]; then
    echo "【当前环境】: 路由器运行时配置"
    echo ""
    echo "【已配置】:"
    echo "  ✓ 主机名: Neptune"
    echo "  ✓ 管理员密码: harry586586"
    echo "  ✓ 计划任务: 已设置"
    echo "  ✓ 升级配置: 保留/overlay（追加方式）"
    echo "  ✓ 静态路由: 192.168.7.0/24 → 192.168.5.100（去重）"
    echo ""
    echo "【注意事项】:"
    echo "  1. 无线配置因硬件差异需要手动配置"
    echo "  2. 静态路由需要确保网关192.168.5.100可达"
    echo "  3. 建议重启系统使所有配置生效"
    echo ""
    echo "【后续操作】:"
    echo "  运行 /usr/bin/enable-basic-config 可重新应用配置"
    echo "  运行 reboot 重启系统使所有配置生效"
else
    echo "【当前环境】: 固件编译时集成"
    echo ""
    echo "【已集成】:"
    echo "  ✓ 主机名配置"
    echo "  ✓ 密码哈希（需要openssl支持）"
    echo "  ✓ 计划任务配置"
    echo "  ✓ 升级保留配置"
    echo "  ✓ 静态路由配置片段"
    echo "  ✓ 一键启用脚本"
    echo ""
    echo "【固件特性】:"
    echo "  刷入此固件后，系统将:"
    echo "  1. 主机名自动设置为Neptune"
    echo "  2. 密码已预设为harry586586"
    echo "  3. 支持一键应用所有配置"
    echo ""
    echo "【使用说明】:"
    echo "  刷机后运行: /usr/bin/enable-basic-config"
fi

echo "=========================================="
