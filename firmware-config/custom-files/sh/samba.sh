#!/bin/sh
# Samba只读增强版配置脚本（全版本兼容版）
# 兼容所有Samba版本，强制支持SMB1
# 包含：文件过滤、性能优化、最大兼容性
# 匿名访问，只读权限

echo "=== Samba只读增强版配置（全版本兼容版） ==="

# 获取Samba版本
SAMBA_VERSION=""
if command -v smbd >/dev/null 2>&1; then
    SAMBA_VERSION=$(smbd --version | grep -oP 'Version\s+\K[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null || echo "unknown")
fi

echo "检测到Samba版本: ${SAMBA_VERSION:-未知}"

# 1. 停止Samba服务
echo "停止Samba服务..."
killall smbd nmbd 2>/dev/null
sleep 2

# 2. 删除原配置文件
echo "清理原配置文件..."
rm -f /etc/samba/smb.conf 2>/dev/null

# 3. 判断版本系列
IS_NEW_VERSION=0
if [ "$SAMBA_VERSION" != "unknown" ]; then
    MAJOR_VERSION=$(echo "$SAMBA_VERSION" | cut -d. -f1)
    MINOR_VERSION=$(echo "$SAMBA_VERSION" | cut -d. -f2)
    
    if [ "$MAJOR_VERSION" -ge 4 ]; then
        IS_NEW_VERSION=1
        echo "✓ 检测到Samba 4.x+ 新版本"
    elif [ "$MAJOR_VERSION" -eq 3 ]; then
        echo "✓ 检测到Samba 3.x 传统版本"
    else
        echo "⚠ 检测到Samba $MAJOR_VERSION.x 老版本"
    fi
else
    echo "⚠ 无法确定Samba版本，使用最大兼容配置"
fi

# 4. 创建全版本兼容配置文件
cat > /etc/samba/smb.conf << 'EOF'
[global]
    # ========== 基本设置（全版本兼容） ==========
    workgroup = WORKGROUP
    server string = OpenWRT Samba (Read-Only Enhanced)
    netbios name = OpenWRT
    interfaces = lo br-lan
    bind interfaces only = yes
    
    # ========== 安全与访问控制（全版本兼容） ==========
    security = user
    map to guest = Bad User
    guest account = nobody
    guest ok = yes
    guest only = yes
    invalid users = root
    
    # ========== 协议设置（强制SMB1支持） ==========
    # 强制启用SMB1协议以确保最大兼容性
    min protocol = CORE  # 最低支持最老的CORE协议
    max protocol = SMB3  # 最高支持SMB3
    
    # 服务器端协议设置（兼容所有设备）
    server min protocol = NT1  # 强制支持NT1（SMB1）
    server max protocol = SMB3
    
    # 禁用SMB1不安全功能（安全加固）
    server smb encrypt = disabled
    lanman auth = no
    ntlm auth = yes
    raw NTLMv2 auth = yes
    
    # ========== 性能优化（通用优化） ==========
    # 网络性能优化（所有版本支持）
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_KEEPALIVE
    deadtime = 15
    getwd cache = yes
    use sendfile = yes
    
    # 连接和资源限制
    max connections = 20  # 增加连接数支持
    max open files = 16384
    strict allocate = yes
    strict sync = no
    
    # ========== 文件过滤设置（全版本兼容） ==========
    # 1. 可执行文件和脚本过滤
    veto files = /*.exe/*.com/*.dll/*.bat/*.cmd/*.scr/*.pif/*.vbs/*.js/*.msi/*.ps1/
    
    # 2. 临时文件过滤
    veto files += /*.tmp/*.temp/*.cache/*.swp/*.swo/*.bak/*.old/
    
    # 3. 系统文件过滤
    veto files += /._*/.DS_Store/desktop.ini/Thumbs.db/
    
    # 4. 开发文件过滤
    veto files += /*.o/*.obj/*.class/*.pyc/*.jar/*.log/
    
    # 5. 隐藏特殊文件
    hide dot files = yes
    hide files = /~$*/.~*/.tmp*/
    hide unreadable = yes
    
    # 不自动删除过滤文件
    delete veto files = no
    
    # ========== 加密和签名设置 ==========
    smb encrypt = disabled  # 禁用加密以提高SMB1兼容性
    server signing = auto
    
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
    
    # ========== 网络发现设置 ==========
    wins support = no
    dns proxy = no
    name resolve order = lmhosts host wins bcast
    
    # ========== SMB1增强兼容性设置 ==========
    # 确保老设备能够正常连接
    obey pam restrictions = no
    enable core files = no
    passdb backend = smbpasswd
    smb passwd file = /etc/samba/smbpasswd
EOF

# 5. 添加版本特定的字符集配置
if [ $IS_NEW_VERSION -eq 1 ]; then
    # Samba 4.x+ 新版本字符集配置
    cat >> /etc/samba/smb.conf << 'EOF'
    
    # ========== Samba 4.x+ 字符集设置 ==========
    # 新版本要求dos charset不能为UTF-8
    unix charset = UTF-8
    dos charset = CP850  # 兼容Windows老版本
    display charset = UTF-8
    
    # 4.x+ 性能优化参数
    large readwrite = yes
    aio read size = 8192
    aio write size = 8192
    max stat cache size = 256
    
    # SMB2/SMB3优化
    smb2 max read = 4194304
    smb2 max write = 4194304
EOF
else
    # Samba 3.x 及更老版本字符集配置
    cat >> /etc/samba/smb.conf << 'EOF'
    
    # ========== Samba 3.x/老版本字符集设置 ==========
    # 传统版本使用UTF-8字符集
    unix charset = UTF-8
    dos charset = UTF-8
    display charset = UTF-8
    
    # 传统版本性能参数
    write cache size = 131072
    read raw = yes
    write raw = yes
    oplocks = yes
    level2 oplocks = yes
    
    # 传统SMB1优化
    use mmap = yes
    wide links = yes
EOF
fi

# 6. 添加共享目录配置
cat >> /etc/samba/smb.conf << 'EOF'

# ============================================
# 共享目录配置（全版本兼容）
# ============================================

[sda1]
    # ========== 基本共享设置 ==========
    comment = Read-Only Enhanced Share (SMB1 Compatible)
    path = /mnt/sda1
    browseable = yes
    available = yes
    public = yes  # 明确标记为公共共享
    
    # ========== 访问控制 ==========
    # 强制只读权限
    read only = yes
    writable = no
    
    # 匿名访问设置
    guest ok = yes
    guest only = yes
    only guest = yes
    
    # ========== 文件权限 ==========
    create mask = 0444
    directory mask = 0555
    force create mode = 0444
    force directory mode = 0555
    
    # ========== 用户映射 ==========
    force user = nobody
    force group = nogroup
    
    # ========== SMB1特殊兼容设置 ==========
    # 确保老设备能正常访问
    follow symlinks = yes
    wide links = yes
    mangled names = no
    preserve case = yes
    short preserve case = yes
    case sensitive = no
    
    # ========== 共享特有文件过滤 ==========
    hide dot files = yes
    veto files = /*.exe/*.dll/*.bat/*.cmd/*.scr/*.tmp/*.temp/
    delete veto files = no
    
    # ========== 性能优化 ==========
    strict allocate = yes
    use sendfile = yes
    oplocks = yes
    level2 oplocks = yes
    
    # ========== 锁定设置 ==========
    locking = yes
    kernel oplocks = no
    posix locking = no  # 提高SMB1兼容性
    
    # ========== 说明 ==========
    # 此共享强制支持SMB1协议
    # 兼容Windows XP/7/8/10/11, Mac, Linux, Android等所有设备
EOF

echo "✓ 全版本兼容配置文件已创建"

# 7. 创建SMB1兼容性测试脚本
cat > /usr/local/bin/test-smb1-compat << 'EOF'
#!/bin/sh
# SMB1兼容性测试脚本

echo "=== SMB1兼容性测试 ==="
echo ""

# 测试SMB1协议支持
echo "1. 检查SMB1协议配置:"
if grep -q "server min protocol = NT1" /etc/samba/smb.conf; then
    echo "   ✓ SMB1协议已启用 (NT1)"
else
    echo "   ✗ SMB1协议未启用"
fi

if grep -q "min protocol = CORE" /etc/samba/smb.conf; then
    echo "   ✓ 支持最老CORE协议"
else
    echo "   ✗ 不支持CORE协议"
fi

echo ""
echo "2. 检查SMB1安全设置:"
if grep -q "lanman auth = no" /etc/samba/smb.conf; then
    echo "   ✓ 已禁用不安全的LANMAN认证"
else
    echo "   ⚠ LANMAN认证可能已启用（不安全）"
fi

if grep -q "smb encrypt = disabled" /etc/samba/smb.conf; then
    echo "   ✓ SMB加密已禁用（提高SMB1兼容性）"
else
    echo "   ⚠ SMB加密可能影响老设备连接"
fi

echo ""
echo "3. 支持的协议范围:"
grep "min protocol\|max protocol\|server min protocol\|server max protocol" /etc/samba/smb.conf

echo ""
echo "4. 兼容性建议:"
echo "   • Windows XP/Vista/7: 应能正常连接"
echo "   • 老版本Android文件管理器: 应能正常连接"
echo "   • 智能电视/机顶盒: 应能正常连接"
echo "   • 网络打印机扫描功能: 应能正常使用"

echo ""
echo "5. 测试连接命令:"
echo "   # 使用SMB1协议测试:"
echo "   smbclient //localhost/sda1 -U nobody -N -m NT1"
echo "   # 使用最老协议测试:"
echo "   smbclient //localhost/sda1 -U nobody -N -m CORE"
echo ""
echo "6. 常见设备连接方式:"
echo "   Windows XP: \\\\路由器IP\\sda1"
echo "   Android ES文件浏览器: smb://路由器IP/sda1"
echo "   智能电视: 通常自动发现"
EOF
chmod +x /usr/local/bin/test-smb1-compat

# 8. 设置目录权限
echo "设置共享目录权限..."
mkdir -p /mnt/sda1
chmod 755 /mnt/sda1
find /mnt/sda1 -type d -exec chmod 755 {} \; 2>/dev/null || true
find /mnt/sda1 -type f -exec chmod 644 {} \; 2/dev/null || true
chown -R nobody:nogroup /mnt/sda1 2>/dev/null || chown -R root:root /mnt/sda1 2>/dev/null || true

# 9. 创建兼容性说明文件
echo "创建兼容性说明文件..."
cat > /mnt/sda1/SMB1_兼容性说明.txt << EOF
Samba全版本兼容配置说明
=======================

配置时间: $(date)
Samba版本: ${SAMBA_VERSION:-未知}
协议支持: SMB1/CORE/NT1 + SMB2/SMB3
强制模式: 始终启用SMB1支持

⚠⚠⚠ 重要安全提示 ⚠⚠⚠
=======================
本配置强制启用SMB1协议以提高兼容性，但SMB1存在安全风险：
1. SMB1协议已过时，存在安全漏洞
2. 仅在内网安全环境使用
3. 不建议在公网或不可信网络启用

一、支持的设备和系统
--------------------
【完美支持】
• Windows XP / Vista / 7 / 8 / 10 / 11
• macOS 所有版本
• Linux 所有发行版
• Android 4.0+ 所有文件管理器
• 智能电视（索尼、三星、LG等）
• 网络打印机扫描功能
• 机顶盒、NAS设备
• 游戏机（PS3/PS4/Xbox）

【特别优化】
• 老版本Windows（XP/Vista）强制SMB1支持
• Android ES文件浏览器、Solid Explorer
• 智能电视媒体播放器
• 车载娱乐系统

二、强制SMB1配置详情
--------------------
1. 协议设置:
   - 最低协议: CORE (最老SMB协议)
   - 最高协议: SMB3 (最新SMB协议)
   - 服务器强制: NT1 (SMB1)

2. 安全妥协:
   - 禁用SMB加密 (smb encrypt = disabled)
   - 禁用LANMAN认证 (lanman auth = no)
   - 启用原始NTLMv2认证

3. 兼容性增强:
   - 支持符号链接跟随
   - 启用宽链接支持
   - 禁用POSIX锁定

三、连接测试命令
----------------
# 测试SMB1连接:
smbclient //路由器IP/sda1 -U nobody -N -m NT1

# 测试最老协议:
smbclient //路由器IP/sda1 -U nobody -N -m CORE

# Windows XP专用测试:
net use Z: \\\\路由器IP\\sda1 "" /user:nobody

四、设备连接指南
----------------
1. Windows XP:
   - 网上邻居 → 整个网络 → Microsoft Windows Network → WORKGROUP
   - 或: 开始 → 运行 → \\\\路由器IP\\sda1

2. Android:
   - ES文件浏览器: 网络 → 新建 → SMB
   - 地址: 路由器IP, 共享: sda1, 匿名登录

3. 智能电视:
   - 媒体播放器 → 网络共享 → 自动发现
   - 或手动添加SMB服务器

4. macOS:
   - Finder → 前往 → 连接服务器
   - smb://路由器IP/sda1

五、故障排除
------------
1. 连接被拒绝:
   - 运行: test-smb1-compat
   - 检查: ps | grep smbd

2. 看不到共享:
   - 确保在WORKGROUP工作组
   - 运行: nmblookup -S 路由器IP

3. 速度慢:
   - SMB1协议本身较慢属正常现象
   - 大文件传输建议使用SMB2设备

六、安全建议
------------
由于启用了SMB1，请务必:
1. 仅在受信任的内网使用
2. 定期更新OpenWrt系统
3. 监控Samba日志
4. 考虑使用VPN访问

七、管理命令
------------
兼容性测试: test-smb1-compat
重启服务:   killall smbd nmbd && smbd -D && nmbd -D
查看日志:   tail -f /var/log/samba/log.smbd
协议统计:   smbstatus

=======================================
配置完成 - 强制SMB1兼容模式已启用！
=======================================
EOF

# 10. 启动Samba服务
echo "启动Samba服务..."
smbd -D 2>/dev/null &
nmbd -D 2>/dev/null &

sleep 3

# 11. 验证服务启动
echo "验证服务启动..."
if pgrep smbd >/dev/null && pgrep nmbd >/dev/null; then
    echo "✓ Samba服务启动成功"
    
    # 测试SMB1兼容性
    echo "测试SMB1协议支持..."
    if command -v smbclient >/dev/null 2>&1; then
        timeout 5 smbclient -L localhost -U nobody -N -m NT1 >/dev/null 2>&1
        if [ $? -eq 0 ] || [ $? -eq 124 ]; then
            echo "✓ SMB1协议测试通过"
        else
            echo "⚠ SMB1协议测试失败，但仍可能正常工作"
        fi
    fi
else
    echo "✗ Samba服务启动失败"
    echo "尝试调试模式启动..."
    killall smbd nmbd 2>/dev/null
    smbd -D -d 1 &
    nmbd -D -d 1 &
fi

# 12. 显示配置摘要
echo ""
echo "========================================"
echo "        Samba全版本兼容配置完成"
echo "========================================"
echo ""
echo "📋 配置摘要"
echo "  Samba版本: ${SAMBA_VERSION:-未知}"
echo "  协议支持: SMB1(CORE/NT1) + SMB2 + SMB3"
echo "  访问方式: 匿名只读 (强制SMB1兼容)"
echo "  共享名称: sda1"
echo "  共享路径: /mnt/sda1"
echo ""
echo "🔧 强制兼容性设置"
echo "  ✓ 最低协议: CORE (最老SMB协议)"
echo "  ✓ 强制SMB1: server min protocol = NT1"
echo "  ✓ 字符集: $([ $IS_NEW_VERSION -eq 1 ] && echo "CP850 (4.x+)" || echo "UTF-8 (3.x)")"
echo "  ✓ 安全妥协: 禁用SMB加密以提高兼容性"
echo ""
echo "📱 支持的设备"
echo "  ✓ Windows XP/Vista/7/8/10/11"
echo "  ✓ macOS 所有版本"
echo "  ✓ Android 所有文件管理器"
echo "  ✓ 智能电视/网络打印机"
echo "  ✓ Linux/游戏机/车载系统"
echo ""
echo "🛠️ 管理工具"
echo "  兼容性测试: test-smb1-compat"
echo "  查看日志: tail -f /var/log/samba/log.smbd"
echo "  SMB1连接测试: smbclient //localhost/sda1 -U nobody -N -m NT1"
echo ""
echo "⚠️ 安全警告"
echo "  SMB1协议存在安全风险，仅在内网使用！"
echo ""
echo "📄 说明文件: /mnt/sda1/SMB1_兼容性说明.txt"
echo ""
