# Shell 和 Docker 工具集

这个仓库包含了一系列实用的 Shell 脚本和 Docker 相关工具，用于系统配置、安全防护和开发环境设置。

## 目录结构

- `shell/`: Shell 脚本目录
  - `zsh_init.sh`: ZSH 环境初始化脚本
  - `p10k.zsh`: Powerlevel10k ZSH 主题配置
- `docker/`: Docker 相关工具目录
  - `close_2375.sh`: Docker 安全加固脚本
  - `kill_virus`: Docker 病毒清理脚本
- `vps_bak/`: S3 备份系统目录
  - `install.sh`: S3 备份系统安装脚本
  - `backup.sh`: 备份执行脚本

## 一键执行命令

### ZSH 环境初始化

```bash
bash <(curl -sL https://raw.githubusercontent.com/huhengbo/sh/main/shell/zsh_init.sh)
```

### Docker 安全加固

```bash
sudo bash <(curl -sL https://raw.githubusercontent.com/huhengbo/sh/main/docker/close_2375.sh)
```

### Docker 病毒清理

```bash
sudo bash <(curl -sL https://raw.githubusercontent.com/huhengbo/sh/main/docker/kill_virus)
```

### S3 备份系统安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/huhengbo/sh/main/vps_bak/install.sh)
```

## 脚本说明

### Shell 脚本

#### zsh_init.sh

这是一个 ZSH 环境初始化脚本，用于配置和优化 ZSH 环境。

**功能特点：**
- 安装和配置 ZSH
- 安装 Oh My ZSH
- 配置 Powerlevel10k 主题
- 安装常用插件
- 设置环境变量和别名

#### p10k.zsh

Powerlevel10k ZSH 主题的配置文件，提供美观且功能丰富的终端界面。

### Docker 脚本

#### close_2375.sh

用于关闭 Docker 的 2375 端口，增强 Docker 安全性。

**功能特点：**
- 检测 Docker 2375 端口是否开放
- 关闭 2375 端口
- 配置 Docker 安全选项
- 安装必要的依赖（如 jq）

#### kill_virus

用于清理 Docker 环境中的恶意软件和病毒。

**功能特点：**
- 清理恶意文件
- 解除文件权限限制
- 重置系统配置
- 增强系统安全性

### S3 备份系统

#### install.sh

S3 备份系统的安装和配置脚本，用于自动化备份数据到 S3 兼容的云存储服务。

**功能特点：**
- 自动安装依赖（rclone、jq 等）
- 配置 S3 存储连接（支持AWS、阿里云、腾讯云、Cloudflare R2 等）
- 设置备份任务计划
- 灵活的备份策略（频率、保留天数、压缩方式等）
- 一键执行备份

#### backup.sh

备份执行脚本，负责实际的备份操作。

**功能特点：**
- 备份指定文件夹到 S3 存储
- 自动压缩备份文件
- 自动清理过期备份
- 日志记录

## 注意事项

- 所有 Docker 相关脚本需要 root 权限运行
- 运行脚本前请确保已备份重要数据
- 部分脚本可能会修改系统配置，请谨慎使用

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这些脚本。

## 许可证

MIT