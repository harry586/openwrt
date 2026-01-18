#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# Samba4文件共享设置脚本
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

echo "开始配置Samba4文件共享..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/samba"
    mkdir -p "${prefix}/mnt/sda1"
}

create_dirs "$INSTALL_DIR"

# ==================== 配置Samba4 ====================
create_samba_config() {
    local prefix="$1"
    cat > "${prefix}/etc/config/samba4" << 'EOF'
config samba
    option workgroup 'WORKGROUP'
    option charset 'UTF-8'
    option description 'Samba on OpenWRT'
    option disable_async_io '1'
    option macos '1'
    option disable_netbios '1'

config sambashare
    option name 'sda1'
    option path '/mnt/sda1/'
    option read_only 'yes'
    option guest_ok 'yes'
    option create_mask '0666'
    option dir_mask '0777'
EOF
}

create_smb_conf() {
    local prefix="$1"
    cat > "${prefix}/etc/samba/smb.conf" << 'EOF'
[global]
    workgroup = WORKGROUP
    server string = Samba on OpenWRT
    netbios name = OpenWRT
    security = user
    map to guest = Bad User
    guest account = nobody
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_KEEPALIVE SO_RCVBUF=131072 SO_SNDBUF=131072
    deadtime = 30
    use sendfile = yes
    min receivefile size = 16384
    getwd cache = yes
    wide links = yes
    unix extensions = no
    disable netbios = yes
    smb2 leases = yes
    vfs objects = acl_xattr
    map acl inherit = yes
    store dos attributes = yes
    dos filemode = yes
    load printers = no
    printing = bsd
    printcap name = /dev/null
    disable spoolss = yes
    log file = /var/log/samba.log
    max log size = 1000
    dns proxy = no

[sda1]
    path = /mnt/sda1
    read only = no
    guest ok = yes
    create mask = 0666
    directory mask = 0777
    force user = root
    force group = root
EOF
}

create_smb_template() {
    local prefix="$1"
    cat > "${prefix}/etc/samba/smb.conf.template" << 'EOF'
# Samba configuration template for OpenWRT

[global]
    workgroup = {{.global.workgroup|default "WORKGROUP"}}
    server string = {{.global.server_string|default "Samba on OpenWRT"}}
    security = {{.global.security|default "user"}}
    map to guest = Bad User
    guest account = nobody
    
    # Performance optimizations
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_KEEPALIVE
    deadtime = 30
    use sendfile = yes
    min receivefile size = 16384
    
    # Disable NetBIOS for security
    disable netbios = yes
    
    # Logging
    log file = /var/log/samba.log
    max log size = 1000
    
    # DNS
    dns proxy = no

# Share template
#{{range .shares}}
#[{{.name}}]
#    path = {{.path}}
#    read only = {{if .read_only}}yes{{else}}no{{end}}
#    guest ok = {{if .guest_ok}}yes{{else}}no{{end}}
#    create mask = {{.create_mask|default "0666"}}
#    directory mask = {{.dir_mask|default "0777"}}
#    force user = root
#    force group = root
#{{end}}
EOF
}

add_user_to_passwd() {
    local prefix="$1"
    # 检查/etc/passwd文件是否存在
    if [ "$RUNTIME_MODE" = "true" ]; then
        if [ -f "/etc/passwd" ]; then
            # 检查是否已存在sai用户
            if ! grep -q "^sai:" /etc/passwd; then
                echo "sai:x:0:0:sai:/sai:/bin/ash" >> /etc/passwd
                echo "✓ sai用户已添加到/etc/passwd"
            else
                echo "✓ sai用户已存在"
            fi
        fi
    else
        # 编译时：创建passwd文件或追加内容
        if [ -f "${prefix}/etc/passwd" ]; then
            if ! grep -q "^sai:" "${prefix}/etc/passwd"; then
                echo "sai:x:0:0:sai:/sai:/bin/ash" >> "${prefix}/etc/passwd"
            fi
        else
            echo "sai:x:0:0:sai:/sai:/bin/ash" > "${prefix}/etc/passwd"
        fi
    fi
}

if [ "$RUNTIME_MODE" = "true" ]; then
    create_samba_config ""
    create_smb_conf ""
    create_smb_template ""
    
    # 复制配置文件
    cp -f /etc/config/samba4 /etc/config/samba 2>/dev/null || true
    cp -f /etc/samba/smb.conf /etc/samba/smb.conf.backup 2>/dev/null || true
    
    # 创建共享目录
    mkdir -p /mnt/sda1 2>/dev/null || true
    chmod 777 /mnt/sda1 2>/dev/null || true
    
    # 添加用户
    add_user_to_passwd ""
    
    # 重启服务
    if [ -f /etc/init.d/samba4 ]; then
        /etc/init.d/samba4 restart 2>/dev/null || true
    elif [ -f /etc/init.d/samba ]; then
        /etc/init.d/samba restart 2>/dev/null || true
    fi
    echo "✓ Samba4配置已应用"
else
    create_samba_config "files"
    create_smb_conf "files"
    create_smb_template "files"
    add_user_to_passwd "files"
    echo "✓ Samba4配置已集成到固件"
fi

echo "Samba4文件共享设置完成！"