#!/bin/bash
# common.sh - Общие функции и константы
# WorkerNet Installer v5.0

# Константы
readonly SCRIPT_VERSION="5.0"
readonly MIN_DISK_GB=20
readonly MIN_RAM_GB=2
readonly MIN_CPU_CORES=2

# Директории
readonly INSTALL_DIR="/var/www/workernet"
readonly LOG_DIR="/var/log/workernet"
readonly LOCK_DIR="/var/log/workernet"
readonly BACKUP_DIR="/var/backups/workernet"

# Файлы
readonly LOCK_FILE="${LOCK_DIR}/workernet.lock"
readonly INSTALL_LOG="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
readonly STATE_FILE="${LOCK_DIR}/install_state.json"
readonly CREDENTIALS_FILE="${LOCK_DIR}/install_credentials.env"

# Алиас для совместимости (используется в некоторых модулях)
readonly LOG_FILE="$INSTALL_LOG"

# База данных
readonly DB_NAME="workernet"
readonly DB_USER="root"

# Порты
readonly PORTS_TO_CHECK=(80 443 5432 6379 5672 15672 15674)

# Цвета для вывода
readonly COLOR_RESET="\033[0m"
readonly COLOR_RED="\033[1;31m"
readonly COLOR_GREEN="\033[1;32m"
readonly COLOR_YELLOW="\033[1;33m"
readonly COLOR_BLUE="\033[1;34m"
readonly COLOR_CYAN="\033[0;36m"
readonly COLOR_GRAY="\033[0;90m"

# Глобальные переменные для отслеживания установки
declare -a INSTALLED_PACKAGES=()
declare -a CREATED_DIRS=()
declare -a CREATED_FILES=()
declare -a CREATED_USERS=()
declare -a CREATED_DATABASES=()
declare -a STARTED_SERVICES=()

# Переменные установки
# DOMAIN и WEBSERVER устанавливаются интерактивно или через параметры
DOMAIN=""
WEBSERVER=""
GENPASSDB=""
GENHASH=""
NAMERABBITADMIN="admin"
GENPASSRABBITADMIN=""
NAMERABBITUSER="workernet"
GENPASSRABBITUSER=""
WEBSTOMPUSER="workernet-stomp"
GENPASSWEBSTOMPUSER=""

# Функции цветного вывода
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${COLOR_RESET}"
}

# Утилиты
generate_password() {
    local length=${1:-13}
    tr -dc A-Za-z0-9 </dev/urandom | head -c "$length"
}

generate_hash() {
    echo | sha256sum | cut -d" " -f1
}

# Проверка, запущен ли от root
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Получить тип ОС
get_os_type() {
    grep "^ID=" /etc/os-release | cut -f 2 -d '=' | tr -d '"'
}

# Получить версию ОС
get_os_version() {
    grep "^VERSION_ID=" /etc/os-release | cut -f 2 -d '=' | tr -d '"' | cut -d '.' -f 1
}

# Проверить, существует ли команда
command_exists() {
    command -v "$1" &> /dev/null
}

# Проверить, активен ли сервис
is_service_active() {
    systemctl is-active "$1" &> /dev/null
}

# Проверить, существует ли база данных
database_exists() {
    local dbname=$1
    sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$dbname"
}

# Проверить, существует ли пользователь PostgreSQL
postgres_user_exists() {
    local username=$1
    sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$username'" | grep -q 1
}

# Проверить, занят ли порт
is_port_in_use() {
    local port=$1
    ss -tuln | grep -q ":${port} "
}

# Сохранить состояние установки
save_install_state() {
    local state=$1
    local message=$2
    
    cat > "$STATE_FILE" <<EOF
{
  "state": "$state",
  "message": "$message",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "packages": $(printf '%s\n' "${INSTALLED_PACKAGES[@]}" | jq -R . | jq -s .),
  "databases": $(printf '%s\n' "${CREATED_DATABASES[@]}" | jq -R . | jq -s .),
  "users": $(printf '%s\n' "${CREATED_USERS[@]}" | jq -R . | jq -s .)
}
EOF
}

# Загрузить состояние установки
load_install_state() {
    if [ -f "$STATE_FILE" ]; then
        return 0
    fi
    return 1
}

# ASCII лого
print_logo() {
    print_color "$COLOR_BLUE" '
__          __        _             _   _      _
\ \        / /       | |           | \ | |    | |
 \ \  /\  / /__  _ __| | _____ _ __|  \| | ___| |_
  \ \/  \/ / _ \| '"'"'__| |/ / _ \ '"'"'__| . ` |/ _ \ __|
   \  /\  / (_) | |  |   <  __/ |  | |\  |  __/ |_
    \/  \/ \___/|_|  |_|\_\___|_|  |_| \_|\___|\__|
'
    print_color "$COLOR_CYAN" "    Installer v${SCRIPT_VERSION} - Improved Edition"
    echo ""
}

# Системная информация
print_system_info() {
    local kernel=$(uname -r -m)
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/Mem:/ {print $3}')
    local mem_percent=$(awk "BEGIN {printf \"%.2f\", ($mem_used/$mem_total)*100}")
    local disk_info=$(df -h / | awk 'NR==2 {print $5 " used, Total: " $2 ", Free: " $4}')
    local load_avg=$(awk '{print $1 " " $2 " " $3}' /proc/loadavg)
    local uptime=$(uptime -p | sed 's/up //')
    local users=$(who | wc -l)
    
    echo "$(print_color $COLOR_CYAN "════════════════════════════════════════════════════════════════════════")"
    printf "    $(print_color $COLOR_YELLOW "KERNEL"):  %s\n" "$kernel"
    printf "    $(print_color $COLOR_YELLOW "MEMORY"):  %d MB / %d MB - %.2f%% (Used)\n" "$mem_used" "$mem_total" "$mem_percent"
    printf "  $(print_color $COLOR_YELLOW "USE DISK"):  %s\n" "$disk_info"
    echo "$(print_color $COLOR_CYAN "────────────────────────────────────────────────────────────────────────")"
    printf "  $(print_color $COLOR_YELLOW "LOAD AVG"):  %s\n" "$load_avg"
    printf "    $(print_color $COLOR_YELLOW "UPTIME"):  %s\n" "$uptime"
    printf "     $(print_color $COLOR_YELLOW "USERS"):  %d users logged in\n" "$users"
    echo "$(print_color $COLOR_CYAN "════════════════════════════════════════════════════════════════════════")"
    echo ""
}

# Экспортировать функции
export -f print_color
export -f generate_password
export -f generate_hash
export -f is_root
export -f get_os_type
export -f get_os_version
export -f command_exists
export -f is_service_active
export -f database_exists
# Проверить версию пакета
check_package_version() {
    local package=$1
    local min_version=$2
    local current_version=""
    
    case $(get_os_type) in
        ubuntu|debian)
            current_version=$(apt-cache policy "$package" 2>/dev/null | grep "Installed:" | awk '{print $2}' | head -1)
            ;;
        almalinux)
            current_version=$(rpm -q --queryformat '%{VERSION}' "$package" 2>/dev/null || echo "")
            ;;
    esac
    
    if [ -z "$current_version" ]; then
        log_debug "Пакет $package не установлен"
        return 1
    fi
    
    log_debug "Версия пакета $package: $current_version"
    
    # Простая проверка версии (можно улучшить)
    if [ -n "$min_version" ]; then
        if [ "$current_version" = "$min_version" ] || [ "$current_version" \> "$min_version" ]; then
            log_debug "Версия $package ($current_version) >= $min_version"
            return 0
        else
            log_warn "Версия $package ($current_version) < $min_version"
            return 1
        fi
    fi
    
    return 0
}

# Диагностика ошибки
diagnose_error() {
    local component=$1
    local error=$2
    local exit_code=$3
    
    log_error "════════════════════════════════════════════════════════════════"
    log_error "🔍 ДИАГНОСТИКА ОШИБКИ"
    log_error "════════════════════════════════════════════════════════════════"
    log_error "Компонент: $component"
    log_error "Ошибка: $error"
    log_error "Код выхода: $exit_code"
    log_error ""
    
    # Общая диагностика системы
    log_error "📊 СОСТОЯНИЕ СИСТЕМЫ:"
    log_error "OS: $(get_os_type) $(get_os_version)"
    log_error "RAM: $(free -h | awk '/Mem:/ {print $3 "/" $2}')"
    log_error "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    log_error "Load: $(uptime | awk -F'load average:' '{print $2}')"
    log_error ""
    
    # Диагностика по компонентам
    case $component in
        "postgresql"|"database")
            log_error "🗄️ ДИАГНОСТИКА POSTGRESQL:"
            log_error "Статус сервиса:"
            systemctl status postgresql 2>&1 | head -10 || true
            log_error ""
            log_error "Порты:"
            ss -tlnp | grep :5432 || log_error "  Порт 5432 не слушается"
            log_error ""
            log_error "Процессы:"
            ps aux | grep postgres | head -5 || log_error "  Процессы PostgreSQL не найдены"
            ;;
        "redis"|"cache")
            log_error "💾 ДИАГНОСТИКА REDIS:"
            log_error "Статус сервиса:"
            systemctl status redis 2>&1 | head -10 || true
            log_error ""
            log_error "Порты:"
            ss -tlnp | grep :6379 || log_error "  Порт 6379 не слушается"
            ;;
        "rabbitmq"|"queue")
            log_error "📨 ДИАГНОСТИКА RABBITMQ:"
            log_error "Статус сервиса:"
            systemctl status rabbitmq-server 2>&1 | head -10 || true
            log_error ""
            log_error "Порты:"
            ss -tlnp | grep :5672 || log_error "  Порт 5672 не слушается"
            ss -tlnp | grep :15672 || log_error "  Порт 15672 не слушается"
            ;;
        "php"|"backend")
            log_error "⚙️ ДИАГНОСТИКА PHP:"
            if command_exists php; then
                log_error "Версия PHP: $(php -v | head -1)"
                log_error "Расширения:"
                php -m | grep -E "(pgsql|redis|curl|mbstring)" || log_error "  Критические расширения отсутствуют"
            else
                log_error "  PHP не установлен"
            fi
            ;;
        "apache"|"nginx"|"webserver")
            log_error "🌐 ДИАГНОСТИКА ВЕБ-СЕРВЕРА:"
            if [ "$WEBSERVER" = "apache" ]; then
                local apache_service=$(get_apache_service_name)
                log_error "Статус Apache ($apache_service):"
                systemctl status "$apache_service" 2>&1 | head -10 || true
            else
                log_error "Статус NGINX:"
                systemctl status nginx 2>&1 | head -10 || true
            fi
            log_error ""
            log_error "Порты:"
            ss -tlnp | grep -E ":(80|443)" || log_error "  Порты 80/443 не слушаются"
            ;;
    esac
    
    log_error ""
    log_error "🔧 РЕКОМЕНДАЦИИ:"
    log_error "1. Проверьте логи: tail -f /var/log/workernet/install_*.log"
    log_error "2. Проверьте свободное место: df -h"
    log_error "3. Проверьте память: free -h"
    log_error "4. Перезапустите установку: sudo ./install.sh --force"
    log_error "════════════════════════════════════════════════════════════════"
}

# Проверить минимальные требования к версиям
check_minimum_versions() {
    log_info "Проверка минимальных версий компонентов..."
    
    local errors=0
    
    # PostgreSQL
    if command_exists psql; then
        local pg_version=$(psql --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        if [ -n "$pg_version" ]; then
            if [ "${pg_version%%.*}" -ge 14 ]; then
                log_debug "PostgreSQL $pg_version (требуется 14+)"
            else
                log_warn "PostgreSQL $pg_version (требуется 14+)"
                ((errors++))
            fi
        fi
    fi
    
    # PHP
    if command_exists php; then
        local php_version=$(php -v 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        if [ -n "$php_version" ]; then
            if [ "${php_version%%.*}" -ge 8 ]; then
                log_debug "PHP $php_version (требуется 8+)"
            else
                log_warn "PHP $php_version (требуется 8+)"
                ((errors++))
            fi
        fi
    fi
    
    # Python
    if command_exists python3; then
        local python_version=$(python3 --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        if [ -n "$python_version" ]; then
            if [ "${python_version%%.*}" -ge 3 ]; then
                log_debug "Python $python_version (требуется 3+)"
            else
                log_warn "Python $python_version (требуется 3+)"
                ((errors++))
            fi
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log_debug "Все версии компонентов соответствуют требованиям"
        return 0
    else
        log_warn "Обнаружены компоненты с устаревшими версиями"
        return 1
    fi
}

# Сохранить учётные данные в файл
save_credentials() {
    local key="$1"
    local value="$2"
    
    # Создать директорию если не существует
    mkdir -p "$(dirname "$CREDENTIALS_FILE")"
    
    # Добавить/обновить в файле
    if [ -f "$CREDENTIALS_FILE" ]; then
        # Удалить старое значение если есть
        sed -i "/^${key}=/d" "$CREDENTIALS_FILE" 2>/dev/null || true
    fi
    
    # Добавить новое значение
    echo "${key}=${value}" >> "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"  # Только root может читать
    
    log_debug "Сохранён пароль: $key"
}

# Загрузить учётные данные из файла
load_credentials() {
    if [ -f "$CREDENTIALS_FILE" ]; then
        # Загрузить все переменные из файла
        set -a  # Автоматический export всех переменных
        source "$CREDENTIALS_FILE" 2>/dev/null || true
        set +a
        log_debug "Учётные данные загружены из $CREDENTIALS_FILE"
        return 0
    else
        log_debug "Файл учётных данных не найден: $CREDENTIALS_FILE"
        return 1
    fi
}

export -f save_credentials
export -f load_credentials
export -f postgres_user_exists
export -f is_port_in_use
export -f save_install_state
export -f load_install_state
export -f print_logo
export -f print_system_info
export -f check_package_version
export -f check_minimum_versions
export -f diagnose_error

