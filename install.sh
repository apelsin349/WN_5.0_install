#!/bin/bash
# install.sh - Главный установочный скрипт WorkerNet v5.0
# WorkerNet Installer - Improved Edition

set -euo pipefail

# Определить директорию скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Загрузить библиотеки
source "$LIB_DIR/common.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/version.sh"
source "$LIB_DIR/interactive.sh"
source "$LIB_DIR/checks.sh"
source "$LIB_DIR/progress.sh"
source "$LIB_DIR/rollback.sh"
source "$LIB_DIR/firewall.sh"
source "$LIB_DIR/database.sh"
source "$LIB_DIR/cache.sh"
source "$LIB_DIR/queue.sh"
source "$LIB_DIR/backend.sh"
source "$LIB_DIR/webserver.sh"
source "$LIB_DIR/finalize.sh"
source "$LIB_DIR/postinstall.sh"
source "$LIB_DIR/tests.sh"

# Параметры по умолчанию
SKIP_CHECKS=false
NO_ROLLBACK=false
FORCE_INSTALL=false
FORCE_WEBSERVER_CONFIG=false
CONFIG_FILE=""
# WORKERNET_VERSION будет установлен в setup_version()

# Обработка аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --webserver)
            WEBSERVER="$2"
            shift 2
            ;;
        --version)
            WORKERNET_VERSION="$2"
            shift 2
            ;;
        --skip-checks)
            SKIP_CHECKS=true
            shift
            ;;
        --no-rollback)
            NO_ROLLBACK=true
            shift
            ;;
        --force)
            FORCE_INSTALL=true
            shift
            ;;
        --force-webserver-config)
            FORCE_WEBSERVER_CONFIG=true
            shift
            ;;
        --debug)
            export LOG_LEVEL=0
            shift
            ;;
        --help)
            cat <<EOF
WorkerNet Installer v${SCRIPT_VERSION} - Улучшенная версия

Использование: $0 [ОПЦИИ]

Опции:
  --config FILE              Использовать конфигурационный файл
  --version VERSION          Указать версию WorkerNet (3.x, 4.x, 5.x)
  --domain DOMAIN            Указать домен (по умолчанию: _)
  --webserver SERVER         Выбрать веб-сервер (apache/nginx)
  --force                    Автоматически остановить конфликтующие сервисы
  --force-webserver-config   Перезаписать конфиг веб-сервера без вопросов
  --skip-checks              Пропустить pre-flight проверки (НЕ РЕКОМЕНДУЕТСЯ)
  --no-rollback              Отключить автоматический откат
  --debug                    Включить DEBUG логирование
  --help                     Показать эту справку

Переменные окружения:
  LOG_LEVEL             Уровень логирования (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR)
  ROLLBACK_ENABLED      Включить/отключить rollback (true/false)
  INSTALL_DIR           Директория установки (по умолчанию: /var/www/workernet)

Примеры:
  # Базовая установка (интерактивный выбор версии)
  sudo $0

  # С указанием версии
  sudo $0 --version 4.x

  # С конфигурационным файлом
  sudo $0 --config install.conf.yml

  # Полная конфигурация
  sudo $0 --version 4.x --domain workernet.example.com --webserver apache

  # DEBUG режим
  sudo LOG_LEVEL=0 $0 --debug

Поддерживаемые версии: 3.x (Legacy), 4.x (Рекомендуется), 5.x (В разработке)

Подробнее см. README.md
EOF
            exit 0
            ;;
        *)
            log_error "Неизвестная опция: $1"
            log_info "Используйте --help для справки"
            exit 1
            ;;
    esac
done

# Главная функция
main() {
    local start_time=$(date +%s)
    
    # Инициализация
    init_logging
    print_logo
    print_system_info
    init_progress
    
    # Установить rollback trap
    if [ "$NO_ROLLBACK" != "true" ]; then
        setup_rollback_trap
    fi
    
    # Загрузить конфигурацию (если указана) - ДО интерактивных запросов
    load_config || exit 1
    show_loaded_config
    
    # Выбор версии WorkerNet (если не задана в конфиге)
    setup_version || exit 1
    show_version_info
    
    # Интерактивная настройка (если не задано в конфиге)
    setup_interactive || exit 1
    
    # Экспортировать флаги для модулей
    export FORCE_INSTALL
    export FORCE_WEBSERVER_CONFIG
    
    # Pre-flight checks
    if [ "$SKIP_CHECKS" != "true" ]; then
        if [ "$FORCE_INSTALL" = "true" ]; then
            log_info "Режим --force: конфликтующие сервисы будут остановлены автоматически"
        fi
        run_preflight_checks || exit 1
    else
        log_warn "Пропуск предварительных проверок (--skip-checks)"
    fi
    
    # Начать установку
    log_section "🚀 НАЧАЛО УСТАНОВКИ"
    
    # Создать lock-файл
    mkdir -p "$LOCK_DIR"
    touch "$LOCK_FILE"
    
    # Этап 1: Настройка домена
    if [ "$DOMAIN" = "auto" ] || [ -z "$DOMAIN" ]; then
        log_info "Настройка домена"
        log_info "IP-адреса сетевых интерфейсов:"
        ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.0\.0\.1$'
        echo ""
        log_info "Выберите вариант домена:"
        log_info "  1) default - Использовать '_' для всех доменов"
        log_info "  2) custom - Указать доменное имя или IP адрес"
        
        select choice in "default" "custom"; do
            case $choice in
                "default")
                    DOMAIN="_"
                    log_info "Используется домен по умолчанию для всех"
                    break
                    ;;
                "custom")
                    read -p "Введите доменное имя или IP адрес: " DOMAIN
                    log_info "Используется домен: $DOMAIN"
                    break
                    ;;
                *)
                    log_warn "Неверный выбор"
                    ;;
            esac
        done
    fi
    
    # Этап 2: Firewall
    setup_firewall || return 1
    
    # Этап 3: База данных
    setup_database || return 1
    
    # Этап 4: Кэш
    setup_cache || return 1
    
    # Этап 5: Очереди
    setup_queue || return 1
    
    # Этап 6: Backend
    setup_backend || return 1
    
    # Этап 7: Веб-сервер
    setup_webserver || return 1
    
    # Этап 8: Финализация
    finalize_installation || return 1
    
    # Этап 9: Post-install конфигурация
    show_progress "Post-install configuration"
    setup_postinstall || log_warn "Post-install конфигурация не завершена (выполните шаги вручную)"
    
    # Этап 10: Тесты
    show_progress "Запуск smoke tests"
    run_smoke_tests || log_warn "Некоторые smoke tests не прошли, но установка может быть функциональная"
    
    # Записать финальную информацию о версии
    log_info ""
    log_info "Установленная версия: WorkerNet $WORKERNET_VERSION"
    log_info "Префикс модулей: $(get_module_prefix)_*"
    
    # Записать финальный lock файл для успешной установки
    local version_num="${WORKERNET_VERSION//./}"  # 4.x → 4x
    echo "successful-${version_num}" > "$LOCK_FILE"
    log_info "Lock файл обновлён: successful-${version_num}"
    
    # Отключить rollback при успешном завершении
    disable_rollback
    
    # Включить обратно unattended-upgrades (если был остановлен)
    re_enable_unattended_upgrades
    
    # Итоги
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    show_installation_summary true
    finalize_logging true $duration
    
    return 0
}

# Запуск
main "$@"

