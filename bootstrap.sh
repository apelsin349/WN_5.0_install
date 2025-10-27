#!/bin/bash
# bootstrap.sh - Bootstrap скрипт для удаленной установки
# WorkerNet Installer v5.0
# 
# Использование:
# curl -O http://workernet.online/improved/bootstrap.sh && chmod +x bootstrap.sh && ./bootstrap.sh

# НЕ используем set -e чтобы обработать ошибки curl вручную
set -uo pipefail

# Цвета
COLOR_GREEN="\033[1;32m"
COLOR_BLUE="\033[1;34m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_RESET="\033[0m"

# Базовый URL (настроить на реальный сервер)
BASE_URL="http://workernet.online/improved"

# Директория для загрузки
DOWNLOAD_DIR="workernet_installer_v5"

# Функции вывода
info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $@"
}

ok() {
    echo -e "${COLOR_GREEN}✅${COLOR_RESET} $@"
}

error() {
    echo -e "${COLOR_RED}❌ [ERROR]${COLOR_RESET} $@"
}

warn() {
    echo -e "${COLOR_YELLOW}⚠️  [WARN]${COLOR_RESET} $@"
}

# Лого
echo -e "${COLOR_BLUE}"
cat << 'EOF'
__          __        _             _   _      _
\ \        / /       | |           | \ | |    | |
 \ \  /\  / /__  _ __| | _____ _ __|  \| | ___| |_
  \ \/  \/ / _ \| '__| |/ / _ \ '__| . ` |/ _ \ __|
   \  /\  / (_) | |  |   <  __/ |  | |\  |  __/ |_
    \/  \/ \___/|_|  |_|\_\___|_|  |_| \_|\___|\__|

    Installer v5.0 - Bootstrap
EOF
echo -e "${COLOR_RESET}"

info "════════════════════════════════════════════════════════════════"
info "  Загрузка улучшенного инсталлятора WorkerNet v5.0"
info "════════════════════════════════════════════════════════════════"
echo ""

# Проверка root
if [ "$(id -u)" != "0" ]; then
    error "Скрипт должен быть запущен от root"
    error "Выполните: sudo $0"
    exit 1
fi

ok "Запущен от root"

# Проверка доступности сервера
info "Проверка доступности сервера..."
if curl -f -s --head --max-time 5 "$BASE_URL/install.sh" > /dev/null 2>&1; then
    ok "Сервер доступен: $BASE_URL"
else
    error "Сервер недоступен: $BASE_URL"
    error ""
    error "Возможные причины:"
    error "  1. Файлы еще не размещены на сервере"
    error "  2. Неверный URL (проверьте BASE_URL в скрипте)"
    error "  3. Нет интернет-соединения"
    error ""
    error "Для локальной установки:"
    error "  1. Скопируйте всю папку 'improved/' на сервер"
    error "  2. Запустите: cd improved && sudo ./install.sh"
    exit 1
fi

# Создать временную директорию
info "Создание директории: $DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# Список файлов для загрузки
FILES_TO_DOWNLOAD=(
    "install.sh"
    "install.conf.example.yml"
    "update_credentials.sh"
    "ИНСТРУКЦИЯ_ПОЛЬЗОВАТЕЛЯ.md"
    "ПОСЛЕ_УСТАНОВКИ.md"
    "lib/common.sh"
    "lib/logging.sh"
    "lib/config.sh"
    "lib/version.sh"
    "lib/interactive.sh"
    "lib/checks.sh"
    "lib/progress.sh"
    "lib/rollback.sh"
    "lib/firewall.sh"
    "lib/database.sh"
    "lib/cache.sh"
    "lib/queue.sh"
    "lib/backend.sh"
    "lib/webserver.sh"
    "lib/finalize.sh"
    "lib/postinstall.sh"
    "lib/tests.sh"
)

# Создать структуру директорий
mkdir -p lib

# Загрузить файлы
info "Загрузка файлов инсталлятора..."
echo ""

DOWNLOADED=0
FAILED=0

for file in "${FILES_TO_DOWNLOAD[@]}"; do
    url="$BASE_URL/$file"
    
    info "Загрузка: $file"
    
    if curl -f -s -o "$file" "$url"; then
        ok "  Загружен: $file"
        ((DOWNLOADED++))
    else
        error "  Не удалось загрузить: $file"
        ((FAILED++))
    fi
done

echo ""
info "════════════════════════════════════════════════════════════════"
info "Результат загрузки:"
info "  Загружено: $DOWNLOADED файлов"
if [ $FAILED -gt 0 ]; then
    error "  Не удалось: $FAILED файлов"
    error ""
    error "Некоторые файлы не загружены!"
    error "Проверьте доступность: $BASE_URL"
    exit 1
fi
info "════════════════════════════════════════════════════════════════"
echo ""

# Установить права на выполнение
chmod +x install.sh
chmod +x lib/*.sh

ok "Все файлы загружены успешно!"
echo ""

# Информация
info "════════════════════════════════════════════════════════════════"
info "  Инсталлятор готов к запуску!"
info "════════════════════════════════════════════════════════════════"
echo ""
info "Директория: $(pwd)"
info ""
info "Запустить установку:"
info "  ./install.sh --help         # Справка"
info "  ./install.sh                # Интерактивная установка"
info "  ./install.sh --version 4.x  # С выбором версии"
echo ""

# Спросить о немедленном запуске
read -p "Запустить установку сейчас? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Запуск установки..."
    echo ""
    exec ./install.sh
else
    info "Установка отложена"
    info "Для запуска выполните: cd $(pwd) && ./install.sh"
fi

