#!/bin/bash

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or use sudo."
    exit 1
fi

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
    if netstat -tuln | grep -q '0.0.0.0:2375'; then
        return 0  # 端口开放
    else
        return 1  # 端口未开放
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
    if [ -f /etc/docker/daemon.json.bak ]; then
        current_config=$(cat /etc/docker/daemon.json.bak)

        if command_exists jq; then
            updated_config=$(echo "$current_config" | jq 'if .hosts then .hosts -= ["tcp://0.0.0.0:2375"] else . end')
            echo "$updated_config" | ${SUDO_CMD} tee /etc/docker/daemon.json > /dev/null
        else
            echo "jq is not installed. Cannot reliably update JSON."
            exit 1
        fi
    fi
}

# 更新docker服务配置文件，移除2375端口
update_docker_service() {
    for path in /usr/lib/systemd/system/docker.service /lib/systemd/system/docker.service; do
        if [ -f "$path" ]; then
            ${SUDO_CMD} sed -i 's/ -H tcp:\/\/0.0.0.0:2375//g' "$path"
            break
        fi
    done
}

# 恢复备份
restore_backup() {
    if [ -f /etc/docker/daemon.json.bak ]; then
        echo "Restoring daemon.json from backup..."
        ${SUDO_CMD} mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
    fi
}

# 重新加载systemd配置
reload_systemd() {
    ${SUDO_CMD} systemctl daemon-reload
}

restart_docker() {
    # 捕获第一次重启失败的错误信息
    if ! restart_output=$(${SUDO_CMD} systemctl restart docker 2>&1); then
        echo "Failed to restart Docker. Error details:"
        echo "$restart_output"  # 打印错误信息
        
        echo "Restoring backup..."
        restore_backup
        reload_systemd

        # 捕获恢复后再次重启的错误信息
        if ! restart_output=$(${SUDO_CMD} systemctl restart docker 2>&1); then
            echo "Failed to restart Docker even after restoring backup. Error details:"
            echo "$restart_output"  # 打印错误信息
            echo "Manual intervention is required."
            exit 1
        else
            echo "Docker successfully restarted after restoring backup."
            return 0  # 正常返回
        fi
    fi
}


# 捕获错误并恢复
trap 'restore_backup; echo "An error occurred, restoring daemon.json."; exit 1' ERR

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
