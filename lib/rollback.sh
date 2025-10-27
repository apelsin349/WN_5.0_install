#!/bin/bash
# rollback.sh - Механизм отката установки
# WorkerNet Installer v5.0

ROLLBACK_ENABLED=true
ROLLBACK_REMOVE_PACKAGES="${ROLLBACK_REMOVE_PACKAGES:-no}"

# Функция отката
perform_rollback() {
    local exit_code=${1:-$?}
    
    # Если установка успешна, не откатывать
    if [ $exit_code -eq 0 ]; then
        return 0
    fi
    
    if [ "$ROLLBACK_ENABLED" != "true" ]; then
        log_warn "Откат отключен, пропуск очистки"
        return 0
    fi
    
    echo ""
    log_error "════════════════════════════════════════════════════════════"
    log_error "  УСТАНОВКА НЕ УДАЛАСЬ (exit code: $exit_code)"
    log_error "════════════════════════════════════════════════════════════"
    echo ""
    log_info "🔄 Запуск процедуры отката..."
    echo ""
    
    # 0. Остановить ВСЕ потенциальные сервисы WorkerNet (в том числе "призраков")
    rollback_cleanup_services
    
    # 1. Остановить сервисы, которые были запущены этой установкой
    rollback_services
    
    # 2. Удалить базы данных
    rollback_databases
    
    # 3. Удалить пользователей
    rollback_users
    
    # 4. Удалить файлы
    rollback_files
    
    # 5. Удалить директории
    rollback_directories
    
    # 6. Удалить пакеты (опционально)
    if [ "$ROLLBACK_REMOVE_PACKAGES" = "yes" ]; then
        rollback_packages
    else
        log_info "Skipping package removal (set ROLLBACK_REMOVE_PACKAGES=yes to enable)"
    fi
    
    # 7. Удалить lock-файл
    rm -f "$LOCK_FILE"
    rm -f "$STATE_FILE"
    
    echo ""
    ok "✅ Откат завершен"
    echo ""
    log_error "Система восстановлена в исходное состояние"
    log_error ""
    log_error "Для отладки проблемы:"
    log_error "  1. Проверьте логи: $INSTALL_LOG"
    log_error "  2. Исправьте проблему"
    log_error "  3. Запустите установку снова"
    echo ""
    
    # Включить обратно unattended-upgrades (если был остановлен)
    if command -v re_enable_unattended_upgrades &>/dev/null; then
        re_enable_unattended_upgrades
    fi
    
    exit $exit_code
}

# Откат: остановка ВСЕХ потенциальных сервисов WorkerNet (очистка "призраков")
rollback_cleanup_services() {
    log_info "Очистка зависших сервисов от предыдущих установок..."
    
    local services_to_cleanup=("postgresql" "redis-server" "rabbitmq-server" "apache2" "nginx" "supervisor")
    local stopped_count=0
    local errors=0
    
    for service in "${services_to_cleanup[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${service}.service"; then
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                log_debug "  Остановка $service (возможно от предыдущей установки)..."
                if systemctl stop "$service" 2>/dev/null; then
                    ((stopped_count++))
                else
                    log_warn "    Не удалось остановить $service"
                    ((errors++))
                fi
                
                # Попытка убить процесс принудительно, если stop не сработал
                if systemctl is-active --quiet "$service" 2>/dev/null; then
                    log_debug "    Принудительное завершение $service..."
                    systemctl kill --signal=SIGKILL "$service" 2>/dev/null || true
                    sleep 1
                fi
            fi
            
            # Отключить автозапуск, если был включен
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                log_debug "  Отключение автозапуска $service..."
                systemctl disable "$service" 2>/dev/null || true
            fi
        fi
    done
    
    # Дополнительная очистка портов через fuser (если доступен)
    if command_exists fuser; then
        log_debug "  Принудительная очистка портов..."
        for port in 5432 6379 5672 15672 80 443; do
            fuser -k ${port}/tcp 2>/dev/null || true
        done
    fi
    
    if [ $stopped_count -gt 0 ]; then
        ok "Очищено зависших сервисов: $stopped_count"
        if [ $errors -gt 0 ]; then
            log_warn "  Ошибок при остановке: $errors (некритично)"
        fi
    else
        log_debug "Зависших сервисов не обнаружено"
    fi
    
    # Подождать освобождения портов
    sleep 2
}

# Откат: остановка сервисов, запущенных текущей установкой
rollback_services() {
    if [ ${#STARTED_SERVICES[@]} -eq 0 ]; then
        return 0
    fi
    
    log_info "Остановка сервисов, запущенных этой установкой..."
    
    for service in "${STARTED_SERVICES[@]}"; do
        if systemctl is-active "$service" &> /dev/null; then
            log_debug "  Stopping $service..."
            systemctl stop "$service" 2>/dev/null || true
        fi
    done
    
    ok "Сервисы остановлены"
}

# Откат: удаление баз данных
rollback_databases() {
    if [ ${#CREATED_DATABASES[@]} -eq 0 ]; then
        return 0
    fi
    
    log_info "Удаление баз данных..."
    
    for db in "${CREATED_DATABASES[@]}"; do
        if database_exists "$db"; then
            log_debug "  Dropping database: $db"
            sudo -u postgres dropdb "$db" 2>/dev/null || true
        fi
    done
    
    ok "Базы данных удалены"
}

# Откат: удаление пользователей
rollback_users() {
    if [ ${#CREATED_USERS[@]} -eq 0 ]; then
        return 0
    fi
    
    log_info "Удаление пользователей..."
    
    for user in "${CREATED_USERS[@]}"; do
        # PostgreSQL пользователи
        if postgres_user_exists "$user"; then
            log_debug "  Dropping PostgreSQL user: $user"
            sudo -u postgres psql -c "DROP ROLE IF EXISTS $user;" 2>/dev/null || true
        fi
        
        # RabbitMQ пользователи
        if command_exists rabbitmqctl; then
            log_debug "  Deleting RabbitMQ user: $user"
            rabbitmqctl delete_user "$user" 2>/dev/null || true
        fi
    done
    
    ok "Пользователи удалены"
}

# Откат: удаление файлов
rollback_files() {
    if [ ${#CREATED_FILES[@]} -eq 0 ]; then
        return 0
    fi
    
    log_info "Удаление файлов..."
    
    for file in "${CREATED_FILES[@]}"; do
        if [ -f "$file" ]; then
            log_debug "  Removing: $file"
            rm -f "$file" 2>/dev/null || true
        fi
    done
    
    ok "Файлы удалены"
}

# Откат: удаление директорий
rollback_directories() {
    if [ ${#CREATED_DIRS[@]} -eq 0 ]; then
        return 0
    fi
    
    log_info "Удаление директорий..."
    
    # Удалить в обратном порядке (сначала вложенные)
    for (( idx=${#CREATED_DIRS[@]}-1 ; idx>=0 ; idx-- )) ; do
        local dir="${CREATED_DIRS[idx]}"
        if [ -d "$dir" ]; then
            log_debug "  Removing: $dir"
            rm -rf "$dir" 2>/dev/null || true
        fi
    done
    
    ok "Директории удалены"
}

# Откат: удаление пакетов
rollback_packages() {
    if [ ${#INSTALLED_PACKAGES[@]} -eq 0 ]; then
        return 0
    fi
    
    log_warn "Удаление установленных пакетов..."
    log_warn "Это может занять несколько минут..."
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            for package in "${INSTALLED_PACKAGES[@]}"; do
                log_debug "  Removing: $package"
                apt remove --purge -y "$package" 2>/dev/null || true
            done
            apt autoremove -y 2>/dev/null || true
            ;;
        almalinux)
            for package in "${INSTALLED_PACKAGES[@]}"; do
                log_debug "  Removing: $package"
                dnf remove -y "$package" 2>/dev/null || true
            done
            ;;
    esac
    
    ok "Пакеты удалены"
}

# Установить trap для автоматического отката
setup_rollback_trap() {
    trap 'perform_rollback $?' EXIT ERR
    log_debug "Ловушка отката включена"
}

# Отключить rollback (при успешном завершении)
disable_rollback() {
    trap - EXIT ERR
    ROLLBACK_ENABLED=false
    log_debug "Ловушка отката отключена"
}

# Создать точку восстановления
create_restore_point() {
    local restore_point_file="${LOCK_DIR}/restore_point_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$restore_point_file" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "packages": $(printf '%s\n' "${INSTALLED_PACKAGES[@]}" | jq -R . | jq -s .),
  "databases": $(printf '%s\n' "${CREATED_DATABASES[@]}" | jq -R . | jq -s .),
  "users": $(printf '%s\n' "${CREATED_USERS[@]}" | jq -R . | jq -s .),
  "directories": $(printf '%s\n' "${CREATED_DIRS[@]}" | jq -R . | jq -s .),
  "files": $(printf '%s\n' "${CREATED_FILES[@]}" | jq -R . | jq -s .)
}
EOF
    
    log_debug "Точка восстановления создана: $restore_point_file"
}

# Интерактивный выбор: продолжить или откатить
ask_rollback_on_error() {
    local error_message="$1"
    
    log_error "$error_message"
    echo ""
    log_warn "Установка столкнулась с ошибкой"
    echo ""
    
    read -p "Хотите откатить изменения? (y/n): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        perform_rollback 1
    else
        log_warn "Продолжение с частичной установкой"
        log_warn "Возможно потребуется ручная очистка позже"
    fi
}

# Экспортировать функции
export -f perform_rollback
export -f rollback_cleanup_services
export -f rollback_services
export -f rollback_databases
export -f rollback_users
export -f rollback_files
export -f rollback_directories
export -f rollback_packages
export -f setup_rollback_trap
export -f disable_rollback
export -f create_restore_point
export -f ask_rollback_on_error

