#!/bin/bash
# finalize.sh - Финализация установки
# WorkerNet Installer v5.0

# Настройка firewall (iptables)
setup_firewall() {
    log_section "🔥 НАСТРОЙКА FIREWALL"
    
    show_progress "Настройка firewall"
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            setup_firewall_debian
            ;;
        almalinux)
            setup_firewall_almalinux
            ;;
    esac
    
    ok "Firewall настроен успешно"
    return 0
}

# Настройка firewall для Debian/Ubuntu
setup_firewall_debian() {
    log_info "Настройка iptables для Debian/Ubuntu..."
    
    # Остановить и отключить ufw
    systemctl stop ufw 2>/dev/null || true
    ufw disable 2>/dev/null || true
    apt remove --auto-remove ufw -y 2>/dev/null || true
    
    # Остановить и отключить nftables (Debian)
    if [ "$(get_os_type)" = "debian" ]; then
        systemctl stop nftables 2>/dev/null || true
        systemctl disable nftables 2>/dev/null || true
        apt remove --purge nftables -y 2>/dev/null || true
    fi
    
    # Установить iptables-persistent
    DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
    INSTALLED_PACKAGES+=("iptables-persistent")
    
    # Применить правила
    apply_iptables_rules
    
    # Сохранить правила
    service netfilter-persistent save
    systemctl start iptables
}

# Настройка firewall для AlmaLinux
setup_firewall_almalinux() {
    log_info "Настройка iptables для AlmaLinux..."
    
    # Остановить и отключить firewalld
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    dnf remove -y firewalld 2>/dev/null || true
    
    # Установить iptables
    dnf install -y iptables iptables-services
    INSTALLED_PACKAGES+=("iptables" "iptables-services")
    
    systemctl enable iptables
    systemctl start iptables
    STARTED_SERVICES+=("iptables")
    
    # Применить правила
    apply_iptables_rules
    
    # Сохранить правила
    service iptables save
}

# Применить правила iptables
apply_iptables_rules() {
    log_info "Применение правил iptables..."
    
    # Очистить таблицы
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -X
    
    # Политики по умолчанию
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
    
    # Разрешить трафик по петлевому интерфейсу
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Разрешить установленные соединения
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Разрешить входящий PING
    iptables -A INPUT -p icmp -j ACCEPT
    
    # Разрешить все исходящие
    iptables -I OUTPUT 1 -j ACCEPT
    
    # Доступ по SSH
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Разрешить доступ к WEB серверу
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    
    # Разрешить доступ к RabbitMQ Management (рекомендуется закрыть после настройки)
    iptables -A INPUT -p tcp --dport 15672 -j ACCEPT
    
    ok "Правила iptables применены"
}

# Создание .env файла
create_env_file() {
    log_info "Создание .env файла..."
    
    local env_file="${INSTALL_DIR}/.env"
    local domain_for_url="$DOMAIN"
    
    if [ "$domain_for_url" = "_" ]; then
        domain_for_url="127.0.0.1"
    fi
    
    # Создать .env
    cat > "$env_file" <<EOF
URL=http://$domain_for_url/
DB_DSN=pgsql:host=127.0.0.1;port=5432;dbname=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$GENPASSDB
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=$GENHASH
AMQP_DSN=amqp://$NAMERABBITUSER:$GENPASSRABBITUSER@127.0.0.1:5672/%2f
EOF
    
    CREATED_FILES+=("$env_file")
    
    # Установить права
    chmod 640 "$env_file"
    
    ok ".env файл создан: $env_file"
}

# Установка прав доступа
set_permissions() {
    log_info "Установка прав доступа..."
    
    local os_type=$(get_os_type)
    local web_user="www-data"
    local web_group="www-data"
    
    if [ "$os_type" = "almalinux" ]; then
        if [ "$WEBSERVER" = "apache" ]; then
            web_user="apache"
            web_group="apache"
        else
            web_user="nginx"
            web_group="nginx"
        fi
    fi
    
    # Установить владельца
    chown -R $web_user:$web_group "$INSTALL_DIR"
    
    # Установить права
    chmod -R u=rwX,g=rwX "$INSTALL_DIR"
    
    ok "Права доступа установлены: $web_user:$web_group"
}

# Загрузка workernet_install.phar
download_installer_phar() {
    log_info "Загрузка установщика WorkerNet (phar)..."
    log_info "Версия: $WORKERNET_VERSION"
    
    local phar_file="${INSTALL_DIR}/workernet_install.phar"
    local phar_url=$(get_phar_url "$WORKERNET_VERSION")
    
    # Проверка idempotent
    if [ -f "$phar_file" ]; then
        ok "Phar файл уже существует, пропуск загрузки"
        return 0
    fi
    
    cd "$INSTALL_DIR"
    
    # Загрузить через PHP
    if php -r "copy('$phar_url', 'workernet_install.phar');" ; then
        ok "Phar файл загружен успешно"
        CREATED_FILES+=("$phar_file")
    else
        log_error "Не удалось загрузить phar файл"
        log_warn "Попытка с curl..."
        
        if curl -f -L -o "$phar_file" "$phar_url"; then
            ok "Phar файл загружен через curl"
            CREATED_FILES+=("$phar_file")
        else
            log_error "Не удалось загрузить phar файл with curl"
            return 1
        fi
    fi
    
    # Установить права на phar файл (критично!)
    log_info "Установка прав на phar файл..."
    chown www-data:www-data "$phar_file"
    chmod 775 "$phar_file"  # Writable для owner и group
    ok "Права на phar файл установлены (www-data:www-data, 775)"
    
    return 0
}

# Запуск финальной установки
run_phar_installer() {
    log_info "Запуск установщика WorkerNet phar..."
    
    local os_type=$(get_os_type)
    local web_user="www-data"
    
    if [ "$os_type" = "almalinux" ]; then
        # Определить пользователя веб-сервера
        web_user=$(stat -c '%U' "${INSTALL_DIR}/workernet_install.phar" 2>/dev/null || echo "www-data")
    fi
    
    cd "$INSTALL_DIR"
    
    # Запустить установщик от имени веб-пользователя
    if sudo -u $web_user php workernet_install.phar install; then
        ok "Приложение WorkerNet установлено успешно"
        return 0
    else
        log_error "Установщик phar не удался"
        return 1
    fi
}

# Показ паролей пользователю
show_credentials() {
    log_section "🔑 ПАРАМЕТРЫ УСТАНОВКИ"
    
    print_color "$COLOR_CYAN" "════════════════════════════════════════════════════════════════════════"
    print_color "$COLOR_BLUE" "  УСТАНОВЛЕННАЯ ВЕРСИЯ: WorkerNet $WORKERNET_VERSION"
    print_color "$COLOR_BLUE" "  Префикс модулей: $(get_module_prefix)_*"
    print_color "$COLOR_CYAN" "────────────────────────────────────────────────────────────────────────"
    print_color "$COLOR_GREEN" "  PostgreSQL database name: $DB_NAME"
    print_color "$COLOR_GREEN" "  PostgreSQL username: $DB_USER"
    print_color "$COLOR_GREEN" "  PostgreSQL password: $GENPASSDB"
    echo ""
    print_color "$COLOR_GREEN" "  Redis password: $GENHASH"
    echo ""
    print_color "$COLOR_GREEN" "  RabbitMQ admin user: $NAMERABBITADMIN"
    print_color "$COLOR_GREEN" "  RabbitMQ admin password: $GENPASSRABBITADMIN"
    print_color "$COLOR_GREEN" "  RabbitMQ workernet user: $NAMERABBITUSER"
    print_color "$COLOR_GREEN" "  RabbitMQ workernet password: $GENPASSRABBITUSER"
    print_color "$COLOR_GREEN" "  RabbitMQ WebSocket user: $WEBSTOMPUSER"
    print_color "$COLOR_GREEN" "  RabbitMQ WebSocket password: $GENPASSWEBSTOMPUSER"
    print_color "$COLOR_CYAN" "════════════════════════════════════════════════════════════════════════"
    echo ""
    print_color "$COLOR_YELLOW" "⚠️  ВАЖНО: Скопируйте и сохраните эти параметры в безопасном месте!"
    echo ""
    
    read -p "Нажмите Enter после копирования паролей..."
}

# Запись lock-файла
write_lock_file() {
    log_info "Запись lock файла..."
    
    local lock_value=$(get_lock_value "$WORKERNET_VERSION")
    echo "$lock_value" > "$LOCK_FILE"
    
    log_info "Версия: $WORKERNET_VERSION → Lock: $lock_value"
    ok "Lock файл создан: $LOCK_FILE"
}

# Главная функция финализации
finalize_installation() {
    create_env_file || return 1
    write_lock_file || return 1
    download_installer_phar || return 1
    
    # Установить права ПОСЛЕ загрузки всех файлов (критично!)
    set_permissions || return 1
    
    show_credentials
    
    run_phar_installer || return 1
    
    return 0
}

# Алиас для совместимости с install.sh
setup_finalize() {
    finalize_installation
}

# Экспортировать функции
export -f setup_firewall
export -f setup_firewall_debian
export -f setup_firewall_almalinux
export -f apply_iptables_rules
export -f create_env_file
export -f set_permissions
export -f download_installer_phar
export -f run_phar_installer
export -f show_credentials
export -f write_lock_file
export -f finalize_installation
export -f setup_finalize

