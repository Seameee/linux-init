#!/bin/bash

# ============================================
# Linux系统初始化脚本
# 兼容 Ubuntu, Debian, Alpine 系统
# ============================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 进度文件
PROGRESS_FILE="/tmp/linux-init-progress.md"
LOG_FILE="/tmp/linux-init.log"

# 初始化进度文件
init_progress() {
    cat > "$PROGRESS_FILE" << EOF
# Linux系统初始化进度记录
开始时间: $(date)

## 执行步骤
- [ ] 系统环境检测
- [ ] 软件包更新
- [ ] 基础软件安装
- [ ] oh-my-zsh配置
- [ ] SSH安全配置
- [ ] 网络优化配置
- [ ] zram配置（如适用）
- [ ] 监控探针安装
- [ ] 日志轮转配置
- [ ] 初始化完成

## 详细日志
EOF
    echo -e "${GREEN}进度文件已初始化: $PROGRESS_FILE${NC}"
}

# 更新进度
update_progress() {
    local step="$1"
    local status="$2"
    local message="$3"
    
    sed -i "s/- \[ \] $step/- \[$status\] $step/" "$PROGRESS_FILE"
    echo "- $(date): $message" >> "$PROGRESS_FILE"
    echo -e "${GREEN}✓ $step 完成${NC}"
}

# 日志记录
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 错误处理
error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    exit 1
}

# 警告信息
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

# 系统检测函数
detect_system() {
    log "开始检测系统环境..."
    
    # 检测系统类型
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        SYSTEM_ID="$ID"
        SYSTEM_VERSION="$VERSION_ID"
        log "检测到系统: $PRETTY_NAME"
    else
        error "无法检测系统类型，/etc/os-release 文件不存在"
    fi
    
    # 检测虚拟化类型
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE=$(systemd-detect-virt)
    else
        # 备选检测方法
        if grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
            VIRT_TYPE="lxc"
        elif grep -q "container" /proc/1/environ 2>/dev/null; then
            VIRT_TYPE="container"
        else
            VIRT_TYPE="kvm"
        fi
    fi
    log "虚拟化类型: $VIRT_TYPE"
    
    # 检测硬盘大小
    DISK_SIZE=$(df / | awk 'NR==2 {print $2}')
    DISK_SIZE_GB=$((DISK_SIZE / 1024 / 1024))
    log "根分区大小: ${DISK_SIZE_GB}GB"
    
    # 检测sudo是否存在
    if command -v sudo >/dev/null 2>&1; then
        HAS_SUDO=true
        log "检测到sudo命令"
    else
        HAS_SUDO=false
        warning "未检测到sudo命令，将尝试直接使用root权限"
    fi
    
    update_progress "系统环境检测" "x" "系统类型: $SYSTEM_ID, 虚拟化: $VIRT_TYPE, 硬盘: ${DISK_SIZE_GB}GB"
}

# 软件包管理函数
update_packages() {
    log "开始更新系统软件包..."
    
    local update_cmd=""
    local upgrade_cmd=""
    
    case "$SYSTEM_ID" in
        ubuntu|debian)
            update_cmd="apt update"
            upgrade_cmd="apt upgrade -y"
            ;;
        alpine)
            update_cmd="apk update"
            upgrade_cmd="apk -U upgrade"
            ;;
        *)
            error "不支持的系统类型: $SYSTEM_ID"
            ;;
    esac
    
    # 处理sudo权限
    if [ "$HAS_SUDO" = true ]; then
        update_cmd="sudo $update_cmd"
        upgrade_cmd="sudo $upgrade_cmd"
    fi
    
    # 执行更新
    log "执行: $update_cmd"
    if ! eval "$update_cmd"; then
        warning "软件包更新失败，尝试继续执行"
    fi
    
    log "执行: $upgrade_cmd"
    if ! eval "$upgrade_cmd"; then
        warning "软件包升级失败，尝试继续执行"
    fi
    
    update_progress "软件包更新" "x" "已完成系统软件包更新和升级"
}

# 基础软件安装函数
install_basic_tools() {
    log "开始安装基础工具..."
    
    local packages="wget curl jq sudo vnstat nano zsh git"
    local install_cmd=""
    
    case "$SYSTEM_ID" in
        ubuntu|debian)
            install_cmd="apt install -y"
            ;;
        alpine)
            install_cmd="apk add"
            packages="wget curl jq sudo vnstat nano zsh git"
            ;;
    esac
    
    # 处理sudo权限
    if [ "$HAS_SUDO" = true ]; then
        install_cmd="sudo $install_cmd"
    fi
    
    # 检查并安装缺失的包
    for pkg in $packages; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            log "安装 $pkg..."
            if ! eval "$install_cmd $pkg"; then
                warning "安装 $pkg 失败"
            fi
        else
            log "$pkg 已安装"
        fi
    done
    
    update_progress "基础软件安装" "x" "已完成基础工具安装"
}

# oh-my-zsh配置函数
install_ohmyzsh() {
    log "开始配置oh-my-zsh..."
    
    # 检查是否已安装zsh
    if ! command -v zsh >/dev/null 2>&1; then
        error "zsh未安装，请先运行基础软件安装"
    fi
    
    # 根据系统类型采用不同的安装方式
    case "$SYSTEM_ID" in
        ubuntu|debian)
            log "在Debian/Ubuntu系统上配置oh-my-zsh..."
            # 切换默认shell到zsh
            if [ "$HAS_SUDO" = true ]; then
                sudo chsh -s /bin/zsh "$USER"
            else
                chsh -s /bin/zsh
            fi
            ;;
        alpine)
            log "在Alpine系统上配置oh-my-zsh..."
            # 修改root用户的默认shell
            if [ "$HAS_SUDO" = true ]; then
                sudo sed -i 's|^root:x:0:0:root:/root:/bin/sh|root:x:0:0:root:/root:/bin/zsh|' /etc/passwd
            else
                sed -i 's|^root:x:0:0:root:/root:/bin/sh|root:x:0:0:root:/root:/bin/zsh|' /etc/passwd
            fi
            ;;
    esac
    
    # 安装oh-my-zsh
    log "安装oh-my-zsh..."
    if ! sh -c "$(curl -fsSL https://install.ohmyz.sh/)"; then
        warning "oh-my-zsh安装失败，尝试继续执行"
    fi
    
    # 安装zsh-autosuggestions插件
    log "安装zsh-autosuggestions插件..."
    if [ ! -d "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    else
        log "zsh-autosuggestions插件已存在"
    fi
    
    # 安装zsh-syntax-highlighting插件
    log "安装zsh-syntax-highlighting插件..."
    if [ ! -d "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    else
        log "zsh-syntax-highlighting插件已存在"
    fi
    
    # 下载自定义zshrc配置
    log "下载自定义zshrc配置..."
    if ! wget -qO ~/.zshrc "https://gist.githubusercontent.com/Seameee/ab0a81e3ef476e6059f35a0785f12a32/raw/.zshrc"; then
        warning "下载自定义zshrc配置失败"
    else
        # 应用配置
        source ~/.zshrc
    fi
    
    update_progress "oh-my-zsh配置" "x" "已完成oh-my-zsh和插件安装"
}

# SSH安全配置函数
configure_ssh() {
    log "开始配置SSH安全..."
    
    echo -e "${YELLOW}注意：SSH配置将禁用密码登录，只允许密钥登录${NC}"
    echo -e "${YELLOW}请确保您已经设置了SSH密钥对${NC}"
    read -p "是否继续配置SSH？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warning "用户跳过SSH配置"
        return 0
    fi
    
    # 下载并运行OpenSSH升级脚本
    log "下载OpenSSH升级脚本..."
    if ! wget -O upgrade_openssh.sh "https://gist.github.com/Seameee/2061e673132b05e5ed8dd6eb125f1fd1/raw/upgrade_openssh.sh"; then
        warning "下载OpenSSH升级脚本失败"
    else
        if [ "$HAS_SUDO" = true ]; then
            sudo chmod +x ./upgrade_openssh.sh
            sudo ./upgrade_openssh.sh
        else
            chmod +x ./upgrade_openssh.sh
            ./upgrade_openssh.sh
        fi
        # 清理临时文件
        rm -f upgrade_openssh.sh
    fi
    
    # 确保.ssh目录存在
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    # 交互式输入SSH公钥
    echo -e "${YELLOW}请输入您的SSH公钥（将以EOF结束输入，输入完成后按Ctrl+D）：${NC}"
    echo "请粘贴您的SSH公钥内容："
    temp_key_file=$(mktemp)
    cat > "$temp_key_file"
    
    if [ -s "$temp_key_file" ]; then
        log "添加SSH公钥到authorized_keys"
        cat "$temp_key_file" >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        echo -e "${GREEN}SSH公钥已成功添加${NC}"
    else
        warning "未输入有效的SSH公钥，跳过密钥配置"
    fi
    rm -f "$temp_key_file"
    
    # 配置SSH认证方式
    log "配置SSH认证方式..."
    local sshd_config_dir="/etc/ssh/sshd_config.d"
    local sshd_config_file="$sshd_config_dir/00-custom_auth.conf"
    
    if [ "$HAS_SUDO" = true ]; then
        sudo mkdir -p "$sshd_config_dir"
        echo -e "PasswordAuthentication no\nPubkeyAuthentication yes" | sudo tee "$sshd_config_file" > /dev/null
    else
        mkdir -p "$sshd_config_dir"
        echo -e "PasswordAuthentication no\nPubkeyAuthentication yes" > "$sshd_config_file"
    fi
    
    # 重启SSH服务
    log "重启SSH服务..."
    case "$SYSTEM_ID" in
        ubuntu|debian)
            if [ "$HAS_SUDO" = true ]; then
                sudo systemctl restart sshd
            else
                systemctl restart sshd
            fi
            ;;
        alpine)
            if [ "$HAS_SUDO" = true ]; then
                sudo rc-service sshd restart
            else
                rc-service sshd restart
            fi
            ;;
    esac
    
    update_progress "SSH安全配置" "x" "已完成SSH安全配置和密钥设置"
}

# 显示欢迎信息
show_welcome() {
    echo -e "${GREEN}"
    echo "==========================================="
    echo "    Linux系统初始化脚本"
    echo "    兼容 Ubuntu, Debian, Alpine"
    echo "==========================================="
    echo -e "${NC}"
    echo "此脚本将执行以下操作："
    echo "1. 系统环境检测"
    echo "2. 软件包更新和升级"
    echo "3. 基础工具安装"
    echo "4. oh-my-zsh配置"
    echo "5. SSH安全配置"
    echo "6. 网络优化"
    echo "7. zram配置（如适用）"
    echo "8. 监控探针安装"
    echo "9. 日志轮转配置"
    echo ""
    echo -e "${YELLOW}注意：某些步骤需要用户交互输入${NC}"
    echo ""
    
    read -p "是否继续？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "用户取消执行"
        exit 0
    fi
}

# 网络优化配置函数
configure_network() {
    log "开始配置网络优化..."
    
    # 如果是LXC容器，跳过此步骤
    if [ "$VIRT_TYPE" = "lxc" ]; then
        log "检测到LXC容器，跳过网络优化配置"
        update_progress "网络优化配置" "x" "LXC容器，跳过网络优化"
        return 0
    fi
    
    # 检查是否为Debian系统且版本>=13
    if [ "$SYSTEM_ID" = "debian" ] && [ "$SYSTEM_VERSION" -ge "13" ]; then
        log "在Debian 13+系统上配置BBR..."
        if [ "$HAS_SUDO" = true ]; then
            echo -e "net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr" | sudo tee /etc/sysctl.d/99-bbr.conf > /dev/null
            sudo sysctl --system
        else
            echo -e "net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr" > /etc/sysctl.d/99-bbr.conf
            sysctl --system
        fi
    else
        log "使用外部脚本进行网络优化..."
        if ! wget -N "http://sh.nekoneko.cloud/tools.sh" -O tools.sh; then
            warning "下载网络优化脚本失败"
        else
            chmod +x tools.sh
            echo -e "${YELLOW}即将运行外部网络优化脚本，完成后请按Ctrl+C返回本脚本${NC}"
            ./tools.sh
        fi
    fi
    
    update_progress "网络优化配置" "x" "已完成网络优化配置"
}

# zram配置函数
configure_zram() {
    log "开始配置zram..."
    
    # 如果是LXC容器，跳过此步骤
    if [ "$VIRT_TYPE" = "lxc" ]; then
        log "检测到LXC容器，跳过zram配置"
        update_progress "zram配置" "x" "LXC容器，跳过zram配置"
        return 0
    fi
    
    # 确保是KVM虚拟化
    if [ "$VIRT_TYPE" = "kvm" ]; then
        log "在KVM虚拟化环境下配置zram..."
        if ! curl -L https://raw.githubusercontent.com/spiritLHLS/addzram/main/addzram.sh -o addzram.sh; then
            warning "下载zram脚本失败"
        else
            chmod +x addzram.sh
            bash addzram.sh
        fi
    else
        log "非KVM虚拟化环境，跳过zram配置"
    fi
    
    update_progress "zram配置" "x" "已完成zram配置"
}

# 监控探针安装函数
install_monitor_agent() {
    log "开始安装监控探针..."
    
    echo -e "${YELLOW}请输入--auto-discovery参数值：${NC}"
    read -p "auto-discovery值: " auto_discovery
    if [ -z "$auto_discovery" ]; then
        warning "未输入auto-discovery参数，跳过监控探针安装"
        update_progress "监控探针安装" "x" "用户取消监控探针安装"
        return 0
    fi
    
    echo -e "${YELLOW}请输入--month-rotate参数值（默认为12）：${NC}"
    read -p "month-rotate值: " month_rotate
    month_rotate=${month_rotate:-12}
    
    log "安装komari监控探针，auto-discovery: $auto_discovery, month-rotate: $month_rotate"
    
    bash <(curl -sL https://raw.githubusercontent.com/komari-monitor/komari-agent/refs/heads/main/install.sh) \
        -e https://monitor.seaya.link \
        --auto-discovery "$auto_discovery" \
        --disable-web-ssh \
        --month-rotate "$month_rotate"
    
    update_progress "监控探针安装" "x" "已安装komari监控探针，auto-discovery: $auto_discovery, month-rotate: $month_rotate"
}

# 日志轮转配置函数
configure_logrotate() {
    log "开始配置日志轮转..."
    
    # 只在硬盘小于8GB时配置
    if [ "$DISK_SIZE_GB" -lt 8 ]; then
        log "硬盘空间小于8GB，配置日志轮转..."
        
        local logrotate_file="/etc/logrotate.d/custom-vps"
        local logrotate_content=$(cat << 'EOF'
# 系统日志轮转配置
/var/log/syslog
/var/log/kern.log
/var/log/auth.log
{
    # 每天轮转
    daily
    # 保留3个备份
    rotate 3
    # 启用压缩
    compress
    # 延迟压缩
    delaycompress
    # 文件不存在不报错
    missingok
    # 空文件不轮转
    notifempty
    # 达到50MB立即轮转（优先级高于daily）
    size 50M
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}

# systemd journal日志轮转配置
/var/log/journal/*/*.journal
{
    # 每天检查
    daily
    # 只保留2个备份
    rotate 2
    # 启用压缩
    compress
    # 延迟压缩
    delaycompress
    # 文件不存在不报错
    missingok
    # 空文件不轮转
    notifempty
    # 达到10MB立即轮转
    size 10M
    # 对正在写入的文件安全处理
    copytruncate
    postrotate
        # 重新加载journal配置
        systemctl kill --kill-who=main --signal=SIGUSR2 systemd-journald
    endscript
}
EOF
        )
        
        if [ "$HAS_SUDO" = true ]; then
            echo "$logrotate_content" | sudo tee "$logrotate_file" > /dev/null
        else
            echo "$logrotate_content" > "$logrotate_file"
        fi
        
        update_progress "日志轮转配置" "x" "已配置日志轮转（硬盘小于8GB）"
    else
        log "硬盘空间大于等于8GB，跳过日志轮转配置"
        update_progress "日志轮转配置" "x" "硬盘空间充足，跳过日志轮转"
    fi
}

# 主函数
main() {
    show_welcome
    init_progress
    
    # 执行初始化步骤（将oh-my-zsh配置放在最后）
    detect_system
    update_packages
    install_basic_tools
    configure_ssh
    configure_network
    configure_zram
    install_monitor_agent
    configure_logrotate
    install_ohmyzsh
    
    # 完成初始化
    update_progress "初始化完成" "x" "所有初始化步骤已完成"
    
    echo -e "${GREEN}"
    echo "==========================================="
    echo "    Linux系统初始化完成！"
    echo "    详细进度记录: $PROGRESS_FILE"
    echo "    执行日志: $LOG_FILE"
    echo ""
    echo "    已完成以下配置："
    echo "    ✓ 系统环境检测"
    echo "    ✓ 软件包更新和升级"
    echo "    ✓ 基础工具安装"
    echo "    ✓ SSH安全配置"
    echo "    ✓ 网络优化配置"
    echo "    ✓ zram配置（如适用）"
    echo "    ✓ 监控探针安装"
    echo "    ✓ 日志轮转配置（如适用）"
    echo "    ✓ oh-my-zsh配置"
    echo "==========================================="
    echo -e "${NC}"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
