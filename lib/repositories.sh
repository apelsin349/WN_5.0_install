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
    
    # 3. RabbitMQ репозиторий (пропускаем, используется fallback в lib/queue.sh)
    # RabbitMQ будет установлен позже через lib/queue.sh с правильной настройкой репозитория
    log_debug "Репозиторий RabbitMQ будет настроен в lib/queue.sh (если необходимо)"
    
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
        
        # Проверить что репозитории действительно активны в apt
        verify_repositories_added || {
            log_error "Репозитории не были корректно добавлены в apt cache"
            return 1
        }
        
        # Проверить приоритеты (для отладки)
        check_repository_priorities
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

# Проверка доступности пакета в репозиториях
check_package_availability() {
    local package=$1
    local min_version=${2:-""}
    
    log_debug "Проверка доступности пакета: $package..."
    
    # Получить доступную версию
    local available_version=$(apt-cache policy "$package" 2>/dev/null | \
                              grep "Candidate:" | awk '{print $2}')
    
    if [ -z "$available_version" ] || [ "$available_version" = "(none)" ]; then
        log_warn "⚠️  Пакет $package недоступен в репозиториях"
        return 1
    fi
    
    log_debug "Доступная версия $package: $available_version"
    
    # Если указана минимальная версия, проверить её
    if [ -n "$min_version" ]; then
        # Простое сравнение версий (для более сложных нужен dpkg --compare-versions)
        if dpkg --compare-versions "$available_version" ge "$min_version" 2>/dev/null; then
            log_debug "Версия $available_version >= $min_version (OK)"
        else
            log_warn "⚠️  Версия $available_version < $min_version"
            return 1
        fi
    fi
    
    return 0
}

# Проверка что все добавленные репозитории активны в apt
verify_repositories_added() {
    log_info "Проверка добавленных репозиториев в apt cache..."
    
    local all_ok=true
    local repos_checked=0
    local repos_ok=0
    
    # PostgreSQL
    ((repos_checked++))
    if apt-cache policy 2>/dev/null | grep -q "apt.postgresql.org"; then
        ok "  ✅ PostgreSQL репозиторий активен"
        ((repos_ok++))
    else
        log_error "  ❌ PostgreSQL репозиторий не найден в apt cache"
        all_ok=false
    fi
    
    # PHP (Sury)
    ((repos_checked++))
    if apt-cache policy 2>/dev/null | grep -q "packages.sury.org/php"; then
        ok "  ✅ PHP (Sury) репозиторий активен"
        ((repos_ok++))
    else
        log_error "  ❌ PHP репозиторий не найден в apt cache"
        all_ok=false
    fi
    
    # Проверить доступность ключевых пакетов
    log_info "Проверка доступности ключевых пакетов..."
    
    local packages_checked=0
    local packages_ok=0
    
    for pkg in postgresql-16 php8.3; do
        ((packages_checked++))
        local version=$(apt-cache policy "$pkg" 2>/dev/null | \
                        grep "Candidate:" | awk '{print $2}')
        if [ -n "$version" ] && [ "$version" != "(none)" ]; then
            ok "  ✅ $pkg: $version"
            ((packages_ok++))
        else
            log_warn "  ⚠️  $pkg: недоступен"
        fi
    done
    
    if [ "$all_ok" = true ]; then
        ok "Все репозитории активны в apt ($repos_ok/$repos_checked)"
        ok "Ключевые пакеты доступны ($packages_ok/$packages_checked)"
        return 0
    else
        log_error "Некоторые репозитории не активны в apt ($repos_ok/$repos_checked)"
        return 1
    fi
}

# Проверка приоритетов репозиториев
check_repository_priorities() {
    log_debug "Проверка приоритетов репозиториев..."
    
    # Проверить что Sury имеет приоритет для PHP
    local php_source=$(apt-cache policy php8.3 2>/dev/null | \
                       grep "Candidate:" -A5 | \
                       grep "packages.sury.org")
    
    if [ -n "$php_source" ]; then
        log_debug "  ✅ PHP 8.3 будет установлен из Sury репозитория"
    else
        log_warn "  ⚠️  PHP 8.3 может установиться не из Sury"
    fi
    
    # Проверить PostgreSQL
    local pg_source=$(apt-cache policy postgresql-16 2>/dev/null | \
                      grep "Candidate:" -A5 | \
                      grep "apt.postgresql.org")
    
    if [ -n "$pg_source" ]; then
        log_debug "  ✅ PostgreSQL 16 будет установлен из официального репозитория"
    else
        log_warn "  ⚠️  PostgreSQL 16 может установиться не из официального репозитория"
    fi
    
    return 0
}

# Экспорт функций
export -f download_gpg_keys_parallel
export -f setup_debian_repositories
export -f check_repository
export -f check_package_availability
export -f verify_repositories_added
export -f check_repository_priorities

