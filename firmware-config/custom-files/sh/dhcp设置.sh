#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# DHCP静态IP分配设置脚本
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

echo "开始配置DHCP静态IP分配..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
}

create_dirs "$INSTALL_DIR"

# ==================== 配置DHCP静态分配 ====================
create_dhcp_config() {
    local prefix="$1"
    cat > "${prefix}/etc/config/dhcp" << 'EOF'
config dnsmasq
    option domainneeded '1'
    option boguspriv '1'
    option filterwin2k '0'
    option localise_queries '1'
    option rebind_protection '1'
    option rebind_localhost '1'
    option local '/lan/'
    option domain 'lan'
    option expandhosts '1'
    option nonegcache '0'
    option authoritative '1'
    option readethers '1'
    option leasefile '/tmp/dhcp.leases'
    option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
    option localservice '1'
    option ednspacket_max '1232'
    option noresolv '0'
    option cachesize '10000'

config dhcp 'lan'
    option interface 'lan'
    option start '100'
    option limit '150'
    option leasetime '12h'
    option dhcpv4 'server'
    option dhcpv6 'server'
    option ra 'server'
    option ra_management '1'

config dhcp 'wan'
    option interface 'wan'
    option ignore '1'

config host
    option name 'DELL-min-pc-wifi'
    option dns '1'
    option mac '7c:67:a2:99:f8:d6'

config host
    option name 'harry586-iPad'
    option dns '1'
    option mac '5c:96:9d:99:a4:85'

config host
    option name 'MI8-min'
    option dns '1'
    option mac 'a4:50:46:eb:02:0a'

config host
    option name 'Yeelight-LED-01'
    option dns '1'
    option mac '04:CF:8C:78:71:08'

config host
    option name 'Yeelight-LED-02'
    option dns '1'
    option mac '04:cf:8c:8e:ad:de'

config host
    option name 'Yeelight-LED-03'
    option dns '1'
    option mac '04:cf:8c:8e:a1:41'

config host
    option name 'PgyBox-X1-2111-xisanqu'
    option dns '1'
    option mac 'a0:c5:f2:b1:c6:64'

config host
    option name 'PgyBox-X1-2111-shibanfang'
    option dns '1'
    option mac 'a0:c5:f2:b1:c6:16'
    option ip '192.168.5.100'

config host
    option name 'kaicheng-pc'
    option dns '1'
    option mac 'ac:ed:5c:77:35:e4'

config host
    option name 'hp-m281fdwc'
    option dns '1'
    option mac '10:5b:ad:4d:49:49'
    option ip '192.168.5.101'

config host
    option name 'MI10-min'
    option dns '1'
    option mac '22:DC:C1:F5:05:68'

config host
    option name 'huawei-P40-pro'
    option dns '1'
    option mac 'e0:e0:fc:09:25:16'

config host
    option name 'huawei-pad'
    option dns '1'
    option mac '00:94:ec:72:6f:f7'

config host
    option name 'hezi'
    option dns '1'
    option mac '00:9e:c8:8a:cd:b6'

config host
    option name 'new-computer'
    option dns '1'
    option mac '84:14:4D:BE:AF:41'

config host
    option name 'K60U'
    option dns '1'
    option ip '192.168.5.240'
    option mac 'CC:EB:5E:F2:B3:42'

config host
    option name 'apple-ruimin'
    option dns '1'
    option mac 'c0:2c:5c:26:80:e1'

config host
    option name 'oppo-ma'
    option dns '1'
    option mac '00:ca:e0:32:59:e7'

config host
    option name 'mi-clean'
    option dns '1'
    option mac '84:46:93:F7:A8:AA'
    option ip '192.168.5.244'

config host
    option name 'mi-yuba'
    option dns '1'
    option mac 'EC:4D:3E:91:B8:D6'
    option ip '192.168.5.220'

config host
    option name 'kaicheng-01'
    option dns '1'
    option mac '38:8f:30:e2:2e:96'

config host
    option name 'newmine-wifi'
    option dns '1'
    option mac '00:13:EF:3F:26:93'

config host
    option name 'ruimindi'
    option dns '1'
    option mac 'c0:17:54:09:0e:60'

config host
    option name 'kc2025'
    option dns '1'
    option mac '00:0a:f5:a1:47:38'

config host
    option name 'asus-rt-acrh17'
    option dns '1'
    option mac '26:4B:FE:DD:B1:54'

config host
    option name '3800'
    option dns '1'
    option mac 'C2:04:15:9B:36:64'

config host
    option name 'wifi6'
    option dns '1'
    option mac '68:8F:C9:A2:5F:7B'
EOF
}

if [ "$RUNTIME_MODE" = "true" ]; then
    create_dhcp_config ""
    
    # 重启dnsmasq使配置生效
    if [ -f /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart 2>/dev/null || true
    fi
    echo "✓ DHCP静态IP分配配置已应用"
else
    create_dhcp_config "files"
    echo "✓ DHCP静态IP分配配置已集成到固件"
fi

echo "DHCP静态IP分配设置完成！"