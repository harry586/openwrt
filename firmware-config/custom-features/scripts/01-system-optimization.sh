#!/bin/bash

echo "=== 系统优化与自定义功能配置 ==="

# 设置时区为亚洲/上海
echo "🔧 设置系统时区..."
sed -i "s/system.@system\[0\].timezone='UTC'/system.@system\[0\].timezone='CST-8'/" package/base-files/files/bin/config_generate
sed -i "s/system.@system\[0\].zonename='UTC'/system.@system\[0\].zonename='Asia\/Shanghai'/" package/base-files/files/bin/config_generate

# 设置默认语言为中文
echo "🔧 设置系统语言..."
sed -i "s/system.@system\[0\].language='en'/system.@system\[0\].language='zh_cn'/" package/base-files/files/bin/config_generate

# 创建内存释放脚本
echo "🔧 创建内存释放脚本..."
mkdir -p files/usr/bin
cat > files/usr/bin/freemem << 'EOF'
#!/bin/sh
# =============================================
# 内存释放脚本
# 功能：清理系统缓存，释放内存空间
# 说明：此脚本会清理页面缓存、目录项和inodes
#       建议在系统运行一段时间后定期执行
# =============================================

echo "🔄 开始内存清理过程..."

# 同步文件系统，确保数据写入磁盘
echo "📝 同步文件系统..."
sync

# 清理页面缓存（PageCache）
echo "🧹 清理页面缓存..."
echo 1 > /proc/sys/vm/drop_caches

# 清理目录项和inodes
echo "🗂️ 清理目录项和inodes..."
echo 2 > /proc/sys/vm/drop_caches

# 清理页面缓存、目录项和inodes
echo "🧽 深度清理所有缓存..."
echo 3 > /proc/sys/vm/drop_caches

# 显示清理后的内存状态
echo "📊 内存清理完成，当前内存状态："
free -h

echo "✅ 内存释放脚本执行完毕"
echo "⏰ 下次自动清理时间：明天凌晨3点"
EOF

# 设置脚本权限
chmod +x files/usr/bin/freemem

# 配置定时任务 - 每天早上3点释放内存
echo "🔧 配置定时任务..."
mkdir -p files/etc/crontabs
cat > files/etc/crontabs/root << 'EOF'
# =============================================
# 系统定时任务配置
# 注意：修改此文件后需要重启crond服务生效
# =============================================

# 分钟 小时 日 月 星期 命令

# 每天凌晨3点执行内存释放
# 这个时间点通常系统负载较低，适合进行维护操作
0 3 * * * /usr/bin/freemem >/dev/null 2>&1

# 每30分钟同步一次时间（可选）
*/30 * * * * /usr/sbin/ntpd -q -n -p ntp.aliyun.com >/dev/null 2>&1

# 每天凌晨2点清理日志文件（可选）
#0 2 * * * echo "" > /tmp/system.log >/dev/null 2>&1

# 每周一凌晨1点重启系统（可选，谨慎使用）
# 0 1 * * 1 /sbin/reboot >/dev/null 2>&1
EOF

# 创建系统信息显示脚本
cat > files/usr/bin/system-info << 'EOF'
#!/bin/sh
# =============================================
# 系统信息显示脚本
# 功能：显示系统基本信息和状态
# =============================================

echo "=== 系统基本信息 ==="
echo "设备型号: $(cat /tmp/sysinfo/model 2>/dev/null || echo "未知")"
echo "固件版本: $(cat /etc/openwrt_release 2>/dev/null | grep "DISTRIB_DESCRIPTION" | cut -d"'" -f2 || echo "未知")"
echo "系统时间: $(date)"
echo "运行时间: $(uptime | sed 's/.*up //' | sed 's/,.*//')"

echo ""
echo "=== 内存使用情况 ==="
free -h

echo ""
echo "=== 磁盘使用情况 ==="
df -h | grep -E "rootfs|overlay|/dev/"

echo ""
echo "=== 网络接口 ==="
ifconfig | grep -E "eth|wlan|br-" | grep "Link" | awk '{print $1}'

echo ""
echo "===  CPU负载 ==="
cat /proc/loadavg
EOF

chmod +x files/usr/bin/system-info

# 添加自定义欢迎信息
echo "🔧 配置自定义欢迎信息..."
cat > files/etc/banner << 'EOF'
╔═══════════════════════════════════════════╗
║              OpenWrt 系统                 ║
║         Universal Firmware Builder        ║
║                通用固件构建               ║
╚═══════════════════════════════════════════╝

系统信息:
  - 版本: $(cat /etc/openwrt_release 2>/dev/null | grep "DISTRIB_DESCRIPTION" | cut -d"'" -f2)
  - 时间: $(date)
  - 运行: $(uptime | sed 's/.*up //' | sed 's/,.*//')

常用命令:
  - 系统信息: system-info
  - 释放内存: freemem
  - 磁盘管理: diskman (Web界面)

EOF

echo "✅ 系统优化与自定义功能配置完成"
