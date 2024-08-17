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

# 判断docker是否开放2375端口
check_docker_port() {
    if docker system info | grep -q '0.0.0.0:2375'; then
        return 0
    else
        return 1
    fi
}

# 备份daemon.json文件
backup_daemon_json() {
    if [ -f /etc/docker/daemon.json ]; then
        ${SUDO_CMD} cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
    fi
}

# 更新daemon.json文件以移除2375端口
update_daemon_json() {
    if [ -f /etc/docker/daemon.json ]; then
        current_config=$(cat /etc/docker/daemon.json.bak)
        
        # 使用jq移除tcp://0.0.0.0:2375配置
        if command_exists jq; then
            updated_config=$(echo "$current_config" | jq 'del(.hosts[] | select(. == "tcp://0.0.0.0:2375"))')
            echo "$updated_config" | ${SUDO_CMD} tee /etc/docker/daemon.json > /dev/null
        else
            echo "jq is not installed. Manually handling JSON."
            updated_config=$(echo "$current_config" | sed 's/\"tcp:\/\/0.0.0.0:2375\"//g')
            echo "$updated_config" | ${SUDO_CMD} tee /etc/docker/daemon.json > /dev/null
        fi
    fi
}

# 确保docker服务不使用2375端口，检查多个常见路径
update_docker_service() {
    for path in /usr/lib/systemd/system/docker.service /lib/systemd/system/docker.service; do
        if [ -f "$path" ]; then
            ${SUDO_CMD} sed -i 's/ -H tcp:\/\/0.0.0.0:2375//g' "$path"
            break
        fi
    done
}

# 重新加载systemd配置
reload_systemd() {
    ${SUDO_CMD} systemctl daemon-reload
}

# 重启docker服务
restart_docker() {
    if ! ${SUDO_CMD} systemctl restart docker; then
        echo "Docker restart failed. Restoring backup."
        ${SUDO_CMD} mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
        reload_systemd
        if ! ${SUDO_CMD} systemctl restart docker; then
            echo "Failed to restart Docker after restoring backup. Please check the system manually."
            exit 1
        fi
        echo "Docker successfully restarted after restoring backup."
        exit 1
    fi
}

# 主程序
if check_docker_port; then
    echo "2375 port is open. Proceeding with configuration update."
    backup_daemon_json
    update_daemon_json
    update_docker_service
    reload_systemd
    restart_docker
    echo "Configuration update completed."
else
    echo "2375 port is not open. No changes needed."
fi
