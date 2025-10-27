#!/bin/bash
# update_credentials.sh - Обновление реквизитов в БД после первого запуска
# WorkerNet Installer v5.0
# 
# ИСПОЛЬЗОВАНИЕ:
#   sudo ./update_credentials.sh [webstomp_user] [webstomp_password]
#
# ПРИМЕР:
#   sudo ./update_credentials.sh workernet-stomp xY9zA3bC5dE7

set -uo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции вывода
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}✅${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Параметры
DB_NAME="${DB_NAME:-workernet}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-/var/log/workernet/install_credentials.env}"

# Попытка загрузить из файла учётных данных
if [ -f "$CREDENTIALS_FILE" ]; then
    info "Загрузка учётных данных из файла: $CREDENTIALS_FILE"
    set -a
    source "$CREDENTIALS_FILE" 2>/dev/null || true
    set +a
fi

WEBSTOMP_USER="${1:-${RABBITMQ_WEBSTOMP_USER:-}}"
WEBSTOMP_PASSWORD="${2:-${RABBITMQ_WEBSTOMP_PASSWORD:-}}"

# Проверка параметров
if [ -z "$WEBSTOMP_USER" ] || [ -z "$WEBSTOMP_PASSWORD" ]; then
    error "Использование: $0 <webstomp_user> <webstomp_password>"
    echo ""
    info "Пример:"
    echo "  sudo $0 workernet-stomp xY9zA3bC5dE7"
    echo ""
    info "Пароли можно найти:"
    if [ -f "$CREDENTIALS_FILE" ]; then
        echo "  1. В файле учётных данных: $CREDENTIALS_FILE"
    fi
    echo "  2. В логе установки:"
    echo "     grep 'RabbitMQ WebSocket password' /var/log/workernet/install_*.log"
    echo ""
    exit 1
fi

info "Обновление WebSocket реквизитов в базе данных $DB_NAME"
echo ""

# Проверка что БД существует
if ! sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    error "База данных $DB_NAME не найдена"
    info "Создайте базу данных или укажите правильное имя:"
    echo "  DB_NAME=your_db_name sudo $0 $WEBSTOMP_USER $WEBSTOMP_PASSWORD"
    exit 1
fi

ok "База данных $DB_NAME найдена"

# Проверка что таблица erp.settings существует
if ! sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT to_regclass('erp.settings');" 2>/dev/null | grep -q "settings"; then
    error "Таблица erp.settings не найдена в базе $DB_NAME"
    echo ""
    warn "Таблица создаётся при первом запуске WorkerNet"
    info "Пожалуйста:"
    echo "  1. Откройте WorkerNet в браузере"
    echo "  2. Дождитесь завершения миграций"
    echo "  3. Запустите этот скрипт снова"
    echo ""
    exit 1
fi

ok "Таблица erp.settings найдена"
echo ""

# Обновить реквизиты
info "Обновление настроек..."

sudo -u postgres psql -d "$DB_NAME" <<EOF
-- WebSocket пользователь (UPDATE существующей записи)
UPDATE erp.settings 
SET option_value = '${WEBSTOMP_USER}' 
WHERE option_name = 'WEB_SOCKET_USER';

-- WebSocket пароль
UPDATE erp.settings 
SET option_value = '${WEBSTOMP_PASSWORD}' 
WHERE option_name = 'WEB_SOCKET_PASSWORD';

-- Включить WebSocket
UPDATE erp.settings 
SET option_value = '1' 
WHERE option_name = 'IS_WEB_SOCKET_ENABLE';

-- Показать результат
SELECT option_name, option_value 
FROM erp.settings 
WHERE option_name LIKE 'WEB_SOCKET%'
ORDER BY option_name;
EOF

if [ $? -eq 0 ]; then
    echo ""
    ok "Реквизиты успешно обновлены!"
    echo ""
    info "Проверьте в веб-интерфейсе:"
    echo "  Настройки → Сервисы → WebSocket"
    echo ""
    info "Должно быть заполнено:"
    echo "  Имя пользователя: $WEBSTOMP_USER"
    echo "  Пароль: [скрыт]"
    echo "  WebSocket включен: Да"
    echo ""
else
    error "Не удалось обновить реквизиты"
    exit 1
fi

exit 0

