#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 基础系统配置设置脚本（完整版）
# 功能：主机名、IP地址、DNS、计划任务、升级配置、静态路由
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

# ==================== 2. 设置默认IP地址为192.168.10.1 ====================
echo "设置默认LAN IP地址为: 192.168.10.1"
LAN_CONFIG="config interface 'lan'
	option type 'bridge'
	option ifname 'eth0'
	option proto 'static'
	option ipaddr '192.168.10.1'
	option netmask '255.255.255.0'
	option ip6assign '60'
	option dns '127.0.0.1'

config dhcp 'lan'
	option interface 'lan'
	option start '100'
	option limit '150'
	option leasetime '12h'
	option dhcpv4 'server'
	option dhcpv6 'server'
	option ra 'server'
	option ra_slaac '1'
	list ra_flags 'managed-config'
	list ra_flags 'other-config'"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：修改网络配置
    if uci get network.lan >/dev/null 2>&1; then
        # 备份原配置
        uci export network > /etc/config/network.backup.$(date +%Y%m%d%H%M%S)
        
        # 修改IP地址
        uci set network.lan.ipaddr='192.168.10.1'
        uci set network.lan.netmask='255.255.255.0'
        
        # 设置LAN DNS为127.0.0.1
        uci delete network.lan.dns 2>/dev/null
        uci set network.lan.dns='127.0.0.1'
        
        uci commit network
        
        # 设置WAN DNS为127.0.0.1（如果WAN接口存在）
        if uci get network.wan >/dev/null 2>&1; then
            uci delete network.wan.dns 2>/dev/null
            uci set network.wan.dns='127.0.0.1'
            uci commit network
            echo "WAN DNS已设置为: 127.0.0.1"
        fi
        
        # 修改DHCP配置
        if uci get dhcp.lan >/dev/null 2>&1; then
            uci set dhcp.lan.start='100'
            uci set dhcp.lan.limit='150'
            uci set dhcp.lan.leasetime='12h'
            uci commit dhcp
        fi
        
        echo "LAN IP地址已设置为: 192.168.10.1"
        echo "LAN DNS已设置为: 127.0.0.1"
        echo "注意：需要重启网络或重启系统才能生效"
        echo "重启网络命令: /etc/init.d/network restart"
    else
        echo "警告：未找到network.lan配置，跳过IP设置"
    fi
else
    # 编译时：创建完整的LAN配置文件
    mkdir -p "${INSTALL_DIR}etc/config"
    echo "$LAN_CONFIG" > "${INSTALL_DIR}etc/config/network-lan"
    echo "LAN IP配置已集成到固件"
    
    # 创建默认的完整network配置
    cat > "${INSTALL_DIR}etc/config/network" << 'EOF'
config interface 'loopback'
	option ifname 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option ula_prefix 'fd00:ab:cd::/48'

config interface 'lan'
	option type 'bridge'
	option ifname 'eth0'
	option proto 'static'
	option ipaddr '192.168.10.1'
	option netmask '255.255.255.0'
	option ip6assign '60'
	option dns '127.0.0.1'

config interface 'wan'
	option ifname 'eth1'
	option proto 'dhcp'
	option dns '127.0.0.1'

config interface 'wan6'
	option ifname 'eth1'
	option proto 'dhcpv6'
EOF
    echo "DNS配置已集成到固件：LAN和WAN均使用127.0.0.1"
fi

# ==================== 3. 设置自定义计划任务（追加方式） ====================
echo "设置自定义计划任务（追加方式）..."
CRON_CONTENT="# =================================================================
# OpenWrt 自定义计划任务
# =================================================================
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

# 每30分钟同步时间（如果网络可用）
*/30 * * * * /usr/sbin/ntpd -q -n -p ntp.aliyun.com >/dev/null 2>&1

# 每天凌晨4点重启无线服务（提高稳定性）
0 4 * * * wifi down && sleep 5 && wifi up >/dev/null 2>&1

# 每周日凌晨2点清理临时文件
0 2 * * 0 rm -rf /tmp/luci-* /tmp/upload/* >/dev/null 2>&1"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：追加到crontab
    if [ -f "/etc/crontabs/root" ]; then
        # 备份原配置
        cp /etc/crontabs/root /etc/crontabs/root.backup.$(date +%Y%m%d%H%M%S)
        echo "计划任务已备份"
    fi
    
    # 追加自定义配置
    echo "$CRON_CONTENT" >> /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
    echo "计划任务已追加并启用"
else
    # 编译时：集成到固件
    mkdir -p "${INSTALL_DIR}etc/crontabs"
    # 创建包含自定义计划任务的文件，实际使用时会追加到系统计划任务
    echo "$CRON_CONTENT" > "${INSTALL_DIR}etc/crontabs/custom-cron"
    echo "自定义计划任务已集成到固件，需手动追加使用"
fi

# ==================== 4. 设置备份与升级配置（追加方式） ====================
echo "设置备份与升级配置..."
UPGRADE_CONTENT="
# =================================================================
# OpenWrt 自定义升级保留配置
# =================================================================
# 自定义保留文件和目录
/overlay"

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
    # 编译时：创建路由配置文件片段
    mkdir -p "${INSTALL_DIR}etc/config"
    echo "$ROUTE_CONFIG" > "${INSTALL_DIR}etc/config/route-neptune"
    echo "静态路由配置片段已创建，请手动合并到network配置"
fi

# ==================== 6. 创建一键启用脚本（完整版） ====================
echo "创建一键启用脚本..."

create_enable_script() {
    local dest="$1"
    cat > "$dest" << 'EOF'
#!/bin/sh
# 基础系统配置一键启用脚本（完整版）

echo "正在启用基础系统配置..."
echo "================================"

# 1. 应用主机名设置
if [ -f /etc/config/system ]; then
    uci set system.@system[0].hostname='Neptune'
    uci commit system
    echo "✓ 主机名已设置为: Neptune"
fi

# 2. 设置LAN IP地址为192.168.10.1
if uci get network.lan >/dev/null 2>&1; then
    current_ip=$(uci get network.lan.ipaddr 2>/dev/null)
    if [ "$current_ip" != "192.168.10.1" ]; then
        uci set network.lan.ipaddr='192.168.10.1'
        uci set network.lan.netmask='255.255.255.0'
        
        # 设置LAN DNS为127.0.0.1
        uci delete network.lan.dns 2>/dev/null
        uci set network.lan.dns='127.0.0.1'
        
        uci commit network
        echo "✓ LAN IP地址已设置为: 192.168.10.1/24"
        echo "✓ LAN DNS已设置为: 127.0.0.1"
        echo "  注意：需要重启网络使IP更改生效"
    else
        echo "✓ LAN IP地址已经是192.168.10.1"
    fi
    
    # 设置WAN DNS为127.0.0.1
    if uci get network.wan >/dev/null 2>&1; then
        uci delete network.wan.dns 2>/dev/null
        uci set network.wan.dns='127.0.0.1'
        uci commit network
        echo "✓ WAN DNS已设置为: 127.0.0.1"
    fi
    
    # 配置DHCP
    if uci get dhcp.lan >/dev/null 2>&1; then
        uci set dhcp.lan.start='100'
        uci set dhcp.lan.limit='150'
        uci set dhcp.lan.leasetime='12h'
        uci commit dhcp
        echo "✓ DHCP服务已配置（100-250）"
    fi
fi

# 3. 追加自定义计划任务（避免重复）
if [ -f /etc/crontabs/custom-cron ]; then
    # 检查是否已经追加过
    if ! grep -q "OpenWrt 自定义计划任务" /etc/crontabs/root 2>/dev/null; then
        cat /etc/crontabs/custom-cron >> /etc/crontabs/root
        echo "✓ 自定义计划任务已追加"
    else
        echo "✓ 自定义计划任务已存在，跳过追加"
    fi
    /etc/init.d/cron enable 2>/dev/null || true
    /etc/init.d/cron restart 2>/dev/null || true
    echo "✓ 计划任务服务已启用"
fi

# 4. 追加升级配置（避免重复）
if ! grep -q "^/overlay$" /etc/sysupgrade.conf 2>/dev/null; then
    echo "/overlay" >> /etc/sysupgrade.conf
    echo "✓ 升级配置已追加（保留/overlay）"
else
    echo "✓ 升级配置已存在，跳过追加"
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
echo "  ✓ LAN IP地址: 192.168.10.1/24"
echo "  ✓ LAN DNS: 127.0.0.1（指向路由器自身）"
echo "  ✓ WAN DNS: 127.0.0.1（指向路由器自身）"
echo "  ✓ DHCP范围: 192.168.10.100-250"
echo "  ✓ 计划任务: 已追加自定义任务"
echo "  ✓ 升级保留: /overlay（追加方式）"
echo "  ✓ 静态路由: 192.168.7.0/24 via 192.168.5.100"
echo ""
echo "【重要提示】:"
echo "  IP地址更改后需要重启网络或重启系统"
echo "  重启网络命令: /etc/init.d/network restart"
echo "  重启系统命令: reboot"
echo "  访问地址: http://192.168.10.1"
echo ""
echo "【DNS配置说明】:"
echo "  DNS设置为127.0.0.1表示使用路由器自身的DNS服务"
echo "  需要确保已安装并配置dnsmasq或DNS相关服务"
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
echo ""
echo "注意：首次配置需要访问 http://192.168.10.1"

# ==================== 8. 总结信息 ====================
echo ""
echo "=========================================="
echo "基础系统配置设置完成（完整版）"
echo "=========================================="

if [ "$RUNTIME_MODE" = "true" ]; then
    echo "【当前环境】: 路由器运行时配置"
    echo ""
    echo "【已配置】:"
    echo "  ✓ 主机名: Neptune"
    echo "  ✓ LAN IP地址: 192.168.10.1/24"
    echo "  ✓ LAN DNS: 127.0.0.1"
    echo "  ✓ WAN DNS: 127.0.0.1"
    echo "  ✓ DHCP服务: 已配置（100-250）"
    echo "  ✓ 计划任务: 已追加（不覆盖原有任务）"
    echo "  ✓ 升级配置: 保留/overlay（追加方式）"
    echo "  ✓ 静态路由: 192.168.7.0/24 → 192.168.5.100（去重）"
    echo ""
    echo "【注意事项】:"
    echo "  1. IP地址更改需要重启网络或系统才能生效"
    echo "  2. DNS设置为127.0.0.1需要路由器上有DNS服务"
    echo "  3. 无线配置因硬件差异需要手动配置"
    echo "  4. 静态路由需要确保网关192.168.5.100可达"
    echo "  5. 重启后访问地址: http://192.168.10.1"
    echo ""
    echo "【网络重启命令】:"
    echo "  /etc/init.d/network restart"
    echo ""
    echo "【后续操作】:"
    echo "  运行 /usr/bin/enable-basic-config 可重新应用配置"
    echo "  运行 reboot 重启系统使所有配置生效"
else
    echo "【当前环境】: 固件编译时集成"
    echo ""
    echo "【已集成】:"
    echo "  ✓ 主机名配置"
    echo "  ✓ LAN IP地址配置（192.168.10.1）"
    echo "  ✓ LAN DNS配置（127.0.0.1）"
    echo "  ✓ WAN DNS配置（127.0.0.1）"
    echo "  ✓ DHCP服务配置"
    echo "  ✓ 自定义计划任务（需手动追加）"
    echo "  ✓ 升级保留配置"
    echo "  ✓ 静态路由配置片段"
    echo "  ✓ 一键启用脚本"
    echo ""
    echo "【固件特性】:"
    echo "  刷入此固件后，系统将:"
    echo "  1. 默认IP地址: 192.168.10.1"
    echo "  2. 主机名自动设置为Neptune"
    echo "  3. DHCP服务自动开启（100-250）"
    echo "  4. DNS指向路由器自身（127.0.0.1）"
    echo ""
    echo "【首次访问】:"
    echo "  刷机后访问: http://192.168.10.1"
    echo ""
    echo "【使用说明】:"
    echo "  刷机后运行: /usr/bin/enable-basic-config"
fi

echo "=========================================="
