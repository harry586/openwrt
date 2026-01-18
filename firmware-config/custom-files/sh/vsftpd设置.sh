#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# vsftpd FTP服务器设置脚本
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

echo "开始配置vsftpd FTP服务器..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/vsftpd"
    mkdir -p "${prefix}/var/log"
    mkdir -p "${prefix}/mnt/sdb5/tftp/os"
}

create_dirs "$INSTALL_DIR"

# ==================== 配置vsftpd ====================
create_vsftpd_config() {
    local prefix="$1"
    cat > "${prefix}/etc/config/vsftpd" << 'EOF'
config listen 'listen'
    option enable4 '1'
    option ipv4 '0.0.0.0'
    option enable6 '0'
    option ipv6 '::1'
    option port '60000'
    option dataport '60001'
    option pasv_min_port '50000'
    option pasv_max_port '51000'

config local 'local'
    option enabled '1'

config global 'global'
    option write '1'
    option download '1'
    option umask '022'
    option dirlist '1'
    option dirmsgfile '.message'
    option dotfile '1'
    option banner 'Neptune'

config connection 'connection'
    option pasvmode '1'
    option ascii 'both'
    option idletimeout '1800'
    option conntimeout '120'
    option dataconntimeout '120'
    option maxperip '0'
    option maxrate '0'
    option maxretry '3'
    option maxclient '1'

config anonymous 'anonymous'
    option username 'ftp'
    option umask '022'
    option writemkdir '0'
    option upload '0'
    option others '0'
    option maxrate '0'
    option enabled '1'
    option root '/mnt/sdb5/tftp/os'

config log 'log'
    option syslog '0'
    option xreflog '1'
    option file '/var/log/vsftpd.log'

config vuser 'vuser'
    option username 'ftp'
    option enabled '1'

config user
    option username 'harry'
    option password '83.10.10'
    option home '/'
    option umask '022'
    option maxrate '0'
    option writemkdir '1'
    option upload '1'
    option others '1'
EOF
}

create_vsftpd_conf() {
    local prefix="$1"
    cat > "${prefix}/etc/vsftpd.conf" << 'EOF'
# 基础配置
listen=YES
listen_ipv6=NO
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_file=/var/log/vsftpd.log
xferlog_std_format=YES
idle_session_timeout=1800
data_connection_timeout=120
nopriv_user=ftp
async_abor_enable=YES
ascii_upload_enable=YES
ascii_download_enable=YES

# 安全配置
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/vsftpd.pem

# 被动模式
pasv_enable=YES
pasv_min_port=50000
pasv_max_port=51000
port_enable=YES

# 连接限制
max_clients=10
max_per_ip=5
EOF
}

if [ "$RUNTIME_MODE" = "true" ]; then
    create_vsftpd_config ""
    create_vsftpd_conf ""
    
    # 创建FTP用户目录
    mkdir -p /mnt/sdb5/tftp/os 2>/dev/null || true
    chmod 755 /mnt/sdb5/tftp/os 2>/dev/null || true
    
    # 重启服务
    if [ -f /etc/init.d/vsftpd ]; then
        /etc/init.d/vsftpd restart 2>/dev/null || true
    fi
    echo "✓ vsftpd配置已应用"
else
    create_vsftpd_config "files"
    create_vsftpd_conf "files"
    echo "✓ vsftpd配置已集成到固件"
fi

echo "vsftpd FTP服务器设置完成！"