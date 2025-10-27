#!/bin/bash
# version.sh - Управление версиями WorkerNet
# WorkerNet Installer v5.0

# Поддерживаемые версии WorkerNet
VERSIONS=("3.x" "4.x" "5.x")
DESCRIPTIONS=("Стабильная версия (Legacy)" "Текущая стабильная (Рекомендуется)" "Новая версия с React + Go (В разработке)")
FEATURES=("PHP 8.3, PostgreSQL 15-16, Python 3.8+, 14 модулей интеграции" "PHP 8.3, PostgreSQL 16, Python 3.9+, 11 модулей, улучшенный UI" "React+MUI frontend, Go microservices (опционально), современный стек")
# Глобальная переменная выбранной версии
WORKERNET_VERSION=""

# Показать список версий
show_versions() {
    echo ""
    log_info "════════════════════════════════════════════════════════════════════════"
    log_info "  ВЫБОР ВЕТКИ WORKERNET"
    log_info "════════════════════════════════════════════════════════════════════════"
    echo ""
    
    local counter=1
    for i in "${!VERSIONS[@]}"; do
        local version="${VERSIONS[$i]}"
        local description="${DESCRIPTIONS[$i]}"
        local features="${FEATURES[$i]}"
        
        print_color "$COLOR_CYAN" "  $counter) WorkerNet $version"
        print_color "$COLOR_YELLOW" "     $description"
        print_color "$COLOR_GRAY" "     $features"
        echo ""
        
        ((counter++))
    done
    
    echo ""
}

# Интерактивный выбор версии
select_version_interactive() {
    show_versions
    
    local version_names=()
    for i in "${!VERSIONS[@]}"; do
        version_names+=("${VERSIONS[$i]} - ${DESCRIPTIONS[$i]}")
    done
    
    log_info "Выберите версию для установки:"
    
    PS3="Введите номер версии: "
    select choice in "${version_names[@]}" "Выход"; do
        case $REPLY in
            [1-3])
                local selected_version="${VERSIONS[$((REPLY-1))]}"
                WORKERNET_VERSION="$selected_version"
                
                echo ""
                ok "Выбрана версия: WorkerNet $WORKERNET_VERSION"
                log_info "Описание: ${DESCRIPTIONS[$((REPLY-1))]}"
                log_info "Возможности: ${FEATURES[$((REPLY-1))]}"
                echo ""
                
                return 0
                ;;
            4)
                log_info "Выход из установки"
                exit 0
                ;;
            *)
                log_warn "Неверный выбор. Пожалуйста, выберите 1, 2, 3 или 4"
                ;;
        esac
    done
}

# Получить префикс модулей для версии
get_module_prefix() {
    local version="${1:-$WORKERNET_VERSION}"
    echo "${VERSION_MODULE_PREFIX[$version]}"
}

# Проверить, поддерживается ли версия
is_version_supported() {
    local version="$1"
    
    [[ -n "${SUPPORTED_VERSIONS[$version]}" ]]
}

# Получить lock-значение для версии
get_lock_value() {
    local version="${1:-$WORKERNET_VERSION}"
    local major_minor=$(echo "$version" | tr -d '.')
    
    echo "successful-${major_minor}"
}

# Проверить совместимость версии с ОС
check_version_compatibility() {
    local version="${1:-$WORKERNET_VERSION}"
    local os_type=$(get_os_type)
    local os_version=$(get_os_version)
    
    # Все текущие версии поддерживают все ОС
    # В будущем можно добавить ограничения
    case $version in
        "3.x"|"4.x")
            # Поддерживают все ОС
            return 0
            ;;
        "5.x")
            # Новая версия может иметь особые требования
            if [ "$os_version" -lt 24 ] && [ "$os_type" = "ubuntu" ]; then
                log_warn "WorkerNet 5.x рекомендуется устанавливать на Ubuntu 24+"
                log_warn "На Ubuntu $os_version возможны проблемы совместимости"
            fi
            return 0
            ;;
        *)
            log_error "Неизвестная версия: $version"
            return 1
            ;;
    esac
}

# Получить URL для загрузки phar
get_phar_url() {
    local version="${1:-$WORKERNET_VERSION}"
    
    # По умолчанию один URL для всех версий
    echo "https://bill.workernet.ru:8443/install"
    
    # Для будущих версий можно разные URL:
    # case $version in
    #     "3.17")
    #         echo "https://bill.workernet.ru:8443/install-317"
    #         ;;
    #     "4.10")
    #         echo "https://bill.workernet.ru:8443/install-410"
    #         ;;
    #     "5.0")
    #         echo "https://bill.workernet.ru:8443/install-50"
    #         ;;
    # esac
}

# Показать информацию о версии
show_version_info() {
    local version="${1:-$WORKERNET_VERSION}"
    
    echo ""
    log_separator "="
    log_info "ИНФОРМАЦИЯ О ВЕРСИИ"
    log_separator "="
    echo ""
    
    print_color "$COLOR_CYAN" "  Версия: WorkerNet $version"
    print_color "$COLOR_YELLOW" "  Описание: ${SUPPORTED_VERSIONS[$version]}"
    print_color "$COLOR_GRAY" "  Возможности: ${VERSION_FEATURES[$version]}"
    print_color "$COLOR_BLUE" "  Префикс модулей: ${VERSION_MODULE_PREFIX[$version]}_*"
    
    echo ""
    log_separator "="
    echo ""
}

# Установить версию из параметра или интерактивно
setup_version() {
    # Если версия уже указана через параметр --version
    if [ -n "$WORKERNET_VERSION" ]; then
        if is_version_supported "$WORKERNET_VERSION"; then
            ok "Версия предварительно выбрана: $WORKERNET_VERSION"
            check_version_compatibility || return 1
            return 0
        else
            log_error "Неподдерживаемая версия: $WORKERNET_VERSION"
            log_info "Поддерживаемые версии: ${!SUPPORTED_VERSIONS[*]}"
            return 1
        fi
    fi
    
    # Интерактивный выбор
    select_version_interactive
    check_version_compatibility || return 1
    
    return 0
}

# Добавить новую версию (для будущего)
register_version() {
    local version="$1"
    local description="$2"
    local features="$3"
    local module_prefix="$4"
    
    SUPPORTED_VERSIONS["$version"]="$description"
    VERSION_FEATURES["$version"]="$features"
    VERSION_MODULE_PREFIX["$version"]="$module_prefix"
    VERSION_ORDER+=("$version")
    
    log_info "Зарегистрирована новая версия: $version"
}

# Экспортировать функции и переменные
export WORKERNET_VERSION
export -f show_versions
export -f select_version_interactive
export -f get_module_prefix
export -f is_version_supported
export -f get_lock_value
export -f check_version_compatibility
export -f get_phar_url
export -f show_version_info
export -f setup_version
export -f register_version

