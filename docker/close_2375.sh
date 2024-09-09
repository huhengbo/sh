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

# 自动安装 jq，根据系统判断安装方法
install_jq() {
    if command_exists jq; then
        echo "jq is already installed."
        return 0
    fi

    echo "jq is not installed. Trying to install jq..."

    # 检查系统类型并选择安装命令
    if command_exists apt-get; then
        echo "Detected Debian/Ubuntu. Installing jq using apt-get..."
        sudo apt-get update && sudo apt-get install -y jq
    elif command_exists yum; then
        echo "Detected Red Hat/CentOS/AlmaLinux. Installing jq using yum..."
        sudo yum install -y jq
    elif command_exists apk; then
        echo "Detected Alpine. Installing jq using apk..."
        sudo apk add jq
    elif command_exists pacman; then
        echo "Detected Arch Linux. Installing jq using pacman..."
        sudo pacman -S --noconfirm jq
    else
        echo "Unsupported system. Please install jq manually."
        exit 1
    fi

    # 验证 jq 是否安装成功
    if ! command_exists jq; then
        echo "Failed to install jq. Please install it manually."
        exit 1
    fi
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

# 定义全局变量，记录哪些文件被修改过，便于恢复
MODIFIED_FILES=()

# 判断docker是否开放2375端口
check_docker_port() {
    # 获取docker信息并检查警告信息
    if docker system info | grep -q '0.0.0.0:2375'; then
        return 0  # 端口2375已开放
    else
        return 1  # 端口2375未开放
    fi
}

# 备份配置文件
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        ${SUDO_CMD} cp "$file" "$file.bak"
        echo "Backup of $file created."
        MODIFIED_FILES+=("$file")
    fi
}

# 备份相关的所有配置文件
backup_all_files() {
    # 备份daemon.json
    backup_file /etc/docker/daemon.json

    # 备份docker.service文件
    backup_file /usr/lib/systemd/system/docker.service
    backup_file /lib/systemd/system/docker.service

    # 备份/etc/systemd/system/docker.service.d/下的所有文件
    if [ -d /etc/systemd/system/docker.service.d/ ]; then
        for file in /etc/systemd/system/docker.service.d/*; do
            backup_file "$file"
        done
    fi
}

# 更新daemon.json文件以移除2375端口
update_daemon_json() {
    if [ -f /etc/docker/daemon.json ]; then
        current_config=$(cat /etc/docker/daemon.json)

        # 安装jq
        install_jq

        updated_config=$(echo "$current_config" | jq 'if .hosts then .hosts -= ["tcp://0.0.0.0:2375"] else . end')
        echo "$updated_config" | ${SUDO_CMD} tee /etc/docker/daemon.json > /dev/null
        echo "daemon.json updated to remove port 2375."
    fi
}

# 更新docker服务配置文件，移除2375端口
update_docker_service_files() {
    for path in /usr/lib/systemd/system/docker.service /lib/systemd/system/docker.service; do
        if [ -f "$path" ]; then
            ${SUDO_CMD} sed -i 's/ -H tcp:\/\/0.0.0.0:2375//g' "$path"
            ${SUDO_CMD} sed -i 's/ --host tcp:\/\/0.0.0.0:2375//g' "$path"
            echo "Port 2375 removed from $path."
        fi
    done

    # 处理/etc/systemd/system/docker.service.d/目录下的文件
    if [ -d /etc/systemd/system/docker.service.d/ ]; then
        for file in /etc/systemd/system/docker.service.d/*; do
            if [ -f "$file" ]; then
                ${SUDO_CMD} sed -i 's/ -H tcp:\/\/0.0.0.0:2375//g' "$file"
                ${SUDO_CMD} sed -i 's/ --host tcp:\/\/0.0.0.0:2375//g' "$file"
                echo "Port 2375 removed from $file."
            fi
        done
    fi
}

# 恢复备份的文件
restore_backups() {
    for file in "${MODIFIED_FILES[@]}"; do
        if [ -f "$file.bak" ]; then
            echo "Restoring $file from backup..."
            ${SUDO_CMD} mv "$file.bak" "$file"
            echo "$file restored."
        fi
    done
}

# 重新加载systemd配置
reload_systemd() {
    ${SUDO_CMD} systemctl daemon-reload
    echo "Systemd daemon reloaded."
}

# 重启docker服务
restart_docker() {
    # 捕获第一次重启失败的错误信息
    if ! restart_output=$(${SUDO_CMD} systemctl restart docker 2>&1); then
        echo "Failed to restart Docker. Error details:"
        echo "$restart_output"  # 打印错误信息

        echo "Restoring backups..."
        restore_backups
        reload_systemd

        # 捕获恢复后再次重启的错误信息
        if ! restart_output=$(${SUDO_CMD} systemctl restart docker 2>&1); then
            echo "Failed to restart Docker even after restoring backups. Error details:"
            echo "$restart_output"  # 打印错误信息
            echo "Manual intervention is required."
            exit 1
        else
            echo "Docker successfully restarted after restoring backups."
            return 0  # 正常返回
        fi
    else
        echo "Docker successfully restarted."
        return 0  # 正常返回
    fi
}

# 捕获错误并恢复
trap 'restore_backups; echo "An error occurred, restoring backups."; exit 1' ERR

# 主程序
if check_docker_port; then
    echo "2375 port is open. Proceeding with configuration update."

    # 确认更新操作
    read -p "This will remove port 2375 from Docker configuration. Do you want to proceed? (y/n): " confirmation
    if [[ "$confirmation" != "y" ]]; then
        echo "Operation canceled."
        exit 0
    fi

    backup_all_files
    update_daemon_json
    update_docker_service_files
    reload_systemd
    restart_docker
    echo "Configuration update completed."
else
    echo "2375 port is not open. No changes needed."
fi
