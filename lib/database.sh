#!/bin/bash
# database.sh - Установка PostgreSQL 16 + PostGIS 3
# WorkerNet Installer v5.0

# Установка PostgreSQL
install_postgresql() {
    log_section "🗄️ УСТАНОВКА POSTGRESQL 16 + POSTGIS 3"
    
    show_progress "Установка PostgreSQL"
    
    # Проверка idempotent - уже установлен?
    if command_exists psql && sudo -u postgres psql --version | grep -q "16"; then
        ok "PostgreSQL 16 уже установлен, пропускаем"
        return 0
    fi
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            install_postgresql_debian
            ;;
        almalinux)
            install_postgresql_almalinux
            ;;
        *)
            log_error "Неподдерживаемая ОС для установки PostgreSQL"
            return 1
            ;;
    esac
    
    # Проверка установки
    if ! command_exists psql; then
        log_error "Установка PostgreSQL не удалась"
        return 1
    fi
    
    ok "PostgreSQL установлен успешно"
    return 0
}

# Установка PostgreSQL для Debian/Ubuntu
install_postgresql_debian() {
    log_info "Установка PostgreSQL для Debian/Ubuntu..."
    
    # Добавить репозиторий PostgreSQL
    if [ ! -f /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc ]; then
        timed_run "Добавление репозитория PostgreSQL" \
            "install -d /usr/share/postgresql-common/pgdg && \
             curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
             sh -c 'echo \"deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt \$(lsb_release -cs)-pgdg main\" > /etc/apt/sources.list.d/pgdg.list'"
    fi
    
    # Обновить списки пакетов
    run_cmd "apt update"
    
    # Установить PostgreSQL 16
    timed_run "Установка PostgreSQL 16" \
        "apt install -y postgresql-16"
    INSTALLED_PACKAGES+=("postgresql-16")
    STARTED_SERVICES+=("postgresql")
    
    # Установить PostGIS 3
    timed_run "Установка PostGIS 3" \
        "apt install -y postgresql-16-postgis-3"
    INSTALLED_PACKAGES+=("postgresql-16-postgis-3")
}

# Установка PostgreSQL для AlmaLinux
install_postgresql_almalinux() {
    log_info "Установка PostgreSQL для AlmaLinux..."
    
    # Добавить репозиторий PostgreSQL
    if [ ! -f /etc/yum.repos.d/pgdg-redhat-all.repo ]; then
        timed_run "Добавление репозитория PostgreSQL" \
            "dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    fi
    
    # Отключить встроенный модуль PostgreSQL
    run_cmd "dnf -qy module disable postgresql"
    
    # Установить PostgreSQL 16
    timed_run "Установка PostgreSQL 16" \
        "dnf install -y postgresql16-server"
    INSTALLED_PACKAGES+=("postgresql16-server")
    
    # Инициализировать кластер
    if [ ! -d /var/lib/pgsql/16/data/base ]; then
        timed_run "Инициализация кластера PostgreSQL" \
            "/usr/pgsql-16/bin/postgresql-16-setup initdb"
    fi
    
    # Запустить и добавить в автозапуск
    run_cmd "systemctl enable postgresql-16"
    run_cmd "systemctl start postgresql-16"
    STARTED_SERVICES+=("postgresql-16")
    
    # Установить PostGIS
    timed_run "Установка PostGIS 3" \
        "dnf install -y postgis33_16"
    INSTALLED_PACKAGES+=("postgis33_16")
}

# Реинициализация PostgreSQL кластера с ru_RU.UTF-8
reinit_postgresql_cluster() {
    log_warn "🔄 Реинициализация кластера PostgreSQL с локалью ru_RU.UTF-8..."
    log_warn "   ⚠️ ВНИМАНИЕ: Текущий кластер будет удален!"
    
    local os_type=$(get_os_type)
    local pg_version="16"
    local data_dir=""
    local conf_dir=""
    
    case $os_type in
        ubuntu|debian)
            data_dir="/var/lib/postgresql/${pg_version}/main"
            conf_dir="/etc/postgresql/${pg_version}/main"
            ;;
        almalinux)
            data_dir="/var/lib/pgsql/${pg_version}/data"
            conf_dir="$data_dir"
            ;;
    esac
    
    # Остановить PostgreSQL
    log_info "Остановка PostgreSQL..."
    systemctl stop postgresql 2>/dev/null || systemctl stop postgresql-${pg_version} 2>/dev/null || true
    sleep 2
    
    # Убедиться что сервис остановлен
    systemctl kill postgresql 2>/dev/null || true
    systemctl kill postgresql-${pg_version} 2>/dev/null || true
    sleep 2
    
    # Убить все процессы postgres (АГРЕССИВНО)
    log_info "Завершение всех процессов PostgreSQL (все пользователи)..."
    pkill -9 -u postgres 2>/dev/null || true
    pkill -9 postgres 2>/dev/null || true
    killall -9 postgres 2>/dev/null || true
    sleep 3
    
    # Проверить что процессы убиты
    local postgres_count=$(ps aux | grep postgres | grep -v grep | wc -l)
    if [ "$postgres_count" -gt 0 ]; then
        log_warn "Найдено $postgres_count процессов postgres после остановки"
        log_info "Принудительное завершение оставшихся процессов..."
        ps aux | grep postgres | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
        sleep 2
    fi
    
    # Удалить ВСЕ файлы блокировки и сокеты PostgreSQL
    log_info "Удаление файлов блокировки и сокетов..."
    rm -f "$data_dir/postmaster.pid" 2>/dev/null || true
    rm -f "$data_dir/postmaster.opts" 2>/dev/null || true
    rm -f /var/run/postgresql/.s.PGSQL.* 2>/dev/null || true
    rm -f /var/run/postgresql/*.pid 2>/dev/null || true
    rm -f /tmp/.s.PGSQL.* 2>/dev/null || true
    sleep 2
    
    # КРИТИЧНО: Сначала удалить кластер из реестра PostgreSQL!
    if command_exists pg_dropcluster; then
        log_info "Удаление старого кластера из реестра PostgreSQL..."
        # --stop-server гарантирует что кластер будет остановлен перед удалением
        pg_dropcluster --stop ${pg_version} main 2>&1 | tail -5 || true
        sleep 2
    fi
    
    # Создать backup текущих данных (ПОСЛЕ удаления из реестра!)
    local backup_suffix="backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -d "$data_dir" ]; then
        log_info "Создание backup данных: ${data_dir}.${backup_suffix}"
        mv "$data_dir" "${data_dir}.${backup_suffix}" 2>/dev/null || rm -rf "$data_dir"
    fi
    
    if [ -d "$conf_dir" ] && [ "$conf_dir" != "$data_dir" ]; then
        log_info "Создание backup конфигурации: ${conf_dir}.${backup_suffix}"
        mv "$conf_dir" "${conf_dir}.${backup_suffix}" 2>/dev/null || rm -rf "$conf_dir"
    fi
    
    # Реинициализировать кластер с ru_RU.UTF-8
    log_info "Инициализация нового кластера с локалью ru_RU.UTF-8..."
    
    # КРИТИЧНО: Установить правильные переменные окружения для локали
    log_info "Настройка переменных окружения для локали..."
    
    # Проверить что локаль доступна
    if ! locale -a 2>/dev/null | grep -q "ru_RU.utf8\|ru_RU.UTF-8"; then
        log_error "Локаль ru_RU.UTF-8 недоступна в системе!"
        log_error "Установите локаль перед реинициализацией кластера"
        return 1
    fi
    
    # Установить переменные окружения глобально для всей функции
    export LANG=ru_RU.UTF-8
    export LANGUAGE=ru_RU:ru
    export LC_ALL=ru_RU.UTF-8
    export LC_CTYPE=ru_RU.UTF-8
    export LC_COLLATE=ru_RU.UTF-8
    export LC_MESSAGES=ru_RU.UTF-8
    
    # Проверить что переменные установлены
    log_debug "Переменные локали: LANG=$LANG, LC_ALL=$LC_ALL, LC_CTYPE=$LC_CTYPE"
    
    local cluster_created=false
    
    case $os_type in
        ubuntu|debian)
            # Ubuntu/Debian используют pg_createcluster
            if command_exists pg_createcluster; then
                log_info "Создание кластера через pg_createcluster..."
                
                # Проверить поддержку флага --no-start
                local no_start_flag=""
                if pg_createcluster --help 2>&1 | grep -q "no-start"; then
                    no_start_flag="--no-start"
                    log_debug "Флаг --no-start поддерживается"
                else
                    log_debug "Флаг --no-start не поддерживается, будет остановлен после создания"
                fi
                
                # Создать кластер с учетом поддержки флага и правильными переменными окружения
                if LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8 LC_CTYPE=ru_RU.UTF-8 pg_createcluster ${pg_version} main --port=5432 --locale=ru_RU.UTF-8 --encoding=UTF8 $no_start_flag 2>&1 | tee /tmp/pg_create.log | tail -10; then
                    cluster_created=true
                    log_info "Кластер создан через pg_createcluster на порту 5432"
                    
                    # Если флаг --no-start не поддерживался, остановить кластер
                    if [ -z "$no_start_flag" ]; then
                        if pg_lsclusters | grep "^${pg_version}.*main.*online" >/dev/null 2>&1; then
                            log_info "Останавливаем кластер после создания (флаг --no-start не поддерживается)..."
                            pg_ctlcluster ${pg_version} main stop 2>/dev/null || true
                            sleep 2
                        fi
                    fi
                else
                    log_warn "Ошибка pg_createcluster (возможно --no-start не поддерживается), пробуем прямую инициализацию..."
                fi
            fi
            
            # Если pg_createcluster не сработал - прямая инициализация
            if [ "$cluster_created" = false ]; then
                log_info "Прямая инициализация кластера через initdb..."
                # Создать директории
                mkdir -p "$data_dir"
                mkdir -p "$conf_dir"
                chown -R postgres:postgres "$data_dir"
                chown -R postgres:postgres "$conf_dir"
                chmod 700 "$data_dir"
                
                # Прямая инициализация с правильными переменными окружения
                sudo -u postgres env LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8 LC_CTYPE=ru_RU.UTF-8 /usr/lib/postgresql/${pg_version}/bin/initdb -D "$data_dir" \
                    --locale=ru_RU.UTF-8 --encoding=UTF8 2>&1 | tail -10
            fi
            ;;
        almalinux)
            mkdir -p "$data_dir"
            chown postgres:postgres "$data_dir"
            chmod 700 "$data_dir"
            
            # Прямая инициализация с правильными переменными окружения
            sudo -u postgres env LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8 LC_CTYPE=ru_RU.UTF-8 /usr/pgsql-${pg_version}/bin/initdb -D "$data_dir" \
                --locale=ru_RU.UTF-8 --encoding=UTF8 2>&1 | tail -10
            ;;
    esac
    
    # Запустить PostgreSQL
    log_info "Запуск PostgreSQL..."
    
    # Использовать правильный метод запуска в зависимости от того, как создан кластер
    if [ "$cluster_created" = true ] && command_exists pg_ctlcluster; then
        # Кластер создан через pg_createcluster - использовать pg_ctlcluster
        log_info "Запуск кластера через pg_ctlcluster..."
        pg_ctlcluster ${pg_version} main start 2>&1 | tail -10 || true
        sleep 3
    else
        # Прямая инициализация - использовать systemctl
        log_info "Запуск PostgreSQL через systemctl..."
        
        # Проверить что PostgreSQL НЕ запущен уже
        if systemctl is-active --quiet postgresql 2>/dev/null || systemctl is-active --quiet postgresql-${pg_version} 2>/dev/null; then
            log_warn "PostgreSQL уже запущен, перезапускаем..."
            systemctl restart postgresql 2>/dev/null || systemctl restart postgresql-${pg_version} 2>/dev/null || true
        else
            # Запустить PostgreSQL
            systemctl start postgresql 2>/dev/null || systemctl start postgresql-${pg_version} 2>/dev/null || pg_ctlcluster ${pg_version} main start || true
        fi
        sleep 3
    fi
    
    # Подождать запуска
    log_info "Ожидание запуска PostgreSQL (до 60 секунд)..."
    sleep 5
    
    # Проверить что PostgreSQL реально готов принимать подключения
    local retries=0
    local max_retries=20  # Увеличено с 15 до 20 (60 секунд вместо 45)
    
    while ! sudo -u postgres pg_isready -q 2>/dev/null; do
        ((retries++))
        if [ $retries -ge $max_retries ]; then
            log_error "PostgreSQL не готов принимать подключения после реинициализации"
            log_error "Проверка через pg_isready не прошла"
            log_error ""
            log_error "Проверка процессов PostgreSQL:"
            ps aux | grep postgres | grep -v grep || echo "Нет процессов postgres"
            log_error ""
            log_error "Проверка кластеров (pg_lsclusters):"
            pg_lsclusters 2>/dev/null || echo "pg_lsclusters недоступен"
            log_error ""
            log_error "Лог PostgreSQL (последние 30 строк):"
            tail -30 /var/log/postgresql/postgresql-${pg_version}-main.log 2>/dev/null || \
            journalctl -u postgresql -n 30 --no-pager 2>/dev/null || \
            echo "Логи PostgreSQL недоступны"
            log_error ""
            log_error "Статус systemctl:"
            systemctl status postgresql 2>&1 | head -20 || true
            log_error ""
            log_error "Попробуйте запустить вручную:"
            log_error "  sudo pg_ctlcluster ${pg_version} main start"
            log_error "  sudo systemctl start postgresql"
            return 1
        fi
        log_info "Попытка $retries/$max_retries (pg_isready)..."
        sleep 3
    done
    
    ok "PostgreSQL готов принимать подключения"
    
    # Проверить что кластер на правильном порту (5432)
    local cluster_port=$(sudo -u postgres psql -tAc "SHOW port" 2>/dev/null | tr -d ' ')
    if [ "$cluster_port" != "5432" ]; then
        log_warn "⚠️  Кластер запущен на порту $cluster_port вместо 5432"
        log_info "Это нормально, продолжаем..."
    else
        ok "Кластер работает на порту 5432"
    fi
    
    # Проверить результат
    local new_locale=$(sudo -u postgres psql -tAc "SELECT datcollate FROM pg_database WHERE datname='template1'" 2>/dev/null | tr -d ' ')
    
    if [[ "$new_locale" == "ru_RU."* ]]; then
        ok "✅ Кластер успешно реинициализирован с локалью: $new_locale"
        return 0
    else
        log_error "❌ Не удалось реинициализировать кластер с ru_RU.UTF-8"
        log_error "   Текущая локаль: ${new_locale:-пусто}"
        log_error "   Проверьте: sudo -u postgres psql -l"
        return 1
    fi
}

# Проверка существования пользователя PostgreSQL
postgres_user_exists() {
    local username="$1"
    
    # Проверить через pg_roles (безопасно, не требует подключения от этого пользователя)
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${username}'" 2>/dev/null | grep -q 1; then
        return 0  # Пользователь существует
    else
        return 1  # Пользователь не существует
    fi
}

# Проверка существования базы данных
database_exists() {
    local dbname="$1"
    
    # Проверить через pg_database
    if sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$dbname"; then
        return 0  # База существует
    else
        return 1  # База не существует
    fi
}

# Проверка и установка локали для PostgreSQL
ensure_postgresql_locale() {
    # ВАЖНО: Функция НЕ выводит логи! Только результат.
    
    # Проверить системную локаль
    if ! locale -a 2>/dev/null | grep -q "ru_RU.utf8\|ru_RU.UTF-8"; then
        # Установить language-pack-ru (как в legacy)
        if apt-cache show language-pack-ru &>/dev/null 2>&1; then
            apt-get install -y language-pack-ru &>/dev/null 2>&1 || true
        fi
        
        # Установить локаль через locale-gen
        if command_exists locale-gen; then
            locale-gen ru_RU.UTF-8 &>/dev/null 2>&1 || true
        else
            # Для систем без locale-gen
            echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen 2>/dev/null || true
            if command_exists localedef; then
                localedef -i ru_RU -f UTF-8 ru_RU.UTF-8 &>/dev/null 2>&1 || true
            fi
        fi
        
        # Обновить локали
        if command_exists update-locale; then
            update-locale &>/dev/null 2>&1 || true
        fi
        
        # Дополнительная проверка после установки
        if ! locale -a 2>/dev/null | grep -q "ru_RU.utf8\|ru_RU.UTF-8"; then
            # Если локаль все еще недоступна, попробовать альтернативные методы
            if command_exists dpkg-reconfigure; then
                dpkg-reconfigure locales &>/dev/null 2>&1 || true
            fi
        fi
    fi
    
    # Проверить локаль кластера PostgreSQL
    local cluster_locale=$(sudo -u postgres psql -tAc "SELECT datcollate FROM pg_database WHERE datname='template1'" 2>/dev/null | tr -d ' ')
    
    # Если кластер с русской локалью - идеально!
    if [[ "$cluster_locale" == "ru_RU.utf8" ]] || [[ "$cluster_locale" == "ru_RU.UTF-8" ]]; then
        echo "$cluster_locale"
        return
    fi
    
    # Определить доступную русскую локаль в системе
    if locale -a 2>/dev/null | grep -q "^ru_RU.utf8$"; then
        echo "ru_RU.utf8"
    elif locale -a 2>/dev/null | grep -q "^ru_RU.UTF-8$"; then
        echo "ru_RU.UTF-8"
    else
        # Если русской нет - вернуть локаль кластера
        echo "${cluster_locale:-C}"
    fi
}

# Настройка PostgreSQL
configure_postgresql() {
    log_info "Настройка PostgreSQL..."
    
    # КРИТИЧНО: Установить русскую локаль ПЕРЕД всеми операциями PostgreSQL
    log_info "Проверка и установка русской локали..."
    
    # Проверить, нужна ли установка ru_RU.UTF-8 в системе
    if ! locale -a 2>/dev/null | grep -q "ru_RU.utf8\|ru_RU.UTF-8"; then
        log_warn "Локаль ru_RU.UTF-8 не установлена в системе, устанавливаем..."
        
        # Установить language-pack-ru (как в legacy)
        if apt-cache show language-pack-ru &>/dev/null 2>&1; then
            log_info "Установка language-pack-ru..."
            if [ -n "${LOG_FILE:-}" ]; then
                apt-get install -y language-pack-ru 2>&1 | tee -a "$LOG_FILE" | grep -v "^Get:\|^Fetched" | head -20
            else
                apt-get install -y language-pack-ru 2>&1 | grep -v "^Get:\|^Fetched" | head -20
            fi
        fi
        
        # Генерация локали
        if command_exists locale-gen; then
            log_info "Генерация локали ru_RU.UTF-8..."
            if [ -n "${LOG_FILE:-}" ]; then
                locale-gen ru_RU.UTF-8 2>&1 | tee -a "$LOG_FILE" | tail -3
            else
                locale-gen ru_RU.UTF-8 2>&1 | tail -3
            fi
        fi
        
        # Дополнительная проверка после установки
        if ! locale -a 2>/dev/null | grep -q "ru_RU.utf8\|ru_RU.UTF-8"; then
            log_warn "Локаль все еще недоступна, пробуем альтернативные методы..."
            
            # Попробовать dpkg-reconfigure locales
            if command_exists dpkg-reconfigure; then
                log_info "Переконфигурация локалей через dpkg-reconfigure..."
                if [ -n "${LOG_FILE:-}" ]; then
                    dpkg-reconfigure locales 2>&1 | tee -a "$LOG_FILE" | tail -5
                else
                    dpkg-reconfigure locales 2>&1 | tail -5
                fi
            fi
            
            # Финальная проверка
            if ! locale -a 2>/dev/null | grep -q "ru_RU.utf8\|ru_RU.UTF-8"; then
                log_error "❌ Не удалось установить локаль ru_RU.UTF-8!"
                log_error "   Доступные локали:"
                locale -a 2>/dev/null | grep -E "(ru|RU)" | head -5 || log_error "   Русские локали не найдены"
                log_error ""
                log_error "🔧 РЕШЕНИЕ:"
                log_error "   1. Установите локаль вручную:"
                log_error "      sudo apt-get install language-pack-ru"
                log_error "      sudo locale-gen ru_RU.UTF-8"
                log_error "   2. Или используйте существующую локаль"
                log_error ""
                return 1
            fi
        fi
        
        ok "Локаль ru_RU.UTF-8 установлена в системе"
    else
        ok "Локаль ru_RU.UTF-8 доступна в системе"
    fi
    
    # КРИТИЧНО: Убедиться что PostgreSQL запущен и готов!
    log_info "Проверка статуса PostgreSQL..."
    
    # Сначала проверить через pg_isready (более точная проверка)
    if ! sudo -u postgres pg_isready -q 2>/dev/null; then
        log_warn "PostgreSQL не готов, запускаем..."
        
        local os_type=$(get_os_type)
        local pg_version="16"
        local start_success=false
        
        # Определить метод запуска в зависимости от ОС
        if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
            # Ubuntu/Debian: использовать pg_ctlcluster (это ЕДИНСТВЕННЫЙ правильный способ!)
            log_info "Запуск кластера через pg_ctlcluster..."
            
            # Проверить что кластер существует
            if pg_lsclusters -h 2>/dev/null | grep -q "^${pg_version}.*main"; then
                log_info "Кластер ${pg_version}/main найден, запускаем..."
                
                # Запустить кластер
                if pg_ctlcluster ${pg_version} main start 2>&1 | tee /tmp/pg_start.log; then
                    start_success=true
                    log_info "Кластер запущен через pg_ctlcluster"
                else
                    log_error "Ошибка запуска кластера через pg_ctlcluster:"
                    cat /tmp/pg_start.log || true
                fi
            else
                log_warn "Кластер ${pg_version}/main НЕ НАЙДЕН!"
                log_info "Доступные кластеры:"
                pg_lsclusters 2>/dev/null || echo "(пусто)"
                log_info ""
                log_info "Создание кластера ${pg_version}/main..."
                
                # Создать кластер с локалью по умолчанию (будет реинициализирован позже если нужно)
                if pg_createcluster ${pg_version} main 2>&1 | tee /tmp/pg_create.log | tail -10; then
                    log_info "Кластер ${pg_version}/main создан успешно"
                    
                    # Проверить что кластер появился в списке
                    if pg_lsclusters -h 2>/dev/null | grep -q "^${pg_version}.*main"; then
                        # Попробовать запустить
                        if pg_ctlcluster ${pg_version} main start 2>&1 | tail -10; then
                            start_success=true
                            log_info "Кластер запущен успешно"
                        else
                            log_error "Не удалось запустить созданный кластер"
                        fi
                    else
                        log_error "Кластер создан, но не найден в pg_lsclusters"
                    fi
                else
                    log_error "Не удалось создать кластер ${pg_version}/main:"
                    cat /tmp/pg_create.log || true
                    return 1
                fi
            fi
        else
            # AlmaLinux: использовать systemctl
            log_info "Запуск PostgreSQL через systemctl (AlmaLinux)..."
            if systemctl start postgresql-${pg_version} 2>&1; then
                start_success=true
            fi
        fi
        
        # Проверить что запуск удался
        if [ "$start_success" = false ]; then
            log_error "Не удалось запустить PostgreSQL!"
            log_error ""
            log_error "Диагностика:"
            log_error "  Кластеры PostgreSQL:"
            pg_lsclusters 2>/dev/null || echo "pg_lsclusters недоступен"
            log_error ""
            log_error "  Статус сервиса:"
            systemctl status postgresql 2>&1 | head -15 || true
            log_error ""
            log_error "  Процессы:"
            ps aux | grep postgres | head -10 || true
            return 1
        fi
        
        log_info "Ожидание готовности PostgreSQL (до 60 секунд)..."
        
        # Ждём готовности с таймаутом
        local retries=0
        local max_retries=20  # 60 секунд
        while ! sudo -u postgres pg_isready -q 2>/dev/null; do
            ((retries++))
            if [ $retries -ge $max_retries ]; then
                log_error "PostgreSQL не готов после 60 секунд ожидания"
                log_error ""
                log_error "Диагностика:"
                log_error "  Кластеры PostgreSQL:"
                pg_lsclusters 2>/dev/null || echo "pg_lsclusters недоступен"
                log_error ""
                log_error "  Статус сервиса:"
                systemctl status postgresql 2>&1 | head -15 || true
                log_error ""
                log_error "  Лог PostgreSQL (последние 30 строк):"
                tail -30 /var/log/postgresql/postgresql-16-main.log 2>/dev/null || \
                journalctl -u postgresql@16-main -n 30 --no-pager 2>/dev/null || \
                echo "Логи недоступны"
                log_error ""
                log_error "  Процессы postgres:"
                ps aux | grep postgres | head -10 || true
                log_error ""
                log_error "Попробуйте запустить вручную:"
                log_error "  sudo pg_ctlcluster ${pg_version} main start"
                log_error "  sudo tail -50 /var/log/postgresql/postgresql-16-main.log"
                return 1
            fi
            
            log_info "  Попытка $retries/$max_retries..."
            sleep 3
        done
    fi
    
    ok "PostgreSQL готов принимать подключения"
    
    # Проверить подключение к PostgreSQL (с ретраями)
    log_info "Проверка подключения к PostgreSQL..."
    local max_attempts=10
    local attempt=1
    local connected=false
    
    while [ $attempt -le $max_attempts ]; do
        if sudo -u postgres psql -c "SELECT 1" &>/dev/null; then
            connected=true
            break
        fi
        
        log_debug "  Попытка $attempt/$max_attempts..."
        sleep 2
        ((attempt++))
    done
    
    if [ "$connected" = false ]; then
        log_error "Не удается подключиться к PostgreSQL после $max_attempts попыток"
        log_error ""
        log_error "Диагностика:"
        log_error "  1. Проверьте статус: systemctl status postgresql"
        log_error "  2. Проверьте логи: tail -50 /var/log/postgresql/postgresql-16-main.log"
        log_error "  3. Проверьте сокет: ls -la /var/run/postgresql/"
        log_error "  4. Проверьте процессы: ps aux | grep postgres"
        log_error ""
        return 1
    fi
    
    ok "Подключение к PostgreSQL работает"
    
    # КРИТИЧНО: ДО создания пользователя проверить и реинициализировать кластер!
    log_info "Проверка локали PostgreSQL кластера..."
    
    # Проверить локаль кластера template1
    local cluster_locale=$(sudo -u postgres psql -tAc "SELECT datcollate FROM pg_database WHERE datname='template1'" 2>/dev/null | tr -d ' ')
    log_info "Кластер PostgreSQL использует локаль: $cluster_locale"
    
    # Если кластер НЕ с русской локалью - РЕИНИЦИАЛИЗИРОВАТЬ!
    if [[ "$cluster_locale" != "ru_RU.utf8" ]] && [[ "$cluster_locale" != "ru_RU.UTF-8" ]]; then
        log_warn "🔴 КРИТИЧНО: Кластер PostgreSQL НЕ с русской локалью!"
        log_warn "   Для WorkerNet требуется ru_RU.UTF-8"
        log_warn ""
        
        # Автоматическая реинициализация
        reinit_postgresql_cluster || {
            log_error "Не удалось реинициализировать кластер"
            return 1
        }
    else
        ok "✅ Кластер PostgreSQL с русской локалью: $cluster_locale"
    fi
    
    # Получить финальную локаль (после возможной реинициализации)
    local db_locale=$(ensure_postgresql_locale)
    log_info "Финальная локаль для БД: $db_locale"
    
    # Генерация пароля для БД
    if [ -z "$GENPASSDB" ]; then
        # Попытка загрузить из файла (при переустановке)
        load_credentials 2>/dev/null || true
        
        if [ -n "${DATABASE_PASSWORD:-}" ]; then
            GENPASSDB="$DATABASE_PASSWORD"
            log_info "Использование пароля БД из предыдущей установки"
        else
            GENPASSDB=$(generate_password 13)
            log_debug "Сгенерирован новый пароль базы данных"
            
            # Сохранить в файл учётных данных
            save_credentials "DATABASE_PASSWORD" "$GENPASSDB"
        fi
    fi
    
    local dbpass="'$GENPASSDB'"
    
    # Создать роль (пользователя) - ПОСЛЕ реинициализации кластера!
    log_info "Проверка существования пользователя PostgreSQL: $DB_USER..."
    
    # Проверить существование через pg_roles
    local user_check=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" 2>&1)
    log_debug "  Результат проверки: '$user_check'"
    
    if echo "$user_check" | grep -q "1"; then
        log_warn "⚠️  Пользователь PostgreSQL $DB_USER уже существует"
        log_info "   Обновляем пароль на новый..."
        
        # Обновить пароль существующего пользователя
        run_cmd "sudo -u postgres psql -c \"ALTER ROLE $DB_USER PASSWORD $dbpass;\""
        
        ok "Пароль пользователя $DB_USER обновлен"
    else
        log_info "Создание пользователя PostgreSQL: $DB_USER"
        
        # Создать роль с LOGIN и PASSWORD
        run_cmd "sudo -u postgres psql -c \"CREATE ROLE $DB_USER WITH LOGIN PASSWORD $dbpass;\""
        
        CREATED_USERS+=("postgres:$DB_USER")
        ok "Пользователь $DB_USER создан"
    fi
    
    # Создать базу данных
    if ! database_exists "$DB_NAME"; then
        log_info "Создание базы данных: $DB_NAME (локаль: $db_locale)"
        
        # Создать БД с правильной локалью
        if [ -n "$db_locale" ] && [ "$db_locale" != "C" ]; then
            run_cmd "sudo -u postgres createdb -e -E \"UTF-8\" -l \"$db_locale\" -O $DB_USER -T template0 $DB_NAME"
        else
            # Fallback: создать без явной локали
            log_warn "Создание БД без явной локали (будет использована локаль по умолчанию)"
            run_cmd "sudo -u postgres createdb -e -E \"UTF-8\" -O $DB_USER -T template0 $DB_NAME"
        fi
        
        CREATED_DATABASES+=("$DB_NAME")
    else
        ok "База данных $DB_NAME уже существует"
    fi
    
    # Установить расширение PostGIS
    local has_postgis=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT 1 FROM pg_extension WHERE extname='postgis'")
    
    if [ "$has_postgis" != "1" ]; then
        log_info "Установка расширения PostGIS"
        run_cmd "sudo -u postgres psql -d $DB_NAME -c \"CREATE EXTENSION postgis;\""
    else
        ok "Расширение PostGIS уже установлено"
    fi
    
    ok "PostgreSQL настроен успешно"
}

# Проверка PostgreSQL
verify_postgresql() {
    log_info "Проверка установки PostgreSQL..."
    
    # Проверка что PostgreSQL готов принимать подключения
    log_info "Проверка готовности PostgreSQL..."
    
    if ! sudo -u postgres pg_isready -q 2>/dev/null; then
        log_error "PostgreSQL не готов принимать подключения"
        log_error ""
        log_error "Диагностика:"
        log_error "  pg_isready:"
        sudo -u postgres pg_isready 2>&1 || true
        log_error ""
        log_error "  systemctl status:"
        systemctl status postgresql 2>&1 | head -10 || systemctl status postgresql-16 2>&1 | head -10 || true
        return 1
    fi
    ok "PostgreSQL готов принимать подключения"
    
    # Проверка подключения
    if ! sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1" &> /dev/null; then
        log_error "Не удается подключиться к базе данных $DB_NAME"
        return 1
    fi
    ok "База данных $DB_NAME доступна"
    
    # Проверка PostGIS
    local postgis_version=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT PostGIS_Version()" 2>/dev/null)
    if [ -n "$postgis_version" ]; then
        ok "PostGIS установлен: $postgis_version"
    else
        log_error "PostGIS недоступен в базе данных"
        return 1
    fi
    
    log_info "Параметры подключения к БД:"
    log_info "  Имя базы данных: $DB_NAME"
    log_info "  Пользователь: $DB_USER"
    log_info "  Пароль: $GENPASSDB"
    
    return 0
}

# Главная функция установки PostgreSQL
setup_database() {
    # При переустановке: остановить PostgreSQL если запущен
    if systemctl is-active --quiet postgresql 2>/dev/null || systemctl is-active --quiet postgresql-16 2>/dev/null; then
        log_info "Обнаружен запущенный PostgreSQL (переустановка)"
        log_info "Остановка PostgreSQL перед переустановкой..."
        
        # Остановить через systemctl
        systemctl stop postgresql 2>/dev/null || systemctl stop postgresql-16 2>/dev/null || true
        sleep 3
        
        # Убить процессы если ещё живы
        pkill -9 -u postgres 2>/dev/null || true
        pkill -9 postgres 2>/dev/null || true
        sleep 2
        
        # Проверить что все процессы PostgreSQL убиты
        local retries=0
        while pgrep -u postgres >/dev/null 2>&1 || pgrep postgres >/dev/null 2>&1; do
            ((retries++))
            if [ $retries -ge 10 ]; then
                log_warn "Не удалось остановить все процессы PostgreSQL за 10 попыток"
                break
            fi
            log_debug "Ожидание завершения процессов PostgreSQL (попытка $retries/10)..."
            sleep 1
        done
        
        # Удалить файлы блокировки
        rm -f /var/lib/postgresql/16/main/postmaster.pid 2>/dev/null || true
        rm -f /var/lib/postgresql/*/main/postmaster.pid 2>/dev/null || true
        rm -f /var/run/postgresql/.s.PGSQL.* 2>/dev/null || true
        rm -f /var/run/postgresql/*.pid 2>/dev/null || true
        rm -f /tmp/.s.PGSQL.* 2>/dev/null || true
        
        ok "PostgreSQL остановлен и очищен для переустановки"
    fi
    
    install_postgresql || return 1
    configure_postgresql || return 1
    verify_postgresql || return 1
    
    return 0
}

# Экспортировать функции
export -f postgres_user_exists
export -f database_exists
export -f install_postgresql
export -f install_postgresql_debian
export -f install_postgresql_almalinux
export -f reinit_postgresql_cluster
export -f ensure_postgresql_locale
export -f configure_postgresql
export -f verify_postgresql
export -f setup_database

