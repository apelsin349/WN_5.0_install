#!/bin/bash
# backend.sh - Установка PHP 8.3 + Python 3 + Supervisor
# WorkerNet Installer v5.0

# Установка PHP 8.3
install_php() {
    log_section "⚙️ УСТАНОВКА PHP 8.3"
    
    show_progress "Установка PHP"
    
    # Проверка idempotent
    if command_exists php && php -v | grep -q "PHP 8.3"; then
        ok "PHP 8.3 уже установлен, пропускаем"
        return 0
    fi
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu)
            install_php_ubuntu
            ;;
        debian)
            install_php_debian
            ;;
        almalinux)
            install_php_almalinux
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
    elif ! apt-cache policy | grep -q "packages.sury.org/php"; then
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
        
        # Обновить списки пакетов
        log_info "Обновление списков пакетов (может занять время)..."
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
        
        ok "Репозиторий Sury добавлен успешно"
    else
        log_debug "Репозиторий Sury уже добавлен"
    fi
    
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
    
    local os_type=$(get_os_type)
    local php_ini_fpm="/etc/php/8.3/fpm/php.ini"
    local php_ini_cli="/etc/php/8.3/cli/php.ini"
    local php_fpm_conf="/etc/php/8.3/fpm/pool.d/www.conf"
    
    if [ "$os_type" = "almalinux" ]; then
        php_ini_fpm="/etc/opt/remi/php83/php.ini"
        php_ini_cli="$php_ini_fpm"
        php_fpm_conf="/etc/opt/remi/php83/php-fpm.d/www.conf"
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
    local php_service="php8.3-fpm"
    if [ "$os_type" = "almalinux" ]; then
        php_service="php83-php-fpm"
    fi
    
    run_cmd "systemctl restart $php_service"
    
    ok "PHP настроен успешно"
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
export -f install_php
export -f install_php_ubuntu
export -f install_php_debian
export -f install_php_almalinux
export -f configure_php
export -f install_python
export -f configure_python
export -f install_supervisor
export -f setup_backend

