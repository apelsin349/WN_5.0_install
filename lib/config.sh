#!/bin/bash
# config.sh - Загрузка конфигурации из YAML файла
# WorkerNet Installer v5.0

# Валидация конфигурации
validate_config() {
    local config_file="$1"
    local errors=0
    
    log_info "Валидация конфигурации..."
    
    if [ ! -f "$config_file" ]; then
        log_error "Конфигурационный файл не найден: $config_file"
        return 1
    fi
    
    # Проверка синтаксиса YAML (базовая)
    if ! grep -q "^[a-zA-Z]" "$config_file"; then
        log_error "Конфигурационный файл пуст или имеет неверный формат"
        ((errors++))
    fi
    
    # Проверка обязательных секций
    local required_sections=("workernet" "database" "redis" "rabbitmq" "php" "webserver")
    for section in "${required_sections[@]}"; do
        if ! grep -q "^${section}:" "$config_file"; then
            log_warn "Отсутствует секция: $section"
            ((errors++))
        fi
    done
    
    # Проверка значений в секции workernet
    if grep -q "^workernet:" "$config_file"; then
        # Проверка версии
        local version=$(grep -A 10 "^workernet:" "$config_file" | grep "version:" | awk '{print $2}' | tr -d '"')
        if [ -n "$version" ]; then
            if [[ ! "$version" =~ ^[3-5]\.x$ ]]; then
                log_error "Неверная версия WorkerNet: $version (должна быть 3.x, 4.x или 5.x)"
                ((errors++))
            fi
        fi
        
        # Проверка веб-сервера
        local webserver=$(grep -A 10 "^workernet:" "$config_file" | grep "webserver:" | awk '{print $2}' | tr -d '"')
        if [ -n "$webserver" ]; then
            if [[ ! "$webserver" =~ ^(apache|nginx)$ ]]; then
                log_error "Неверный веб-сервер: $webserver (должен быть apache или nginx)"
                ((errors++))
            fi
        fi
    fi
    
    # Проверка значений в секции database
    if grep -q "^database:" "$config_file"; then
        local db_port=$(grep -A 10 "^database:" "$config_file" | grep "port:" | awk '{print $2}' | tr -d '"')
        if [ -n "$db_port" ]; then
            if [[ ! "$db_port" =~ ^[0-9]+$ ]] || [ "$db_port" -lt 1024 ] || [ "$db_port" -gt 65535 ]; then
                log_error "Неверный порт базы данных: $db_port (должен быть 1024-65535)"
                ((errors++))
            fi
        fi
    fi
    
    # Проверка значений в секции redis
    if grep -q "^redis:" "$config_file"; then
        local redis_port=$(grep -A 10 "^redis:" "$config_file" | grep "port:" | awk '{print $2}' | tr -d '"')
        if [ -n "$redis_port" ]; then
            if [[ ! "$redis_port" =~ ^[0-9]+$ ]] || [ "$redis_port" -lt 1024 ] || [ "$redis_port" -gt 65535 ]; then
                log_error "Неверный порт Redis: $redis_port (должен быть 1024-65535)"
                ((errors++))
            fi
        fi
    fi
    
    # Проверка значений в секции php
    if grep -q "^php:" "$config_file"; then
        local php_version=$(grep -A 10 "^php:" "$config_file" | grep "version:" | awk '{print $2}' | tr -d '"')
        if [ -n "$php_version" ]; then
            if [[ ! "$php_version" =~ ^8\.[0-9]+$ ]]; then
                log_error "Неверная версия PHP: $php_version (должна быть 8.x)"
                ((errors++))
            fi
        fi
    fi
    
    # Итоги валидации
    if [ $errors -eq 0 ]; then
        log_info "✅ Конфигурация валидна"
        return 0
    else
        log_error "❌ Обнаружено $errors ошибок в конфигурации"
        log_error "Исправьте ошибки и запустите установку снова"
        return 1
    fi
}

# Простой парсер YAML для конфигурационного файла
parse_yaml_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_error "Конфигурационный файл не найден: $config_file"
        return 1
    fi
    
    log_info "Загрузка конфигурации из: $config_file"
    
    # Парсим YAML построчно (простая реализация)
    while IFS=: read -r key value; do
        # Пропустить комментарии и пустые строки
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Удалить пробелы в начале и конце
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/"//g;s/'\''//g')
        
        # Пропустить секции (без двоеточия в значении)
        [[ -z "$value" ]] && continue
        
        # Сохранить значения из конфига в отдельные переменные
        # НЕ перезаписываем основные переменные! Только сохраняем для fallback
        case "$key" in
            version)
                CONFIG_VERSION="$value"
                log_info "  Версия из конфига: $value (fallback)"
                ;;
            domain)
                if [ "$value" = "default" ]; then
                    CONFIG_DOMAIN="_"
                else
                    CONFIG_DOMAIN="$value"
                fi
                log_info "  Домен из конфига: $CONFIG_DOMAIN (fallback)"
                ;;
            webserver)
                CONFIG_WEBSERVER="$value"
                log_info "  Веб-сервер из конфига: $value (fallback)"
                ;;
            install_dir)
                if [ -z "${INSTALL_DIR:-}" ] || [ "$INSTALL_DIR" = "/var/www/workernet" ]; then
                    INSTALL_DIR="$value"
                    log_info "  Директория из конфига: $value"
                fi
                ;;
            name)
                if [ -z "${DATABASE_NAME:-}" ]; then
                    DATABASE_NAME="$value"
                fi
                ;;
            user)
                if [ -z "${DATABASE_USER:-}" ]; then
                    DATABASE_USER="$value"
                fi
                ;;
            locale)
                if [ -z "${DATABASE_LOCALE:-}" ]; then
                    DATABASE_LOCALE="$value"
                fi
                ;;
            skip_checks)
                if [ "$value" = "true" ]; then
                    SKIP_CHECKS=true
                    log_warn "  Пропуск проверок включен из конфига"
                fi
                ;;
        esac
    done < "$config_file"
    
    # Экспортировать переменные конфига (для fallback)
    export CONFIG_VERSION CONFIG_DOMAIN CONFIG_WEBSERVER
    export INSTALL_DIR DATABASE_NAME DATABASE_USER DATABASE_LOCALE
    export SKIP_CHECKS
    
    ok "Конфигурация загружена из $config_file (используется как fallback)"
    return 0
}

# Применить значения из конфига как fallback (после интерактива)
apply_config_fallbacks() {
    local applied=false
    
    # Применить версию из конфига, если не задана
    if [ -z "${WORKERNET_VERSION:-}" ] && [ -n "${CONFIG_VERSION:-}" ]; then
        WORKERNET_VERSION="$CONFIG_VERSION"
        log_info "Используется версия из конфига: $CONFIG_VERSION"
        applied=true
    fi
    
    # Применить веб-сервер из конфига, если не задан
    if [ -z "${WEBSERVER:-}" ] && [ -n "${CONFIG_WEBSERVER:-}" ]; then
        WEBSERVER="$CONFIG_WEBSERVER"
        log_info "Используется веб-сервер из конфига: $CONFIG_WEBSERVER"
        applied=true
    fi
    
    # Применить домен из конфига, если не задан
    if [ -z "${DOMAIN:-}" ] && [ -n "${CONFIG_DOMAIN:-}" ]; then
        DOMAIN="$CONFIG_DOMAIN"
        log_info "Используется домен из конфига: $CONFIG_DOMAIN"
        applied=true
    fi
    
    if [ "$applied" = true ]; then
        echo ""
        ok "Применены значения из конфигурационного файла"
    fi
    
    # Экспортировать финальные значения
    export WORKERNET_VERSION DOMAIN WEBSERVER
    
    return 0
}

# Загрузить конфигурацию если указан файл
load_config() {
    if [ -n "${CONFIG_FILE:-}" ]; then
        if [ -f "$CONFIG_FILE" ]; then
            parse_yaml_config "$CONFIG_FILE" || return 1
        else
            log_error "Конфигурационный файл не найден: $CONFIG_FILE"
            return 1
        fi
    fi
    return 0
}

# Показать загруженную конфигурацию
show_loaded_config() {
    if [ -n "${CONFIG_FILE:-}" ]; then
        echo ""
        log_info "Загруженная конфигурация:"
        [ -n "${WORKERNET_VERSION:-}" ] && log_info "  Версия: $WORKERNET_VERSION"
        [ -n "${WEBSERVER:-}" ] && log_info "  Веб-сервер: $WEBSERVER"
        [ -n "${DOMAIN:-}" ] && log_info "  Домен: $DOMAIN"
        [ -n "${INSTALL_DIR:-}" ] && log_info "  Директория: $INSTALL_DIR"
        echo ""
    fi
}

# Экспортировать функции
export -f validate_config
export -f parse_yaml_config
export -f apply_config_fallbacks
export -f load_config
export -f show_loaded_config

