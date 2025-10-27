#!/bin/bash
# interactive.sh - Интерактивные запросы при установке
# WorkerNet Installer v5.0

# Интерактивный выбор веб-сервера
select_webserver_interactive() {
    # Если уже указан через параметр - пропустить
    if [ -n "${WEBSERVER:-}" ]; then
        log_info "Веб-сервер указан через параметр: $WEBSERVER"
        return 0
    fi
    
    log_section "🌐 ВЫБОР ВЕБ-СЕРВЕРА"
    
    echo ""
    log_info "Выберите веб-сервер для установки:"
    echo ""
    log_info "  1) Apache"
    log_info "     - Стабильный, популярный"
    log_info "     - Поддержка .htaccess"
    log_info "     - Рекомендуется для большинства случаев"
    echo ""
    log_info "  2) NGINX"
    log_info "     - Быстрый, современный"
    log_info "     - Меньше потребление памяти"
    log_info "     - Отличная производительность"
    echo ""
    log_info "  3) Выход"
    echo ""
    
    local choice
    while true; do
        read -p "Введите номер опции (1-3): " choice
        
        case $choice in
            1)
                WEBSERVER="apache"
                ok "Выбран веб-сервер: Apache"
                break
                ;;
            2)
                WEBSERVER="nginx"
                ok "Выбран веб-сервер: NGINX"
                break
                ;;
            3)
                log_info "Установка отменена пользователем"
                exit 0
                ;;
            *)
                log_warn "Неверный выбор. Пожалуйста, введите 1, 2 или 3."
                ;;
        esac
    done
    
    echo ""
    export WEBSERVER
    return 0
}

# Интерактивный выбор домена
select_domain_interactive() {
    # Если уже указан через параметр - пропустить
    if [ -n "${DOMAIN:-}" ]; then
        log_info "Домен указан через параметр: $DOMAIN"
        return 0
    fi
    
    log_section "🏠 НАСТРОЙКА ДОМЕНА"
    
    # Показать IP адреса
    echo ""
    log_info "IP-адреса сетевых интерфейсов:"
    local ips=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.0\.0\.1$' | head -5)
    if [ -n "$ips" ]; then
        echo "$ips" | while read ip; do
            log_info "  - $ip"
        done
    else
        log_warn "Не удалось определить IP адреса"
    fi
    echo ""
    
    log_info "Выберите действие:"
    echo ""
    log_info "  1) default"
    log_info "     По умолчанию для всех доменов (рекомендуется)"
    log_info "     Будет использован: _"
    echo ""
    log_info "  2) custom"
    log_info "     Указать конкретное доменное имя или IP адрес"
    echo ""
    log_info "  3) Выход"
    echo ""
    
    local choice
    while true; do
        read -p "Введите номер опции (1-3): " choice
        
        case $choice in
            1)
                DOMAIN="_"
                ok "Выбран домен по умолчанию: _ (все домены)"
                break
                ;;
            2)
                echo ""
                read -p "Введите доменное имя или IP адрес: " DOMAIN
                if [ -z "$DOMAIN" ]; then
                    log_warn "Домен не может быть пустым"
                    continue
                fi
                ok "Вы ввели: $DOMAIN"
                break
                ;;
            3)
                log_info "Установка отменена пользователем"
                exit 0
                ;;
            *)
                log_warn "Неверный выбор. Пожалуйста, введите 1, 2 или 3."
                ;;
        esac
    done
    
    echo ""
    export DOMAIN
    return 0
}

# Подтверждение параметров установки
confirm_installation_parameters() {
    log_section "📋 ПОДТВЕРЖДЕНИЕ ПАРАМЕТРОВ"
    
    echo ""
    log_info "════════════════════════════════════════════════════════════════"
    log_info "  ПАРАМЕТРЫ УСТАНОВКИ:"
    log_info "════════════════════════════════════════════════════════════════"
    echo ""
    log_info "  Версия WorkerNet:        $WORKERNET_VERSION"
    log_info "  Префикс модулей:         $(get_module_prefix)_*"
    log_info "  Веб-сервер:              ${WEBSERVER:-не указан}"
    log_info "  Домен:                   ${DOMAIN:-не указан}"
    log_info "  Директория установки:    $INSTALL_DIR"
    log_info "  Операционная система:    $(get_os_type) $(get_os_version)"
    echo ""
    log_info "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Запрос подтверждения
    read -p "Продолжить установку с этими параметрами? (y/n): " -n 1 -r
    echo ""
    echo ""
    
    if [[ $REPLY =~ ^[YyДд]$ ]]; then
        ok "Параметры подтверждены, начинаем установку..."
        echo ""
        return 0
    else
        log_info "Установка отменена пользователем"
        log_info ""
        log_info "Для неинтерактивной установки используйте параметры:"
        log_info "  sudo ./install.sh --version 4.10 --webserver apache --domain example.com"
        log_info ""
        exit 0
    fi
}

# Интерактивный выбор компонентов (опционально)
select_components_interactive() {
    # Пока все компоненты обязательны
    # В будущих версиях можно добавить выбор опциональных компонентов
    
    log_info "Все компоненты будут установлены:"
    log_info "  ✓ PostgreSQL 16 + PostGIS 3"
    log_info "  ✓ Redis 7"
    log_info "  ✓ RabbitMQ 3.x + Erlang"
    log_info "  ✓ PHP 8.3"
    log_info "  ✓ Python 3"
    log_info "  ✓ ${WEBSERVER:-Apache/NGINX}"
    log_info "  ✓ Supervisor"
    echo ""
    
    return 0
}

# Главная функция интерактивной настройки
setup_interactive() {
    # 1. Выбор веб-сервера (интерактив)
    select_webserver_interactive || return 1
    
    # 2. Выбор домена (интерактив)
    select_domain_interactive || return 1
    
    # 3. Применить значения из конфига, если не установлены
    if command -v apply_config_fallbacks &>/dev/null; then
        apply_config_fallbacks
    fi
    
    # 4. Установить значения по умолчанию, если все еще не заданы
    if [ -z "$WEBSERVER" ]; then
        WEBSERVER="apache"
        log_warn "Веб-сервер не выбран, используется по умолчанию: apache"
    fi
    
    if [ -z "$DOMAIN" ]; then
        DOMAIN="_"
        log_warn "Домен не выбран, используется по умолчанию: _ (все домены)"
    fi
    
    # 5. Подтверждение параметров
    confirm_installation_parameters || return 1
    
    return 0
}

# Экспортировать функции
export -f select_webserver_interactive
export -f select_domain_interactive
export -f confirm_installation_parameters
export -f select_components_interactive
export -f setup_interactive

