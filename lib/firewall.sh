#!/bin/bash
# firewall.sh - Настройка firewall для WorkerNet
# WorkerNet Installer v5.0

# Ожидание освобождения apt lock (АГРЕССИВНО)
wait_for_apt_lock() {
    log_info "Проверка доступности apt..."
    
    local retries=0
    local max_retries=10  # 10 × 30 сек = 5 минут
    local kill_threshold=5  # После 5 попыток (2.5 минуты) предложить убить
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        
        ((retries++))
        
        # Найти процесс держащий блокировку
        local lock_pid=$(fuser /var/lib/dpkg/lock-frontend 2>/dev/null | awk '{print $1}')
        local lock_process=$(ps -p "$lock_pid" -o comm= 2>/dev/null || echo "unknown")
        
        # После 2.5 минут - предложить убить процесс
        if [ $retries -eq $kill_threshold ]; then
            log_warn ""
            log_warn "⚠️  apt занят более 2.5 минут процессом: $lock_process (PID: $lock_pid)"
            log_warn "   Это может быть unattended-upgrades (автообновления)"
            echo ""
            
            read -p "Остановить процесс $lock_process и продолжить? (y/n): " -n 1 -r
            echo ""
            echo ""
            
            if [[ $REPLY =~ ^[YyДд]$ ]]; then
                log_info "Остановка процесса $lock_process (PID: $lock_pid)..."
                kill -9 "$lock_pid" 2>/dev/null || true
                
                # Убить все apt процессы
                killall -9 apt apt-get unattended-upgr 2>/dev/null || true
                
                # Удалить lock файлы принудительно
                rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
                rm -f /var/lib/dpkg/lock 2>/dev/null || true
                rm -f /var/lib/apt/lists/lock 2>/dev/null || true
                
                # Переконфигурировать dpkg если нужно
                dpkg --configure -a 2>/dev/null || true
                
                sleep 3
                ok "Процесс остановлен, apt освобождён"
                return 0
            else
                log_info "Продолжаем ждать..."
            fi
        fi
        
        # После 5 минут - таймаут
        if [ $retries -ge $max_retries ]; then
            log_error "apt занят более 5 минут, прерываем ожидание"
            log_error ""
            log_error "Процесс: $lock_process (PID: $lock_pid)"
            log_error ""
            log_error "Решение:"
            log_error "  1. Дождитесь завершения (может занять до 30 минут)"
            log_error "  2. Или остановите вручную:"
            log_error "     sudo killall -9 apt apt-get unattended-upgr"
            log_error "     sudo rm -f /var/lib/dpkg/lock*"
            log_error "     sudo dpkg --configure -a"
            log_error "  3. Запустите установку снова"
            log_error ""
            return 1
        fi
        
        log_warn "apt занят процессом: $lock_process (PID: $lock_pid)"
        log_info "Ожидание освобождения... (попытка $retries/$max_retries, ждём 30 сек)"
        sleep 30
    done
    
    ok "apt доступен"
    return 0
}

# Настройка iptables firewall
setup_firewall() {
    log_section "🔥 НАСТРОЙКА FIREWALL"
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            setup_firewall_debian
            ;;
        almalinux)
            setup_firewall_almalinux
            ;;
        *)
            log_warn "Неизвестная ОС для настройки firewall: $os_type"
            log_info "Пропускаем настройку firewall (настройте вручную)"
            return 0
            ;;
    esac
    
    return 0
}

# Настройка firewall для Debian/Ubuntu
setup_firewall_debian() {
    log_info "Настройка iptables для Debian/Ubuntu..."
    
    # unattended-upgrades уже остановлен в pre-flight checks
    # Финальная проверка apt на всякий случай
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        log_warn "apt всё ещё занят, ожидаем..."
        wait_for_apt_lock || return 1
    fi
    
    # Остановить и отключить ufw (если есть)
    if systemctl is-active --quiet ufw 2>/dev/null; then
        log_info "Отключение ufw..."
        systemctl stop ufw 2>/dev/null || true
        systemctl disable ufw 2>/dev/null || true
        apt remove --purge ufw -y 2>/dev/null || true
    fi
    
    # Остановить и отключить nftables (если есть)
    if systemctl is-active --quiet nftables 2>/dev/null; then
        log_info "Отключение nftables..."
        systemctl stop nftables 2>/dev/null || true
        systemctl disable nftables 2>/dev/null || true
        apt remove --purge nftables -y 2>/dev/null || true
    fi
    
    # Установить iptables-persistent
    log_info "Установка iptables-persistent..."
    
    # apt уже свободен (unattended-upgrades остановлен выше)
    if ! DEBIAN_FRONTEND=noninteractive apt install -y iptables iptables-persistent 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        log_warn "Не удалось установить iptables-persistent"
        log_info "Продолжаем без firewall (настройте вручную)"
        return 0
    fi
    
    ok "iptables-persistent установлен"
    
    # Настроить базовые правила
    log_info "Настройка базовых правил iptables..."
    
    # Очистить существующие правила
    iptables -F 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    
    # Базовые правила (разрешить всё для локальной сети и HTTP/HTTPS)
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT   # SSH
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT   # HTTP
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT  # HTTPS
    
    # Сохранить правила
    netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    
    ok "Firewall настроен (базовые правила)"
    
    return 0
}

# Настройка firewall для AlmaLinux
setup_firewall_almalinux() {
    log_info "Настройка firewalld для AlmaLinux..."
    
    # AlmaLinux использует firewalld
    if ! systemctl is-active --quiet firewalld; then
        systemctl start firewalld
        systemctl enable firewalld
    fi
    
    # Открыть необходимые порты
    firewall-cmd --permanent --add-service=http 2>/dev/null || true
    firewall-cmd --permanent --add-service=https 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
    
    ok "Firewall настроен (firewalld)"
    
    return 0
}

# Экспортировать функции
export -f wait_for_apt_lock
export -f setup_firewall
export -f setup_firewall_debian
export -f setup_firewall_almalinux

