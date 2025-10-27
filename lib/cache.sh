#!/bin/bash
# cache.sh - Установка Redis
# WorkerNet Installer v5.0

# Установка Redis
install_redis() {
    log_section "💾 УСТАНОВКА REDIS"
    
    show_progress "Установка Redis"
    
    # Проверка idempotent - уже установлен?
    if command_exists redis-cli && systemctl list-unit-files | grep -q "redis"; then
        ok "Redis уже установлен, пропускаем"
        return 0
    fi
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            timed_run "Installing Redis" \
                "apt install -y redis-server"
            INSTALLED_PACKAGES+=("redis-server")
            STARTED_SERVICES+=("redis")
            ;;
        almalinux)
            timed_run "Installing Redis" \
                "dnf install -y redis"
            INSTALLED_PACKAGES+=("redis")
            STARTED_SERVICES+=("redis")
            
            # Запустить и добавить в автозапуск (AlmaLinux не делает это автоматически)
            run_cmd "systemctl enable redis"
            run_cmd "systemctl start redis"
            ;;
        *)
            log_error "Неподдерживаемая ОС для установки Redis"
            return 1
            ;;
    esac
    
    # Проверка установки
    if ! command_exists redis-cli; then
        log_error "Установка Redis не удалась"
        return 1
    fi
    
    ok "Redis установлен успешно"
    return 0
}

# Настройка Redis
configure_redis() {
    log_info "Настройка Redis..."
    
    # Генерация пароля для Redis
    if [ -z "$GENHASH" ]; then
        # Попытка загрузить из файла (при переустановке)
        load_credentials 2>/dev/null || true
        
        if [ -n "${REDIS_PASSWORD:-}" ]; then
            GENHASH="$REDIS_PASSWORD"
            log_info "Использование пароля Redis из предыдущей установки"
        else
            GENHASH=$(generate_hash)
            log_debug "Сгенерирован новый пароль Redis (SHA256 хеш)"
            
            # Сохранить в файл учётных данных
            save_credentials "REDIS_PASSWORD" "$GENHASH"
        fi
    fi
    
    local redis_conf="/etc/redis/redis.conf"
    
    # Резервная копия конфигурации
    if [ -f "$redis_conf" ] && [ ! -f "${redis_conf}.backup" ]; then
        cp "$redis_conf" "${redis_conf}.backup"
        CREATED_FILES+=("${redis_conf}.backup")
    fi
    
    # Настроить пароль
    if grep -q "^requirepass" "$redis_conf"; then
        # Пароль уже установлен, обновить
        sed -i "s@^requirepass .*@requirepass $GENHASH@g" "$redis_conf"
    elif grep -q "^# requirepass" "$redis_conf"; then
        # Раскомментировать и установить
        sed -i "s@^# requirepass .*@requirepass $GENHASH@g" "$redis_conf"
    else
        # Добавить новую строку
        echo "requirepass $GENHASH" >> "$redis_conf"
    fi
    
    # Настроить timeout (0 = бесконечное соединение)
    sed -i 's@^timeout .*@timeout 0@' "$redis_conf"
    
    # Перезапустить Redis
    run_cmd "systemctl restart redis"
    
    ok "Redis настроен успешно"
}

# Проверка Redis
verify_redis() {
    log_info "Проверка установки Redis..."
    
    # Проверка сервиса
    if ! is_service_active "redis"; then
        log_error "Сервис Redis не запущен"
        return 1
    fi
    ok "Сервис Redis запущен"
    
    # Проверка подключения и пароля
    if redis-cli -h 127.0.0.1 -p 6379 -a "$GENHASH" ping 2>/dev/null | grep -q "PONG"; then
        ok "Аутентификация Redis успешна"
    else
        log_error "Аутентификация Redis не удалась"
        log_debug "Попытка без пароля..."
        
        # Попробовать без пароля (если конфигурация не применилась)
        if redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -q "PONG"; then
            log_warn "Redis отвечает без пароля (конфигурация могла не примениться)"
        else
            log_error "Redis не отвечает"
            return 1
        fi
    fi
    
    # Проверка версии
    local redis_version=$(redis-cli -v | grep -oP 'redis-cli \K[0-9.]+')
    log_info "Версия Redis: $redis_version"
    
    log_info "Параметры подключения Redis:"
    log_info "  Хост: 127.0.0.1"
    log_info "  Порт: 6379"
    log_info "  Пароль: $GENHASH"
    
    return 0
}

# Главная функция установки Redis
setup_cache() {
    # При переустановке: остановить Redis если запущен
    if systemctl is-active --quiet redis-server 2>/dev/null || systemctl is-active --quiet redis 2>/dev/null; then
        log_info "Обнаружен запущенный Redis (переустановка)"
        log_info "Остановка Redis перед переустановкой..."
        
        systemctl stop redis-server 2>/dev/null || systemctl stop redis 2>/dev/null || true
        pkill -9 redis-server 2>/dev/null || true
        sleep 2
        
        ok "Redis остановлен для переустановки"
    fi
    
    install_redis || return 1
    configure_redis || return 1
    verify_redis || return 1
    
    return 0
}

# Экспортировать функции
export -f install_redis
export -f configure_redis
export -f verify_redis
export -f setup_cache

