#!/bin/bash
echo "解压压缩的大文件..."
echo "注意: 运行此脚本将解压所有.gz文件并删除压缩文件"
read -p "继续? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  find . -name "*.gz" -type f 2>/dev/null | while read gzfile; do
    orig_file="${gzfile%.gz}"
    echo "解压: $gzfile -> $orig_file"
    gunzip -c "$gzfile" > "$orig_file" && rm -f "$gzfile" && echo "✅ 解压成功"
  done
  echo "所有文件解压完成"
else
  echo "取消解压"
fi
