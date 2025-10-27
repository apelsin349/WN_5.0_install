#!/bin/bash
# progress.sh - Прогресс Bar и индикация прогресса
# WorkerNet Installer v5.0

# Общее количество шагов установки
TOTAL_STEPS=15
CURRENT_STEP=0
START_TIME=0

# Названия шагов
declare -a STEP_NAMES=(
    "Pre-flight checks"
    "System preparation"
    "Firewall configuration"
    "PostgreSQL installation"
    "PostgreSQL configuration"
    "Redis installation"
    "RabbitMQ installation"
    "RabbitMQ configuration"
    "PHP installation"
    "Python installation"
    "Supervisor installation"
    "Web server installation"
    "Web server configuration"
    "Application setup"
    "Final checks"
)

# Инициализация прогресса
init_progress() {
    CURRENT_STEP=0
    START_TIME=$(date +%s)
    TOTAL_STEPS=${#STEP_NAMES[@]}
}

# Показать прогресс
show_progress() {
    local step_name="${1:-${STEP_NAMES[$CURRENT_STEP]}}"
    
    ((CURRENT_STEP++))
    
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((CURRENT_STEP * 50 / TOTAL_STEPS))
    local empty=$((50 - filled))
    
    # Вычислить прошедшее время
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local avg_time_per_step=$((elapsed / CURRENT_STEP))
    local remaining_steps=$((TOTAL_STEPS - CURRENT_STEP))
    local eta=$((remaining_steps * avg_time_per_step))
    
    # Форматировать время
    local eta_min=$((eta / 60))
    local eta_sec=$((eta % 60))
    
    # Создать progress bar
    printf "\r["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%% | Step %d/%d | ETA: %02d:%02d | %s" \
        $percent $CURRENT_STEP $TOTAL_STEPS $eta_min $eta_sec "$step_name"
    
    # Добавить в лог
    log_debug "Прогресс: $percent% - $step_name"
    
    if [ $CURRENT_STEP -eq $TOTAL_STEPS ]; then
        echo ""
        echo ""
    fi
}

# Spinner для длительных операций
spinner() {
    local pid=$1
    local message="${2:-Обработка...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${spin:$i:1} %s" "$message"
        sleep 0.1
    done
    
    printf "\r✅ %s\n" "$message"
}

# Запустить команду со spinner
run_with_spinner() {
    local message="$1"
    shift
    local cmd="$@"
    
    # Запустить команду в фоне
    eval "$cmd" &> /tmp/spinner_output_$$.log &
    local pid=$!
    
    # Показать spinner
    spinner $pid "$message"
    
    # Дождаться завершения
    wait $pid
    local exit_code=$?
    
    # Обработать результат
    if [ $exit_code -eq 0 ]; then
        log_debug "Command succeeded: $cmd"
    else
        log_error "Command failed: $cmd"
        log_error "Output: $(cat /tmp/spinner_output_$$.log)"
    fi
    
    rm -f /tmp/spinner_output_$$.log
    return $exit_code
}

# Показать сводку установки
show_installation_summary() {
    local success=$1
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    local minutes=$((total_duration / 60))
    local seconds=$((total_duration % 60))
    
    echo ""
    log_separator "="
    log_info "INSTALLATION SUMMARY"
    log_separator "="
    echo ""
    
    if [ "$success" = "true" ]; then
        ok "Установка завершена успешно! 🎉"
    else
        log_error "Установка не удалась ❌"
    fi
    
    echo ""
    log_info "Общая длительность: ${minutes}m ${seconds}s"
    log_info "Завершено шагов: $CURRENT_STEP / $TOTAL_STEPS"
    
    if [ ${#INSTALLED_PACKAGES[@]} -gt 0 ]; then
        log_info "Установлено пакетов: ${#INSTALLED_PACKAGES[@]}"
    fi
    
    if [ ${#CREATED_DATABASES[@]} -gt 0 ]; then
        log_info "Созданы базы данных: ${CREATED_DATABASES[*]}"
    fi
    
    if [ ${#STARTED_SERVICES[@]} -gt 0 ]; then
        log_info "Запущены сервисы: ${STARTED_SERVICES[*]}"
    fi
    
    echo ""
    log_info "Файл лога: $INSTALL_LOG"
    log_separator "="
    
    # Показать инструкцию после установки
    if [ "$success" = "true" ]; then
        echo ""
        log_info "📋 СЛЕДУЮЩИЕ ШАГИ:"
        echo ""
        log_info "1. Откройте WorkerNet в браузере:"
        log_info "   http://$(hostname -I | awk '{print $1}')/"
        echo ""
        
        # Проверить наличие файла учётных данных
        if [ -f "${CREDENTIALS_FILE:-/var/log/workernet/install_credentials.env}" ]; then
            log_info "2. Учётные данные установки сохранены в:"
            log_info "   ${CREDENTIALS_FILE:-/var/log/workernet/install_credentials.env}"
            log_info "   (безопасно, доступен только root)"
            echo ""
            log_info "3. Для обновления WebSocket реквизитов (если нужно):"
            
            # Определить директорию установщика
            if [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/update_credentials.sh" ]; then
                log_info "   cd $SCRIPT_DIR"
            elif [ -f "$(pwd)/update_credentials.sh" ]; then
                log_info "   cd $(pwd)"
            else
                log_info "   cd [директория_где_запустили_install.sh]"
            fi
            
            log_info "   sudo ./update_credentials.sh  # Без параметров (использует файл)"
            log_info "   # ИЛИ с параметрами:"
            log_info "   sudo ./update_credentials.sh workernet-stomp [пароль]"
        else
            log_info "2. После первого запуска (создания таблиц) обновите WebSocket реквизиты:"
            
            # Определить директорию установщика
            if [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/update_credentials.sh" ]; then
                log_info "   cd $SCRIPT_DIR"
            elif [ -f "$(pwd)/update_credentials.sh" ]; then
                log_info "   cd $(pwd)"
            else
                log_info "   cd [директория_где_запустили_install.sh]"
            fi
            
            log_info "   sudo ./update_credentials.sh workernet-stomp [пароль_из_лога]"
        fi
        
        echo ""
        log_info "📖 Подробная инструкция: ПОСЛЕ_УСТАНОВКИ.md"
        echo ""
        log_separator "="
    fi
    
    echo ""
}

# Индикатор загрузки с процентами (для больших файлов)
download_with_progress() {
    local url=$1
    local output=$2
    local description="${3:-Загрузка}"
    
    log_info "$description..."
    
    if command_exists curl; then
        curl -# -L -o "$output" "$url" 2>&1 | \
        while IFS= read -r line; do
            if [[ $line =~ ([0-9]+\.[0-9]+)% ]]; then
                local percent="${BASH_REMATCH[1]}"
                printf "\r  Прогресс: %s%%" "$percent"
            fi
        done
        echo ""
    elif command_exists wget; then
        wget --progress=bar:force -O "$output" "$url" 2>&1 | \
        grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | \
        awk '{printf("\r  Прогресс: %s", $2)}'
        echo ""
    else
        log_error "Neither curl nor wget found"
        return 1
    fi
}

# Прогресс для пакетной установки
package_install_progress() {
    local package_manager=$1
    shift
    local packages=("$@")
    local total=${#packages[@]}
    local current=0
    
    log_info "Installing $total packages..."
    
    for package in "${packages[@]}"; do
        ((current++))
        local percent=$((current * 100 / total))
        printf "\r  [%3d%%] Installing: %-30s" $percent "$package"
        
        case $package_manager in
            apt)
                apt install -y "$package" &> /dev/null
                ;;
            dnf)
                dnf install -y "$package" &> /dev/null
                ;;
        esac
        
        INSTALLED_PACKAGES+=("$package")
    done
    
    echo ""
    ok "Все пакеты установлены"
}

# Экспортировать функции
export -f init_progress
export -f show_progress
export -f spinner
export -f run_with_spinner
export -f show_installation_summary
export -f download_with_progress
export -f package_install_progress

