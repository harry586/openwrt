#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 基础系统配置设置脚本
# 功能：主机名、密码、SSH密钥、计划任务、升级配置、静态路由、无线设置
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

# ==================== 3. 设置SSH密钥 ====================
echo "设置SSH密钥..."
SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAgR6/T2s7aX5w/JXCFh/X+7VWh0ovMxl8F4W0HLpIdPgnNUcfzgsvjDPCqIZ3Qws6WaWq+03or8AN06Mrh6JIa6+hV0e7DipnTyWg8khRftwxj4bSBURJ8cFg6DdpW62eoJwPu8zgTX0risI33HrZkGC3rN3pGErES5L3S5tsb24XSRRTPijzJu3Tj56bPK0i2hf2RuK5N6qOW+GiqwD1bMGVwfnwhBuozNyutBsYM6VVUf3hoEiiy4e1Z4TAyUC1YExAo+3TjCgRp6F58UgF+l2e855bqU+9IL2TFOfWnhwT2hoJ795WSdgXYg98V6ZUS+irL7Hc4GrJN1D8LQ6DGw== openwrt-15.05.1-ramips-mt7620-y1"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：创建authorized_keys文件
    mkdir -p /root/.ssh
    echo "$SSH_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    echo "SSH密钥已添加到root用户的authorized_keys"
else
    # 编译时：集成到固件
    mkdir -p "${INSTALL_DIR}root/.ssh"
    echo "$SSH_KEY" > "${INSTALL_DIR}root/.ssh/authorized_keys"
    chmod 600 "${INSTALL_DIR}root/.ssh/authorized_keys"
    chmod 700 "${INSTALL_DIR}root/.ssh"
    echo "SSH密钥已集成到固件"
fi

# ==================== 4. 设置自定义计划任务 ====================
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

# ==================== 5. 设置备份与升级配置 ====================
echo "设置备份与升级配置..."
UPGRADE_CONTENT="## This file contains files and directories that should
## be preserved during an upgrade.

# /etc/example.conf
# /etc/openvpn/

/overlay"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：修改sysupgrade.conf
    echo "$UPGRADE_CONTENT" > /etc/sysupgrade.conf
    echo "升级配置已设置：/overlay 将被保留"
else
    # 编译时：集成到固件
    mkdir -p "${INSTALL_DIR}etc"
    echo "$UPGRADE_CONTENT" > "${INSTALL_DIR}etc/sysupgrade.conf"
    echo "升级配置已集成到固件"
fi

# ==================== 6. 设置静态路由 ====================
echo "设置静态路由..."
ROUTE_CONFIG="config route
	option interface 'lan'
	option target '192.168.7.0'
	option netmask '255.255.255.0'
	option gateway '192.168.5.100'"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：添加到网络配置
    # 检查是否已存在相同路由
    if ! uci show network | grep -q "network.route.*target='192.168.7.0'"; then
        # 添加新路由
        uci add network route
        uci set network.@route[-1].interface='lan'
        uci set network.@route[-1].target='192.168.7.0'
        uci set network.@route[-1].netmask='255.255.255.0'
        uci set network.@route[-1].gateway='192.168.5.100'
        uci commit network
        echo "静态路由已添加到网络配置"
        
        # 尝试重启网络（如果当前不是编译环境）
        /etc/init.d/network restart 2>/dev/null || true
    else
        echo "相同静态路由已存在，跳过"
    fi
else
    # 编译时：需要更复杂的处理，因为network配置结构复杂
    # 创建路由配置文件片段
    mkdir -p "${INSTALL_DIR}etc/config"
    # 注意：实际network配置需要更完整的处理
    # 这里只创建路由配置片段，需要手动合并
    echo "$ROUTE_CONFIG" > "${INSTALL_DIR}etc/config/route-neptune"
    echo "静态路由配置片段已创建，请手动合并到network配置"
fi

# ==================== 7. 设置无线网络 ====================
echo "设置无线网络..."

# 创建无线配置函数
create_wireless_config() {
    local dest="$1"
    cat > "$dest" << 'EOF'
config wifi-device 'radio0'
	option type 'mac80211'
	option channel 'auto'
	option hwmode '11a'
	option path 'pci0000:00/0000:00:00.0'
	option htmode 'VHT80'
	option disabled '0'

config wifi-iface 'default_radio0'
	option device 'radio0'
	option network 'lan'
	option mode 'ap'
	option ssid 'Neptune_5GH'
	option encryption 'psk2'
	option key 'harry586'
	option ieee80211r '0'
	option wpa_disable_eapol_key_retries '1'

config wifi-device 'radio1'
	option type 'mac80211'
	option channel 'auto'
	option hwmode '11g'
	option path 'platform/1e100000.pcie/pci0001:00/0001:00:00.0/0002:00:00.0'
	option htmode 'HT40'
	option disabled '0'

config wifi-iface 'default_radio1'
	option device 'radio1'
	option network 'lan'
	option mode 'ap'
	option ssid 'Neptune_2.4GH'
	option encryption 'psk2'
	option key 'harry586'
	option ieee80211r '0'
	option wpa_disable_eapol_key_retries '1'
EOF
}

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行时：配置无线
    create_wireless_config "/tmp/wireless-neptune"
    
    # 尝试应用配置
    if [ -f /etc/config/wireless ]; then
        # 备份原配置
        cp /etc/config/wireless /etc/config/wireless.backup.$(date +%s)
        
        # 应用新配置
        mv /tmp/wireless-neptune /etc/config/wireless
        
        # 重启无线
        wifi reload 2>/dev/null || {
            wifi down 2>/dev/null
            sleep 2
            wifi up 2>/dev/null
        }
        
        echo "无线网络已配置："
        echo "  - SSID(5GHz): Neptune_5GH, 密码: harry586"
        echo "  - SSID(2.4GHz): Neptune_2.4GH, 密码: harry586"
        echo "  - 加密: WPA2-PSK (强安全性)"
        echo "  - 加密方式: 强制 CCMP（AES）"
    else
        echo "警告：/etc/config/wireless 不存在，无线配置未应用"
    fi
else
    # 编译时：集成到固件
    mkdir -p "${INSTALL_DIR}etc/config"
    create_wireless_config "${INSTALL_DIR}etc/config/wireless"
    echo "无线网络配置已集成到固件"
fi

# ==================== 8. 创建一键启用脚本 ====================
echo "创建一键启用脚本..."

create_enable_script() {
    local dest="$1"
    cat > "$dest" << 'EOF'
#!/bin/sh
# 基础系统配置一键启用脚本

echo "正在启用基础系统配置..."
echo "================================"

# 1. 应用主机名设置
if [ -f /etc/config/system ]; then
    uci set system.@system[0].hostname='Neptune'
    uci commit system
    echo "✓ 主机名已设置为: Neptune"
fi

# 2. 设置密码（如果未设置）
if ! grep -q '^root:\$' /etc/shadow 2>/dev/null; then
    echo -e "harry586586\nharry586586" | passwd root 2>/dev/null && echo "✓ 密码已设置"
fi

# 3. 确保SSH密钥已安装
if [ ! -d /root/.ssh ]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
fi

SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAgR6/T2s7aX5w/JXCFh/X+7VWh0ovMxl8F4W0HLpIdPgnNUcfzgsvjDPCqIZ3Qws6WaWq+03or8AN06Mrh6JIa6+hV0e7DipnTyWg8khRftwxj4bSBURJ8cFg6DdpW62eoJwPu8zgTX0risI33HrZkGC3rN3pGErES5L3S5tsb24XSRRTPijzJu3Tj56bPK0i2hf2RuK5N6qOW+GiqwD1bMGVwfnwhBuozNyutBsYM6VVUf3hoEiiy4e1Z4TAyUC1YExAo+3TjCgRp6F58UgF+l2e855bqU+9IL2TFOfWnhwT2hoJ795WSdgXYg98V6ZUS+irL7Hc4GrJN1D8LQ6DGw== openwrt-15.05.1-ramips-mt7620-y1"
if ! grep -q "$SSH_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "$SSH_KEY" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "✓ SSH密钥已添加"
fi

# 4. 启用计划任务
if [ -f /etc/crontabs/root ]; then
    /etc/init.d/cron enable 2>/dev/null || true
    /etc/init.d/cron restart 2>/dev/null || true
    echo "✓ 计划任务已启用"
fi

# 5. 设置升级配置
echo "/overlay" > /etc/sysupgrade.conf
echo "✓ 升级配置已设置（保留/overlay）"

# 6. 添加静态路由（如果不存在）
if ! uci show network | grep -q "network.route.*target='192.168.7.0'" 2>/dev/null; then
    uci add network route 2>/dev/null && {
        uci set network.@route[-1].interface='lan'
        uci set network.@route[-1].target='192.168.7.0'
        uci set network.@route[-1].netmask='255.255.255.0'
        uci set network.@route[-1].gateway='192.168.5.100'
        uci commit network 2>/dev/null
        echo "✓ 静态路由已添加"
    }
fi

# 7. 配置无线网络
if [ -f /etc/config/wireless ]; then
    # 重启无线使配置生效
    wifi reload 2>/dev/null || {
        wifi down 2>/dev/null
        sleep 2
        wifi up 2>/dev/null
    }
    echo "✓ 无线网络已配置"
fi

echo "================================"
echo "基础系统配置启用完成！"
echo ""
echo "【配置摘要】:"
echo "  ✓ 主机名: Neptune"
echo "  ✓ 管理员密码: 已设置"
echo "  ✓ SSH密钥: 已添加"
echo "  ✓ 计划任务: 已启用"
echo "  ✓ 升级保留: /overlay"
echo "  ✓ 静态路由: 192.168.7.0/24 via 192.168.5.100"
echo "  ✓ 无线网络: Neptune_5GH / Neptune_2.4GH"
echo ""
echo "建议重启系统使所有配置生效"
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

# ==================== 9. 总结信息 ====================
echo ""
echo "=========================================="
echo "基础系统配置设置完成"
echo "=========================================="

if [ "$RUNTIME_MODE" = "true" ]; then
    echo "【当前环境】: 路由器运行时配置"
    echo ""
    echo "【已配置】:"
    echo "  ✓ 主机名: Neptune"
    echo "  ✓ 管理员密码: harry586586"
    echo "  ✓ SSH密钥: 已添加"
    echo "  ✓ 计划任务: 已设置"
    echo "  ✓ 升级配置: 保留/overlay"
    echo "  ✓ 静态路由: 192.168.7.0/24 → 192.168.5.100"
    echo "  ✓ 无线网络: Neptune_5GH / Neptune_2.4GH"
    echo ""
    echo "【注意事项】:"
    echo "  1. 部分配置需要重启服务或系统才能完全生效"
    echo "  2. 静态路由需要确保网关192.168.5.100可达"
    echo "  3. 无线配置需要硬件支持5GHz和2.4GHz"
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
    echo "  ✓ SSH密钥文件"
    echo "  ✓ 计划任务配置"
    echo "  ✓ 升级保留配置"
    echo "  ✓ 静态路由配置片段"
    echo "  ✓ 无线网络配置"
    echo "  ✓ 一键启用脚本"
    echo ""
    echo "【固件特性】:"
    echo "  刷入此固件后，系统将:"
    echo "  1. 主机名自动设置为Neptune"
    echo "  2. 密码已预设为harry586586"
    echo "  3. SSH密钥已预配置"
    echo "  4. 无线网络自动配置"
    echo "  5. 支持一键应用所有配置"
    echo ""
    echo "【使用说明】:"
    echo "  刷机后运行: /usr/bin/enable-basic-config"
fi

echo "=========================================="