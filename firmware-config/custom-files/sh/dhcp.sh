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
	option localise_queries '1'
	option rebind_protection '0'
	option local '/lan/'
	option domain 'lan'
	option expandhosts '1'
	option authoritative '1'
	option readethers '1'
	option leasefile '/tmp/dhcp.leases'
	option localservice '1'
	option ednspacket_max '1232'
	option cachesize '10000'
	option sequential_ip '1'
	option domainneeded '0'
	list server '127.0.0.1#6053'
	option noresolv '1'

config dhcp 'lan'
	option interface 'lan'
	option start '100'
	option limit '150'
	option leasetime '12h'
	option dhcpv4 'server'
	option ra_management '1'

config dhcp 'wan'
	option interface 'wan'
	option ignore '1'
	option start '100'
	option limit '150'
	option leasetime '12h'

config host
	option name 'min-DELL-pc-wifi'
	option dns '1'
	option mac '7c:67:a2:99:f8:d6'
	list tag 'family'

config host
	option name 'harry586-iPad'
	option dns '1'
	option mac '5c:96:9d:99:a4:85'
	list tag 'family'

config host
	option name 'min-MI8'
	option dns '1'
	option mac 'a4:50:46:eb:02:0a'
	list tag 'family'

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
	list tag 'family'

config host
	option name 'min-MI10'
	option dns '1'
	option mac '22:DC:C1:F5:05:68'
	list tag 'family'

config host
	option name 'huawei-P40-pro'
	option dns '1'
	option mac 'e0:e0:fc:09:25:16'
	list tag 'family'

config host
	option name 'huawei-pad'
	option dns '1'
	option mac '00:94:ec:72:6f:f7'
	list tag 'family'

config host
	option name 'kai-computer'
	option dns '1'
	option mac '84:14:4D:BE:AF:41'
	list tag 'family'

config host
	option name 'min-K60U'
	option dns '1'
	option mac 'CC:EB:5E:F2:B3:42'
	list tag 'family'

config host
	option name 'ma-oppo'
	option dns '1'
	option mac '00:ca:e0:32:59:e7'
	list tag 'family'

config host
	option name 'mi-clean'
	option dns '1'
	option mac '84:46:93:F7:A8:AA'

config host
	option name 'mi-yuba'
	option dns '1'
	option mac 'EC:4D:3E:91:B8:D6'

config host
	option name 'min-newmine-wifi'
	option dns '1'
	option mac '00:13:EF:3F:26:93'

config host
	option name 'asus-rt-acrh17'
	option dns '1'
	option mac '26:4B:FE:DD:B1:54'

config host
	option name 'min-wifi6'
	option dns '1'
	option mac '68:8F:C9:A2:5F:7B'

config host
	option name 'min-xisanqu-yeelight-light'
	option dns '1'
	option mac '04:CF:8C:8E:95:37'

config host
	option name 'kai-xisanqu-yeelink-light'
	option dns '1'
	option mac '04:CF:8C:8E:B9:EF'

config host
	option name 'ba-san-xingW21-5G'
	option dns '1'
	option mac '9C:5F:B0:65:72:1A'
	list tag 'family'

config host
	option name 'ma-W2019'
	option dns '1'
	option mac '10:98:C3:1C:34:F9'
	list tag 'family'

config host
	option name 'rui-iPhone'
	option dns '1'
	option mac '7A:59:46:34:9B:44'
	list tag 'family'

config host
	option name 'kai-HONOR-300'
	option dns '1'
	option mac '24:AE:CC:B2:73:1F'
	list tag 'family'

config host
	option name 'min-Mi-10-Ultra'
	option dns '1'
	option mac '7C:2A:DB:64:7F:C9'
	list tag 'family'

config host
	option name 'rui-xisanqu-yeelink-light'
	option dns '1'
	option mac '04:CF:8C:8E:A5:46'
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
