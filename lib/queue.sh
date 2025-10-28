#!/bin/bash
# queue.sh - Установка RabbitMQ + Erlang (с fallback методами)
# WorkerNet Installer v5.0

# Установка RabbitMQ
install_rabbitmq() {
    log_section "📨 УСТАНОВКА RABBITMQ + ERLANG"
    
    show_progress "RabbitMQ installation"
    
    # Проверка idempotent - уже установлен?
    if command_exists rabbitmqctl && systemctl list-unit-files | grep -q "rabbitmq-server"; then
        ok "RabbitMQ уже установлен, пропускаем"
        return 0
    fi
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            install_rabbitmq_debian
            ;;
        almalinux)
            install_rabbitmq_almalinux
            ;;
        *)
            log_error "Неподдерживаемая ОС для установки RabbitMQ"
            return 1
            ;;
    esac
    
    # Проверка установки
    if ! command_exists rabbitmqctl; then
        log_error "Установка RabbitMQ не удалась"
        return 1
    fi
    
    ok "RabbitMQ установлен успешно"
    return 0
}

# Fallback метод установки RabbitMQ (из репозиториев дистрибутива)
install_rabbitmq_fallback() {
    log_info "📦 Установка RabbitMQ из стандартных репозиториев (fallback)..."
    
    # Удалить неработающие репозитории
    rm -f /etc/apt/sources.list.d/rabbitmq.list 2>/dev/null
    
    # Обновить списки через smart_apt_update
    if command -v smart_apt_update &>/dev/null; then
        smart_apt_update
    else
        apt update
    fi
    
    # Установить Erlang из репозиториев Ubuntu/Debian
    log_info "Установка Erlang из стандартных репозиториев..."
    
    # Попробовать разные варианты установки Erlang
    local erlang_packages="erlang-base erlang-nox"
    if [ "$(get_os_type)" = "debian" ]; then
        # Для Debian попробуем минимальный набор
        erlang_packages="erlang-base"
    fi
    
    if ! apt install -y $erlang_packages 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "⚠️  Не удалось установить полный набор Erlang, пробуем минимальный..."
        if ! apt install -y erlang-base 2>&1 | tee -a "$LOG_FILE"; then
            log_error "❌ Не удалось установить Erlang"
            return 1
        fi
    fi
    INSTALLED_PACKAGES+=("erlang-base")
    
    # Установить RabbitMQ из репозиториев Ubuntu/Debian
    log_info "Установка RabbitMQ из стандартных репозиториев..."
    if ! apt install -y rabbitmq-server 2>&1 | tee -a "$LOG_FILE"; then
        log_error "❌ Не удалось установить RabbitMQ"
        return 1
    fi
    INSTALLED_PACKAGES+=("rabbitmq-server")
    
    log_warn "⚠️  RabbitMQ установлен из стандартных репозиториев (может быть старая версия)"
    log_info "   Функциональность WorkerNet не пострадает"
    log_info "   Для получения последней версии настройте репозитории вручную"
    
    return 0
}

# Установка RabbitMQ для Debian/Ubuntu
install_rabbitmq_debian() {
    log_info "Установка RabbitMQ для Debian/Ubuntu..."
    
    local os_version=$(get_os_version)
    local codename="noble"  # Ubuntu 24
    
    if [ "$(get_os_type)" = "debian" ]; then
        codename="bookworm"  # Debian 12
        # Для Debian требуется OpenSSL 1.1, но используем актуальные репозитории
        if ! dpkg -l | grep -q "libssl1.1"; then
            log_info "Установка OpenSSL 1.1 для Debian 12..."
            # Используем актуальные репозитории вместо устаревших
            if ! apt install -y libssl1.1 2>/dev/null; then
                # Если libssl1.1 недоступен, попробуем libssl3
                log_warn "libssl1.1 недоступен, пробуем libssl3..."
                if ! apt install -y libssl3 2>/dev/null; then
                    log_warn "Не удалось установить OpenSSL, продолжаем без него"
                else
                    log_info "Установлен libssl3"
                fi
            else
                log_info "Установлен libssl1.1"
            fi
        fi
    fi
    
    # Попытка 1: Установка из официальных репозиториев RabbitMQ
    log_info "🔄 Попытка установки из официальных репозиториев RabbitMQ..."
    
    # Добавить ключ RabbitMQ
    local key_added=false
    if [ ! -f /usr/share/keyrings/com.rabbitmq.team.gpg ]; then
        if timeout 10 curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" 2>/dev/null | \
            gpg --dearmor | tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null 2>&1; then
            log_info "✅ Ключ RabbitMQ добавлен"
            key_added=true
        else
            log_warn "⚠️  Не удалось загрузить ключ RabbitMQ"
        fi
    else
        key_added=true
    fi
    
    # Добавить репозитории (с зеркалами) только если ключ добавлен
    if [ "$key_added" = true ] && [ ! -f /etc/apt/sources.list.d/rabbitmq.list ]; then
        cat > /etc/apt/sources.list.d/rabbitmq.list <<EOF
# Modern Erlang/OTP releases (с зеркалами)
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://packagecloud.io/rabbitmq/erlang/ubuntu/ $codename main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-erlang/ubuntu/$codename $codename main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-erlang/ubuntu/$codename $codename main

# Latest RabbitMQ releases (с зеркалами)
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ $codename main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-server/ubuntu/$codename $codename main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-server/ubuntu/$codename $codename main
EOF
        log_info "Репозитории RabbitMQ добавлены"
    fi
    
    # Обновить списки пакетов через smart_apt_update
    log_info "Обновление списков пакетов..."
    local update_success=false
    if command -v smart_apt_update &>/dev/null; then
        smart_apt_update && update_success=true
    else
        apt update 2>&1 | tee -a "$LOG_FILE" && update_success=true
    fi
    
    if [ "$update_success" = false ]; then
        log_warn "⚠️  Проблемы с обновлением репозиториев, используем fallback метод"
        install_rabbitmq_fallback
        return $?
    fi
    
    # Проверить доступность пакетов RabbitMQ
    if ! apt-cache show rabbitmq-server >/dev/null 2>&1; then
        log_warn "⚠️  Пакеты RabbitMQ недоступны в официальных репозиториях"
        log_info "🔄 Попытка установки из стандартных репозиториев дистрибутива..."
        
        # Попытка установки из стандартных репозиториев
        if apt-cache show rabbitmq-server >/dev/null 2>&1; then
            log_info "✅ RabbitMQ доступен в стандартных репозиториях"
        else
            log_warn "⚠️  RabbitMQ недоступен, используем fallback метод"
            install_rabbitmq_fallback
            return $?
        fi
    fi
    
    # Установить Erlang
    log_info "Установка Erlang..."
    if ! apt install -y erlang-base erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets \
        erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key erlang-runtime-tools \
        erlang-snmp erlang-ssl erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "⚠️  Не удалось установить Erlang из RabbitMQ репозитория, используем fallback"
        install_rabbitmq_fallback
        return $?
    fi
    INSTALLED_PACKAGES+=("erlang-base")
    
    # Установить RabbitMQ
    log_info "Установка RabbitMQ Server..."
    if ! apt install -y rabbitmq-server --fix-missing 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "⚠️  Не удалось установить RabbitMQ из официального репозитория, используем fallback"
        install_rabbitmq_fallback
        return $?
    fi
    INSTALLED_PACKAGES+=("rabbitmq-server")
    
    # Для Debian создать директорию если не существует
    if [ "$(get_os_type)" = "debian" ] && [ ! -d "/var/lib/rabbitmq" ]; then
        mkdir -p /var/lib/rabbitmq
        chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
    fi
    
    ok "✅ RabbitMQ установлен из официальных репозиториев"
    return 0
}

# Установка RabbitMQ для AlmaLinux
install_rabbitmq_almalinux() {
    log_info "Установка RabbitMQ для AlmaLinux..."
    
    # Добавить EPEL репозиторий
    if ! rpm -q epel-release > /dev/null 2>&1; then
        dnf install -y epel-release
    fi
    
    # Добавить репозиторий Erlang
    if [ ! -f /etc/yum.repos.d/rabbitmq_erlang.repo ]; then
        curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | bash
    fi
    
    # Добавить репозиторий RabbitMQ
    if [ ! -f /etc/yum.repos.d/rabbitmq_rabbitmq-server.repo ]; then
        curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | bash
    fi
    
    # Установить Erlang
    timed_run "Установка Erlang" \
        "dnf install -y erlang"
    INSTALLED_PACKAGES+=("erlang")
    
    # Установить RabbitMQ
    timed_run "Установка RabbitMQ Server" \
        "dnf install -y rabbitmq-server"
    INSTALLED_PACKAGES+=("rabbitmq-server")
}

# Настройка RabbitMQ
configure_rabbitmq() {
    log_info "Настройка RabbitMQ..."
    
    # Запустить службу
    systemctl enable rabbitmq-server
    systemctl start rabbitmq-server
    
    # Подождать запуска
    sleep 5
    
    # Включить management plugin
    log_info "Включение RabbitMQ Management Plugin..."
    rabbitmq-plugins enable rabbitmq_management
    
    # Включить WebSTOMP plugin (для WebSocket)
    log_info "Включение RabbitMQ WebSTOMP Plugin..."
    rabbitmq-plugins enable rabbitmq_web_stomp
    
    # Загрузка или генерация паролей
    load_credentials 2>/dev/null || true
    
    local admin_user="admin"
    local admin_pass="${RABBITMQ_ADMIN_PASSWORD:-$(generate_password 12)}"
    
    local workernet_user="workernet"
    local workernet_pass="${RABBITMQ_WORKERNET_PASSWORD:-$(generate_password 12)}"
    
    local webstomp_user="workernet-stomp"
    local webstomp_pass="${RABBITMQ_WEBSTOMP_PASSWORD:-$(generate_password 12)}"
    
    # Если загрузили из файла
    if [ -n "${RABBITMQ_ADMIN_PASSWORD:-}" ]; then
        log_info "Использование паролей RabbitMQ из предыдущей установки"
    else
        log_debug "Сгенерированы новые пароли RabbitMQ"
    fi
    
    # 1. Создать пользователя admin (administrator)
    log_info "Создание RabbitMQ admin пользователя..."
    rabbitmqctl delete_user "$admin_user" 2>/dev/null || true
    rabbitmqctl add_user "$admin_user" "$admin_pass"
    rabbitmqctl set_user_tags "$admin_user" administrator
    rabbitmqctl set_permissions -p / "$admin_user" ".*" ".*" ".*"
    
    # 2. Создать пользователя workernet (monitoring)
    log_info "Создание RabbitMQ workernet пользователя..."
    rabbitmqctl delete_user "$workernet_user" 2>/dev/null || true
    rabbitmqctl add_user "$workernet_user" "$workernet_pass"
    rabbitmqctl set_user_tags "$workernet_user" monitoring
    rabbitmqctl set_permissions -p / "$workernet_user" ".*" ".*" ".*"
    
    # 3. Создать пользователя workernet-stomp (для WebSocket)
    log_info "Создание RabbitMQ WebSocket пользователя..."
    rabbitmqctl delete_user "$webstomp_user" 2>/dev/null || true
    rabbitmqctl add_user "$webstomp_user" "$webstomp_pass"
    # Permissions: configure: ^erp.stomp:id-.* | write: ^erp.stomp:id-.* | read: ^erp.stomp:id-.*
    # Это разрешает создавать/читать временные очереди для WebSocket
    rabbitmqctl set_permissions -p / "$webstomp_user" "^erp.stomp:id-.*" "^erp.stomp:id-.*" "^erp.stomp:id-.*"
    
    # Проверить аутентификацию
    log_info "Проверка аутентификации пользователей..."
    rabbitmqctl authenticate_user "$admin_user" "$admin_pass" >/dev/null 2>&1 || log_warn "Не удалось проверить admin"
    rabbitmqctl authenticate_user "$workernet_user" "$workernet_pass" >/dev/null 2>&1 || log_warn "Не удалось проверить workernet"
    rabbitmqctl authenticate_user "$webstomp_user" "$webstomp_pass" >/dev/null 2>&1 || log_warn "Не удалось проверить webstomp"
    
    # Перезапустить RabbitMQ для применения изменений
    log_info "Перезапуск RabbitMQ..."
    systemctl restart rabbitmq-server
    sleep 3
    
    # Сохранить учетные данные (для show_credentials в finalize.sh)
    NAMERABBITADMIN="$admin_user"
    GENPASSRABBITADMIN="$admin_pass"
    NAMERABBITUSER="$workernet_user"
    GENPASSRABBITUSER="$workernet_pass"
    WEBSTOMPUSER="$webstomp_user"
    GENPASSWEBSTOMPUSER="$webstomp_pass"
    
    # Экспортировать для использования в других модулях
    export NAMERABBITADMIN GENPASSRABBITADMIN
    export NAMERABBITUSER GENPASSRABBITUSER
    export WEBSTOMPUSER GENPASSWEBSTOMPUSER
    
    # Сохранить в файл учётных данных (для postinstall и будущих переустановок)
    # Всегда сохраняем, даже если загрузили из файла (на случай изменения)
    save_credentials "RABBITMQ_ADMIN_USER" "$admin_user"
    save_credentials "RABBITMQ_ADMIN_PASSWORD" "$admin_pass"
    save_credentials "RABBITMQ_WORKERNET_USER" "$workernet_user"
    save_credentials "RABBITMQ_WORKERNET_PASSWORD" "$workernet_pass"
    save_credentials "RABBITMQ_WEBSTOMP_USER" "$webstomp_user"
    save_credentials "RABBITMQ_WEBSTOMP_PASSWORD" "$webstomp_pass"
    
    log_debug "Учётные данные RabbitMQ сохранены в файл"
    
    ok "RabbitMQ настроен (3 пользователя создано)"
}

# Главная функция установки RabbitMQ (вызывается из install.sh)
setup_queue() {
    # При переустановке: остановить RabbitMQ если запущен
    if systemctl is-active --quiet rabbitmq-server 2>/dev/null; then
        log_info "Обнаружен запущенный RabbitMQ (переустановка)"
        log_info "Остановка RabbitMQ перед переустановкой..."
        
        systemctl stop rabbitmq-server 2>/dev/null || true
        pkill -9 -u rabbitmq 2>/dev/null || true
        pkill -9 beam 2>/dev/null || true
        pkill -9 epmd 2>/dev/null || true
        sleep 2
        
        ok "RabbitMQ остановлен для переустановки"
    fi
    
    # Установить RabbitMQ
    install_rabbitmq || return 1
    
    # Настроить RabbitMQ
    configure_rabbitmq || return 1
    
    return 0
}

# Экспортировать функции
export -f install_rabbitmq
export -f install_rabbitmq_debian
export -f install_rabbitmq_fallback
export -f install_rabbitmq_almalinux
export -f configure_rabbitmq
export -f setup_queue

