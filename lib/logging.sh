#!/bin/bash
# logging.sh - Улучшенное логирование
# WorkerNet Installer v5.0

# Уровни логирования
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_FATAL=4

# Текущий уровень (по умолчанию INFO)
LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Инициализация логирования
init_logging() {
    # Создать директорию для логов
    mkdir -p "$LOG_DIR"
    
    # Создать файл лога
    touch "$INSTALL_LOG"
    chmod 644 "$INSTALL_LOG"
    
    log_info "╔════════════════════════════════════════════════════════════════╗"
    log_info "║  WorkerNet Installer v${SCRIPT_VERSION} - Установка начата  ║"
    log_info "╚════════════════════════════════════════════════════════════════╝"
    log_info "Log file: $INSTALL_LOG"
    log_info "Начато в: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "OS: $(get_os_type) $(get_os_version)"
    log_info ""
}

# Базовая функция логирования
_log() {
    local level=$1
    local level_name=$2
    local color=$3
    shift 3
    local message="$@"
    
    # Проверить уровень
    if [ $level -lt $LOG_LEVEL ]; then
        return
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="[$timestamp] [$level_name] $message"
    
    # Записать в файл
    echo "$log_line" >> "$INSTALL_LOG"
    
    # Вывести на экран с цветом
    echo -e "${color}[$level_name]${COLOR_RESET} $message"
}

# Функции логирования по уровням
log_debug() {
    _log $LOG_LEVEL_DEBUG "DEBUG" "$COLOR_GRAY" "$@"
}

log_info() {
    _log $LOG_LEVEL_INFO "INFO" "$COLOR_CYAN" "$@"
}

log_warn() {
    _log $LOG_LEVEL_WARN "WARN" "$COLOR_YELLOW" "$@"
}

log_error() {
    _log $LOG_LEVEL_ERROR "ERROR" "$COLOR_RED" "$@"
}

log_fatal() {
    _log $LOG_LEVEL_FATAL "FATAL" "$COLOR_RED" "$@"
}

# Алиасы для совместимости
info() { log_info "$@"; }
warn() { log_warn "$@"; }
error() { log_error "$@"; }
ok() { print_color "$COLOR_GREEN" "✅ $@"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $@" >> "$INSTALL_LOG"; }
debug() { log_debug "$@"; }

# Логирование выполнения команд
run_cmd() {
    local cmd="$@"
    log_debug "Выполнение: $cmd"
    
    local output
    local exit_code
    local temp_output=$(mktemp)
    
    # Выполнить команду и захватить вывод
    eval "$cmd" > "$temp_output" 2>&1
    exit_code=$?
    
    output=$(cat "$temp_output")
    rm -f "$temp_output"
    
    if [ $exit_code -eq 0 ]; then
        log_debug "Команда выполнена успешно (exit code: 0)"
        if [ -n "$output" ]; then
            log_debug "Вывод: ${output:0:500}"  # Ограничить длину
        fi
        return 0
    else
        log_error "Команда не удалась (exit code: $exit_code)"
        log_error "Command: $cmd"
        if [ -n "$output" ]; then
            log_error "Вывод: $output"
        fi
        return $exit_code
    fi
}

# Логирование с таймером
timed_run() {
    local description="$1"
    shift
    local cmd="$@"
    
    log_info "⏱️  Starting: $description"
    local start_time=$(date +%s)
    
    if run_cmd "$cmd"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        ok "$description (${duration}s)"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "Failed: $description (${duration}s)"
        return 1
    fi
}

# Разделитель в логах
log_separator() {
    local char="${1:--}"
    local length=70
    local separator=$(printf '%*s' "$length" | tr ' ' "$char")
    log_info "$separator"
}

# Заголовок секции
log_section() {
    local title="$1"
    echo ""
    log_separator "="
    log_info "  $title"
    log_separator "="
    echo ""
}

# Финальный лог
finalize_logging() {
    local success=$1
    local duration=$2
    
    echo ""
    log_separator "="
    if [ "$success" = "true" ]; then
        ok "Installation completed successfully!"
        log_info "Total duration: ${duration}s"
    else
        log_error "Installation failed!"
        log_info "Check logs: $INSTALL_LOG"
    fi
    log_separator "="
    echo ""
}

# Экспортировать функции
export -f init_logging
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_fatal
export -f info
export -f warn
export -f error
export -f ok
export -f debug
export -f run_cmd
export -f timed_run
export -f log_separator
export -f log_section
export -f finalize_logging

