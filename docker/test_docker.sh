#!/bin/bash

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本。" >&2
    exit 1
fi

cat <<'WARN'
警告: 本示例脚本会在 2375 端口上暴露 Docker 守护进程且不启用 TLS, 仅供隔离测试环境使用, 请勿在生产环境执行。
WARN

# 更新软件源并安装基础依赖
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg

# 导入 Docker 官方 GPG 密钥
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod 0644 /etc/apt/keyrings/docker.gpg

# 解析发行版信息
. /etc/os-release
codename=${VERSION_CODENAME:-}
if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
    codename=$(lsb_release -cs)
fi
if [ -z "$codename" ]; then
    echo "无法识别当前系统的发行版代号" >&2
    exit 1
fi

# 写入 Docker 官方仓库
cat <<EOF_REPO >/etc/apt/sources.list.d/docker.list
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $codename stable
EOF_REPO

apt-get update
apt-get install -y docker-ce

systemctl enable docker
systemctl start docker

# 创建 systemd override 文件, 暴露 2375 端口（未加密）
mkdir -p /etc/systemd/system/docker.service.d
cat <<'EOF_OVERRIDE' >/etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375
EOF_OVERRIDE

systemctl daemon-reload
systemctl restart docker

echo "Docker 已安装完成并监听未加密的 2375 端口, 请务必在调试完成后恢复安全配置。"
