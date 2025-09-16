#!/bin/bash

set -euo pipefail

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户运行或使用 sudo 命令。"
    exit 1
fi

# 函数：检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 自动安装 jq，根据系统判断安装方法
install_jq() {
    if command_exists jq; then
        return 0
    fi

    # 检查系统类型并选择安装命令
    if command_exists apt-get; then
        apt-get update && apt-get install -y jq
    elif command_exists yum; then
        yum install -y jq
    elif command_exists apk; then
        apk add jq
    elif command_exists pacman; then
        pacman -S --noconfirm jq
    else
        return 1
    fi

    # 验证 jq 是否安装成功
    if ! command_exists jq; then
        return 1
    fi
    
    return 0
}

# 判断是否安装了docker
if ! command_exists docker; then
    echo "Docker 未安装，请先安装 Docker。"
    exit 1
fi

# 定义全局变量，记录哪些文件被修改过，便于恢复
MODIFIED_FILES=()

# 将修改过的文件加入记录
track_modified_file() {
    local file=$1
    for tracked in "${MODIFIED_FILES[@]}"; do
        if [ "$tracked" = "$file" ]; then
            return
        fi
    done
    MODIFIED_FILES+=("$file")
}

# 检查 Docker 配置中的 2375 端口
check_docker_config() {
    local found=false
    
    # 检查 daemon.json
    if [ -f /etc/docker/daemon.json ]; then
        if grep -q '"hosts":.*"tcp://0.0.0.0:2375"' /etc/docker/daemon.json; then
            echo "在 /etc/docker/daemon.json 中发现端口 2375"
            found=true
        fi
    fi
    
    # 检查 docker.service 文件
    for path in /usr/lib/systemd/system/docker.service /lib/systemd/system/docker.service; do
        if [ -f "$path" ]; then
            if grep -q ' -H tcp://0.0.0.0:2375' "$path" || grep -q ' --host tcp://0.0.0.0:2375' "$path"; then
                echo "在 $path 中发现端口 2375"
                found=true
            fi
        fi
    done
    
    # 检查 docker.service.d 目录下的文件
    if [ -d /etc/systemd/system/docker.service.d/ ]; then
        for file in /etc/systemd/system/docker.service.d/*; do
            if [ -f "$file" ]; then
                if grep -q ' -H tcp://0.0.0.0:2375' "$file" || grep -q ' --host tcp://0.0.0.0:2375' "$file"; then
                    echo "在 $file 中发现端口 2375"
                    found=true
                fi
            fi
        done
    fi
    
    # 检查 docker.socket 文件
    if [ -f /etc/systemd/system/docker.socket ]; then
        if grep -q 'ListenStream=2375' /etc/systemd/system/docker.socket; then
            echo "在 /etc/systemd/system/docker.socket 中发现端口 2375"
            found=true
        fi
    fi
    
    if [ "$found" = true ]; then
        return 0
    fi

    return 1
}

# 判断docker是否开放2375端口
check_docker_port() {
    if check_docker_config; then
        return 0
    fi
    
    return 1
}

# 备份配置文件
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        cp "$file" "$file.bak"
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

    # 备份docker.socket文件
    backup_file /etc/systemd/system/docker.socket

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
        local current_config
        current_config=$(cat /etc/docker/daemon.json)

        # 安装jq
        if ! install_jq; then
            return 1
        fi

        # 移除2375端口配置，并在 hosts 为空数组时删除该字段
        local updated_config
        updated_config=$(echo "$current_config" | jq '
            if .hosts then
                .hosts -= ["tcp://0.0.0.0:2375"]
                | (if (.hosts | length) == 0 then del(.hosts) else . end)
            else
                .
            end
        ')
        echo "$updated_config" | tee /etc/docker/daemon.json > /dev/null
        track_modified_file /etc/docker/daemon.json
    fi
}

# 更新docker服务配置文件，移除2375端口
update_docker_service_files() {
    # 更新主要的 docker.service 文件
    for path in /usr/lib/systemd/system/docker.service /lib/systemd/system/docker.service; do
        if [ -f "$path" ]; then
            if grep -q 'tcp://0.0.0.0:2375' "$path"; then
                sed -i -E 's/ (-H|--host)[ =]tcp:\/\/0.0.0.0:2375//g' "$path"
                track_modified_file "$path"
            fi
        fi
    done

    # 更新 docker.service.d 目录下的文件
    if [ -d /etc/systemd/system/docker.service.d/ ]; then
        for file in /etc/systemd/system/docker.service.d/*; do
            if [ -f "$file" ]; then
                if grep -q 'tcp://0.0.0.0:2375' "$file"; then
                    sed -i 's/ -H tcp:\/\/0.0.0.0:2375//g' "$file"
                    sed -i 's/ --host tcp:\/\/0.0.0.0:2375//g' "$file"
                    track_modified_file "$file"
                fi
            fi
        done
    fi
    
    # 更新 docker.socket 文件
    if [ -f /etc/systemd/system/docker.socket ]; then
        if grep -q 'ListenStream=2375' /etc/systemd/system/docker.socket; then
            sed -i '/ListenStream=2375/d' /etc/systemd/system/docker.socket
            track_modified_file /etc/systemd/system/docker.socket
        fi
    fi
}

# 恢复备份的文件
restore_backups() {
    for file in "${MODIFIED_FILES[@]}"; do
        if [ -f "$file.bak" ]; then
            mv "$file.bak" "$file"
        fi
    done
}

# 重新加载systemd配置
reload_systemd() {
    systemctl daemon-reload
}

# 重启docker服务
restart_docker() {
    # 捕获第一次重启失败的错误信息
    if ! restart_output=$(systemctl restart docker 2>&1); then
        restore_backups
        reload_systemd

        # 捕获恢复后再次重启的错误信息
        if ! restart_output=$(systemctl restart docker 2>&1); then
            echo "恢复备份后 Docker 仍然无法重启。错误详情："
            echo "$restart_output"
            echo "需要手动干预。"
            exit 1
        fi
    fi
}

# 捕获错误并恢复
trap 'restore_backups; exit 1' ERR

# 主程序
if check_docker_port; then
    backup_all_files
    update_daemon_json
    update_docker_service_files
    reload_systemd
    restart_docker
    echo "端口 2375 配置已移除。"
else
    echo "端口 2375 未开放，无需更改。"
fi
