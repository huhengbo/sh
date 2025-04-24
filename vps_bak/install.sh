#!/bin/bash
#
# S3备份系统安装脚本
# 用于安装、卸载、配置和管理S3备份任务
#

# 使用局部变量，避免与环境变量冲突
_VERSION="1.0.1"
GITHUB_REPO="https://raw.githubusercontent.com/huhengbo/sh/main/vps_bak"
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$INSTALL_DIR"
CONFIG_FILE="$CONFIG_DIR/config.json"
RCLONE_CONFIG="$CONFIG_DIR/rclone.conf"
BACKUP_SCRIPT="$CONFIG_DIR/backup.sh"
LOG_DIR="$CONFIG_DIR/logs"
CRON_JOB_MARKER="#S3BACKUP"

# 颜色设置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查目录结构
check_directories() {
    # 确保配置目录存在
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
    fi
    
    # 确保日志目录存在
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
    
    echo -e "${GREEN}目录结构检查完成${NC}"
}

# 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS="Debian"
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | cut -d ' ' -f 1)
        VER=$(cat /etc/redhat-release | sed 's/.*release\ //' | sed 's/\ .*//')
    elif uname -s | grep -q "Darwin"; then
        OS="Darwin"
        VER=$(sw_vers -productVersion)
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi

    echo "检测到操作系统: $OS $VER"
}

# 检查版本更新
check_version() {
    echo -e "${BLUE}检查更新...${NC}"

    # 获取一个唯一标识符，来避免缓存问题
    TIMESTAMP=$(date +%s)
    
    # 检查是否安装wget或curl
    if command -v wget &> /dev/null; then
        latest_version=$(wget -qO- "$GITHUB_REPO/version.txt?t=$TIMESTAMP" 2>/dev/null)
    elif command -v curl &> /dev/null; then
        latest_version=$(curl -s "$GITHUB_REPO/version.txt?t=$TIMESTAMP" 2>/dev/null)
    else
        echo -e "${YELLOW}未找到wget或curl，无法检查更新。${NC}"
        return 1
    fi
    
    # 检查是否成功获取版本
    if [ -z "$latest_version" ]; then
        echo -e "${YELLOW}无法获取最新版本信息。${NC}"
        return 1
    fi
    
    # 去除可能的空格和换行符
    latest_version=$(echo "$latest_version" | tr -d '[:space:]')

    # 检查获取到的版本号是否有效
    if [ -z "$latest_version" ] || [[ ! "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${YELLOW}获取到的版本号 '$latest_version' 格式无效，跳过更新检查。${NC}"
        return 1
    fi
    
    # 比较版本
    if [ "$_VERSION" != "$latest_version" ]; then
        echo -e "${YELLOW}发现新版本: $latest_version (当前版本: $_VERSION)${NC}"
        read -p "是否更新到最新版本? (y/n): " update_now
        if [[ $update_now == "y" || $update_now == "Y" ]]; then
            update_scripts
        else
            echo -e "${YELLOW}您可以稍后通过选择'6'来更新${NC}"
        fi
    else
        echo -e "${GREEN}已是最新版本: $_VERSION${NC}"
    fi
}

# 更新脚本
update_scripts() {
    echo -e "${BLUE}开始更新脚本...${NC}"
    
    # 备份当前配置
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
        echo "已备份当前配置到 $CONFIG_FILE.bak"
    fi
    
    if [ -f "$RCLONE_CONFIG" ]; then
        cp "$RCLONE_CONFIG" "$RCLONE_CONFIG.bak"
        echo "已备份rclone配置到 $RCLONE_CONFIG.bak"
    fi
    
    # 创建临时目录
    TMP_DIR=$(mktemp -d)
    echo "使用临时目录: $TMP_DIR"
    
    # 下载最新脚本到临时目录
    if command -v wget &> /dev/null; then
        wget -O "$TMP_DIR/install.sh" "$GITHUB_REPO/install.sh" && \
        wget -O "$TMP_DIR/backup.sh" "$GITHUB_REPO/backup.sh"
        download_status=$?
    elif command -v curl &> /dev/null; then
        curl -o "$TMP_DIR/install.sh" "$GITHUB_REPO/install.sh" && \
        curl -o "$TMP_DIR/backup.sh" "$GITHUB_REPO/backup.sh"
        download_status=$?
    else
        echo -e "${RED}未找到wget或curl，无法更新。${NC}"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    # 检查下载是否成功
    if [ $download_status -ne 0 ]; then
        echo -e "${RED}下载更新失败。${NC}"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    # 检查文件是否实际存在
    if [ ! -f "$TMP_DIR/install.sh" ] || [ ! -f "$TMP_DIR/backup.sh" ]; then
        echo -e "${RED}下载的文件不存在，更新失败。${NC}"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    # 检查下载的install.sh文件中的版本号
    downloaded_version=$(grep -E "^_VERSION=\"[0-9]+\.[0-9]+\.[0-9]+\"" "$TMP_DIR/install.sh" | cut -d'"' -f2)
    if [ -z "$downloaded_version" ]; then
        echo -e "${RED}无法从下载的文件中获取版本号，更新失败。${NC}"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    echo -e "下载的文件版本: ${GREEN}$downloaded_version${NC}"
    
    # 确保下载的版本是最新的
    if [ "$downloaded_version" != "$latest_version" ]; then
        echo -e "${RED}下载的版本号($downloaded_version)与期望的版本号($latest_version)不匹配，更新失败。${NC}"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    # 替换旧脚本
    chmod +x "$TMP_DIR/install.sh" "$TMP_DIR/backup.sh"
    cp "$TMP_DIR/install.sh" "$INSTALL_DIR/install.sh"
    cp "$TMP_DIR/backup.sh" "$INSTALL_DIR/backup.sh"
    
    # 清理临时目录
    rm -rf "$TMP_DIR"
    
    echo -e "${GREEN}更新成功!${NC}"
    echo -e "${YELLOW}请重新启动脚本以应用更新。${NC}"
    exit 0
}

# 自动安装依赖
install_dependencies() {
    detect_os
    
    echo -e "${BLUE}开始自动安装缺失的依赖...${NC}"
    
    # 根据操作系统选择安装命令
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]] || [[ "$OS" == *"Mint"* ]]; then
        echo "使用apt安装依赖..."
        sudo apt update
        
        # 安装wget
        if ! command -v wget &> /dev/null; then
            echo "安装wget..."
            sudo apt install -y wget
        fi
        
        # 安装jq
        if ! command -v jq &> /dev/null; then
            echo "安装jq..."
            sudo apt install -y jq
        fi
        
        # 安装rclone (如果apt源没有最新版，使用rclone官方安装脚本)
        if ! command -v rclone &> /dev/null; then
            echo "安装rclone..."
            if apt-cache show rclone &>/dev/null; then
                sudo apt install -y rclone
            else
                echo "使用rclone官方安装脚本..."
                curl https://rclone.org/install.sh | sudo bash
            fi
        fi
        
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"RedHat"* ]] || [[ "$OS" == *"Fedora"* ]]; then
        echo "使用yum/dnf安装依赖..."
        
        # 安装wget
        if ! command -v wget &> /dev/null; then
            echo "安装wget..."
            sudo yum install -y wget
        fi
        
        # 安装jq
        if ! command -v jq &> /dev/null; then
            echo "安装jq..."
            sudo yum install -y epel-release
            sudo yum install -y jq
        fi
        
        # 安装rclone
        if ! command -v rclone &> /dev/null; then
            echo "安装rclone..."
            sudo yum install -y curl
            curl https://rclone.org/install.sh | sudo bash
        fi
        
    elif [[ "$OS" == *"Darwin"* ]] || [[ "$OS" == *"macOS"* ]]; then
        echo "使用Homebrew安装依赖..."
        
        # 检查是否安装Homebrew
        if ! command -v brew &> /dev/null; then
            echo "未检测到Homebrew，正在安装..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        
        # 安装wget
        if ! command -v wget &> /dev/null; then
            echo "安装wget..."
            brew install wget
        fi
        
        # 安装jq
        if ! command -v jq &> /dev/null; then
            echo "安装jq..."
            brew install jq
        fi
        
        # 安装rclone
        if ! command -v rclone &> /dev/null; then
            echo "安装rclone..."
            brew install rclone
        fi
        
    elif [[ "$OS" == *"Alpine"* ]]; then
        echo "使用apk安装依赖..."
        
        # 安装wget
        if ! command -v wget &> /dev/null; then
            echo "安装wget..."
            sudo apk add wget
        fi
        
        # 安装jq
        if ! command -v jq &> /dev/null; then
            echo "安装jq..."
            sudo apk add jq
        fi
        
        # 安装rclone
        if ! command -v rclone &> /dev/null; then
            echo "安装rclone..."
            sudo apk add rclone
        fi
        
    else
        echo -e "${YELLOW}未能识别的操作系统: $OS${NC}"
        echo -e "${YELLOW}请手动安装以下依赖:${NC}"
        echo "- wget: 请根据您的系统安装方式安装"
        echo "- rclone: https://rclone.org/install/"
        echo "- jq: 请根据您的系统安装方式安装"
        return 1
    fi
    
    # 验证安装结果
    if command -v wget &> /dev/null && command -v rclone &> /dev/null && command -v jq &> /dev/null; then
        echo -e "${GREEN}所有依赖已成功安装!${NC}"
        return 0
    else
        echo -e "${RED}部分依赖安装失败，请手动安装。${NC}"
        return 1
    fi
}

# 检查是否已安装依赖
check_dependencies() {
    missing_deps=()
    
    # 检查wget
    if ! command -v wget &> /dev/null; then
        missing_deps+=("wget")
    fi
    
    # 检查rclone
    if ! command -v rclone &> /dev/null; then
        missing_deps+=("rclone")
    fi
    
    # 检查jq (用于处理JSON)
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    # 如果有缺失的依赖
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}缺少以下依赖:${NC}"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        
        # 询问是否自动安装
        read -p "是否自动安装缺失的依赖? (y/n): " auto_install
        if [[ $auto_install == "y" || $auto_install == "Y" ]]; then
            install_dependencies
            if [ $? -ne 0 ]; then
                echo -e "\n${RED}自动安装失败，请手动安装缺失的依赖。${NC}"
                echo -e "${YELLOW}安装指南:${NC}"
                echo "wget: 根据您的系统安装方式安装"
                echo "rclone: https://rclone.org/install/"
                echo "jq: 根据您的系统安装方式安装"
                exit 1
            fi
        else
            echo -e "\n${YELLOW}安装指南:${NC}"
            echo "wget: apt install wget 或 yum install wget"
            echo "rclone: https://rclone.org/install/"
            echo "jq: apt install jq 或 brew install jq"
            
            echo -e "\n${RED}请安装缺失的依赖后重新运行此脚本${NC}"
            exit 1
        fi
    fi
}

# 显示上次备份时间
show_last_backup() {
    if [ -f "$CONFIG_FILE" ]; then
        last_backup=$(jq -r '.last_backup // "从未备份"' "$CONFIG_FILE")
        if [ "$last_backup" == "null" ] || [ "$last_backup" == "" ]; then
            echo -e "${YELLOW}上次备份时间: 从未备份${NC}"
        else
            echo -e "${GREEN}上次备份时间: $last_backup${NC}"
        fi
    else
        echo -e "${YELLOW}上次备份时间: 配置文件不存在${NC}"
    fi
}

# 显示版本和功能信息
show_info() {
    echo -e "${BLUE}S3备份系统${NC} - ${GREEN}$_VERSION${NC}"
    echo "========================================"
    echo -e "功能:"
    echo -e "  ${GREEN}1${NC} - 安装/配置备份任务"
    echo -e "  ${GREEN}2${NC} - 卸载备份任务"
    echo -e "  ${GREEN}3${NC} - 立即执行一次备份"
    echo -e "  ${GREEN}4${NC} - 修改设置"
    echo -e "  ${GREEN}5${NC} - 查看当前设置"
    echo -e "  ${GREEN}6${NC} - 检查并更新到最新版本"
    echo -e "  ${GREEN}0${NC} - 退出"
    echo "========================================"
    show_last_backup
    echo ""
}

# 配置rclone
configure_rclone() {
    echo -e "${BLUE}配置rclone连接${NC}"
    echo "我们需要配置rclone以连接到您的S3存储服务。"
    
    if [ -f "$RCLONE_CONFIG" ]; then
        echo -e "${YELLOW}检测到已存在的rclone配置文件。${NC}"
        read -p "您想保留现有配置吗? (y/n): " keep_config
        if [[ $keep_config == "y" || $keep_config == "Y" ]]; then
            return 0
        fi
    fi
    
    # 引导用户创建新的rclone配置
    echo "将创建新的rclone配置。请按照提示进行操作："
    echo -e "${YELLOW}提示: 常见的S3服务包括AWS S3, Cloudflare R2, 阿里云OSS, 腾讯云COS等${NC}"
    
    # 获取配置名称
    read -p "请为此配置命名 (例如: my-s3): " remote_name
    
    # 选择S3服务提供商类型
    echo "请选择S3服务提供商类型:"
    echo "1. AWS S3"
    echo "2. Cloudflare R2"
    echo "3. 阿里云OSS"
    echo "4. 腾讯云COS"
    echo "5. Backblaze B2"
    echo "6. Wasabi"
    echo "7. 其他S3兼容服务"
    read -p "请选择 (1-7): " provider_choice
    
    # 根据选择设置provider
    case $provider_choice in
        1) provider="s3" 
           provider_name="AWS" ;;
        2) provider="s3" 
           provider_name="Cloudflare" ;;
        3) provider="s3"
           provider_name="Alibaba" ;;
        4) provider="s3"
           provider_name="TencentCOS" ;;
        5) provider="b2" ;;
        6) provider="s3"
           provider_name="Wasabi" ;;
        7) provider="s3" ;;
        *) echo "无效选择，默认使用s3"; provider="s3" ;;
    esac
    
    # 获取服务特定信息
    if [ "$provider" == "s3" ]; then
        # 阿里云OSS配置
        if [ "$provider_name" == "Alibaba" ]; then
            read -p "OSS区域 (例如: oss-cn-beijing): " region
            read -p "访问密钥ID: " access_key
            read -p "访问密钥Secret: " secret_key
            read -p "桶名称: " bucket
            
            # 创建rclone配置文件
            cat > "$RCLONE_CONFIG" << EOF
[$remote_name]
type = $provider
provider = Alibaba
access_key_id = $access_key
secret_access_key = $secret_key
endpoint = $region.aliyuncs.com
acl = private
bucket_acl = private
force_path_style = false
EOF

        # 腾讯云COS配置
        elif [ "$provider_name" == "TencentCOS" ]; then
            read -p "COS区域 (例如: ap-beijing): " region
            read -p "SecretId: " access_key
            read -p "SecretKey: " secret_key
            read -p "桶名称: " bucket
            
            # 创建rclone配置文件
            cat > "$RCLONE_CONFIG" << EOF
[$remote_name]
type = $provider
provider = TencentCOS
env_auth = false
access_key_id = $access_key
secret_access_key = $secret_key
endpoint = cos.$region.myqcloud.com
acl = private
bucket_acl = private
force_path_style = false
EOF

        # Cloudflare R2配置
        elif [ "$provider_name" == "Cloudflare" ] && [ "$provider_choice" == "2" ]; then
            read -p "R2端点URL (例如: https://xxx.r2.cloudflarestorage.com): " endpoint
            read -p "访问密钥ID: " access_key
            read -p "密钥: " secret_key
            read -p "桶名称: " bucket
            
            # 创建rclone配置文件
            cat > "$RCLONE_CONFIG" << EOF
[$remote_name]
type = $provider
provider = Cloudflare
access_key_id = $access_key
secret_access_key = $secret_key
endpoint = $endpoint
acl = private
bucket_acl = private
no_check_bucket = true
EOF

        # 其他S3服务
        else
            read -p "S3端点URL (例如: https://s3.amazonaws.com): " endpoint
            read -p "访问密钥ID: " access_key
            read -p "密钥: " secret_key
            read -p "桶名称: " bucket
            read -p "区域 (例如: auto): " region
            
            # 创建rclone配置文件
            cat > "$RCLONE_CONFIG" << EOF
[$remote_name]
type = $provider
provider = $provider_name
access_key_id = $access_key
secret_access_key = $secret_key
endpoint = $endpoint
region = $region
acl = private
bucket_acl = private
EOF
        fi
    elif [ "$provider" == "b2" ]; then
        read -p "帐户ID: " account_id
        read -p "应用密钥: " app_key
        read -p "桶名称: " bucket
        
        # 创建rclone配置文件
        cat > "$RCLONE_CONFIG" << EOF
[$remote_name]
type = $provider
account = $account_id
key = $app_key
bucket = $bucket
EOF
    fi
    
    echo -e "${GREEN}rclone配置已保存!${NC}"
    
    # 存储远程和桶信息到主配置
    update_config ".remote" "$remote_name"
    update_config ".bucket" "$bucket"
    
    # 测试连接
    echo "测试连接中..."
    if rclone --config="$RCLONE_CONFIG" lsd "$remote_name:$bucket" &>/dev/null; then
        echo -e "${GREEN}连接成功!${NC}"
        return 0
    else
        echo -e "${RED}连接失败。请检查您的配置。${NC}"
        read -p "是否重新配置? (y/n): " retry
        if [[ $retry == "y" || $retry == "Y" ]]; then
            configure_rclone
        else
            return 1
        fi
    fi
}

# 配置备份设置
configure_backup() {
    echo -e "${BLUE}配置备份设置${NC}"
    
    # 配置备份任务名称
    read -p "请输入备份任务名称 (如服务器名称，用于区分不同备份) [默认: default]: " backup_name
    if [ -z "$backup_name" ]; then
        backup_name="default"  # 默认名称
    fi
    update_config ".backup_name" "$backup_name"
    
    # 配置备份文件夹
    echo "请指定要备份的文件夹路径 (多个路径用空格分隔):"
    read -p "> " backup_dirs
    # 转换为JSON数组
    dirs_json=$(echo "$backup_dirs" | tr ' ' '\n' | jq -R . | jq -s .)
    update_config ".backup_dirs" "$dirs_json"
    
    # 配置备份时间
    echo "请选择备份频率:"
    echo "1. 每天"
    echo "2. 每周"
    echo "3. 每月"
    read -p "请选择 (1-3) [默认: 1]: " freq_choice
    
    if [ -z "$freq_choice" ]; then
        freq_choice=1  # 默认为每天
    fi
    
    case $freq_choice in
        1) frequency="daily" ;;
        2) frequency="weekly" ;;
        3) frequency="monthly" ;;
        *) echo "无效选择，默认使用每天"; frequency="daily" ;;
    esac
    
    update_config ".frequency" "$frequency"
    
    # 备份时间
    read -p "每天备份的时间 (24小时制，例如 23:00) [默认: 02:00]: " backup_time
    if [ -z "$backup_time" ]; then
        backup_time="02:00"  # 默认为凌晨2点
    fi
    update_config ".backup_time" "$backup_time"
    
    # 备份保留期限
    echo "请选择备份保留时间:"
    echo "1. 7天"
    echo "2. 30天"
    echo "3. 90天"
    echo "4. 365天"
    echo "5. 永久保留 (不自动删除)"
    read -p "请选择 (1-5) [默认: 2]: " retention_choice
    
    if [ -z "$retention_choice" ]; then
        retention_choice=2  # 默认为30天
    fi
    
    case $retention_choice in
        1) retention_days=7 ;;
        2) retention_days=30 ;;
        3) retention_days=90 ;;
        4) retention_days=365 ;;
        5) retention_days=0 ;;
        *) echo "无效选择，默认保留30天"; retention_days=30 ;;
    esac
    
    update_config ".retention_days" "$retention_days"
    
    # 压缩方式
    echo "选择压缩方式:"
    echo "1. tar.gz (推荐)"
    echo "2. zip"
    read -p "请选择 (1-2) [默认: 1]: " compression_choice
    
    if [ -z "$compression_choice" ]; then
        compression_choice=1  # 默认为tar.gz
    fi
    
    case $compression_choice in
        1) compression="tar.gz" ;;
        2) compression="zip" ;;
        *) echo "无效选择，默认使用tar.gz"; compression="tar.gz" ;;
    esac
    
    update_config ".compression" "$compression"
    
    echo -e "${GREEN}备份设置已保存!${NC}"
}

# 更新配置文件中的特定项
update_config() {
    key=$1
    value=$2
    
    # 如果配置文件不存在，创建一个空的JSON对象
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{}' > "$CONFIG_FILE"
    fi
    
    # 使用临时文件以防更新失败
    tmp_file=$(mktemp)
    
    # 判断值是否已经是JSON格式(以[或{开头)
    if [[ "$value" == \[* ]] || [[ "$value" == \{* ]]; then
        jq "$key = $value" "$CONFIG_FILE" > "$tmp_file"
    else
        jq "$key = \"$value\"" "$CONFIG_FILE" > "$tmp_file"
    fi
    
    # 检查jq命令是否成功
    if [ $? -eq 0 ]; then
        mv "$tmp_file" "$CONFIG_FILE"
    else
        echo -e "${RED}更新配置文件失败${NC}"
        rm "$tmp_file"
        return 1
    fi
}

# 安装cron作业
install_cron_job() {
    # 解析配置的备份时间
    if [ -f "$CONFIG_FILE" ]; then
        backup_time=$(jq -r '.backup_time // "03:00"' "$CONFIG_FILE")
        hour=${backup_time%%:*}
        minute=${backup_time##*:}
        
        # 移除现有的cron作业
        crontab -l | grep -v "$CRON_JOB_MARKER" > temp_cron
        
        # 添加新的cron作业
        echo "$minute $hour * * * bash $(realpath "$BACKUP_SCRIPT") $CRON_JOB_MARKER" >> temp_cron
        crontab temp_cron
        rm temp_cron
        
        echo -e "${GREEN}备份计划已设置为每天 $backup_time 执行${NC}"
    else
        echo -e "${RED}配置文件不存在，无法安装cron作业${NC}"
        return 1
    fi
}

# 卸载cron作业
uninstall_cron_job() {
    if crontab -l | grep -q "$CRON_JOB_MARKER"; then
        crontab -l | grep -v "$CRON_JOB_MARKER" > temp_cron
        crontab temp_cron
        rm temp_cron
        echo -e "${GREEN}备份计划已卸载${NC}"
    else
        echo -e "${YELLOW}未找到备份计划${NC}"
    fi
}

# 显示当前设置
show_settings() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}当前备份设置:${NC}"
        
        remote=$(jq -r '.remote // "未配置"' "$CONFIG_FILE")
        bucket=$(jq -r '.bucket // "未配置"' "$CONFIG_FILE")
        backup_name=$(jq -r '.backup_name // "default"' "$CONFIG_FILE")
        backup_dirs=$(jq -r '.backup_dirs // []' "$CONFIG_FILE")
        frequency=$(jq -r '.frequency // "daily"' "$CONFIG_FILE")
        backup_time=$(jq -r '.backup_time // "03:00"' "$CONFIG_FILE")
        retention_days=$(jq -r '.retention_days // 30' "$CONFIG_FILE")
        compression=$(jq -r '.compression // "tar.gz"' "$CONFIG_FILE")
        last_backup=$(jq -r '.last_backup // "从未备份"' "$CONFIG_FILE")
        
        echo -e "S3远程存储: ${GREEN}$remote${NC}"
        echo -e "存储桶: ${GREEN}$bucket${NC}"
        echo -e "备份任务名称: ${GREEN}$backup_name${NC}"
        echo -e "备份目录: ${GREEN}$(echo $backup_dirs | jq -r 'if type=="array" then .[] else . end' | tr '\n' ' ')${NC}"
        echo -e "备份频率: ${GREEN}$frequency${NC}"
        echo -e "备份时间: ${GREEN}$backup_time${NC}"
        
        if [ "$retention_days" == "0" ]; then
            echo -e "保留期限: ${GREEN}永久保留${NC}"
        else
            echo -e "保留期限: ${GREEN}$retention_days 天${NC}"
        fi
        
        echo -e "压缩方式: ${GREEN}$compression${NC}"
        
        if [ "$last_backup" == "null" ] || [ "$last_backup" == "" ]; then
            echo -e "上次备份: ${YELLOW}从未备份${NC}"
        else
            echo -e "上次备份: ${GREEN}$last_backup${NC}"
        fi
        
        # 检查cron作业是否已安装
        if crontab -l 2>/dev/null | grep -q "$CRON_JOB_MARKER"; then
            echo -e "备份状态: ${GREEN}已启用${NC}"
        else
            echo -e "备份状态: ${YELLOW}未启用${NC}"
        fi
    else
        echo -e "${RED}配置文件不存在${NC}"
    fi
}

# 执行立即备份
run_backup_now() {
    echo -e "${BLUE}执行备份...${NC}"
    bash "$BACKUP_SCRIPT"
    echo -e "${GREEN}备份操作已完成${NC}"
}

# 下载脚本文件
download_scripts() {
    echo -e "${BLUE}下载所需脚本文件...${NC}"
    
    # 下载备份脚本
    if [ ! -f "$BACKUP_SCRIPT" ]; then
        echo "下载备份脚本..."
        wget -O "$BACKUP_SCRIPT" "$GITHUB_REPO/backup.sh" || {
            echo -e "${RED}下载备份脚本失败${NC}"
            return 1
        }
        chmod +x "$BACKUP_SCRIPT"
    else
        echo "备份脚本已存在，跳过下载"
    fi
    
    # 下载版本信息文件
    wget -O "$CONFIG_DIR/version.txt" "$GITHUB_REPO/version.txt" 2>/dev/null
    
    echo -e "${GREEN}脚本文件下载完成${NC}"
    return 0
}

# 安装备份系统
install_backup() {
    echo -e "${BLUE}安装备份系统${NC}"
    
    # 检查并创建目录
    check_directories
    
    # 检查依赖
    check_dependencies
    
    # 下载必要的脚本文件
    download_scripts
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载脚本文件失败，安装中止${NC}"
        return 1
    fi
    
    # 配置rclone
    configure_rclone
    if [ $? -ne 0 ]; then
        echo -e "${RED}rclone配置失败，安装中止${NC}"
        return 1
    fi
    
    # 配置备份设置
    configure_backup
    
    # 安装cron作业
    install_cron_job
    
    echo -e "${GREEN}备份系统安装成功!${NC}"
}

# 卸载备份系统
uninstall_backup() {
    echo -e "${YELLOW}卸载备份系统${NC}"
    
    read -p "您确定要卸载备份系统吗? 这将删除cron作业，但保留配置文件 (y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo "已取消卸载"
        return 0
    fi
    
    # 卸载cron作业
    uninstall_cron_job
    
    echo -e "${GREEN}备份系统已卸载${NC}"
    
    read -p "是否也删除配置文件? (y/n): " delete_config
    if [[ $delete_config == "y" || $delete_config == "Y" ]]; then
        rm -f "$CONFIG_FILE" "$RCLONE_CONFIG"
        echo -e "${GREEN}配置文件已删除${NC}"
    fi
}

# 主菜单
main_menu() {
    # 初次运行检查更新
    if [ "$1" != "noupdate" ]; then
        check_version
    fi
    
    while true; do
        show_info
        read -p "请选择操作 (0-6): " choice
        
        case $choice in
            1) install_backup ;;
            2) uninstall_backup ;;
            3) run_backup_now ;;
            4) configure_backup; install_cron_job ;;
            5) show_settings ;;
            6) check_version ;;
            0) echo "再见!"; exit 0 ;;
            *) echo -e "${RED}无效选择，请重试${NC}" ;;
        esac
        
        echo ""
        read -p "按Enter继续..."
        clear
    done
}

# 脚本入口
main_menu "$@" 