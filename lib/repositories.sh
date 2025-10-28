#!/bin/bash
# repositories.sh - Централизованное управление репозиториями для Debian/Ubuntu
# WorkerNet Installer v5.0

# Параллельная загрузка GPG ключей
download_gpg_keys_parallel() {
    log_info "Загрузка GPG ключей параллельно..."
    
    local pids=()
    local keys_downloaded=0
    
    # PostgreSQL ключ
    if [ ! -f /etc/apt/trusted.gpg.d/postgresql.gpg ]; then
        (
            if curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc 2>/dev/null | \
               gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg 2>/dev/null; then
                log_debug "PostgreSQL GPG ключ загружен"
            else
                log_warn "Не удалось загрузить PostgreSQL GPG ключ"
            fi
        ) &
        pids+=($!)
    fi
    
    # PHP (Sury) ключ
    if [ ! -f /etc/apt/trusted.gpg.d/php.gpg ]; then
        (
            if curl -fsSL https://packages.sury.org/php/apt.gpg 2>/dev/null | \
               gpg --dearmor -o /etc/apt/trusted.gpg.d/php.gpg 2>/dev/null; then
                log_debug "PHP (Sury) GPG ключ загружен"
            else
                log_warn "Не удалось загрузить PHP GPG ключ"
            fi
        ) &
        pids+=($!)
    fi
    
    # Дождаться завершения всех загрузок
    for pid in "${pids[@]}"; do
        if wait "$pid" 2>/dev/null; then
            ((keys_downloaded++))
        fi
    done
    
    if [ ${#pids[@]} -gt 0 ]; then
        ok "GPG ключи загружены параллельно ($keys_downloaded/${#pids[@]})"
    else
        log_debug "Все GPG ключи уже присутствуют"
    fi
    
    return 0
}

# Централизованная настройка репозиториев для Debian/Ubuntu
setup_debian_repositories() {
    log_info "Настройка всех необходимых репозиториев для Debian/Ubuntu..."
    
    local repos_added=false
    local os_codename=$(lsb_release -sc 2>/dev/null || echo "bookworm")
    
    # 1. PostgreSQL репозиторий
    if ! apt-cache policy 2>/dev/null | grep -q "apt.postgresql.org"; then
        log_info "Добавление репозитория PostgreSQL..."
        
        # Загрузить GPG ключ
        if [ ! -f /etc/apt/trusted.gpg.d/postgresql.gpg ]; then
            if curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc 2>/dev/null | \
               gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg 2>/dev/null; then
                log_debug "PostgreSQL GPG ключ добавлен"
            else
                log_warn "Не удалось загрузить PostgreSQL GPG ключ, используем wget..."
                wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc 2>/dev/null | \
                    gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg 2>/dev/null || true
            fi
        fi
        
        # Добавить репозиторий
        echo "deb http://apt.postgresql.org/pub/repos/apt ${os_codename}-pgdg main" > \
            /etc/apt/sources.list.d/pgdg.list
        ok "Репозиторий PostgreSQL добавлен"
        repos_added=true
    else
        log_debug "Репозиторий PostgreSQL уже добавлен"
    fi
    
    # 2. PHP (Sury) репозиторий
    if ! apt-cache policy 2>/dev/null | grep -q "packages.sury.org/php"; then
        log_info "Добавление репозитория Sury (PHP 8.3)..."
        
        # Загрузить GPG ключ
        if [ ! -f /etc/apt/trusted.gpg.d/php.gpg ]; then
            if curl -fsSL https://packages.sury.org/php/apt.gpg 2>/dev/null | \
               gpg --dearmor -o /etc/apt/trusted.gpg.d/php.gpg 2>/dev/null; then
                log_debug "PHP (Sury) GPG ключ добавлен"
            else
                log_warn "Не удалось загрузить PHP GPG ключ, используем wget..."
                wget -qO- https://packages.sury.org/php/apt.gpg 2>/dev/null | \
                    gpg --dearmor -o /etc/apt/trusted.gpg.d/php.gpg 2>/dev/null || true
            fi
        fi
        
        # Добавить репозиторий
        echo "deb https://packages.sury.org/php/ ${os_codename} main" > \
            /etc/apt/sources.list.d/php.list
        ok "Репозиторий Sury (PHP) добавлен"
        repos_added=true
    else
        log_debug "Репозиторий Sury уже добавлен"
    fi
    
    # 3. RabbitMQ репозиторий (опционально, может использовать fallback)
    if ! apt-cache policy 2>/dev/null | grep -q "rabbitmq"; then
        log_info "Попытка добавления репозитория RabbitMQ (необязательно)..."
        
        # Попробовать добавить, но не критично если не получится
        if curl -1sLf 'https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA' 2>/dev/null | \
           gpg --dearmor -o /usr/share/keyrings/com.rabbitmq.team.gpg 2>/dev/null; then
            
            cat > /etc/apt/sources.list.d/rabbitmq.list << RABBITMQ
## Provides modern Erlang/OTP releases
deb [signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/${os_codename} main
deb-src [signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/${os_codename} main

## Provides RabbitMQ
deb [signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-server/deb/${os_codename} main
deb-src [signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-server/deb/${os_codename} main
RABBITMQ
            log_debug "Репозиторий RabbitMQ добавлен"
            repos_added=true
        else
            log_debug "Репозиторий RabbitMQ недоступен, будет использован fallback"
        fi
    else
        log_debug "Репозиторий RabbitMQ уже добавлен"
    fi
    
    # Один apt update для всех репозиториев
    if [ "$repos_added" = true ]; then
        log_info "Обновление списков пакетов после добавления репозиториев..."
        if command -v smart_apt_update &>/dev/null; then
            smart_apt_update || return 1
        else
            # Fallback если smart_apt_update недоступен
            apt-get update 2>&1 | grep -v "^WARNING:" | tail -10 || return 1
        fi
        ok "Все репозитории добавлены и обновлены"
    else
        log_debug "Все репозитории уже добавлены"
    fi
    
    return 0
}

# Проверка наличия репозитория в системе
check_repository() {
    local repo_pattern=$1
    
    if apt-cache policy 2>/dev/null | grep -q "$repo_pattern"; then
        return 0
    else
        return 1
    fi
}

# Экспорт функций
export -f download_gpg_keys_parallel
export -f setup_debian_repositories
export -f check_repository

