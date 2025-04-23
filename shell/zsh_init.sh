#!/bin/bash

# 设置严格模式（确保使用 bash shell）
if [ -n "$BASH_VERSION" ]; then
    set -euo pipefail
else
    set -eu
fi

IFS=$'\n\t'

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[1;34m'
readonly NC='\033[0m' # No Color

# 版本信息
readonly SCRIPT_VERSION="1.0.0"
readonly MIN_ZSH_VERSION="5.0"

# 日志函数
log() {
    echo -e "${BLUE}==>${NC} $1"
}

info() {
    echo -e "${GREEN}==>${NC} $1"
}

warn() {
    echo -e "${YELLOW}==>${NC} $1"
}

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

# 错误处理
if [ -n "$BASH_VERSION" ]; then
    # 只在 bash 中设置 ERR 和 INT TERM 陷阱
    trap 'error "在行 $LINENO 发生错误"' ERR
    trap 'error "用户中断"' INT TERM
else
    # 在其他 shell 中只设置中断陷阱
    trap 'error "用户中断"' INT TERM
fi

# 检查系统要求
check_requirements() {
    log "检查系统要求..."
    
    # 检测操作系统（如果还没有检测过）
    if [ -z "${OS:-}" ]; then
        detect_os
    fi
    
    # 检查并安装必要工具
    install_required_tools "$OS"
    
    # 检查 sudo 权限
    if ! sudo -v; then
        error "需要 sudo 权限"
    fi
}

# 检测操作系统
detect_os() {
    log "检测操作系统..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macOS"
    elif [[ -e /etc/os-release ]]; then
        # 使用临时变量避免冲突
        local os_id
        . /etc/os-release
        os_id="$ID"
        case "$os_id" in
            ubuntu|debian) OS="Debian" ;;
            centos|rhel|fedora) OS="CentOS" ;;
            *) OS="Unknown" ;;
        esac
    else
        OS="Unknown"
    fi
    
    if [ "$OS" = "Unknown" ]; then
        error "不支持的操作系统"
    fi
    
    info "检测到操作系统: $OS"
}

# 安装必要工具
install_required_tools() {
    local os=$1
    log "安装必要工具..."
    
    case "$os" in
        macOS)
            if ! command -v brew &>/dev/null; then
                log "安装 Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                
                # 检测 Homebrew 安装路径
                if [[ -d "/opt/homebrew" ]]; then
                    BREW_PREFIX="/opt/homebrew"
                elif [[ -d "/usr/local" ]]; then
                    BREW_PREFIX="/usr/local"
                else
                    error "无法找到 Homebrew 安装路径"
                fi
                
                echo "eval \"($BREW_PREFIX/bin/brew shellenv)\"" >> ~/.zprofile
                eval "$($BREW_PREFIX/bin/brew shellenv)"
            fi
            brew install curl git wget
            ;;
        Debian)
            if ! command -v apt-get &>/dev/null; then
                error "无法找到 apt-get，请确保系统为 Debian/Ubuntu 系列"
            fi
            if ! command -v sudo &>/dev/null; then
                log "安装 sudo..."
                apt-get update
                apt-get install -y sudo
            fi
            if ! command -v curl &>/dev/null || ! command -v git &>/dev/null || ! command -v wget &>/dev/null; then
                log "安装必要工具..."
                sudo apt-get update
                sudo apt-get install -y curl git wget
            fi
            ;;
        CentOS)
            if ! command -v yum &>/dev/null; then
                error "无法找到 yum，请确保系统为 CentOS/RHEL 系列"
            fi
            if ! command -v sudo &>/dev/null; then
                log "安装 sudo..."
                yum install -y sudo
            fi
            if ! command -v curl &>/dev/null || ! command -v git &>/dev/null || ! command -v wget &>/dev/null; then
                log "安装必要工具..."
                sudo yum install -y epel-release
                sudo yum install -y curl git wget
            fi
            ;;
        *) error "不支持的操作系统: $os" ;;
    esac
}

# 安装包管理器
install_package_manager() {
    local os=$1
    log "检查包管理器..."
    
    case "$os" in
        macOS)
            if ! command -v brew &>/dev/null; then
                log "安装 Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                
                # 检测 Homebrew 安装路径
                if [[ -d "/opt/homebrew" ]]; then
                    BREW_PREFIX="/opt/homebrew"
                elif [[ -d "/usr/local" ]]; then
                    BREW_PREFIX="/usr/local"
                else
                    error "无法找到 Homebrew 安装路径"
                fi
                
                echo "eval \"($BREW_PREFIX/bin/brew shellenv)\"" >> ~/.zprofile
                eval "$($BREW_PREFIX/bin/brew shellenv)"
            fi
            ;;
        Debian)
            # 确保 apt-get 可用
            if ! command -v apt-get &>/dev/null; then
                error "无法找到 apt-get，请确保系统为 Debian/Ubuntu 系列"
            fi
            ;;
        CentOS)
            # 确保 yum 可用
            if ! command -v yum &>/dev/null; then
                error "无法找到 yum，请确保系统为 CentOS/RHEL 系列"
            fi
            ;;
        *) error "不支持的操作系统: $os" ;;
    esac
}

# 安装基础包
install_base_packages() {
    local os=$1
    log "安装基础包..."
    
    case "$os" in
        macOS)
            brew install zsh git curl wget
            ;;
        Debian)
            sudo apt install -y zsh git curl wget fonts-powerline
            ;;
        CentOS)
            sudo yum install -y zsh git curl wget fontconfig
            ;;
        *) error "不支持的操作系统: $os" ;;
    esac
}

# 安装 zsh
install_zsh() {
    log "安装 Zsh..."
    
    if ! command -v zsh &>/dev/null; then
        install_base_packages "$OS"
    fi
    
    # 检查 zsh 版本
    local zsh_version
    zsh_version=$(zsh --version | cut -d' ' -f2)
    if ! command -v zsh &>/dev/null || [[ "$zsh_version" < "$MIN_ZSH_VERSION" ]]; then
        error "需要 Zsh $MIN_ZSH_VERSION 或更高版本"
    fi
}

# 添加 zsh 到 shells
add_zsh_to_shells() {
    log "添加 Zsh 到系统 shells..."
    
    local zsh_path
    zsh_path=$(which zsh)
    
    if ! grep -Fxq "$zsh_path" /etc/shells; then
        echo "$zsh_path" | sudo tee -a /etc/shells
    fi
}

# 设置默认 shell
set_default_shell() {
    log "设置默认 shell 为 Zsh..."
    
    local zsh_path
    zsh_path=$(which zsh)
    
    if [ "$SHELL" != "$zsh_path" ]; then
        add_zsh_to_shells
        chsh -s "$zsh_path" || error "设置默认 shell 失败。请手动运行:\nchsh -s $zsh_path"
    fi
}

# 安装 Oh My Zsh
install_ohmyzsh() {
    log "安装 Oh My Zsh..."
    
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        # 设置环境变量以自动确认
        export CHSH=yes
        RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    else
        # 使用 bash 更新 Oh My Zsh，而不是 sh
        if [ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]; then
            if command -v bash &>/dev/null; then
                bash "$HOME/.oh-my-zsh/tools/upgrade.sh" || warn "Oh My Zsh 更新失败，继续安装..."
            else
                warn "未找到 bash，跳过 Oh My Zsh 更新..."
            fi
        else
            warn "Oh My Zsh 更新脚本不存在，跳过更新..."
        fi
    fi
}

# 安装 Powerlevel10k
install_powerlevel10k() {
    log "安装 Powerlevel10k 主题..."
    
    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [ ! -d "$p10k_dir" ]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir" || error "Powerlevel10k 安装失败"
    else
        git -C "$p10k_dir" pull || warn "Powerlevel10k 更新失败，继续安装..."
    fi
}

# 配置 Powerlevel10k
configure_powerlevel10k() {
    log "配置 Powerlevel10k 主题..."
    
    local p10k_config="$HOME/.p10k.zsh"
    
    # 备份现有配置
    if [ -f "$p10k_config" ]; then
        local backup="${p10k_config}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$p10k_config" "$backup" || error "无法备份 .p10k.zsh"
        info "已备份 .p10k.zsh 到 $backup"
    fi
    
    # 从远程服务器下载配置文件
    log "从远程服务器下载 Powerlevel10k 配置..."
    curl -fsSL "https://raw.githubusercontent.com/huhengbo/sh/main/shell/p10k.zsh" -o "$p10k_config" || error "无法下载 Powerlevel10k 配置文件"
    
    # 确保在 .zshrc 中禁用 Powerlevel10k 配置向导
    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q "POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true" "$HOME/.zshrc"; then
            sed -i'.tmp' '1s/^/# 禁用 Powerlevel10k 配置向导\nPOWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true\n\n/' "$HOME/.zshrc"
            rm -f "${HOME}/.zshrc.tmp"
        fi
    fi
    
    log "Powerlevel10k 主题配置已下载: $p10k_config"
}

# 安装 Nerd Fonts
install_nerdfonts() {
    log "安装 Nerd Fonts..."
    
    local fonts=(
        "MesloLGS%20NF%20Regular.ttf"
        "MesloLGS%20NF%20Bold.ttf"
        "MesloLGS%20NF%20Italic.ttf"
        "MesloLGS%20NF%20Bold%20Italic.ttf"
    )
    
    # 字体本地名称
    local font_names=(
        "MesloLGS NF Regular.ttf"
        "MesloLGS NF Bold.ttf"
        "MesloLGS NF Italic.ttf"
        "MesloLGS NF Bold Italic.ttf"
    )
    
    case "$OS" in
        macOS)
            local font_dir="$HOME/Library/Fonts"
            ;;
        *)
            local font_dir="$HOME/.local/share/fonts"
            mkdir -p "$font_dir"
            ;;
    esac
    
    for i in "${!fonts[@]}"; do
        local font_url="https://github.com/romkatv/powerlevel10k-media/raw/master/${fonts[$i]}"
        local font_dest="$font_dir/${font_names[$i]}"
        
        if [ ! -f "$font_dest" ]; then
            log "下载字体 ${font_names[$i]}..."
            curl -fLo "$font_dest" --create-dirs "$font_url" || warn "字体 ${font_names[$i]} 下载失败"
        fi
    done
    
    if [ "$OS" != "macOS" ]; then
        fc-cache -f || warn "字体缓存更新失败"
    fi
}

# 安装插件
install_plugins() {
    log "安装 Zsh 插件..."
    
    local plugins=(
        "zsh-syntax-highlighting:https://github.com/zsh-users/zsh-syntax-highlighting.git"
        "zsh-autosuggestions:https://github.com/zsh-users/zsh-autosuggestions.git"
        "zsh-history-substring-search:https://github.com/zsh-users/zsh-history-substring-search.git"
        "zsh-completions:https://github.com/zsh-users/zsh-completions.git"
    )
    
    for plugin in "${plugins[@]}"; do
        local name="${plugin%%:*}"
        local url="${plugin#*:}"
        local dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$name"
        
        if [ ! -d "$dir" ]; then
            git clone --depth=1 "$url" "$dir" || warn "插件 $name 安装失败"
        else
            git -C "$dir" pull || warn "插件 $name 更新失败"
        fi
    done
}

# 配置 .zshrc
configure_zshrc() {
    log "配置 .zshrc..."
    
    local zshrc="$HOME/.zshrc"
    local backup="${zshrc}.bak.$(date +%Y%m%d_%H%M%S)"
    
    # 备份现有配置
    if [ -f "$zshrc" ]; then
        cp "$zshrc" "$backup" || error "无法备份 .zshrc"
        info "已备份 .zshrc 到 $backup"
    fi
    
    # 检查是否已经有 POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD
    local has_disable_wizard=false
    if [ -f "$zshrc" ] && grep -q "POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD" "$zshrc"; then
        has_disable_wizard=true
    fi
    
    # 设置主题 - 修复 sed 表达式
    if [ -f "$zshrc" ]; then
        sed -i'.tmp' 's/^ZSH_THEME=.*$/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$zshrc"
        
        # 更新插件列表
        local plugin_str="zsh-syntax-highlighting zsh-autosuggestions zsh-history-substring-search zsh-completions"
        sed -i'.tmp' "s/^plugins=(.*)/plugins=($plugin_str)/" "$zshrc"
        
        # 删除临时文件
        rm -f "${zshrc}.tmp"
    else
        # 如果 .zshrc 不存在，创建一个新的
        cat > "$zshrc" << EOF
# 禁用 Powerlevel10k 配置向导
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true

# 基本配置
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(zsh-syntax-highlighting zsh-autosuggestions zsh-history-substring-search zsh-completions)
source \$ZSH/oh-my-zsh.sh

# 自定义配置
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 历史记录配置
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# 自动补全配置
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# 别名配置
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
EOF
        has_disable_wizard=true
    fi
    
    # 确保 Powerlevel10k 主题加载
    if ! grep -q 'powerlevel10k.zsh-theme' "$zshrc"; then
        echo 'source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k/powerlevel10k.zsh-theme"' >> "$zshrc"
    fi
    
    # 添加 p10k 配置加载
    if ! grep -q '\.p10k\.zsh' "$zshrc"; then
        echo '[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh' >> "$zshrc"
    fi
    
    # 添加禁用配置向导设置（如果还没有）
    if [ "$has_disable_wizard" = "false" ]; then
        sed -i'.tmp' '1s/^/# 禁用 Powerlevel10k 配置向导\nPOWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true\n\n/' "$zshrc"
        rm -f "${zshrc}.tmp"
    fi
}

# 清理函数
cleanup() {
    log "清理临时文件..."
    rm -f "${HOME}/.zshrc.bak"
}

# 卸载函数
uninstall() {
    log "开始卸载..."
    
    # 恢复原始 shell
    if [ -f "${HOME}/.zshrc.bak" ]; then
        mv "${HOME}/.zshrc.bak" "${HOME}/.zshrc"
    fi
    
    # 删除 Oh My Zsh
    if [ -d "${HOME}/.oh-my-zsh" ]; then
        rm -rf "${HOME}/.oh-my-zsh"
    fi
    
    # 删除字体
    case "$OS" in
        macOS)
            rm -f "${HOME}/Library/Fonts/MesloLGS NF"*.ttf
            ;;
        *)
            rm -f "${HOME}/.local/share/fonts/MesloLGS NF"*.ttf
            ;;
    esac
    
    info "卸载完成"
}

# 检查已安装的组件
check_installed_components() {
    log "检查已安装组件..."
    
    # 初始化数组
    local components=()
    local versions=()
    
    # 检查 zsh
    if command -v zsh &>/dev/null; then
        components+=("zsh")
        versions+=("$(zsh --version | cut -d' ' -f2 2>/dev/null || echo "未知")")
    fi
    
    # 检查 Oh My Zsh
    if [ -d "$HOME/.oh-my-zsh" ]; then
        components+=("Oh My Zsh")
        local omz_version="未知"
        # 尝试多种方式获取 Oh My Zsh 版本
        if [ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]; then
            omz_version=$(grep -o 'OMZ_VERSION="[^"]*"' "$HOME/.oh-my-zsh/tools/upgrade.sh" 2>/dev/null | grep -o '".*"' | tr -d '"' || echo "未知")
        fi
        # 如果未能通过 upgrade.sh 获取版本，尝试其他方法
        if [ "$omz_version" = "未知" ] && [ -d "$HOME/.oh-my-zsh/.git" ]; then
            omz_version=$(cd "$HOME/.oh-my-zsh" && git describe --tags 2>/dev/null || echo "未知")
        fi
        versions+=("$omz_version")
    fi
    
    # 检查 Powerlevel10k
    if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
        components+=("Powerlevel10k")
        if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k/.git" ]; then
            versions+=("$(cd "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" && git describe --tags 2>/dev/null || echo "未知")")
        else
            versions+=("未知")
        fi
    fi
    
    # 检查插件
    local plugins=(
        "zsh-syntax-highlighting"
        "zsh-autosuggestions"
        "zsh-history-substring-search"
        "zsh-completions"
    )
    
    for plugin in "${plugins[@]}"; do
        if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin" ]; then
            components+=("$plugin")
            if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin/.git" ]; then
                versions+=("$(cd "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin" && git describe --tags 2>/dev/null || echo "未知")")
            else
                versions+=("未知")
            fi
        fi
    done
    
    # 显示安装状态
    echo -e "\n${BLUE}当前安装状态:${NC}"
    echo "----------------------------------------"
    if [ ${#components[@]} -eq 0 ]; then
        echo -e "${YELLOW}未检测到已安装的组件${NC}"
    else
        for i in "${!components[@]}"; do
            if [ "${versions[$i]}" = "未知" ]; then
                echo -e "${GREEN}✓${NC} ${components[$i]}: ${YELLOW}已安装${NC}"
            else
                echo -e "${GREEN}✓${NC} ${components[$i]}: ${GREEN}已安装${NC} (v${versions[$i]})"
            fi
        done
    fi
    echo "----------------------------------------"
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}Zsh 环境管理脚本 v$SCRIPT_VERSION${NC}"
    echo "----------------------------------------"
    check_installed_components
    echo -e "\n${BLUE}请选择操作:${NC}"
    echo "1) 安装/更新 Zsh 环境"
    echo "2) 卸载 Zsh 环境"
    echo "3) 仅更新已安装组件"
    echo "4) 退出"
    echo "----------------------------------------"
    read -p "请输入选项 [1-4]: " choice
    
    case "$choice" in
        1)
            main
            ;;
        2)
            uninstall
            ;;
        3)
            update_components
            ;;
        4)
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项${NC}"
            sleep 1
            show_menu
            ;;
    esac
}

# 更新组件
update_components() {
    log "开始更新组件..."
    
    # 更新 Oh My Zsh
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log "更新 Oh My Zsh..."
        omz update || warn "Oh My Zsh 更新失败"
    fi
    
    # 更新 Powerlevel10k
    if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
        log "更新 Powerlevel10k..."
        git -C "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" pull || warn "Powerlevel10k 更新失败"
    fi
    
    # 更新插件
    local plugins=(
        "zsh-syntax-highlighting"
        "zsh-autosuggestions"
        "zsh-history-substring-search"
        "zsh-completions"
    )
    
    for plugin in "${plugins[@]}"; do
        if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin" ]; then
            log "更新插件 $plugin..."
            git -C "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin" pull || warn "插件 $plugin 更新失败"
        fi
    done
    
    info "更新完成！"
    read -p "按回车键继续..."
    show_menu
}

# 主函数
main() {
    log "开始安装 Zsh 环境 (v$SCRIPT_VERSION)..."
    
    # 检查系统要求
    check_requirements
    
    # 安装包管理器
    install_package_manager "$OS"
    
    # 安装 zsh
    install_zsh
    
    # 设置默认 shell
    set_default_shell
    
    # 安装 Oh My Zsh
    install_ohmyzsh
    
    # 安装 Powerlevel10k
    install_powerlevel10k
    
    # 配置 Powerlevel10k
    configure_powerlevel10k
    
    # 安装字体
    install_nerdfonts
    
    # 安装插件
    install_plugins
    
    # 配置 .zshrc
    configure_zshrc
    
    # 清理
    cleanup
    
    info "安装完成！"
    info "请重启终端或运行: source ~/.zshrc"
    info "已设置 Powerlevel10k 默认主题，如需自定义请运行: p10k configure"
    
    read -p "按回车键继续..."
    show_menu
}

# 直接启动菜单
show_menu