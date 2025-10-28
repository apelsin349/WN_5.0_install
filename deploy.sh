#!/bin/bash
# deploy.sh - Скрипт для развертывания инсталлятора на целевом сервере
# WorkerNet Installer v5.0
# 
# Использование:
#   Способ 1 (локальное копирование):
#     cp -r WN_5.0_install/ /tmp/workernet_installer/
#     cd /tmp/workernet_installer/
#     sudo ./install.sh
#
#   Способ 2 (через SCP):
#     tar czf WN_5.0_install.tar.gz WN_5.0_install/
#     scp WN_5.0_install.tar.gz root@server:/tmp/
#     ssh root@server "cd /tmp && tar xzf WN_5.0_install.tar.gz && cd WN_5.0_install && ./install.sh"
#
#   Способ 3 (этот скрипт - копирование на веб-сервер):
#     sudo ./deploy.sh /var/www/html/WN_5.0_install

set -uo pipefail

# Цвета
COLOR_GREEN="\033[1;32m"
COLOR_BLUE="\033[1;34m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_RESET="\033[0m"

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

    Installer v5.0 - Deploy Script
EOF
echo -e "${COLOR_RESET}"

info "════════════════════════════════════════════════════════════════"
info "  Развертывание улучшенного инсталлятора WorkerNet v5.0"
info "════════════════════════════════════════════════════════════════"
echo ""

# Проверка аргументов
if [ $# -eq 0 ]; then
    error "Не указана целевая директория"
    echo ""
    echo "Использование:"
    echo "  sudo $0 <целевая_директория>"
    echo ""
    echo "Примеры:"
    echo "  # Развернуть на веб-сервер для удаленной установки:"
    echo "  sudo $0 /var/www/html/WN_5.0_install"
    echo ""
    echo "  # Развернуть локально для установки:"
    echo "  sudo $0 /tmp/workernet_installer"
    echo ""
    exit 1
fi

TARGET_DIR="$1"

# Проверка root
if [ "$(id -u)" != "0" ]; then
    error "Скрипт должен быть запущен от root"
    error "Выполните: sudo $0 $TARGET_DIR"
    exit 1
fi

ok "Запущен от root"

# Получить директорию скрипта
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
info "Директория инсталлятора: $SCRIPT_DIR"

# Файлы для копирования
FILES_TO_COPY=(
    "bootstrap.sh"
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

# Создать целевую директорию
info "Создание директории: $TARGET_DIR"
mkdir -p "$TARGET_DIR/lib"

# Копировать файлы
info "Копирование файлов..."
echo ""

COPIED=0
FAILED=0

for file in "${FILES_TO_COPY[@]}"; do
    source_file="$SCRIPT_DIR/$file"
    target_file="$TARGET_DIR/$file"
    
    info "Копирование: $file"
    
    if [ -f "$source_file" ]; then
        if cp "$source_file" "$target_file"; then
            ok "  Скопирован: $file"
            ((COPIED++))
        else
            error "  Не удалось скопировать: $file"
            ((FAILED++))
        fi
    else
        error "  Файл не найден: $source_file"
        ((FAILED++))
    fi
done

echo ""
info "════════════════════════════════════════════════════════════════"
info "Результат копирования:"
info "  Скопировано: $COPIED файлов"
if [ $FAILED -gt 0 ]; then
    error "  Не удалось: $FAILED файлов"
    error ""
    error "Некоторые файлы не скопированы!"
    exit 1
fi
info "════════════════════════════════════════════════════════════════"
echo ""

# Установить права
info "Установка прав доступа..."
chmod +x "$TARGET_DIR/bootstrap.sh"
chmod +x "$TARGET_DIR/install.sh"
chmod +x "$TARGET_DIR/lib/"*.sh
ok "Права установлены"
echo ""

# Установить владельца (для веб-сервера)
if [[ "$TARGET_DIR" == /var/www/* ]]; then
    info "Установка владельца www-data (веб-сервер)..."
    chown -R www-data:www-data "$TARGET_DIR"
    ok "Владелец установлен: www-data"
    echo ""
fi

ok "Все файлы скопированы успешно!"
echo ""

# Информация о следующих шагах
info "════════════════════════════════════════════════════════════════"
info "  Что дальше?"
info "════════════════════════════════════════════════════════════════"
echo ""

if [[ "$TARGET_DIR" == /var/www/* ]]; then
    # Веб-сервер
    info "✅ Файлы развернуты на веб-сервере"
    echo ""
    info "Теперь на целевых серверах можно запустить:"
    echo ""
    echo "  curl -O http://$(hostname -f | sed 's|^.*//||')/$(basename $TARGET_DIR)/bootstrap.sh && \\"
    echo "  chmod +x bootstrap.sh && \\"
    echo "  sudo ./bootstrap.sh"
    echo ""
    info "Или напрямую:"
    echo ""
    echo "  curl -O http://YOUR_SERVER_IP/$(basename $TARGET_DIR)/bootstrap.sh && \\"
    echo "  chmod +x bootstrap.sh && \\"
    echo "  sudo ./bootstrap.sh"
    echo ""
else
    # Локальная директория
    info "✅ Файлы скопированы локально"
    echo ""
    info "Для запуска установки:"
    echo ""
    echo "  cd $TARGET_DIR"
    echo "  sudo ./install.sh"
    echo ""
    info "Или с выбором версии:"
    echo ""
    echo "  cd $TARGET_DIR"
    echo "  sudo ./install.sh --version 4.x"
    echo ""
fi

info "════════════════════════════════════════════════════════════════"
echo ""

ok "Развертывание завершено! 🎉"

