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

