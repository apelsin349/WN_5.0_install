#!/bin/bash
# postinstall.sh - Post-install конфигурация WorkerNet
# WorkerNet Installer v5.0

# Установка зависимостей poller
setup_poller_dependencies() {
    log_info "Установка зависимостей Python для poller..."
    
    local poller_dir="${INSTALL_DIR}/microservice/poller"
    
    # Проверить существование директории
    if [ ! -d "$poller_dir" ]; then
        log_warn "Директория poller не найдена: $poller_dir"
        log_info "Пропускаем установку зависимостей poller (будет установлено при post-install)"
        return 0
    fi
    
    cd "$poller_dir"
    
    # Создать venv
    log_info "Создание Python virtual environment..."
    if sudo -H python3 -m venv venv 2>&1 | tail -5; then
        ok "Virtual environment создан"
    else
        log_error "Не удалось создать venv"
        return 1
    fi
    
    # Обновить pip
    log_info "Обновление pip, wheel, setuptools (до 3 минут)..."
    if timeout 180 sudo -H ./venv/bin/pip install -U pip wheel setuptools 2>&1 | tee -a "${LOG_FILE:-/dev/null}" | tail -10; then
        ok "pip обновлен"
    else
        log_warn "Не удалось обновить pip (продолжаем с системной версией)"
    fi
    
    # Установить зависимости
    if [ -f "requirements.txt" ]; then
        log_info "Установка зависимостей из requirements.txt (до 5 минут)..."
        log_info "Это может занять время при первой установке..."
        
        if timeout 300 sudo -H ./venv/bin/pip install -U -r requirements.txt 2>&1 | tee -a "${LOG_FILE:-/dev/null}" | tail -30; then
            ok "Зависимости poller установлены"
        else
            log_error "Не удалось установить зависимости (таймаут 5 минут)"
            log_error "Попробуйте установить вручную:"
            log_error "  cd ${INSTALL_DIR}/microservice/poller"
            log_error "  sudo -H ./venv/bin/pip install -U -r requirements.txt"
            return 1
        fi
    else
        log_warn "requirements.txt не найден"
    fi
    
    cd "$INSTALL_DIR"
    return 0
}

# Настройка конфигураций Supervisor
setup_supervisor_configs() {
    log_info "Настройка конфигураций Supervisor..."
    
    local prefix=$(get_module_prefix)
    local version_num="${WORKERNET_VERSION//./}"  # 4.10 → 410
    
    # Определить имена конфигов в зависимости от версии
    local core_worker_conf=""
    local poller_conf=""
    
    case "$WORKERNET_VERSION" in
        "3.x")
            core_worker_conf="us-core-worker.conf-example"
            poller_conf="usm_poller.conf-example"
            ;;
        "4.x"|"5.x")
            core_worker_conf="core-worker.conf-example"
            poller_conf="poller.conf-example"
            ;;
    esac
    
    # Копировать core-worker конфиг
    if [ -f "${INSTALL_DIR}/etc/${core_worker_conf}" ]; then
        log_info "Копирование ${core_worker_conf}..."
        local target_name=$(basename "$core_worker_conf" -example)
        sudo cp "${INSTALL_DIR}/etc/${core_worker_conf}" "/etc/supervisor/conf.d/${target_name}"
        ok "Конфигурация core-worker скопирована"
    else
        log_warn "Конфигурация core-worker не найдена: ${core_worker_conf}"
    fi
    
    # Копировать poller конфиг
    if [ -f "${INSTALL_DIR}/microservice/poller/etc/${poller_conf}" ]; then
        log_info "Копирование ${poller_conf}..."
        local target_name=$(basename "$poller_conf" -example)
        sudo cp "${INSTALL_DIR}/microservice/poller/etc/${poller_conf}" "/etc/supervisor/conf.d/${target_name}"
        ok "Конфигурация poller скопирована"
    else
        log_warn "Конфигурация poller не найдена: ${poller_conf}"
    fi
    
    return 0
}

# Настройка crontab
setup_crontab() {
    log_info "Настройка crontab..."
    
    if [ -f "${INSTALL_DIR}/etc/crontab-example" ]; then
        log_info "Копирование crontab-example..."
        sudo cp "${INSTALL_DIR}/etc/crontab-example" /etc/cron.d/workernet
        
        # Установить права
        sudo chmod 644 /etc/cron.d/workernet
        
        ok "Crontab настроен"
    else
        log_warn "crontab-example не найден"
        log_info "Пропускаем настройку crontab (будет настроено вручную)"
    fi
    
    return 0
}

# Настройка logrotate
setup_logrotate() {
    log_info "Настройка logrotate..."
    
    local prefix=$(get_module_prefix)
    
    # Копировать logrotate для основного приложения
    if [ -f "${INSTALL_DIR}/etc/logrotate-example" ]; then
        log_info "Копирование logrotate для WorkerNet..."
        sudo cp "${INSTALL_DIR}/etc/logrotate-example" /etc/logrotate.d/workernet
        sudo chmod 644 /etc/logrotate.d/workernet
        ok "Logrotate для WorkerNet настроен"
    else
        log_warn "logrotate-example не найден"
    fi
    
    # Копировать logrotate для poller
    if [ -f "${INSTALL_DIR}/microservice/poller/etc/logrotate-example" ]; then
        log_info "Копирование logrotate для poller..."
        sudo cp "${INSTALL_DIR}/microservice/poller/etc/logrotate-example" /etc/logrotate.d/poller
        sudo chmod 644 /etc/logrotate.d/poller
        ok "Logrotate для poller настроен"
    else
        log_warn "logrotate для poller не найден"
    fi
    
    return 0
}

# Обновление реквизитов в базе данных
update_database_credentials() {
    log_info "Автоматическое заполнение реквизитов в БД..."
    
    # Загрузить учётные данные из файла
    load_credentials || log_warn "Файл учётных данных не найден, используем переменные окружения"
    
    local db_name="${DATABASE_NAME:-workernet}"
    local db_user="${DATABASE_USER:-root}"
    
    # Проверить что база существует
    if ! sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$db_name"; then
        log_warn "База данных $db_name не найдена, пропускаем обновление реквизитов"
        return 0
    fi
    
    # Проверить что таблица erp.settings существует
    # Ждём до 30 секунд (миграции могли только что завершиться)
    log_info "Ожидание завершения миграций БД..."
    local retries=0
    local max_retries=6  # 6 × 5 сек = 30 секунд
    local table_found=false
    
    while [ $retries -lt $max_retries ]; do
        # Проверка существования таблицы
        local check_result=$(sudo -u postgres psql -d "$db_name" -tAc "SELECT to_regclass('erp.settings');" 2>&1)
        
        if echo "$check_result" | grep -q "settings"; then
            table_found=true
            break
        fi
        
        ((retries++))
        if [ $retries -lt $max_retries ]; then
            log_info "  Попытка $retries/$max_retries: таблица erp.settings ещё не создана, ждём..."
            sleep 5
        fi
    done
    
    if [ "$table_found" = false ]; then
        log_warn "Таблица erp.settings не найдена после $((max_retries * 5)) секунд"
        log_info ""
        log_info "Диагностика:"
        
        # Показать список существующих таблиц в схеме erp
        log_info "  Существующие таблицы в схеме 'erp':"
        sudo -u postgres psql -d "$db_name" -tAc "SELECT tablename FROM pg_tables WHERE schemaname = 'erp' ORDER BY tablename LIMIT 10;" 2>&1 | while read -r line; do
            [ -n "$line" ] && log_info "    - $line"
        done
        
        # Проверить что миграции прошли
        local migration_count=$(sudo -u postgres psql -d "$db_name" -tAc "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'erp';" 2>/dev/null || echo "0")
        log_info "  Всего таблиц в схеме 'erp': $migration_count"
        
        log_warn ""
        log_warn "Таблица erp.settings будет создана при первом запуске WorkerNet"
        log_warn "После первого запуска выполните:"
        log_warn "  cd $(dirname "$SCRIPT_DIR")"
        log_warn "  sudo ./update_credentials.sh workernet-stomp [пароль]"
        log_info ""
        return 0
    fi
    
    ok "Таблица erp.settings найдена"
    
    log_info "Обновление настроек в таблице erp.settings..."
    
    # Подготовить SQL команды
    local sql_updates=""
    
    # 1. Обновить WebSocket настройки (RabbitMQ STOMP)
    # Приоритет: загруженные из файла > переменные окружения
    local webstomp_user="${RABBITMQ_WEBSTOMP_USER:-${WEBSTOMPUSER:-}}"
    local webstomp_pass="${RABBITMQ_WEBSTOMP_PASSWORD:-${GENPASSWEBSTOMPUSER:-}}"
    
    if [ -n "$webstomp_user" ] && [ -n "$webstomp_pass" ]; then
        log_info "  - WebSocket пользователь: ${webstomp_user}"
        log_info "  - WebSocket пароль: ${webstomp_pass:0:4}... (скрыт)"
        
        sql_updates+="
-- WebSocket пользователь (UPDATE существующей записи)
UPDATE erp.settings 
SET option_value = '${webstomp_user}' 
WHERE option_name = 'WEB_SOCKET_USER';

-- WebSocket пароль
UPDATE erp.settings 
SET option_value = '${webstomp_pass}' 
WHERE option_name = 'WEB_SOCKET_PASSWORD';

-- Включить WebSocket (если запись существует)
UPDATE erp.settings 
SET option_value = '1' 
WHERE option_name = 'IS_WEB_SOCKET_ENABLE';

-- Проверка результата
SELECT option_name, option_value 
FROM erp.settings 
WHERE option_name LIKE 'WEB_SOCKET%' 
ORDER BY option_name;
"
    else
        log_warn "WebSocket учётные данные не найдены (пропускаем обновление)"
    fi
    
    # 2. Обновить RabbitMQ настройки (если нужны другие пользователи)
    # TODO: Добавить RABBITMQ_ADMIN_USER, RABBITMQ_ADMIN_PASSWORD если требуется
    
    # Выполнить SQL обновления
    if [ -n "$sql_updates" ]; then
        log_debug "SQL для обновления настроек:"
        log_debug "$sql_updates"
        
        local sql_output=$(sudo -u postgres psql -d "$db_name" -c "$sql_updates" 2>&1)
        local sql_result=$?
        
        if [ $sql_result -eq 0 ]; then
            ok "Реквизиты обновлены в базе данных"
            log_debug "Результат SQL: $sql_output"
        else
            log_warn "Не удалось обновить реквизиты в БД"
            log_error "SQL ошибка: $sql_output"
            log_info ""
            log_info "Попробуйте обновить вручную после установки:"
            log_info "  cd $(dirname "${SCRIPT_DIR:-/tmp}")"
            log_info "  sudo ./update_credentials.sh workernet-stomp [пароль]"
            log_info ""
        fi
    else
        log_info "Нет реквизитов для обновления"
    fi
    
    return 0
}

# Перезапуск Supervisor
restart_supervisor() {
    log_info "Перезапуск Supervisor..."
    
    if systemctl restart supervisor 2>&1 | tail -5; then
        ok "Supervisor перезапущен"
        sleep 3
        
        # Показать статус workers
        log_info "Статус Supervisor workers:"
        if supervisorctl status 2>/dev/null; then
            ok "Supervisor workers запущены"
        else
            log_warn "Не удалось получить статус workers"
        fi
    else
        log_error "Не удалось перезапустить Supervisor"
        return 1
    fi
    
    return 0
}

# Главная функция post-install
setup_postinstall() {
    log_section "⚙️ POST-INSTALL КОНФИГУРАЦИЯ"
    
    show_progress "Post-install configuration"
    
    # 1. Установка зависимостей poller
    setup_poller_dependencies || log_warn "Зависимости poller не установлены (выполните вручную)"
    
    # 2. Настройка Supervisor
    setup_supervisor_configs || log_warn "Supervisor конфиги не скопированы"
    
    # 3. Настройка crontab
    setup_crontab || log_warn "Crontab не настроен"
    
    # 4. Настройка logrotate
    setup_logrotate || log_warn "Logrotate не настроен"
    
    # 5. Очистка Redis кэша ПЕРЕД обновлением настроек
    log_info "Очистка Redis кэша перед обновлением настроек..."
    # КРИТИЧНО: Использовать пароль Redis если установлен
    if [ -n "${GENPASSREDIS:-}" ]; then
        redis-cli -a "$GENPASSREDIS" FLUSHALL 2>&1 | grep -v "Warning:" || log_warn "Не удалось очистить Redis кэш"
    else
        redis-cli FLUSHALL >/dev/null 2>&1 || log_warn "Не удалось очистить Redis кэш"
    fi
    ok "Redis кэш очищен"
    
    # 6. Обновление реквизитов в базе данных (ДО запуска workers!)
    # КРИТИЧНО: Обновить БД ПЕРЕД запуском workers, иначе они создадут дефолтные настройки!
    update_database_credentials || log_warn "Реквизиты не обновлены в БД"
    
    # 7. Перезапуск PHP-FPM для сброса opcache (ДО запуска workers!)
    log_info "Перезапуск PHP-FPM для сброса opcache..."
    systemctl restart php8.3-fpm 2>/dev/null || log_warn "PHP-FPM не перезапущен"
    sleep 2
    
    # 8. Перезапуск Supervisor (ПОСЛЕ обновления БД и сброса PHP кэша!)
    # Workers загрузят НОВЫЕ настройки из БД
    restart_supervisor || log_warn "Supervisor не перезапущен"
    
    ok "Post-install конфигурация завершена"
    
    return 0
}

# Экспортировать функции
export -f setup_poller_dependencies
export -f setup_supervisor_configs
export -f setup_crontab
export -f setup_logrotate
export -f update_database_credentials
export -f restart_supervisor
export -f setup_postinstall

