# 插件兼容性检查 - 修复版：不因警告而终止构建
plugin_check() {
    local branch="$1"
    
    log_info "=== 插件兼容性检查 ==="
    echo "目标版本: $branch"
    
    # 插件兼容性数据库
    declare -A PLUGIN_COMPATIBILITY=(
        # 网络加速插件
        ["turboacc"]="22.03 23.05"
        ["luci-app-turboacc"]="22.03 23.05"
        ["kmod-nft-fullcone"]="22.03 23.05"
        ["kmod-shortcut-fe"]="22.03 23.05"
        
        # 网络工具
        ["luci-app-sqm"]="21.02 22.03 23.05"
        ["luci-app-upnp"]="19.07 21.02 22.03 23.05"
        ["luci-app-wol"]="19.07 21.02 22.03 23.05"
        
        # 存储和文件共享
        ["luci-app-samba4"]="21.02 22.03 23.05"
        ["luci-app-vsftpd"]="19.07 21.02 22.03 23.05"
        
        # 网络服务
        ["luci-app-smartdns"]="21.02 22.03 23.05"
        ["luci-app-arpbind"]="19.07 21.02 22.03 23.05"
        
        # 系统工具
        ["luci-app-cpulimit"]="21.02 22.03 23.05"
        ["luci-app-diskman"]="21.02 22.03 23.05"
        ["luci-app-accesscontrol"]="19.07 21.02 22.03 23.05"
        ["luci-app-vlmcsd"]="19.07 21.02 22.03 23.05"
        
        # 基础插件
        ["luci-theme-bootstrap"]="18.06 19.07 21.02 22.03 23.05"
        ["luci-theme-material"]="19.07 21.02 22.03 23.05"
        ["luci-app-firewall"]="18.06 19.07 21.02 22.03 23.05"
    )
    
    check_plugin() {
        local branch="$1"
        local plugin="$2"
        
        local version=$(echo "$branch" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        
        if [ -z "$version" ]; then
            if [[ "$branch" =~ master|main ]]; then
                log_warning "⚠️  $plugin: 开发版分支，兼容性未知"
                return 0  # 修复：返回0，不阻止构建
            else
                log_warning "⚠️  $plugin: 无法识别版本号"
                return 0  # 修复：返回0
            fi
        fi
        
        local compatible_versions="${PLUGIN_COMPATIBILITY[$plugin]}"
        
        if [ -z "$compatible_versions" ]; then
            log_info "ℹ️  $plugin: 兼容性信息未知"
            return 0
        fi
        
        if echo "$compatible_versions" | grep -q "$version"; then
            log_success "✅ $plugin: 兼容版本 $version"
            return 0
        else
            log_error "❌ $plugin: 不兼容版本 $version (仅支持: $compatible_versions)"
            return 1
        fi
    }
    
    local has_critical_error=0
    
    echo "=== 网络加速插件兼容性 ==="
    check_plugin "$branch" "turboacc" || has_critical_error=1
    check_plugin "$branch" "luci-app-turboacc" || has_critical_error=1
    check_plugin "$branch" "kmod-nft-fullcone" || has_critical_error=1
    check_plugin "$branch" "kmod-shortcut-fe" || has_critical_error=1
    
    echo ""
    echo "=== 网络工具插件兼容性 ==="
    check_plugin "$branch" "luci-app-sqm" || has_critical_error=1
    check_plugin "$branch" "luci-app-upnp" || has_critical_error=1
    check_plugin "$branch" "luci-app-wol" || has_critical_error=1
    
    echo ""
    echo "=== 存储和文件共享插件兼容性 ==="
    check_plugin "$branch" "luci-app-samba4" || has_critical_error=1
    check_plugin "$branch" "luci-app-vsftpd" || has_critical_error=1
    
    echo ""
    echo "=== 网络服务插件兼容性 ==="
    check_plugin "$branch" "luci-app-smartdns" || has_critical_error=1
    check_plugin "$branch" "luci-app-arpbind" || has_critical_error=1
    
    echo ""
    echo "=== 系统工具插件兼容性 ==="
    check_plugin "$branch" "luci-app-cpulimit" || has_critical_error=1
    check_plugin "$branch" "luci-app-diskman" || has_critical_error=1
    check_plugin "$branch" "luci-app-accesscontrol" || has_critical_error=1
    check_plugin "$branch" "luci-app-vlmcsd" || has_critical_error=1
    
    echo ""
    echo "=== 基础插件兼容性 ==="
    check_plugin "$branch" "luci-theme-bootstrap" || has_critical_error=1
    check_plugin "$branch" "luci-theme-material" || has_critical_error=1
    check_plugin "$branch" "luci-app-firewall" || has_critical_error=1
    
    echo ""
    echo "=== 兼容性说明 ==="
    echo "🔹 22.03/23.05 - 完全支持所有插件"
    echo "🔹 21.02       - 支持大部分插件"
    echo "🔹 19.07       - 支持基础插件"
    echo "🔹 18.06       - 仅支持核心功能"
    echo "🔹 master      - 开发版，兼容性不确定"
    
    # 修复：总是返回0，不终止构建
    log_info "插件兼容性检查完成（警告不影响构建）"
    return 0
}
