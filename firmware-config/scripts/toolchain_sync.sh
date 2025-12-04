#!/bin/bash

# 工具链同步脚本
set -e

BUILD_DIR="/mnt/openwrt-build"
TOOLCHAIN_DIR="/mnt/openwrt-toolchain"
REPO_DIR="$GITHUB_WORKSPACE/openwrt-config/toolchain-cache"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

# 生成工具链ID
get_toolchain_id() {
    local branch="$1"
    local target="$2"
    local subtarget="$3"
    echo "${branch}-${target}-${subtarget}"
}

# 检查工具链是否有效
check_toolchain() {
    local toolchain_id="$1"
    local toolchain_path="$TOOLCHAIN_DIR/$toolchain_id"
    
    if [ ! -d "$toolchain_path" ]; then
        return 1
    fi
    
    # 检查是否有toolchain_info.txt文件
    if [ ! -f "$toolchain_path/toolchain_info.txt" ]; then
        return 1
    fi
    
    # 检查是否有staging_dir目录
    if [ ! -d "$toolchain_path/staging_dir" ]; then
        return 1
    fi
    
    return 0
}

# 从仓库下载工具链
download_from_repo() {
    local toolchain_id="$1"
    local repo_path="$REPO_DIR/$toolchain_id"
    local dest_path="$TOOLCHAIN_DIR/$toolchain_id"
    
    log "下载工具链: $toolchain_id"
    
    if [ ! -d "$repo_path" ]; then
        log "❌ 仓库中不存在此工具链"
        return 1
    fi
    
    mkdir -p "$dest_path"
    
    # 复制工具链文件
    if [ -d "$repo_path" ]; then
        log "复制工具链文件..."
        cp -r "$repo_path/"* "$dest_path/" 2>/dev/null || true
        
        if [ -f "$dest_path/toolchain_info.txt" ]; then
            log "✅ 工具链下载成功"
            cat "$dest_path/toolchain_info.txt"
            return 0
        else
            log "❌ 工具链文件不完整"
            return 1
        fi
    else
        log "❌ 仓库目录为空"
        return 1
    fi
}

# 上传工具链到仓库
upload_to_repo() {
    local toolchain_id="$1"
    local src_path="$TOOLCHAIN_DIR/$toolchain_id"
    local repo_path="$REPO_DIR/$toolchain_id"
    
    log "上传工具链: $toolchain_id"
    
    if [ ! -d "$src_path" ]; then
        log "❌ 工具链目录不存在"
        return 1
    fi
    
    mkdir -p "$repo_path"
    
    # 清理旧文件
    rm -rf "$repo_path"/*
    
    # 复制工具链文件
    log "复制文件..."
    cp -r "$src_path/"* "$repo_path/" 2>/dev/null || true
    
    # 创建上传标记
    echo "上传时间: $(date)" > "$repo_path/upload_time.txt"
    echo "工具链ID: $toolchain_id" >> "$repo_path/upload_time.txt"
    echo "大小: $(du -sh $src_path 2>/dev/null | cut -f1)" >> "$repo_path/upload_time.txt"
    
    log "✅ 工具链上传完成"
    return 0
}

# 列出所有工具链
list_toolchains() {
    log "可用的工具链:"
    
    if [ -d "$REPO_DIR" ]; then
        for dir in "$REPO_DIR"/*; do
            if [ -d "$dir" ]; then
                local toolchain_id=$(basename "$dir")
                if [ -f "$dir/toolchain_info.txt" ]; then
                    local info=$(head -1 "$dir/toolchain_info.txt" 2>/dev/null)
                    local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                    echo "🔧 $toolchain_id | $info | 📦 $size"
                else
                    echo "🔧 $toolchain_id | 📦 $(du -sh "$dir" 2>/dev/null | cut -f1)"
                fi
            fi
        done
    else
        log "❌ 仓库目录不存在"
    fi
}

# 清理旧工具链
cleanup_old() {
    local days="${1:-30}"
    log "清理超过 $days 天的工具链"
    
    if [ -d "$REPO_DIR" ]; then
        find "$REPO_DIR" -name "upload_time.txt" -mtime "+$days" | while read file; do
            local dir=$(dirname "$file")
            local toolchain_id=$(basename "$dir")
            log "清理: $toolchain_id"
            rm -rf "$dir"
        done
    fi
}

# 主函数
main() {
    case "$1" in
        "download")
            local branch="$2"
            local target="$3"
            local subtarget="$4"
            
            local toolchain_id=$(get_toolchain_id "$branch" "$target" "$subtarget")
            download_from_repo "$toolchain_id"
            ;;
            
        "upload")
            local branch="$2"
            local target="$3"
            local subtarget="$4"
            
            local toolchain_id=$(get_toolchain_id "$branch" "$target" "$subtarget")
            upload_to_repo "$toolchain_id"
            ;;
            
        "list")
            list_toolchains
            ;;
            
        "cleanup")
            cleanup_old "$2"
            ;;
            
        *)
            echo "用法: $0 <command> [args]"
            echo "命令:"
            echo "  download <branch> <target> <subtarget>  - 从仓库下载工具链"
            echo "  upload <branch> <target> <subtarget>    - 上传工具链到仓库"
            echo "  list                                   - 列出所有工具链"
            echo "  cleanup [days]                         - 清理旧工具链"
            exit 1
            ;;
    esac
}

main "$@"
