#!/bin/bash
# backend.sh - Установка PHP 8.3 + Python 3 + Supervisor
# WorkerNet Installer v5.0

# Получить требуемую версию PHP для WorkerNet
get_required_php_version() {
    local required_php_version="8.3"
    
    # Определить требуемую версию PHP в зависимости от WORKERNET_VERSION
    if [ -n "${WORKERNET_VERSION:-}" ]; then
        case "$WORKERNET_VERSION" in
            "3.x")
                required_php_version="7.4"
                ;;
            "4.x"|"5.x")
                required_php_version="8.3"
                ;;
            *)
                required_php_version="8.3"
                ;;
        esac
    fi
    
    echo "$required_php_version"
}

# Проверка совместимости версии PHP с WorkerNet
check_php_version_compatibility() {
    local required_php_version
    local current_php_version
    
    # Получить требуемую версию
    required_php_version=$(get_required_php_version)
    
    # Если PHP уже установлен, проверить его версию
    if command_exists php; then
        current_php_version=$(php -v 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        if [ -n "$current_php_version" ]; then
            local php_major="${current_php_version%%.*}"
            local php_minor=$(echo "$current_php_version" | cut -d. -f2)
            
            if [ "$WORKERNET_VERSION" = "3.x" ]; then
                # Для версии 3.x: PHP не выше 7.4
                if [ "$php_major" -eq 7 ] && [ "$php_minor" -le 4 ]; then
                    log_info "Установлен PHP $current_php_version (WorkerNet 3.x: требуется <= 7.4) ✓"
                    return 0
                elif [ "$php_major" -lt 7 ]; then
                    log_info "Установлен PHP $current_php_version (WorkerNet 3.x: требуется <= 7.4) ✓"
                    return 0
                else
                    log_error "❌ Установлен PHP $current_php_version, но для WorkerNet 3.x требуется PHP <= 7.4"
                    log_error "   Автоматически переключим на PHP 7.4"
                    return 1
                fi
            else
                # Для версий 4.x и 5.x: PHP 8.x
                if [ "$php_major" -ge 8 ]; then
                    log_info "Установлен PHP $current_php_version (WorkerNet ${WORKERNET_VERSION:-unknown}: требуется 8+) ✓"
                    return 0
                else
                    log_error "❌ Установлен PHP $current_php_version, но для WorkerNet ${WORKERNET_VERSION:-unknown} требуется PHP 8+"
                    log_error "   Автоматически переключим на PHP 8.3"
                    return 1
                fi
            fi
        fi
    fi
    
    # Если PHP не установлен, версия совместима (будет установлена нужная)
    return 0
}

# Удалить все версии PHP, кроме указанной
remove_other_php_versions() {
    local keep_version="$1"
    local os_type=$(get_os_type)
    
    log_info "Удаление других версий PHP (оставляем $keep_version)..."
    
    case $os_type in
        ubuntu|debian)
            # Получить список установленных версий PHP
            local installed_versions=$(dpkg -l | grep -E '^ii.*php[0-9]+\.[0-9]+' | awk '{print $2}' | grep -oP 'php[0-9]+\.[0-9]+' | sort -u || true)
            
            if [ -z "$installed_versions" ]; then
                log_info "Другие версии PHP не найдены"
                return 0
            fi
            
            for version in $installed_versions; do
                # Извлечь версию из формата "php7.4" -> "7.4"
                local version_num=$(echo "$version" | grep -oP '[0-9]+\.[0-9]+' | head -1)
                
                if [ "$version_num" != "$keep_version" ]; then
                    local major=$(echo "$version_num" | cut -d. -f1)
                    local minor=$(echo "$version_num" | cut -d. -f2)
                    
                    # Остановить сервисы
                    systemctl stop "php${major}.${minor}-fpm" 2>/dev/null || true
                    systemctl disable "php${major}.${minor}-fpm" 2>/dev/null || true
                    
                    # Удалить пакеты
                    log_info "Удаление PHP $major.$minor..."
                    apt-get remove -y --purge "php${major}.${minor}*" 2>&1 | grep -v "^WARNING:" | tail -10 || true
                fi
            done
            
            # Очистить неиспользуемые зависимости
            apt-get autoremove -y 2>&1 | grep -v "^WARNING:" | tail -5 || true
            ;;
        almalinux)
            # Для AlmaLinux удаляем все версии REMI PHP, кроме нужной
            local major=$(echo "$keep_version" | cut -d. -f1)
            local minor=$(echo "$keep_version" | cut -d. -f2)
            local keep_prefix="php${major}${minor}"
            
            # Получить список установленных версий REMI PHP
            local remi_packages=$(rpm -qa | grep -E '^php[0-9]+-php-' | grep -v "^$keep_prefix-" || true)
            
            if [ -n "$remi_packages" ]; then
                log_info "Удаление других версий REMI PHP..."
                dnf remove -y $remi_packages 2>&1 | tail -10 || true
            fi
            ;;
    esac
    
    ok "Другие версии PHP удалены"
}

# Установка PHP 7.4 для Ubuntu
install_php74_ubuntu() {
    log_info "Установка PHP 7.4 для Ubuntu..."
    
    # Проверка apt lock
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        log_warn "apt занят, ожидаем..."
        if command -v wait_for_apt_lock &>/dev/null; then
            wait_for_apt_lock || return 1
        else
            sleep 5
        fi
    fi
    
    # Добавить PPA Ondřej Surý (если еще не добавлен)
    if ! apt-cache policy | grep -q "ondrej/php"; then
        run_cmd "apt install -y software-properties-common"
        run_cmd "add-apt-repository ppa:ondrej/php -y"
        run_cmd "apt update"
    fi
    
    # Проверить доступность PHP 7.4
    if ! apt-cache show php7.4 &>/dev/null; then
        log_warn "Пакет php7.4 недоступен, обновляем списки пакетов..."
        run_apt_update
        
        if ! apt-cache show php7.4 &>/dev/null; then
            log_error "PHP 7.4 недоступен в репозиториях"
            return 1
        fi
    fi
    
    log_info "✅ PHP 7.4 доступен в репозиториях"
    
    # Список расширений PHP 7.4
    local php_packages="php7.4 php7.4-fpm php7.4-cli php7.4-common php7.4-curl php7.4-intl php7.4-mbstring php7.4-opcache php7.4-mysql php7.4-pgsql php7.4-readline php7.4-xml php7.4-zip php7.4-snmp php7.4-gd php7.4-posix php7.4-soap php7.4-ldap"
    
    timed_run "Установка PHP 7.4 и расширений" \
        "apt install -y $php_packages"
    
    INSTALLED_PACKAGES+=($php_packages)
    STARTED_SERVICES+=("php7.4-fpm")
}

# Установка PHP 7.4 для Debian
install_php74_debian() {
    log_info "Установка PHP 7.4 для Debian..."
    
    # Проверка apt lock
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        log_warn "apt занят, ожидаем..."
        if command -v wait_for_apt_lock &>/dev/null; then
            wait_for_apt_lock || return 1
        else
            sleep 5
        fi
    fi
    
    # Добавить репозиторий Sury (если еще не добавлен)
    local need_repo=false
    if [ ! -f /etc/apt/trusted.gpg.d/php.gpg ] || [ ! -f /etc/apt/sources.list.d/php.list ]; then
        need_repo=true
    elif ! LC_ALL=C apt-cache policy | grep -q "packages.sury.org/php"; then
        need_repo=true
    fi
    
    if [ "$need_repo" = true ]; then
        log_info "Добавление репозитория Sury для PHP 7.4..."
        
        if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
           fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            log_warn "apt занят, ожидаем освобождения..."
            if command -v wait_for_apt_lock &>/dev/null; then
                wait_for_apt_lock || return 1
            else
                sleep 10
            fi
        fi
        
        apt-get install -y apt-transport-https lsb-release ca-certificates curl gnupg2 2>&1 | grep -v "^WARNING:" | tail -5 || true
        
        log_info "Загрузка GPG ключа Sury..."
        if ! curl -fsSL -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg 2>/dev/null; then
            wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg || {
                log_error "Не удалось загрузить GPG ключ Sury"
                return 1
            }
        fi
        
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        
        if fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            if command -v wait_for_apt_lock &>/dev/null; then
                wait_for_apt_lock || return 1
            else
                sleep 10
            fi
        fi
        
        if command -v smart_apt_update &>/dev/null; then
            smart_apt_update || return 1
        else
            apt-get update 2>&1 | grep -v "^WARNING:" | tail -10 || return 1
        fi
    fi
    
    # Проверить доступность PHP 7.4
    if ! apt-cache show php7.4 &>/dev/null; then
        log_warn "Пакет php7.4 недоступен, обновляем списки пакетов..."
        run_apt_update
        
        if ! apt-cache show php7.4 &>/dev/null; then
            log_error "PHP 7.4 недоступен в репозиториях"
            return 1
        fi
    fi
    
    log_info "✅ PHP 7.4 доступен в репозиториях"
    
    # Список расширений PHP 7.4
    local php_packages="php7.4 php7.4-fpm php7.4-cli php7.4-common php7.4-curl php7.4-intl php7.4-mbstring php7.4-opcache php7.4-mysql php7.4-pgsql php7.4-readline php7.4-xml php7.4-zip php7.4-snmp php7.4-gd php7.4-posix php7.4-soap php7.4-ldap"
    
    timed_run "Установка PHP 7.4 и расширений" \
        "apt install -y $php_packages"
    
    INSTALLED_PACKAGES+=($php_packages)
    STARTED_SERVICES+=("php7.4-fpm")
}

# Установка PHP 7.4 для AlmaLinux
install_php74_almalinux() {
    log_info "Установка PHP 7.4 для AlmaLinux..."
    
    # Репозиторий REMI должен быть добавлен
    local php_packages="php74 php74-php-fpm php74-php-cli php74-php-common php74-php-curl php74-php-intl php74-php-json php74-php-mbstring php74-php-opcache php74-php-mysql php74-php-pgsql php74-php-readline php74-php-xml php74-php-zip php74-php-snmp php74-php-gd php74-php-soap php74-php-posix"
    
    timed_run "Установка PHP 7.4 и расширений" \
        "dnf install -y $php_packages"
    
    INSTALLED_PACKAGES+=($php_packages)
    STARTED_SERVICES+=("php74-php-fpm")
    
    # Настроить alternatives для php команды
    update-alternatives --install /usr/bin/php php /opt/remi/php74/root/usr/bin/php 10
    update-alternatives --set php /opt/remi/php74/root/usr/bin/php
}

# Проверить, установлена ли версия PHP
is_php_version_installed() {
    local target_version="$1"
    local os_type=$(get_os_type)
    local major=$(echo "$target_version" | cut -d. -f1)
    local minor=$(echo "$target_version" | cut -d. -f2)
    
    case $os_type in
        ubuntu|debian)
            # Проверить наличие пакетов PHP нужной версии
            if dpkg -l | grep -q "^ii.*php${major}.${minor}" 2>/dev/null; then
                return 0
            fi
            # Проверить наличие бинарника
            if [ -f "/usr/bin/php${major}.${minor}" ]; then
                return 0
            fi
            ;;
        almalinux)
            # Проверить наличие пакетов REMI PHP
            if rpm -qa | grep -q "^php${major}${minor}-php" 2>/dev/null; then
                return 0
            fi
            # Проверить наличие бинарника
            if [ -f "/opt/remi/php${major}${minor}/root/usr/bin/php" ]; then
                return 0
            fi
            ;;
    esac
    
    return 1
}

# Переключение на нужную версию PHP
switch_php_version() {
    local target_version="$1"
    local os_type=$(get_os_type)
    local current_version=""
    
    # Определить текущую версию PHP
    if command_exists php; then
        current_version=$(php -v 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
    fi
    
    # Если нужная версия уже установлена и активна
    if [ -n "$current_version" ] && [ "$current_version" = "$target_version" ]; then
        log_info "PHP $target_version уже установлен и активен ✓"
        return 0
    fi
    
    log_section "🔄 ПЕРЕКЛЮЧЕНИЕ НА PHP $target_version"
    
    # Проверить, установлена ли нужная версия PHP
    if ! is_php_version_installed "$target_version"; then
        log_info "PHP $target_version не установлен, выполняется установка..."
        
        # Установить нужную версию
        case $os_type in
            ubuntu)
                if [ "$target_version" = "7.4" ]; then
                    install_php74_ubuntu || return 1
                elif [ "$target_version" = "8.3" ]; then
                    install_php_ubuntu || return 1
                fi
                ;;
            debian)
                if [ "$target_version" = "7.4" ]; then
                    install_php74_debian || return 1
                elif [ "$target_version" = "8.3" ]; then
                    install_php_debian || return 1
                fi
                ;;
            almalinux)
                if [ "$target_version" = "7.4" ]; then
                    install_php74_almalinux || return 1
                elif [ "$target_version" = "8.3" ]; then
                    install_php_almalinux || return 1
                fi
                ;;
        esac
    else
        log_info "PHP $target_version уже установлен, выполняю переключение..."
    fi
    
    # Переключить на нужную версию
    local major=$(echo "$target_version" | cut -d. -f1)
    local minor=$(echo "$target_version" | cut -d. -f2)
    local php_service="php${major}.${minor}-fpm"
    
    case $os_type in
        ubuntu|debian)
            # Для Ubuntu/Debian переключение через update-alternatives или прямое использование
            local php_bin="/usr/bin/php${major}.${minor}"
            
            # Если есть прямое имя команды - используем его
            if [ -f "$php_bin" ]; then
                log_info "Переключение на PHP $target_version через обновление альтернатив..."
                # Обновить альтернативы для php
                update-alternatives --install /usr/bin/php php "$php_bin" 10 2>/dev/null || true
                update-alternatives --set php "$php_bin" 2>/dev/null || true
                
                # Также обновить php-config и phpize, если есть
                if [ -f "/usr/bin/php-config${major}.${minor}" ]; then
                    update-alternatives --install /usr/bin/php-config php-config "/usr/bin/php-config${major}.${minor}" 10 2>/dev/null || true
                    update-alternatives --set php-config "/usr/bin/php-config${major}.${minor}" 2>/dev/null || true
                fi
                if [ -f "/usr/bin/phpize${major}.${minor}" ]; then
                    update-alternatives --install /usr/bin/phpize phpize "/usr/bin/phpize${major}.${minor}" 10 2>/dev/null || true
                    update-alternatives --set phpize "/usr/bin/phpize${major}.${minor}" 2>/dev/null || true
                fi
            fi
            ;;
        almalinux)
            php_service="php${major}${minor}-php-fpm"
            
            # Настроить alternatives для php команды
            local php_bin="/opt/remi/php${major}${minor}/root/usr/bin/php"
            if [ -f "$php_bin" ]; then
                log_info "Настройка alternatives для PHP $target_version..."
                update-alternatives --install /usr/bin/php php "$php_bin" 10 2>/dev/null || true
                update-alternatives --set php "$php_bin" 2>/dev/null || true
                
                # Также настроить php-config и phpize
                local php_config="/opt/remi/php${major}${minor}/root/usr/bin/php-config"
                local phpize_bin="/opt/remi/php${major}${minor}/root/usr/bin/phpize"
                
                if [ -f "$php_config" ]; then
                    update-alternatives --install /usr/bin/php-config php-config "$php_config" 10 2>/dev/null || true
                    update-alternatives --set php-config "$php_config" 2>/dev/null || true
                fi
                if [ -f "$phpize_bin" ]; then
                    update-alternatives --install /usr/bin/phpize phpize "$phpize_bin" 10 2>/dev/null || true
                    update-alternatives --set phpize "$phpize_bin" 2>/dev/null || true
                fi
            fi
            ;;
    esac
    
    # Остановить другие версии PHP-FPM
    log_info "Остановка других версий PHP-FPM..."
    case $os_type in
        ubuntu|debian)
            # Остановить все версии PHP-FPM, кроме нужной
            for fpm_service in $(systemctl list-units --type=service --all | grep -oP 'php[0-9]+\.[0-9]+-fpm' 2>/dev/null || true); do
                if [ "$fpm_service" != "$php_service" ]; then
                    systemctl stop "$fpm_service" 2>/dev/null || true
                    systemctl disable "$fpm_service" 2>/dev/null || true
                fi
            done
            ;;
        almalinux)
            # Остановить все версии PHP-FPM, кроме нужной
            for fpm_service in $(systemctl list-units --type=service --all | grep -oP 'php[0-9]+-php-fpm' 2>/dev/null || true); do
                if [ "$fpm_service" != "$php_service" ]; then
                    systemctl stop "$fpm_service" 2>/dev/null || true
                    systemctl disable "$fpm_service" 2>/dev/null || true
                fi
            done
            ;;
    esac
    
    # Запустить нужный сервис PHP-FPM
    run_cmd "systemctl enable $php_service"
    run_cmd "systemctl start $php_service"
    
    # Проверить, что версия переключилась
    if command_exists php; then
        local active_version=$(php -v 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        if [ "$active_version" = "$target_version" ]; then
            ok "Переключение на PHP $target_version завершено успешно"
        else
            log_warn "PHP переключён на $target_version, но активна версия $active_version"
            log_warn "Попытка принудительного переключения через альтернативы..."
            
            # Принудительное переключение для Ubuntu/Debian
            if [ "$os_type" != "almalinux" ]; then
                local php_bin="/usr/bin/php${major}.${minor}"
                if [ -f "$php_bin" ]; then
                    update-alternatives --set php "$php_bin" 2>/dev/null || true
                fi
            fi
        fi
    else
        log_error "PHP не найден после переключения"
        return 1
    fi
    
    return 0
}

# Установка PHP (версия зависит от WORKERNET_VERSION)
install_php() {
    # Получить требуемую версию PHP
    local required_php_version
    required_php_version=$(get_required_php_version)
    
    # Проверить совместимость текущей версии PHP
    if ! check_php_version_compatibility; then
        # PHP установлен, но несовместим - нужно переключить
        # Сообщение об ошибке уже показано в check_php_version_compatibility
        
        # Автоматически переключить на нужную версию
        log_info "Автоматическое переключение на требуемую версию PHP..."
        switch_php_version "$required_php_version" || return 1
        
        # Проверить после переключения
        if ! check_php_version_compatibility; then
            log_error "Не удалось переключить на PHP $required_php_version"
            return 1
        fi
        
        return 0
    fi
    
    # Если PHP уже установлен и совместим
    if command_exists php; then
        # Сообщение об успехе уже показано в check_php_version_compatibility
        return 0
    fi
    
    # PHP не установлен - установить нужную версию
    if [ "$required_php_version" = "7.4" ]; then
        log_section "⚙️ УСТАНОВКА PHP 7.4"
    else
        log_section "⚙️ УСТАНОВКА PHP 8.3"
    fi
    
    show_progress "Установка PHP"
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu)
            if [ "$required_php_version" = "7.4" ]; then
                install_php74_ubuntu || return 1
            else
                install_php_ubuntu || return 1
            fi
            ;;
        debian)
            if [ "$required_php_version" = "7.4" ]; then
                install_php74_debian || return 1
            else
                install_php_debian || return 1
            fi
            ;;
        almalinux)
            if [ "$required_php_version" = "7.4" ]; then
                install_php74_almalinux || return 1
            else
                install_php_almalinux || return 1
            fi
            ;;
        *)
            log_error "Unsupported OS for Установка PHP"
            return 1
            ;;
    esac
    
    ok "PHP установлен успешно"
    return 0
}

# Установка PHP для Ubuntu
install_php_ubuntu() {
    log_info "Установка PHP для Ubuntu..."
    
    # unattended-upgrades остановлен в pre-flight checks
    # Быстрая проверка apt lock на всякий случай
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        log_warn "apt занят, ожидаем..."
        if command -v wait_for_apt_lock &>/dev/null; then
            wait_for_apt_lock || return 1
        else
            sleep 5
        fi
    fi
    
    # Добавить PPA Ondřej Surý
    run_cmd "apt install -y software-properties-common"
    run_cmd "add-apt-repository ppa:ondrej/php -y"
    run_cmd "apt update"
    
    # Список расширений PHP
    local php_packages="php8.3-fpm php8.3-cli php8.3-common php8.3-curl php8.3-intl php8.3-mbstring php8.3-opcache php8.3-mysql php8.3-pgsql php8.3-readline php8.3-xml php8.3-zip php8.3-snmp php8.3-gd php8.3-posix php8.3-soap php8.3-ldap"
    
    timed_run "Установка PHP 8.3 и расширений" \
        "apt install -y $php_packages"
    
    INSTALLED_PACKAGES+=($php_packages)
    STARTED_SERVICES+=("php8.3-fpm")
}

# Установка PHP для Debian
install_php_debian() {
    log_info "Установка PHP для Debian..."
    
    # unattended-upgrades остановлен в pre-flight checks
    # Быстрая проверка apt lock на всякий случай
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        log_warn "apt занят, ожидаем..."
        if command -v wait_for_apt_lock &>/dev/null; then
            wait_for_apt_lock || return 1
        else
            sleep 5
        fi
    fi
    
    # Добавить репозиторий Sury (обязательно для Debian!)
    # Проверить наличие файлов И что репозиторий действительно в apt cache
    local need_repo=false
    if [ ! -f /etc/apt/trusted.gpg.d/php.gpg ] || [ ! -f /etc/apt/sources.list.d/php.list ]; then
        need_repo=true
    elif ! LC_ALL=C apt-cache policy | grep -q "packages.sury.org/php"; then
        # Файлы есть, но репозиторий не в кэше apt - нужно обновить
        log_warn "Репозиторий Sury присутствует в файлах, но не в кэше apt. Обновляем..."
        need_repo=true
    fi
    
    if [ "$need_repo" = true ]; then
        log_info "Добавление репозитория Sury для PHP 8.3..."
        
        # Дополнительная проверка блокировки перед добавлением репозитория
        if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
           fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            log_warn "apt занят, ожидаем освобождения..."
            if command -v wait_for_apt_lock &>/dev/null; then
                wait_for_apt_lock || return 1
            else
                sleep 10
            fi
        fi
        
        # Установить необходимые пакеты
        log_info "Установка зависимостей (curl, gnupg2, ca-certificates)..."
        apt-get install -y apt-transport-https lsb-release ca-certificates curl gnupg2 2>&1 | grep -v "^WARNING:" | tail -5 || true
        
        # Скачать и добавить GPG ключ
        log_info "Загрузка GPG ключа Sury..."
        if ! curl -fsSL -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg 2>/dev/null; then
            # Fallback: старый метод с wget
            log_warn "curl не сработал, пробуем wget..."
            wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg || {
                log_error "Не удалось загрузить GPG ключ Sury"
                return 1
            }
        fi
        ok "GPG ключ Sury загружен"
        
        # Добавить репозиторий
        log_info "Добавление репозитория PHP..."
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        ok "Репозиторий PHP добавлен в /etc/apt/sources.list.d/php.list"
        
        # Проверить блокировку перед apt update
        if fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            log_warn "apt списки заблокированы, ожидаем..."
            if command -v wait_for_apt_lock &>/dev/null; then
                wait_for_apt_lock || return 1
            else
                sleep 10
            fi
        fi
        
        # Обновить списки пакетов через smart_apt_update
        log_info "Обновление списков пакетов (может занять время)..."
        if command -v smart_apt_update &>/dev/null; then
            smart_apt_update || {
                log_error "Не удалось обновить списки пакетов"
                log_error "Проверьте сетевое подключение и доступность репозитория Sury"
                return 1
            }
        else
            # Fallback: ручное обновление если smart_apt_update недоступен
            local update_retries=0
            local update_success=false
            
            while [ $update_retries -lt 3 ]; do
                if apt-get update 2>&1 | tee -a "${LOG_FILE:-/dev/null}" | grep -v "^WARNING:" | tail -10; then
                    update_success=true
                    break
                else
                    update_retries=$((update_retries + 1))
                    if [ $update_retries -lt 3 ]; then
                        log_warn "apt update не удался, попытка $update_retries/3. Ожидаем 10 секунд..."
                        sleep 10
                    fi
                fi
            done
            
            if [ "$update_success" = false ]; then
                log_error "Не удалось обновить списки пакетов после 3 попыток"
                log_error "Проверьте сетевое подключение и доступность репозитория Sury"
                return 1
            fi
        fi
        
        ok "Репозиторий Sury добавлен успешно"
    else
        log_debug "Репозиторий Sury уже добавлен"
    fi
    
    # Проверить доступность пакета php8.3
    log_info "Проверка доступности пакетов PHP..."
    if ! apt-cache show php8.3 &>/dev/null; then
        log_warn "⚠️  Пакет php8.3 недоступен, обновляем списки пакетов..."
        run_apt_update
        
        if ! apt-cache show php8.3 &>/dev/null; then
            log_error "PHP 8.3 недоступен в репозиториях"
            log_error "Проверьте репозиторий: apt-cache policy php8.3"
            log_error "Убедитесь что packages.sury.org/php активен"
            return 1
        fi
    fi
    log_info "✅ PHP 8.3 доступен в репозиториях"
    
    # Список расширений PHP
    local php_packages="php8.3 php8.3-fpm php8.3-cli php8.3-common php8.3-curl php8.3-intl php8.3-mbstring php8.3-opcache php8.3-mysql php8.3-pgsql php8.3-readline php8.3-xml php8.3-zip php8.3-snmp php8.3-gd php8.3-posix php8.3-soap php8.3-ldap"
    
    timed_run "Установка PHP 8.3 и расширений" \
        "apt install -y $php_packages"
    
    INSTALLED_PACKAGES+=($php_packages)
    STARTED_SERVICES+=("php8.3-fpm")
}

# Установка PHP для AlmaLinux
install_php_almalinux() {
    log_info "Установка PHP для AlmaLinux..."
    
    # Репозиторий REMI уже должен быть добавлен
    local php_packages="php83 php83-php-fpm php83-php-cli php83-php-common php83-php-curl php83-php-intl php83-php-json php83-php-mbstring php83-php-opcache php83-php-mysql php83-php-pgsql php83-php-readline php83-php-xml php83-php-zip php83-php-snmp php83-php-gd php83-php-soap php83-php-posix"
    
    timed_run "Установка PHP 8.3 и расширений" \
        "dnf install -y $php_packages"
    
    INSTALLED_PACKAGES+=($php_packages)
    STARTED_SERVICES+=("php83-php-fpm")
    
    # Настроить alternatives для php команды
    update-alternatives --install /usr/local/bin/php php /opt/remi/php83/root/usr/bin/php 10
    update-alternatives --set php /opt/remi/php83/root/usr/bin/php
}

# Настройка PHP
configure_php() {
    log_info "Настройка PHP..."
    
    # Определить установленную версию PHP
    local php_version="8.3"
    if command_exists php; then
        php_version=$(php -v 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
    fi
    
    local os_type=$(get_os_type)
    local php_ini_fpm="/etc/php/${php_version}/fpm/php.ini"
    local php_ini_cli="/etc/php/${php_version}/cli/php.ini"
    local php_fpm_conf="/etc/php/${php_version}/fpm/pool.d/www.conf"
    
    if [ "$os_type" = "almalinux" ]; then
        local major=$(echo "$php_version" | cut -d. -f1)
        local minor=$(echo "$php_version" | cut -d. -f2)
        local php_dir="/etc/opt/remi/php${major}${minor}"
        php_ini_fpm="${php_dir}/php.ini"
        php_ini_cli="$php_ini_fpm"
        php_fpm_conf="${php_dir}/php-fpm.d/www.conf"
    fi
    
    # Получить timezone
    local timezone=$(cat /etc/timezone 2>/dev/null || timedatectl | grep "Time zone" | awk '{print $3}')
    
    # Настроить php.ini (FPM)
    if [ -f "$php_ini_fpm" ]; then
        sed -i "s@^;date.timezone.*@date.timezone = $timezone@" "$php_ini_fpm"
        sed -i "s@;cgi.fix_pathinfo=1@cgi.fix_pathinfo=0@" "$php_ini_fpm"
        sed -i "s@post_max_size = 8M@post_max_size = 100M@" "$php_ini_fpm"
        sed -i "s@upload_max_filesize = 2M@upload_max_filesize = 100M@" "$php_ini_fpm"
        sed -i "s@max_execution_time.*@max_execution_time = 300@" "$php_ini_fpm"
        sed -i "s@max_input_time.*@max_input_time = 300@" "$php_ini_fpm"
    fi
    
    # Настроить php.ini (CLI)
    if [ -f "$php_ini_cli" ] && [ "$php_ini_cli" != "$php_ini_fpm" ]; then
        sed -i "s@^;date.timezone.*@date.timezone = $timezone@" "$php_ini_cli"
    fi
    
    # Настроить PHP-FPM pool
    if [ -f "$php_fpm_conf" ]; then
        sed -i "s@^;request_terminate_timeout =.*@request_terminate_timeout = 300@" "$php_fpm_conf"
        
        # Для AlmaLinux настроить пользователя nginx
        if [ "$os_type" = "almalinux" ]; then
            sed -i -E 's/user\s*=\s*apache/user = nginx/; s/group\s*=\s*apache/group = nginx/' "$php_fpm_conf"
            sed -i 's/;listen\.owner\s*=\s*nobody/listen.owner = nginx/' "$php_fpm_conf"
            sed -i 's/;listen\.group\s*=\s*nobody/listen.group = nginx/' "$php_fpm_conf"
            sed -i 's/;listen\.mode\s*=\s*0660/listen.mode = 0666/' "$php_fpm_conf"
        fi
    fi
    
    # Перезапустить PHP-FPM
    local major=$(echo "$php_version" | cut -d. -f1)
    local minor=$(echo "$php_version" | cut -d. -f2)
    local php_service="php${major}.${minor}-fpm"
    
    if [ "$os_type" = "almalinux" ]; then
        php_service="php${major}${minor}-php-fpm"
    fi
    
    run_cmd "systemctl restart $php_service"
    
    ok "PHP настроен успешно (версия $php_version)"
}

# Установка Python
install_python() {
    log_section "🐍 УСТАНОВКА PYTHON 3"
    
    show_progress "Установка Python"
    
    # Проверка idempotent
    if command_exists python3 && command_exists pip3; then
        ok "Python 3 уже установлен, пропускаем"
        return 0
    fi
    
    # Ожидание освобождения apt (если функция доступна)
    if command -v wait_for_apt_lock &>/dev/null; then
        wait_for_apt_lock || return 1
    fi
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            timed_run "Установка Python 3" \
                "apt install -y python3 python3-dev python3-pip python3-venv libffi-dev pkg-config libsnmp-dev"
            INSTALLED_PACKAGES+=("python3" "python3-pip" "python3-venv")
            ;;
        almalinux)
            timed_run "Установка Python 3" \
                "dnf install -y python3 python3-devel python3-pip libffi-devel pkg-config net-snmp-devel"
            INSTALLED_PACKAGES+=("python3" "python3-pip")
            ;;
    esac
    
    ok "Python установлен успешно"
    return 0
}

# Настройка Python
configure_python() {
    log_info "Настройка Python..."
    
    # Отключить EXTERNALLY-MANAGED (для Ubuntu/Debian)
    local os_type=$(get_os_type)
    
    if [ "$os_type" = "ubuntu" ]; then
        local externally_managed="/usr/lib/python3.12/EXTERNALLY-MANAGED"
        if [ -f "$externally_managed" ]; then
            mv "$externally_managed" "${externally_managed}.old"
            log_info "Отключен EXTERNALLY-MANAGED для Python 3.12"
        fi
    elif [ "$os_type" = "debian" ]; then
        local externally_managed="/usr/lib/python3.11/EXTERNALLY-MANAGED"
        if [ -f "$externally_managed" ]; then
            mv "$externally_managed" "${externally_managed}.old"
            log_info "Отключен EXTERNALLY-MANAGED для Python 3.11"
        fi
    fi
    
    # Обновить pip и virtualenv
    # В Ubuntu 24.04 системный pip нельзя обновить без --break-system-packages
    log_info "Установка/обновление pip и virtualenv..."
    
    # Определить версию Python и нужные флаги
    local python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
    local pip_flags=""
    
    # Для Python 3.12+ в Ubuntu 24.04 нужен --break-system-packages
    if [ "$os_type" = "ubuntu" ] && [ "$(get_os_version)" = "24" ]; then
        if [ -n "$python_version" ] && [ "${python_version%%.*}" -ge 3 ] && [ "${python_version##*.}" -ge 12 ]; then
            pip_flags="--break-system-packages"
            log_debug "Используем --break-system-packages для Python $python_version в Ubuntu 24.04"
        fi
    fi
    
    # Проверить версию pip
    local current_pip_version=$(python3 -m pip --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
    if [ -n "$current_pip_version" ] && [ "${current_pip_version%%.*}" -ge 24 ]; then
        log_info "pip $current_pip_version уже установлен (достаточно новый)"
    else
        log_info "Обновление pip (может занять до 2 минут)..."
        
        # Обновление pip с правильными флагами
        if timeout 120 python3 -m pip install --upgrade pip $pip_flags 2>&1 | tee -a "${LOG_FILE:-/dev/null}" | tail -5; then
            ok "pip обновлён успешно"
        elif [ -n "$pip_flags" ]; then
            # Если с --break-system-packages не получилось, попробовать без него
            log_warn "Повторная попытка обновления pip без --break-system-packages..."
            if timeout 120 python3 -m pip install --upgrade pip --ignore-installed 2>&1 | tee -a "${LOG_FILE:-/dev/null}" | tail -5; then
                ok "pip обновлён успешно"
            else
                log_warn "Не удалось обновить pip (используется системная версия)"
            fi
        else
            log_warn "Не удалось обновить pip (используется системная версия)"
        fi
    fi
    
    # Установить virtualenv если нужно
    if ! python3 -m pip show virtualenv >/dev/null 2>&1; then
        log_info "Установка virtualenv (может занять до 2 минут)..."
        
        # Установка virtualenv с правильными флагами
        if timeout 120 python3 -m pip install virtualenv $pip_flags 2>&1 | tee -a "${LOG_FILE:-/dev/null}" | tail -10; then
            ok "virtualenv установлен успешно"
        elif [ -n "$pip_flags" ]; then
            # Если с --break-system-packages не получилось, попробовать без него
            log_warn "Повторная попытка установки virtualenv без --break-system-packages..."
            if timeout 120 python3 -m pip install virtualenv --ignore-installed 2>&1 | tee -a "${LOG_FILE:-/dev/null}" | tail -10; then
                ok "virtualenv установлен успешно"
            else
                log_warn "Не удалось установить virtualenv (может повлиять на poller)"
            fi
        else
            log_warn "Не удалось установить virtualenv (может повлиять на poller)"
        fi
    else
        log_info "virtualenv уже установлен"
    fi
    
    # Проверить версию
    local python_version=$(python3 --version)
    ok "Python настроен: $python_version"
    
    return 0
}

# Установка Supervisor
install_supervisor() {
    log_section "📋 УСТАНОВКА SUPERVISOR"
    
    show_progress "Установка Supervisor"
    
    # Проверка idempotent
    if command_exists supervisorctl; then
        ok "Supervisor уже установлен, пропускаем"
        return 0
    fi
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            timed_run "Установка Supervisor" \
                "apt install -y supervisor"
            INSTALLED_PACKAGES+=("supervisor")
            STARTED_SERVICES+=("supervisor")
            ;;
        almalinux)
            timed_run "Установка Supervisor" \
                "dnf install -y supervisor"
            INSTALLED_PACKAGES+=("supervisor")
            
            # Запустить и добавить в автозапуск
            run_cmd "systemctl enable supervisord"
            run_cmd "systemctl start supervisord"
            STARTED_SERVICES+=("supervisord")
            
            # Настроить конфигурацию для .conf файлов
            sed -i 's/files = supervisord\.d\/\*\.ini/files = supervisord.d\/\*.conf/' /etc/supervisord.conf
            ;;
    esac
    
    ok "Supervisor установлен успешно"
    return 0
}

# Главная функция установки backend
setup_backend() {
    install_php || return 1
    configure_php || return 1
    install_python || return 1
    configure_python || return 1
    install_supervisor || return 1
    
    return 0
}

# Экспортировать функции
export -f get_required_php_version
export -f check_php_version_compatibility
export -f remove_other_php_versions
export -f is_php_version_installed
export -f install_php74_ubuntu
export -f install_php74_debian
export -f install_php74_almalinux
export -f switch_php_version
export -f install_php
export -f install_php_ubuntu
export -f install_php_debian
export -f install_php_almalinux
export -f configure_php
export -f install_python
export -f configure_python
export -f install_supervisor
export -f setup_backend

