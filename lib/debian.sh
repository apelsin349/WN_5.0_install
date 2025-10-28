#!/bin/bash
# debian.sh - Специфичные настройки и оптимизации для Debian 12
# WorkerNet Installer v5.0

# Оптимизация системы Debian для production
optimize_debian_system() {
    log_info "Оптимизация системы Debian 12 для production..."
    
    # 1. Отключить ненужные сервисы (если они запущены)
    local services_to_disable=(
        "bluetooth.service"
        "ModemManager.service"
        "wpa_supplicant.service"
    )
    
    local services_disabled=0
    for service in "${services_to_disable[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_debug "Отключение сервиса: $service"
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            ((services_disabled++))
        fi
    done
    
    if [ $services_disabled -gt 0 ]; then
        log_debug "Отключено ненужных сервисов: $services_disabled"
    fi
    
    # 2. Настроить journald (ограничение размера логов)
    log_debug "Настройка journald..."
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/workernet.conf << 'JOURNALD'
# WorkerNet - Ограничение размера журналов
[Journal]
SystemMaxUse=100M
SystemMaxFileSize=10M
MaxRetentionSec=2week
JOURNALD
    systemctl restart systemd-journald 2>/dev/null || true
    
    # 3. Настроить sysctl для production
    log_debug "Настройка sysctl для production..."
    cat > /etc/sysctl.d/99-workernet.conf << 'SYSCTL'
# WorkerNet Production Settings

# Сетевые настройки
net.core.somaxconn=1024
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_keepalive_intvl=15

# Память и swap
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5

# Файловая система
fs.file-max=65536
fs.inotify.max_user_watches=524288
SYSCTL
    sysctl -p /etc/sysctl.d/99-workernet.conf >/dev/null 2>&1 || true
    
    # 4. Настроить limits для пользователей
    log_debug "Настройка system limits..."
    if ! grep -q "# WorkerNet Limits" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'LIMITS'

# WorkerNet Limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 4096
* hard nproc 4096
www-data soft nofile 65536
www-data hard nofile 65536
postgres soft nofile 65536
postgres hard nofile 65536
LIMITS
    fi
    
    ok "Debian 12 оптимизирован для production"
    
    # Показать краткую информацию об оптимизациях
    log_info "Применены оптимизации:"
    log_info "  • journald: логи ограничены 100MB"
    log_info "  • sysctl: network tuning, vm.swappiness=10"
    log_info "  • limits: file descriptors 65536"
    log_info "  • отключено сервисов: $services_disabled"
    
    return 0
}

# Настройка безопасности Debian (опционально)
harden_debian_security() {
    log_info "Настройка безопасности Debian 12..."
    
    # 1. Установить fail2ban (защита от brute-force)
    if ! command_exists fail2ban-client; then
        log_info "Установка fail2ban..."
        if apt-get install -y fail2ban 2>&1 | grep -v "^WARNING:" | tail -5; then
            INSTALLED_PACKAGES+=("fail2ban")
            ok "fail2ban установлен"
        else
            log_warn "Не удалось установить fail2ban"
            return 0  # Не критично
        fi
    fi
    
    # 2. Настроить fail2ban для SSH, PostgreSQL, NGINX
    log_debug "Настройка fail2ban..."
    cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
# WorkerNet fail2ban configuration

[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log

[postgresql]
enabled = true
port = 5432
logpath = /var/log/postgresql/postgresql-*-main.log
maxretry = 3
FAIL2BAN
    
    systemctl restart fail2ban 2>/dev/null || true
    systemctl enable fail2ban 2>/dev/null || true
    
    # 3. Настроить автоматические обновления безопасности
    log_debug "Настройка автоматических обновлений безопасности..."
    if apt-get install -y unattended-upgrades apt-listchanges 2>&1 | \
       grep -v "^WARNING:" | tail -5; then
        INSTALLED_PACKAGES+=("unattended-upgrades" "apt-listchanges")
        
        cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UNATTENDED'
// WorkerNet - Автоматические обновления безопасности
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
    // Не обновлять PostgreSQL автоматически
    "postgresql-*";
    "php*";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UNATTENDED
        
        cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOUPGRADES'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
AUTOUPGRADES
    fi
    
    ok "Безопасность Debian 12 настроена"
    
    log_info "Настройки безопасности:"
    log_info "  • fail2ban: защита SSH, PostgreSQL, NGINX"
    log_info "  • auto-updates: только обновления безопасности"
    log_info "  • ban time: 1 час, max retries: 5"
    
    return 0
}

# Экспорт функций
export -f optimize_debian_system
export -f harden_debian_security

