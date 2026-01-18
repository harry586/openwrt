#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 无线网络优化脚本
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

echo "开始优化无线网络..."

# ==================== 创建无线优化脚本 ====================
create_wifi_optimization() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/optimize-wifi" << 'EOF'
#!/bin/sh
# 无线网络优化脚本

echo "正在优化无线网络设置..."

# 获取无线接口
WIFI_INTERFACES=$(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | uniq)

for wifi in $WIFI_INTERFACES; do
    echo "优化无线设备: $wifi"
    
    # 设置国家代码（中国）
    uci set wireless.$wifi.country='CN'
    
    # 禁用DFS频道（减少干扰）
    uci set wireless.$wifi.dfs='0'
    
    # 设置发射功率（根据设备调整）
    uci set wireless.$wifi.txpower='20'  # 20dBm
    
    # 启用短前导码
    uci set wireless.$wifi.short_preamble='1'
    
    # 设置Beacon间隔
    uci set wireless.$wifi.beacon_int='100'
    
    # 设置RTS阈值
    uci set wireless.$wifi.rts='2347'
    
    # 设置Fragmentation阈值
    uci set wireless.$wifi.frag='2346'
    
    # 设置距离优化
    uci set wireless.$wifi.distance='1000'
    
    # 启用空间流
    uci set wireless.$wifi.noscan='1'
    
    # 设置HT模式
    uci set wireless.$wifi.htmode='HT40'
    
    # 优化2.4G频段
    if uci get wireless.$wifi.band 2>/dev/null | grep -q "2g"; then
        echo "优化2.4GHz频段..."
        uci set wireless.$wifi.channel='1'  # 使用1、6、11频道减少干扰
        uci set wireless.$wifi.ht_capab='[SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40]'
    fi
    
    # 优化5G频段
    if uci get wireless.$wifi.band 2>/dev/null | grep -q "5g"; then
        echo "优化5GHz频段..."
        uci set wireless.$wifi.channel='36'  # 低干扰频道
        uci set wireless.$wifi.ht_capab='[SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40]'
        uci set wireless.$wifi.noscan='1'
    fi
    
    # 应用设置
    uci commit wireless
done

# 优化无线客户端设置
echo "优化无线客户端设置..."
for interface in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | uniq); do
    # 禁用WMM
    uci set wireless.$interface.wmm='1'
    
    # 设置隔离模式
    uci set wireless.$interface.isolate='0'
    
    # 设置最大客户端数
    uci set wireless.$interface.maxassoc='64'
    
    # 设置隐藏SSID
    uci set wireless.$interface.hidden='0'
    
    # 启用802.11k/v/r
    uci set wireless.$interface.ieee80211k='1'
    uci set wireless.$interface.ieee80211v='1'
    uci set wireless.$interface.ieee80211r='1'
    
    # 设置快速切换
    uci set wireless.$interface.mobility_domain='4f57'
    
    # 应用设置
    uci commit wireless
done

# 重启无线服务
echo "重启无线服务..."
wifi down
sleep 2
wifi up

echo "无线网络优化完成！"

# 显示优化后的状态
echo ""
echo "无线网络状态："
iwinfo
EOF
    chmod +x "${prefix}/usr/sbin/optimize-wifi"
}

# ==================== 创建无线干扰检测 ====================
create_wifi_analyzer() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/wifi-analyzer" << 'EOF'
#!/bin/sh
# 无线干扰分析脚本

echo "无线网络干扰分析..."
echo "=========================="

# 检查当前频道使用情况
echo "当前无线频道："
iwlist scan 2>/dev/null | grep -E "(Channel|ESSID|Quality)" | head -30

echo ""
echo "建议的优化频道："

# 分析2.4GHz频道
echo "2.4GHz频段分析："
CHANNELS="1 6 11"
for chan in $CHANNELS; do
    count=$(iwlist scan 2>/dev/null | grep -c "Channel:$chan")
    echo "  频道 $chan: $count 个AP"
done

# 分析5GHz频道
echo "5GHz频段分析："
CHANNELS_5G="36 40 44 48 149 153 157 161"
for chan in $CHANNELS_5G; do
    count=$(iwlist scan 2>/dev/null | grep -c "Channel:$chan")
    echo "  频道 $chan: $count 个AP"
done

echo ""
echo "无线信号质量："
for iface in $(iw dev | grep Interface | awk '{print $2}'); do
    echo "接口 $iface:"
    iw dev $iface link | grep -E "(signal|tx bitrate|rx bitrate)"
done

echo ""
echo "优化建议："
echo "1. 选择使用最少的频道"
echo "2. 避免与其他AP使用相同频道"
echo "3. 5GHz干扰较少，优先使用"
echo "4. 调整发射功率避免过强干扰"
EOF
    chmod +x "${prefix}/usr/sbin/wifi-analyzer"
}

create_wifi_optimization "$INSTALL_DIR"
create_wifi_analyzer "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行优化脚本
    /usr/sbin/optimize-wifi
    
    # 运行干扰分析
    /usr/sbin/wifi-analyzer
    
    # 创建计划任务
    echo "# 每天凌晨2点优化无线网络" >> /etc/crontabs/root
    echo "0 2 * * * /usr/sbin/optimize-wifi >/dev/null 2>&1" >> /etc/crontabs/root
    echo "0 3 * * 1 /usr/sbin/wifi-analyzer >> /var/log/wifi-analyzer.log 2>&1" >> /etc/crontabs/root
    
    /etc/init.d/cron restart 2>/dev/null || true
    
    echo "✓ 无线网络优化已应用"
else
    echo "✓ 无线网络优化已集成到固件"
fi

echo "无线网络优化完成！"