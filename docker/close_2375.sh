#!/bin/bash

# 函数：检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 判断是否安装了docker
if ! command_exists docker; then
    echo "Docker is not installed. Please install Docker first."
    exit 1
fi

# 判断是否安装了sudo
if command_exists sudo; then
    SUDO_CMD="sudo"
else
    SUDO_CMD=""
fi

# 检查daemon.json文件是否存在
if [ -f /etc/docker/daemon.json ]; then
    # 备份当前的daemon.json配置文件
    ${SUDO_CMD} mv /etc/docker/daemon.json /etc/docker/daemon.json.bak

    # 读取当前daemon.json文件内容
    current_config=$(cat /etc/docker/daemon.json.bak)

    # 解析当前配置以检查是否包含2375端口
    if echo "$current_config" | grep -q 'tcp://0.0.0.0:2375'; then
        # 移除2375端口
        updated_config=$(echo "$current_config" | sed 's/\"tcp:\/\/0.0.0.0:2375\"//g')
        # 更新daemon.json配置文件以移除2375端口
        echo "$updated_config" | ${SUDO_CMD} tee /etc/docker/daemon.json > /dev/null
    else
        # 如果2375端口未配置，只是将备份文件放回去
        ${SUDO_CMD} mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
    fi
else
    echo "daemon.json file does not exist. Skipping related configuration updates."
fi

# 确保docker服务不使用2375端口，覆盖docker.service文件中的ExecStart参数（如果存在2375端口配置）
if [ -f /usr/lib/systemd/system/docker.service ]; then
    ${SUDO_CMD} sed -i 's/ -H tcp:\/\/0.0.0.0:2375//g' /usr/lib/systemd/system/docker.service
else
    echo "docker.service file does not exist. Skipping related configuration updates."
fi

# 重新加载systemd配置
${SUDO_CMD} systemctl daemon-reload

# 重启docker服务
${SUDO_CMD} systemctl restart docker
