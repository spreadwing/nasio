#!/bin/bash
set -e

export NAS_UID=${PUID:-1000}
export NAS_GID=${PGID:-1000}

# 设置全局 umask 0000，确保新建目录(0777)与文件(0666)对 SMB / 绿联文件管理器 / 其它容器完全开放，零权限冲突
umask 0000

# 确保运行时数据与回收站目录存在并开放读写权限
mkdir -p /app/data /volume1/.trash 2>/dev/null || true
chmod 777 /app/data /volume1/.trash 2>/dev/null || true
chown -R "$NAS_UID:$NAS_GID" /app/data /volume1/.trash 2>/dev/null || true

# 打通宿主机共享存储池顶层及二级目录的基础读写与穿透权限 (a+rwx)，
# 避免绿联 UGOS 重置共享目录权限后导致 qbittorrent (1000:1000) 报 missingFiles 或外部访问受阻
for dir in /volume1/Download /volume1/Media /volume1/Media/Comic; do
    if [ -d "$dir" ]; then
        chmod a+rwx "$dir" 2>/dev/null || true
    fi
done

echo "[Nasio] Starting server with root DAC capability and target NAS ownership alignment ($NAS_UID:$NAS_GID, umask=0000)..."

# 直接以容器默认 root 启动主程序（保留 CAP_DAC_OVERRIDE 與 CAP_CHOWN，无需开启 Docker 特权模式即可读写任意外部创建的目录，
# 同时由 Python 层自动将新建目录/文件的属主对齐为宿主机父目录或 $NAS_UID:$NAS_GID 并赋予 0777/0666 权限）
exec "$@"

