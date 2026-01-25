#!/bin/sh
# Samba只读增强版配置脚本（兼容Samba 3.x/4.x）
# 包含：文件过滤、性能优化、匿名访问，只读权限

echo "=== Samba只读增强版配置（Samba 3.x/4.x兼容版） ==="

# 获取Samba版本
echo "检测Samba版本..."
SAMBA_VERSION="未知"
if command -v smbd >/dev/null 2>&1; then
    # 尝试多种方式获取版本
    if smbd -V 2>/dev/null | head -1 | grep -q "Version"; then
        SAMBA_VERSION=$(smbd -V 2>/dev/null | head -1 | sed 's/.*Version //')
    elif testparm -V 2>/dev/null | head -1 | grep -q "Version"; then
        SAMBA_VERSION=$(testparm -V 2>/dev/null | head -1 | sed 's/.*Version //')
    elif which smbd 2>&1 | grep -q "/"; then
        SAMBA_VERSION="已安装（版本未知）"
    fi
fi
echo "✓ 检测到 Samba 版本: $SAMBA_VERSION"

# 判断是否是3.x版本
SAMBA_MAJOR_VERSION=$(echo $SAMBA_VERSION | cut -d. -f1)

# 1. 停止Samba服务
echo "停止Samba服务..."
killall smbd nmbd 2>/dev/null
sleep 2

# 2. 删除原配置文件
echo "删除原配置文件..."
rm -f /etc/samba/smb.conf 2>/dev/null

# 3. 创建配置（区分3.x和4.x版本）
echo "创建配置文件..."
if [ "$SAMBA_MAJOR_VERSION" = "3" ]; then
    echo "使用 Samba 3.x 兼容配置"
    cat > /etc/samba/smb.conf << 'EOF'
[global]
    # ========== 基本设置 ==========
    workgroup = WORKGROUP
    server string = OpenWRT Samba (Read-Only Enhanced)
    netbios name = OpenWRT
    interfaces = lo br-lan
    bind interfaces only = yes
    
    # ========== 安全与访问控制 ==========
    security = share
    map to guest = Bad User
    guest account = nobody
    guest ok = yes
    invalid users = root
    
    # ========== 协议兼容性 ==========
    # Samba 3.x 只支持到 NT1 (SMB1)
    protocol = NT1
    
    # ========== 性能优化 ==========
    socket options = TCP_NODELAY IPTOS_LOWDELAY
    deadtime = 15
    getwd cache = yes
    large readwrite = yes
    
    # 内存和连接优化
    max connections = 10
    max open files = 16384
    strict allocate = yes
    strict sync = no
    
    # ========== 文件过滤设置 ==========
    veto files = /*.exe/*.com/*.dll/*.bat/*.cmd/*.scr/*.pif/*.vbs/*.js/*.msi/*.tmp/*.temp/*.cache/*.swp/*.swo/*.bak/*.old/._*/.DS_Store/desktop.ini/Thumbs.db/*.o/*.obj/*.class/*.pyc/*.jar/*.log/
    
    hide dot files = yes
    hide files = /~$*/.~*/.tmp*/
    hide unreadable = yes
    delete veto files = no
    
    # ========== 文件属性映射 ==========
    store dos attributes = yes
    map archive = no
    map hidden = no
    map readonly = no
    map system = no
    
    # ========== 日志设置 ==========
    log file = /var/log/samba/log.%m
    max log size = 1024
    log level = 1
    
    # ========== 字符集设置 ==========
    unix charset = UTF-8
    dos charset = CP936  # 3.x 通常用 CP936 (GBK)
    
    # ========== 网络发现设置 ==========
    wins support = no
    dns proxy = no
    name resolve order = bcast host

[sda1]
    comment = Read-Only Enhanced Share
    path = /mnt/sda1
    browseable = yes
    available = yes
    read only = yes
    writable = no
    guest ok = yes
    
    # 文件权限设置
    create mask = 0444
    directory mask = 0555
    force create mode = 0444
    force directory mode = 0555
    
    force user = nobody
    force group = nogroup
    
    # 共享特有过滤
    hide dot files = yes
    veto files = /*.exe/*.dll/*.bat/*.cmd/*.scr/*.tmp/*.temp/
    delete veto files = no
    
    strict allocate = yes
    level2 oplocks = yes
    oplocks = yes
    locking = yes
    kernel oplocks = no
    
    case sensitive = auto
    preserve case = yes
    short preserve case = yes
EOF
else
    echo "使用 Samba 4.x 兼容配置"
    cat > /etc/samba/smb.conf << 'EOF'
[global]
    # ========== 基本设置 ==========
    workgroup = WORKGROUP
    server string = OpenWRT Samba (Read-Only Enhanced)
    netbios name = OpenWRT
    interfaces = lo br-lan
    bind interfaces only = yes
    
    # ========== 安全与访问控制 ==========
    security = user
    map to guest = Bad User
    guest account = nobody
    guest ok = yes
    guest only = yes
    invalid users = root
    
    # ========== 协议兼容性 ==========
    min protocol = NT1
    max protocol = SMB3
    server min protocol = SMB2
    server max protocol = SMB3
    
    # ========== 性能优化 ==========
    socket options = TCP_NODELAY IPTOS_LOWDELAY
    deadtime = 15
    getwd cache = yes
    large readwrite = yes
    use sendfile = yes
    
    max connections = 10
    max open files = 16384
    max stat cache size = 512
    strict allocate = yes
    strict sync = no
    
    aio read size = 16384
    aio write size = 16384
    
    # ========== 文件过滤设置 ==========
    veto files = /*.exe/*.com/*.dll/*.bat/*.cmd/*.scr/*.pif/*.vbs/*.js/*.msi/*.tmp/*.temp/*.cache/*.swp/*.swo/*.bak/*.old/._*/.DS_Store/desktop.ini/Thumbs.db/*.o/*.obj/*.class/*.pyc/*.jar/*.log/
    
    hide dot files = yes
    hide files = /~$*/.~*/.tmp*/
    hide unreadable = yes
    delete veto files = no
    
    # ========== 加密和签名设置 ==========
    smb encrypt = disabled
    server signing = auto
    
    # ========== 高级安全设置 ==========
    logon home = \\
    logon path = \\
    
    # ========== 文件属性映射 ==========
    store dos attributes = yes
    map archive = no
    map hidden = no
    map readonly = no
    map system = no
    unix extensions = no
    
    # ========== 日志设置 ==========
    log file = /var/log/samba/log.%m
    max log size = 1024
    log level = 1
    
    # ========== 字符集设置 ==========
    unix charset = UTF-8
    dos charset = CP850
    
    # ========== 网络发现设置 ==========
    wins support = no
    dns proxy = no
    name resolve order = bcast host

[sda1]
    comment = Read-Only Enhanced Share
    path = /mnt/sda1
    browseable = yes
    available = yes
    read only = yes
    writable = no
    guest ok = yes
    guest only = yes
    
    create mask = 0444
    directory mask = 0555
    force create mode = 0444
    force directory mode = 0555
    
    force user = nobody
    force group = nogroup
    
    hide dot files = yes
    veto files = /*.exe/*.dll/*.bat/*.cmd/*.scr/*.tmp/*.temp/
    delete veto files = no
    
    strict allocate = yes
    use sendfile = yes
    level2 oplocks = yes
    oplocks = yes
    locking = yes
    kernel oplocks = no
    
    case sensitive = auto
    preserve case = yes
    short preserve case = yes
EOF
fi

echo "✓ 配置文件已创建（兼容 Samba $SAMBA_VERSION）"

# 4. 设置目录权限（只读）
echo "设置共享目录权限..."
mkdir -p /mnt/sda1
chmod 755 /mnt/sda1
find /mnt/sda1 -type d -exec chmod 755 {} \; 2>/dev/null || true
find /mnt/sda1 -type f -exec chmod 644 {} \; 2>/dev/null || true
chown -R nobody:nogroup /mnt/sda1 2>/dev/null || 
chown -R root:root /mnt/sda1 2>/dev/null || true

# 5. 启动Samba服务
echo "启动Samba服务..."
smbd -D 2>/dev/null &
nmbd -D 2>/dev/null &
sleep 2

# 6. 检查服务状态
echo "检查服务状态..."
if pgrep smbd >/dev/null && pgrep nmbd >/dev/null; then
    echo "✓ Samba服务已启动 (smbd & nmbd)"
else
    echo "✗ Samba服务启动失败"
fi

# 7. 设置配置文件为只读权限
chmod 444 /etc/samba/smb.conf 2>/dev/null || true
echo "✓ 配置文件已设为只读"

# 8. 显示配置摘要
echo ""
echo "=== 配置完成 ==="
echo ""
echo "配置摘要:"
echo "  Samba版本: $SAMBA_VERSION"
echo "  访问方式: 匿名只读"
echo "  共享名称: sda1"
echo "  共享路径: /mnt/sda1"
echo "  配置文件: /etc/samba/smb.conf (只读)"
echo ""
echo "增强功能:"
echo "  ✓ 文件过滤 (.exe/.dll/.tmp等)"
echo "  ✓ 性能优化"
echo "  ✓ 协议兼容"
echo "  ✓ 安全设置 (只读权限)"
echo ""
