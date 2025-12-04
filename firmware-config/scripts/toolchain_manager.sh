#!/bin/bash

# 工具链管理器
set -e

BUILD_DIR="/mnt/openwrt-build"
TOOLCHAIN_DIR="/mnt/openwrt-toolchain"
TOOLCHAIN_REPO_DIR="$GITHUB_WORKSPACE/toolchain-cache"
CACHE_VERSION="v1"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

# 生成工具链ID
generate_toolchain_id() {
    local branch="$1"
    local target="$2"
    local subtarget="$3"
    echo "${branch}-${target}-${subtarget}"
}

# 检查工具链是否有效
check_toolchain_valid() {
    local toolchain_id="$1"
    local toolchain_path="$TOOLCHAIN_DIR/$toolchain_id"
    
    if [ ! -d "$toolchain_path" ]; then
        return 1
    fi
    
    # 检查关键文件
    local required_files=(
        "toolchain_info.txt"
        "staging_dir/toolchain-mipsel_24kc_gcc-8.4.0_musl/bin/mipsel-openwrt-linux-gcc"
        "staging_dir/toolchain-mipsel_24kc_gcc-8.4.0_musl/bin/mipsel-openwrt-linux-g++"
        "staging_dir/toolchain-mipsel_24kc_gcc-8.4.0_musl/bin/mipsel-openwrt-linux-ld"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$toolchain_path/$file" ] || [ -d "$toolchain_path/$file" ]; then
            continue
        else
            log "❌ 工具链文件缺失: $file"
            return 1
        fi
    done
    
    return 0
}

# 从仓库恢复工具链
restore_toolchain_from_repo() {
    local toolchain_id="$1"
    local repo_path="$TOOLCHAIN_REPO_DIR/$toolchain_id"
    local dest_path="$TOOLCHAIN_DIR/$toolchain_id"
    
    if [ -d "$repo_path" ]; then
        log "📦 从仓库恢复工具链: $toolchain_id"
        mkdir -p "$dest_path"
        
        # 使用rsync恢复，保留权限
        if command -v rsync &> /dev/null; then
            rsync -av "$repo_path/" "$dest_path/"
        else
            cp -r "$repo_path/"* "$dest_path/" 2>/dev/null || true
        fi
        
        if check_toolchain_valid "$toolchain_id"; then
            log "✅ 工具链恢复成功"
            return 0
        else
            log "⚠️ 工具链已恢复但验证失败"
            return 1
        fi
    fi
    return 1
}

# 保存工具链到仓库
save_toolchain_to_repo() {
    local toolchain_id="$1"
    local src_path="$TOOLCHAIN_DIR/$toolchain_id"
    local repo_path="$TOOLCHAIN_REPO_DIR/$toolchain_id"
    
    if [ ! -d "$src_path" ]; then
        log "❌ 源工具链目录不存在: $src_path"
        return 1
    fi
    
    log "💾 保存工具链到仓库: $toolchain_id"
    mkdir -p "$repo_path"
    
    # 先清理旧内容
    rm -rf "$repo_path"/*
    
    # 复制关键文件（排除大文件）
    log "复制工具链文件..."
    
    # 1. 复制工具链信息
    if [ -f "$src_path/toolchain_info.txt" ]; then
        cp "$src_path/toolchain_info.txt" "$repo_path/"
    fi
    
    # 2. 复制toolchain_db.json
    if [ -f "$src_path/toolchain_db.json" ]; then
        cp "$src_path/toolchain_db.json" "$repo_path/"
    fi
    
    # 3. 复制关键的staging_dir内容（只复制工具链）
    if [ -d "$src_path/staging_dir" ]; then
        mkdir -p "$repo_path/staging_dir"
        
        # 只复制工具链目录
        find "$src_path/staging_dir" -maxdepth 1 -name "toolchain-*" -type d | while read toolchain; do
            local toolchain_name=$(basename "$toolchain")
            log "复制工具链: $toolchain_name"
            
            # 使用tar压缩保存
            cd "$src_path/staging_dir"
            tar -czf "$repo_path/staging_dir/${toolchain_name}.tar.gz" "$toolchain_name"
            cd -
        done
        
        # 复制其他必要文件
        cp -r "$src_path/staging_dir/.config" "$repo_path/staging_dir/" 2>/dev/null || true
    fi
    
    # 4. 创建工具链数据库
    create_toolchain_database "$toolchain_id"
    
    log "✅ 工具链保存完成: $(du -sh $repo_path | cut -f1)"
    return 0
}

# 创建工具链数据库
create_toolchain_database() {
    local toolchain_id="$1"
    local repo_path="$TOOLCHAIN_REPO_DIR/$toolchain_id"
    
    cat > "$repo_path/toolchain_db.json" << EOF
{
  "version": "$CACHE_VERSION",
  "toolchain_id": "$toolchain_id",
  "created": "$(date -Iseconds)",
  "size": "$(du -sh $repo_path 2>/dev/null | cut -f1 || echo "0")",
  "files": {
    "info": "$(ls -la $repo_path/toolchain_info.txt 2>/dev/null | head -1 || echo "missing")",
    "staging_dir": "$(find $repo_path/staging_dir -name "*.tar.gz" 2>/dev/null | wc -l) 个工具链包",
    "config": "$(ls -la $repo_path/staging_dir/.config 2>/dev/null | head -1 || echo "missing")"
  },
  "statistics": {
    "restores": 0,
    "last_restored": null,
    "hits": 0,
    "misses": 0
  }
}
EOF
}

# 更新工具链数据库统计
update_toolchain_stats() {
    local toolchain_id="$1"
    local action="$2"  # hit 或 miss
    
    local db_file="$TOOLCHAIN_REPO_DIR/$toolchain_id/toolchain_db.json"
    
    if [ -f "$db_file" ]; then
        if [ "$action" = "hit" ]; then
            # 增加命中计数
            local current_hits=$(jq '.statistics.hits // 0' "$db_file")
            local current_restores=$(jq '.statistics.restores // 0' "$db_file")
            
            jq --argjson hits $((current_hits + 1)) \
               --argjson restores $((current_restores + 1)) \
               --arg date "$(date -Iseconds)" \
               '.statistics.hits = $hits | 
                .statistics.restores = $restores |
                .statistics.last_restored = $date' \
               "$db_file" > "${db_file}.tmp"
            mv "${db_file}.tmp" "$db_file"
        elif [ "$action" = "miss" ]; then
            local current_misses=$(jq '.statistics.misses // 0' "$db_file")
            jq --argjson misses $((current_misses + 1)) \
               '.statistics.misses = $misses' \
               "$db_file" > "${db_file}.tmp"
            mv "${db_file}.tmp" "$db_file"
        fi
    fi
}

# 压缩工具链
compress_toolchain() {
    local toolchain_id="$1"
    local src_path="$TOOLCHAIN_DIR/$toolchain_id"
    local output_file="$GITHUB_WORKSPACE/${toolchain_id}_toolchain.tar.gz"
    
    if [ ! -d "$src_path" ]; then
        log "❌ 工具链目录不存在: $src_path"
        return 1
    fi
    
    log "压缩工具链: $toolchain_id"
    
    # 进入目录进行压缩
    cd "$src_path"
    
    # 创建压缩包（排除大文件）
    tar --exclude='*.o' --exclude='*.a' --exclude='*.so' \
        --exclude='build_dir' --exclude='tmp' \
        -czf "$output_file" .
    
    local size=$(du -h "$output_file" | cut -f1)
    log "✅ 工具链压缩完成: $output_file ($size)"
    
    cd -
    return 0
}

# 主函数
main() {
    case "$1" in
        "restore")
            local branch="$2"
            local target="$3"
            local subtarget="$4"
            
            local toolchain_id=$(generate_toolchain_id "$branch" "$target" "$subtarget")
            
            log "尝试恢复工具链: $toolchain_id"
            
            # 1. 检查本地缓存
            if check_toolchain_valid "$toolchain_id"; then
                log "✅ 本地工具链有效"
                update_toolchain_stats "$toolchain_id" "hit"
                return 0
            fi
            
            # 2. 从仓库恢复
            if restore_toolchain_from_repo "$toolchain_id"; then
                update_toolchain_stats "$toolchain_id" "hit"
                return 0
            fi
            
            # 3. 都没有，需要重新构建
            log "❌ 工具链不存在，需要重新构建"
            update_toolchain_stats "$toolchain_id" "miss"
            return 1
            ;;
            
        "save")
            local branch="$2"
            local target="$3"
            local subtarget="$4"
            
            local toolchain_id=$(generate_toolchain_id "$branch" "$target" "$subtarget")
            
            if [ ! -d "$TOOLCHAIN_DIR/$toolchain_id" ]; then
                log "⚠️ 工具链目录不存在，跳过保存"
                return 0
            fi
            
            log "保存工具链: $toolchain_id"
            
            # 保存到仓库
            if save_toolchain_to_repo "$toolchain_id"; then
                # 同时压缩备份
                compress_toolchain "$toolchain_id"
                log "✅ 工具链保存完成"
                return 0
            else
                log "❌ 工具链保存失败"
                return 1
            fi
            ;;
            
        "list")
            echo "=== 可用的工具链 ==="
            if [ -d "$TOOLCHAIN_REPO_DIR" ]; then
                find "$TOOLCHAIN_REPO_DIR" -name "toolchain_db.json" | while read db; do
                    local id=$(jq -r '.toolchain_id' "$db" 2>/dev/null)
                    local created=$(jq -r '.created' "$db" 2>/dev/null)
                    local size=$(jq -r '.size' "$db" 2>/dev/null)
                    if [ -n "$id" ]; then
                        echo "🔧 $id | 📅 $created | 📦 $size"
                    fi
                done
            else
                echo "暂无工具链"
            fi
            ;;
            
        "cleanup")
            local days="${2:-30}"
            log "清理超过 $days 天的工具链"
            
            if [ -d "$TOOLCHAIN_REPO_DIR" ]; then
                find "$TOOLCHAIN_REPO_DIR" -name "toolchain_db.json" -mtime "+$days" | while read db; do
                    local dir=$(dirname "$db")
                    local id=$(basename "$(dirname "$dir")")
                    log "清理旧工具链: $id"
                    rm -rf "$dir"
                done
            fi
            ;;
            
        *)
            echo "用法: $0 <command> [args]"
            echo "命令:"
            echo "  restore <branch> <target> <subtarget>  - 恢复工具链"
            echo "  save <branch> <target> <subtarget>     - 保存工具链"
            echo "  list                                   - 列出工具链"
            echo "  cleanup [days]                         - 清理旧工具链"
            exit 1
            ;;
    esac
}

main "$@"
