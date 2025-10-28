#!/bin/bash
# checks.sh - Pre-flight проверки перед установкой
# WorkerNet Installer v5.0

# Счетчики ошибок и предупреждений
CHECK_ERRORS=0
CHECK_WARNINGS=0

# Остановить unattended-upgrades (автообновления) для быстрой установки
disable_unattended_upgrades() {
    # Проверить только для Ubuntu/Debian
    local os_type=$(get_os_type)
    if [ "$os_type" != "ubuntu" ] && [ "$os_type" != "debian" ]; then
        return 0
    fi
    
    # Проверить запущен ли unattended-upgrades
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null || \
       pgrep -f unattended-upgrade >/dev/null 2>&1; then
        
        log_warn "⚠️  Обнаружен активный unattended-upgrades (автообновления)"
        log_info "Остановка для предотвращения блокировок apt..."
        
        # Остановить сервис
        systemctl stop unattended-upgrades 2>/dev/null || true
        systemctl disable unattended-upgrades 2>/dev/null || true
        
        # Убить все apt процессы
        killall -9 apt apt-get unattended-upgr 2>/dev/null || true
        
        # Удалить lock файлы
        rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
        rm -f /var/lib/dpkg/lock 2>/dev/null || true
        rm -f /var/lib/apt/lists/lock 2>/dev/null || true
        
        # Переконфигурировать dpkg если нужно
        dpkg --configure -a 2>/dev/null || true
        
        sleep 2
        ok "unattended-upgrades остановлен (будет включен после установки)"
    fi
    
    return 0
}

# Включить обратно unattended-upgrades после установки
re_enable_unattended_upgrades() {
    local os_type=$(get_os_type)
    if [ "$os_type" != "ubuntu" ] && [ "$os_type" != "debian" ]; then
        return 0
    fi
    
    # Включить обратно если был остановлен
    if systemctl list-unit-files | grep -q "unattended-upgrades.service.*disabled"; then
        log_info "Включение unattended-upgrades обратно..."
        systemctl enable unattended-upgrades 2>/dev/null || true
        systemctl start unattended-upgrades 2>/dev/null || true
        ok "unattended-upgrades включен обратно"
    fi
    
    return 0
}

# Проверка свободного места на диске
check_disk_space() {
    log_info "Проверка свободного места на диске..."
    
    local free_space_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [ $free_space_gb -lt $MIN_DISK_GB ]; then
        log_error "❌ Недостаточно места на диске: ${free_space_gb}GB (требуется минимум ${MIN_DISK_GB}GB)"
        ((CHECK_ERRORS++))
        return 1
    else
        ok "Свободное место на диске: ${free_space_gb}GB"
        return 0
    fi
}

# Проверка оперативной памяти
check_memory() {
    log_info "Проверка оперативной памяти..."
    
    # Используем -m для мегабайт, затем конвертируем в GB с точностью
    local total_ram_mb=$(free -m | awk '/Mem:/ {print $2}')
    local total_ram_gb=$((total_ram_mb / 1024))
    
    # Для отображения с десятичными (опционально)
    local total_ram_display=$(awk "BEGIN {printf \"%.1f\", $total_ram_mb/1024}")
    
    if [ $total_ram_gb -lt $MIN_RAM_GB ]; then
        log_error "❌ Недостаточно RAM: ${total_ram_display}GB (требуется минимум ${MIN_RAM_GB}GB)"
        ((CHECK_ERRORS++))
        return 1
    else
        ok "Оперативная память: ${total_ram_display}GB"
        return 0
    fi
}

# Проверка процессора
check_cpu() {
    log_info "Проверка CPU ядер..."
    
    local cpu_cores=$(nproc)
    
    if [ $cpu_cores -lt $MIN_CPU_CORES ]; then
        log_warn "⚠️  Мало CPU ядер: ${cpu_cores} (рекомендуется: ${MIN_CPU_CORES}+)"
        ((CHECK_WARNINGS++))
        return 0
    else
        ok "CPU ядер: ${cpu_cores}"
        return 0
    fi
}

# Проверка интернет-соединения
check_internet() {
    log_info "Проверка интернет-соединения..."
    
    if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        ok "Интернет соединение доступно"
        return 0
    else
        log_error "❌ Нет доступа к интернету"
        ((CHECK_ERRORS++))
        return 1
    fi
}

# Проверка доступности репозиториев
check_repositories() {
    log_info "Проверка доступности репозиториев..."
    
    local os_type=$(get_os_type)
    local repos=()
    
    case $os_type in
        ubuntu|debian)
            repos=(
                "https://apt.postgresql.org/"
                "https://deb1.rabbitmq.com/"
            )
            ;;
        almalinux)
            repos=(
                "https://download.postgresql.org/"
                "https://yum1.novemberain.com/"
            )
            ;;
    esac
    
    local failed_repos=0
    for repo in "${repos[@]}"; do
        if timeout 5 curl -f -s -I "$repo" --max-time 5 &> /dev/null; then
            log_debug "✓ $repo доступен"
        else
            log_warn "⚠️  Репозиторий недоступен: $repo"
            ((failed_repos++))
        fi
    done
    
    if [ $failed_repos -eq 0 ]; then
        ok "Все репозитории доступны"
    elif [ $failed_repos -eq ${#repos[@]} ]; then
        log_warn "❌ Все репозитории недоступны"
        log_info "   Не критично: будут использованы альтернативные источники"
        log_info "   - PostgreSQL: стандартные репозитории дистрибутива"
        log_info "   - RabbitMQ: packagecloud.io или стандартные репозитории"
        ((CHECK_WARNINGS++))
    else
        log_warn "⚠️  Некоторые репозитории недоступны ($failed_repos/${#repos[@]})"
        log_info "   Не критично: будут использованы альтернативные источники"
        ((CHECK_WARNINGS++))
    fi
    
    return 0
}

# Получить процесс, занимающий порт
get_process_on_port() {
    local port=$1
    local process=""
    
    # Попытка определить через ss
    if command_exists ss; then
        process=$(ss -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | sed 's/users:((//' | sed 's/,.*$//' | head -1)
    fi
    
    # Попытка определить через netstat
    if [ -z "$process" ] && command_exists netstat; then
        process=$(netstat -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f2 | head -1)
    fi
    
    # Попытка определить через lsof
    if [ -z "$process" ] && command_exists lsof; then
        local pid=$(lsof -ti:$port -sTCP:LISTEN 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            process=$(ps -p $pid -o comm= 2>/dev/null | head -1)
        fi
    fi
    
    # Если не удалось определить, но порт известный - определяем по порту
    if [ -z "$process" ]; then
        case "$port" in
            5432)
                echo "postgres-unknown"  # PostgreSQL (процесс не определен)
                return
                ;;
            6379)
                echo "redis-unknown"  # Redis (процесс не определен)
                return
                ;;
            5672|15672)
                echo "rabbitmq-unknown"  # RabbitMQ (процесс не определен)
                return
                ;;
            80|443)
                echo "webserver-unknown"  # Apache/NGINX (процесс не определен)
                return
                ;;
            *)
                echo "unknown"
                return
                ;;
        esac
    fi
    
    echo "$process"
}

# Остановить конфликтующие сервисы WorkerNet
stop_conflicting_services() {
    log_info "Остановка конфликтующих сервисов..."
    
    local services_to_stop=("postgresql" "redis-server" "rabbitmq-server" "apache2" "nginx" "supervisor")
    local stopped_count=0
    
    for service in "${services_to_stop[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Остановка $service..."
            if systemctl stop "$service" 2>&1 | tee -a "$LOG_FILE"; then
                ok "  $service остановлен"
                ((stopped_count++))
            else
                log_warn "  Не удалось остановить $service"
            fi
        fi
    done
    
    if [ $stopped_count -gt 0 ]; then
        ok "Остановлено сервисов: $stopped_count"
        sleep 2  # Подождать освобождения портов
    else
        log_info "Нет запущенных сервисов для остановки"
    fi
    
    return 0
}

# Проверка занятых портов
check_ports() {
    log_info "Проверка доступности портов..."
    
    local ports_in_use=()
    local ports_details=()
    local workernet_services=0
    
    for port in "${PORTS_TO_CHECK[@]}"; do
        if is_port_in_use "$port"; then
            local process=$(get_process_on_port "$port")
            ports_in_use+=("$port")
            
            # Определить, это сервис WorkerNet или нет
            case "$process" in
                postgres|postgres-unknown|redis-server|redis-unknown|beam.smp|rabbitmq-unknown|apache2|nginx|webserver-unknown|supervisord)
                    # Это сервис WorkerNet или стандартный порт
                    if [[ "$process" == *"-unknown" ]]; then
                        ports_details+=("$port (сервис WorkerNet - процесс не определен)")
                    else
                        ports_details+=("$port ($process - возможно от предыдущей установки)")
                    fi
                    ((workernet_services++))
                    ;;
                *)
                    ports_details+=("$port ($process)")
                    ;;
            esac
        fi
    done
    
    if [ ${#ports_in_use[@]} -gt 0 ]; then
        log_warn "⚠️  Следующие порты уже заняты:"
        for detail in "${ports_details[@]}"; do
            log_warn "   - $detail"
        done
        
        # Если все занятые порты - это сервисы WorkerNet
        if [ $workernet_services -eq ${#ports_in_use[@]} ]; then
            log_info ""
            log_info "   Похоже, это порты от предыдущей установки WorkerNet"
            log_info "   Они будут автоматически остановлены при установке"
            log_warn "   Продолжаем установку..."
            ((CHECK_WARNINGS++))
            
            # Не останавливаем сервисы здесь! Они будут остановлены в setup_* модулях
            if [ "${FORCE_INSTALL:-false}" = "true" ]; then
                log_info ""
                log_info "   Режим --force: сервисы будут остановлены перед установкой:"
                log_info "   - PostgreSQL → перед setup_database"
                log_info "   - Redis → перед setup_cache"
                log_info "   - RabbitMQ → перед setup_queue"
                log_info "   - Apache/NGINX → перед setup_webserver"
            else
                log_warn ""
                log_warn "   Для автоматической остановки используйте: sudo ./install.sh --force"
            fi
            
            return 0
        else
            log_error ""
            log_error "   Обнаружены конфликтующие сервисы (не от WorkerNet)"
            log_error ""
            log_error "   Варианты решения:"
            log_error "   1. Остановите конфликтующие сервисы вручную"
            log_error "   2. Запустите установку с флагом --force (остановит все автоматически):"
            log_error "      sudo ./install.sh --force"
            log_error ""
            ((CHECK_ERRORS++))
            return 1
        fi
    else
        ok "Все необходимые порты свободны"
        return 0
    fi
}

# Проверка локали
check_locale() {
    log_info "Проверка системной локали..."
    
    local current_locale=$(echo $LANG)
    
    if [[ "$current_locale" == "ru_RU.UTF-8" ]]; then
        ok "Локаль: $current_locale"
        return 0
    else
        log_warn "⚠️  Текущая локаль: $current_locale (требуется: ru_RU.UTF-8)"
        log_info "   Локаль будет установлена автоматически"
        ((CHECK_WARNINGS++))
        return 0
    fi
}

# Проверка прав root
check_root() {
    log_info "Проверка прав root..."
    
    if ! is_root; then
        log_error "❌ Скрипт должен быть запущен от root"
        log_error "   Выполните: sudo $0"
        ((CHECK_ERRORS++))
        return 1
    else
        ok "Запущен от root"
        return 0
    fi
}

# Проверка версии ОС
check_os_version() {
    log_info "Проверка версии ОС..."
    
    local os_type=$(get_os_type)
    local os_version=$(get_os_version)
    
    local supported=false
    
    case "$os_type" in
        ubuntu)
            if [ "$os_version" = "24" ]; then
                supported=true
            fi
            ;;
        debian)
            if [ "$os_version" = "12" ]; then
                supported=true
            fi
            ;;
        almalinux)
            if [ "$os_version" = "9" ]; then
                supported=true
            fi
            ;;
    esac
    
    if [ "$supported" = "true" ]; then
        ok "ОС: $os_type $os_version (поддерживается)"
        return 0
    else
        log_error "❌ Неподдерживаемая ОС: $os_type $os_version"
        log_error "   Поддерживаются: Ubuntu 24, Debian 12, AlmaLinux 9"
        ((CHECK_ERRORS++))
        return 1
    fi
}

# Проверка SELinux (для AlmaLinux)
check_selinux() {
    local os_type=$(get_os_type)
    
    if [ "$os_type" != "almalinux" ]; then
        return 0
    fi
    
    log_info "Проверка статуса SELinux..."
    
    local selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
    
    if [ "$selinux_status" = "Disabled" ]; then
        ok "SELinux: Отключен"
        return 0
    else
        log_warn "⚠️  SELinux включен ($selinux_status)"
        log_info "   SELinux будет отключен автоматически (требуется перезагрузка)"
        ((CHECK_WARNINGS++))
        return 0
    fi
}

# Проверка существующей установки
check_existing_installation() {
    log_info "Проверка существующей установки..."
    
    if [ -f "$LOCK_FILE" ]; then
        local lock_content=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        
        # Если lock файл пустой или не содержит "successful" - это неудачная установка
        if [ -z "$lock_content" ] || [[ "$lock_content" != "successful-"* ]]; then
            log_warn "⚠️  Обнаружен lock файл от неудачной установки"
            log_info "   Удаляем: $LOCK_FILE"
            rm -f "$LOCK_FILE"
            ok "Lock файл от неудачной установки удален"
            return 0
        fi
        
        # Lock файл содержит "successful-XXX" - это успешная установка
        if [[ "$lock_content" == "successful-"* ]]; then
            # Если флаг --force - разрешить переустановку без вопросов
            if [ "${FORCE_INSTALL:-false}" = "true" ]; then
                log_warn "⚠️  WorkerNet уже установлен, но используется флаг --force"
                log_info "   Удаляем lock файл для переустановки..."
                rm -f "$LOCK_FILE"
                ok "Lock файл удален, переустановка разрешена"
                return 0
            fi
            
            # Без --force - спросить пользователя
            log_warn "⚠️  WorkerNet уже установлен (версия: ${lock_content#successful-})"
            log_warn "   Lock файл: $LOCK_FILE"
            echo ""
            
            # Интерактивный запрос
            read -p "Переустановить WorkerNet? Это удалит текущую установку. (y/n): " -n 1 -r
            echo ""
            
            if [[ $REPLY =~ ^[YyДд]$ ]]; then
                log_info "Удаление lock файла для переустановки..."
                rm -f "$LOCK_FILE"
                ok "Lock файл удален, переустановка разрешена"
                echo ""
                return 0
            else
                log_info "Переустановка отменена"
                log_info ""
                log_info "Для автоматической переустановки используйте:"
                log_info "  sudo ./install.sh --force"
                log_info ""
                log_info "Выход из установки..."
                exit 0  # Нормальный выход, пользователь отказался
            fi
        fi
    fi
    
    ok "Существующая установка не найдена"
    return 0
}

# Главная функция pre-flight проверок
run_preflight_checks() {
    log_section "🔍 PRE-FLIGHT CHECKS"
    
    CHECK_ERRORS=0
    CHECK_WARNINGS=0
    
    # КРИТИЧНО: Сначала остановить unattended-upgrades (если есть)
    disable_unattended_upgrades
    
    # Запустить все проверки
    check_root
    check_os_version
    check_existing_installation
    check_disk_space
    check_memory
    check_cpu
    check_internet
    check_repositories
    check_ports
    check_locale
    check_selinux
    
    # Итоги
    echo ""
    log_separator "-"
    
    if [ $CHECK_ERRORS -eq 0 ] && [ $CHECK_WARNINGS -eq 0 ]; then
        ok "Все предварительные проверки пройдены успешно!"
        log_separator "-"
        echo ""
        return 0
    elif [ $CHECK_ERRORS -eq 0 ]; then
        log_warn "Предварительные проверки завершены с $CHECK_WARNINGS предупреждением(-ями)"
        log_info "Установка может продолжиться, но просмотрите предупреждения"
        log_separator "-"
        echo ""
        return 0
    else
        log_error "Предварительные проверки не пройдены: $CHECK_ERRORS ошибок, $CHECK_WARNINGS предупреждений"
        log_error ""
        log_error "Исправьте ошибки выше и запустите установку снова"
        log_separator "-"
        echo ""
        return 1
    fi
}

# ПАРАЛЛЕЛЬНАЯ ВЕРСИЯ ПРОВЕРОК (НОВАЯ ФУНКЦИЯ)
run_preflight_checks_parallel() {
    log_section "🔍 PRE-FLIGHT CHECKS (PARALLEL)"
    
    CHECK_ERRORS=0
    CHECK_WARNINGS=0
    
    # КРИТИЧНО: Сначала остановить unattended-upgrades (если есть)
    disable_unattended_upgrades
    
    log_info "Запуск проверок параллельно..."
    
    # Массивы для хранения PID процессов и результатов
    local pids=()
    local check_names=()
    local check_results=()
    
    # Запустить независимые проверки параллельно
    log_info "Запуск независимых проверок..."
    
    check_root &
    pids+=($!)
    check_names+=("root")
    
    check_os_version &
    pids+=($!)
    check_names+=("os_version")
    
    check_existing_installation &
    pids+=($!)
    check_names+=("existing_installation")
    
    check_disk_space &
    pids+=($!)
    check_names+=("disk_space")
    
    check_memory &
    pids+=($!)
    check_names+=("memory")
    
    check_cpu &
    pids+=($!)
    check_names+=("cpu")
    
    check_internet &
    pids+=($!)
    check_names+=("internet")
    
    check_repositories &
    pids+=($!)
    check_names+=("repositories")
    
    check_ports &
    pids+=($!)
    check_names+=("ports")
    
    check_locale &
    pids+=($!)
    check_names+=("locale")
    
    check_selinux &
    pids+=($!)
    check_names+=("selinux")
    
    # Показать прогресс ожидания
    log_info "Ожидание завершения всех проверок..."
    local total_checks=${#pids[@]}
    local completed=0
    
    # Дождаться завершения всех проверок
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local check_name=${check_names[$i]}
        
        # Ждать завершения конкретного процесса
        wait $pid
        local exit_code=$?
        
        ((completed++))
        local percent=$((completed * 100 / total_checks))
        
        # Показать прогресс
        printf "\r  [%3d%%] Completed: %s" $percent "$check_name"
        
        # Сохранить результат
        check_results+=($exit_code)
        
        # Обновить счетчики ошибок и предупреждений
        if [ $exit_code -ne 0 ]; then
            if [[ "$check_name" == "root" ]] || [[ "$check_name" == "os_version" ]] || [[ "$check_name" == "disk_space" ]]; then
                ((CHECK_ERRORS++))
            else
                ((CHECK_WARNINGS++))
            fi
        fi
    done
    
    echo ""
    log_info "Все проверки завершены"
    
    # Итоги
    echo ""
    log_separator "-"
    
    if [ $CHECK_ERRORS -eq 0 ] && [ $CHECK_WARNINGS -eq 0 ]; then
        ok "Все предварительные проверки пройдены успешно! (параллельно)"
        log_separator "-"
        echo ""
        return 0
    elif [ $CHECK_ERRORS -eq 0 ]; then
        log_warn "Предварительные проверки завершены с $CHECK_WARNINGS предупреждением(-ями) (параллельно)"
        log_info "Установка может продолжиться, но просмотрите предупреждения"
        log_separator "-"
        echo ""
        return 0
    else
        log_error "Предварительные проверки не пройдены: $CHECK_ERRORS ошибок, $CHECK_WARNINGS предупреждений (параллельно)"
        log_error ""
        log_error "Исправьте ошибки выше и запустите установку снова"
        log_separator "-"
        echo ""
        return 1
    fi
}

# Экспортировать функции
export -f get_process_on_port
export -f stop_conflicting_services
export -f disable_unattended_upgrades
export -f re_enable_unattended_upgrades
export -f check_disk_space
export -f check_memory
export -f check_cpu
export -f check_internet
export -f check_repositories
export -f check_ports
export -f check_locale
export -f check_root
export -f check_os_version
export -f check_selinux
export -f check_existing_installation
export -f run_preflight_checks
export -f run_preflight_checks_parallel

