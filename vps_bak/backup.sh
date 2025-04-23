#!/bin/bash
#
# S3备份系统备份脚本
# 用于执行备份任务并上传到S3兼容存储
#

VERSION="1.0.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
RCLONE_CONFIG="$SCRIPT_DIR/rclone.conf"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/backup_$(date +%Y%m%d_%H%M%S).log"

# 颜色设置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 启用日志记录
exec > >(tee -a "$LOG_FILE") 2>&1

echo "==============================================="
echo "S3备份任务开始执行 - $(date)"
echo "==============================================="

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}错误: 配置文件不存在 ($CONFIG_FILE)${NC}"
    exit 1
fi

# 检查rclone配置是否存在
if [ ! -f "$RCLONE_CONFIG" ]; then
    echo -e "${RED}错误: rclone配置文件不存在 ($RCLONE_CONFIG)${NC}"
    exit 1
fi

# 读取配置
if ! command -v jq &> /dev/null; then
    echo -e "${RED}错误: 未安装jq。请先安装jq。${NC}"
    exit 1
fi

remote=$(jq -r '.remote // ""' "$CONFIG_FILE")
bucket=$(jq -r '.bucket // ""' "$CONFIG_FILE")
backup_name=$(jq -r '.backup_name // "default"' "$CONFIG_FILE")
backup_dirs=$(jq -r '.backup_dirs // []' "$CONFIG_FILE")
retention_days=$(jq -r '.retention_days // 30' "$CONFIG_FILE")
compression=$(jq -r '.compression // "tar.gz"' "$CONFIG_FILE")

# 验证必要的配置
if [ -z "$remote" ] || [ -z "$bucket" ]; then
    echo -e "${RED}错误: 缺少必要的配置项 (remote或bucket)${NC}"
    exit 1
fi

if [ "$backup_dirs" == "[]" ] || [ -z "$backup_dirs" ]; then
    echo -e "${RED}错误: 没有指定要备份的目录${NC}"
    exit 1
fi

# 创建临时目录
TEMP_DIR=$(mktemp -d)
if [ $? -ne 0 ]; then
    echo -e "${RED}错误: 无法创建临时目录${NC}"
    exit 1
fi

# 清理函数
cleanup() {
    echo "清理临时文件..."
    rm -rf "$TEMP_DIR"
}

# 退出时执行清理
trap cleanup EXIT

# 获取当前时间戳
timestamp=$(date +%Y%m%d_%H%M%S)
hostname=$(hostname | tr -d ' ')
backup_file_name="${backup_name}_${hostname}_${timestamp}"

echo -e "${BLUE}备份信息:${NC}"
echo "  备份名称: $backup_name"
echo "  主机名: $hostname"
echo "  时间戳: $timestamp"
echo "  压缩方式: $compression"
echo "  远程存储: $remote:$bucket"

# 执行备份
echo -e "${BLUE}开始备份以下目录:${NC}"

# 解析backup_dirs (可能是数组或字符串)
dirs_to_backup=()
if [[ "$backup_dirs" == \[* ]]; then
    # 如果是JSON数组
    readarray -t dirs_to_backup < <(echo "$backup_dirs" | jq -r '.[]')
else
    # 如果是空格分隔的字符串
    IFS=' ' read -ra dirs_to_backup <<< "$backup_dirs"
fi

# 显示要备份的目录
for dir in "${dirs_to_backup[@]}"; do
    if [ -d "$dir" ]; then
        echo "  - $dir"
    else
        echo -e "  - $dir ${RED}(目录不存在)${NC}"
    fi
done

# 执行备份和压缩
echo -e "${BLUE}创建备份归档...${NC}"

# 根据压缩方式选择不同的命令
if [ "$compression" == "tar.gz" ]; then
    archive_file="$TEMP_DIR/${backup_file_name}.tar.gz"
    
    # 使用tar创建归档
    tar_args="-czf"
    tar_args+=" $archive_file"
    
    # 添加要备份的目录
    for dir in "${dirs_to_backup[@]}"; do
        if [ -d "$dir" ]; then
            tar_args+=" -C $(dirname "$dir") $(basename "$dir")"
        fi
    done
    
    # 执行tar命令
    echo "执行命令: tar $tar_args"
    eval "tar $tar_args"
    
elif [ "$compression" == "zip" ]; then
    archive_file="$TEMP_DIR/${backup_file_name}.zip"
    
    # 使用zip创建归档
    for dir in "${dirs_to_backup[@]}"; do
        if [ -d "$dir" ]; then
            (cd "$(dirname "$dir")" && zip -r "$archive_file" "$(basename "$dir")") 
        fi
    done
else
    echo -e "${RED}错误: 不支持的压缩方式 '$compression'${NC}"
    exit 1
fi

# 检查压缩是否成功
if [ $? -ne 0 ] || [ ! -f "$archive_file" ]; then
    echo -e "${RED}错误: 创建备份归档失败${NC}"
    exit 1
fi

# 计算文件大小
archive_size=$(du -h "$archive_file" | cut -f1)
echo -e "${GREEN}备份归档创建成功: $(basename "$archive_file") (大小: $archive_size)${NC}"

# 上传到S3
echo -e "${BLUE}上传备份到S3存储...${NC}"
upload_path="${backup_name}/$(date +%Y)/$(basename "$archive_file")"

echo "上传路径: $remote:$bucket/$upload_path"
rclone --config="$RCLONE_CONFIG" copy "$archive_file" "$remote:$bucket/$upload_path"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}备份上传成功!${NC}"
    
    # 更新最后备份时间
    jq ".last_backup = \"$(date '+%Y-%m-%d %H:%M:%S')\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    # 清理旧备份 (如果设置了保留天数且大于0)
    if [ "$retention_days" -gt 0 ]; then
        echo -e "${BLUE}清理${retention_days}天前的旧备份...${NC}"
        
        # 计算截止日期 (当前日期减去保留天数)
        cutoff_date=$(date -d "-$retention_days days" +%Y-%m-%d)
        
        # 使用rclone的date选项列出要删除的文件并删除它们
        rclone --config="$RCLONE_CONFIG" delete "$remote:$bucket/$backup_name" --min-age "${retention_days}d" --rmdirs
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}旧备份清理完成${NC}"
        else
            echo -e "${YELLOW}旧备份清理过程中出现错误${NC}"
        fi
    else
        echo -e "${YELLOW}备份永久保存，不会自动删除旧备份${NC}"
    fi
else
    echo -e "${RED}备份上传失败!${NC}"
    exit 1
fi

echo "==============================================="
echo "S3备份任务完成 - $(date)"
echo "==============================================="

exit 0 