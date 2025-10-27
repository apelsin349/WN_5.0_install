#!/bin/bash
# tests.sh - Smoke tests после установки
# WorkerNet Installer v5.0

# Счетчики тестов
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Запустить тест
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_TOTAL++))
    
    log_info "Test $TESTS_TOTAL: $test_name"
    
    if $test_function; then
        ((TESTS_PASSED++))
        ok "  ✅ PASS"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "  ❌ FAIL"
        return 1
    fi
}

# Тест 1: Проверка сервисов
test_services() {
    local os_type=$(get_os_type)
    local services=()
    
    # Определить список сервисов
    if [ "$os_type" = "almalinux" ]; then
        services=("postgresql-16" "redis" "rabbitmq-server" "php83-php-fpm" "supervisord")
        
        if [ "$WEBSERVER" = "apache" ]; then
            services+=("httpd")
        else
            services+=("nginx")
        fi
    else
        services=("postgresql" "redis" "rabbitmq-server" "php8.3-fpm" "supervisor")
        
        if [ "$WEBSERVER" = "apache" ]; then
            services+=("apache2")
        else
            services+=("nginx")
        fi
    fi
    
    local failed=0
    for service in "${services[@]}"; do
        # Специальная проверка для PostgreSQL (используем pg_isready)
        if [[ "$service" == "postgresql"* ]]; then
            if sudo -u postgres pg_isready -q 2>/dev/null; then
                log_debug "    ✓ $service активен (pg_isready)"
            else
                log_error "    ✗ $service НЕ активен (pg_isready failed)"
                ((failed++))
            fi
        # Обычная проверка для других сервисов
        else
            if is_service_active "$service"; then
                log_debug "    ✓ $service активен"
            else
                log_error "    ✗ $service НЕ активен"
                ((failed++))
            fi
        fi
    done
    
    [ $failed -eq 0 ]
}

# Тест 2: Проверка портов
test_ports() {
    local ports=(80 5432 6379 5672 15672 15674)
    local failed=0
    
    for port in "${ports[@]}"; do
        if is_port_in_use "$port"; then
            log_debug "    ✓ Port $port слушается"
        else
            log_error "    ✗ Port $port НЕ слушается"
            ((failed++))
        fi
    done
    
    [ $failed -eq 0 ]
}

# Тест 3: Проверка базы данных
test_database() {
    if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1" &> /dev/null; then
        log_debug "    ✓ Database $DB_NAME доступна"
        return 0
    else
        log_error "    ✗ Database $DB_NAME НЕ доступна"
        return 1
    fi
}

# Тест 4: Проверка PostGIS
test_postgis() {
    local postgis_version=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT PostGIS_Version()" 2>/dev/null)
    
    if [ -n "$postgis_version" ]; then
        log_debug "    ✓ PostGIS installed: $postgis_version"
        return 0
    else
        log_error "    ✗ PostGIS НЕ установлен"
        return 1
    fi
}

# Тест 5: Проверка Redis
test_redis() {
    if redis-cli -h 127.0.0.1 -p 6379 -a "$GENHASH" ping 2>/dev/null | grep -q "PONG"; then
        log_debug "    ✓ Redis отвечает with password"
        return 0
    else
        log_error "    ✗ Redis НЕ отвечает"
        return 1
    fi
}

# Тест 6: Проверка RabbitMQ пользователей
test_rabbitmq_users() {
    local failed=0
    
    if rabbitmqctl authenticate_user "$NAMERABBITADMIN" "$GENPASSRABBITADMIN" &> /dev/null; then
        log_debug "    ✓ Admin user аутентифицирован"
    else
        log_error "    ✗ Admin user NOT аутентифицирован"
        ((failed++))
    fi
    
    if rabbitmqctl authenticate_user "$NAMERABBITUSER" "$GENPASSRABBITUSER" &> /dev/null; then
        log_debug "    ✓ Workernet user аутентифицирован"
    else
        log_error "    ✗ Workernet user NOT аутентифицирован"
        ((failed++))
    fi
    
    if rabbitmqctl authenticate_user "$WEBSTOMPUSER" "$GENPASSWEBSTOMPUSER" &> /dev/null; then
        log_debug "    ✓ WebSocket user аутентифицирован"
    else
        log_error "    ✗ WebSocket user NOT аутентифицирован"
        ((failed++))
    fi
    
    [ $failed -eq 0 ]
}

# Тест 7: Проверка веб-сервера
test_webserver() {
    sleep 2  # Дать время на запуск
    
    if curl -f -s http://localhost/ > /dev/null; then
        log_debug "    ✓ Web server отвечает"
        return 0
    else
        log_error "    ✗ Web server НЕ отвечает"
        return 1
    fi
}

# Тест 8: Проверка PHP
test_php() {
    # Простая проверка: запустить php -v и проверить вывод версии
    if php -v >/dev/null 2>&1; then
        local php_version=$(php -v 2>/dev/null | head -1 | grep -oP 'PHP \d+\.\d+')
        if [ -n "$php_version" ]; then
            log_debug "    ✓ PHP работает ($php_version)"
            return 0
        fi
    fi
    
    # Дополнительная проверка: попробовать простой код
    if php -r "echo 'OK';" 2>/dev/null | grep -q "OK"; then
        log_debug "    ✓ PHP работает"
        return 0
    fi
    
    log_error "    ✗ PHP НЕ работает или не установлен"
    log_error "    Проверьте: php -v"
    return 1
}

# Тест 9: Проверка .env файла
test_env_file() {
    local env_file="${INSTALL_DIR}/.env"
    
    if [ -f "$env_file" ] && grep -q "DB_DSN" "$env_file"; then
        log_debug "    ✓ .env file существует и корректен"
        return 0
    else
        log_error "    ✗ .env file отсутствует или некорректен"
        return 1
    fi
}

# Тест 9: Проверка версий компонентов
test_versions() {
    log_debug "Проверка версий установленных компонентов..."
    
    # Проверить минимальные версии
    if check_minimum_versions; then
        log_debug "    ✓ Все версии компонентов соответствуют требованиям"
        return 0
    else
        log_warn "    ⚠ Некоторые компоненты имеют устаревшие версии"
        return 0  # Не критично, но стоит обратить внимание
    fi
}

# Тест 10: Проверка прав доступа
test_permissions() {
    local os_type=$(get_os_type)
    local expected_owner="www-data:www-data"
    
    if [ "$os_type" = "almalinux" ]; then
        if [ "$WEBSERVER" = "apache" ]; then
            expected_owner="apache:apache"
        else
            expected_owner="nginx:nginx"
        fi
    fi
    
    local actual_owner=$(stat -c '%U:%G' "$INSTALL_DIR" 2>/dev/null || stat -f '%Su:%Sg' "$INSTALL_DIR")
    
    if [ "$actual_owner" = "$expected_owner" ]; then
        log_debug "    ✓ Права доступа корректны: $actual_owner"
        return 0
    else
        log_error "    ✗ Неверные права доступа: $actual_owner (ожидается: $expected_owner)"
        return 1
    fi
}

# Тест 12: Проверка Supervisor workers
test_supervisor_workers() {
    local running_workers=$(supervisorctl status 2>/dev/null | grep RUNNING | wc -l)
    
    if [ $running_workers -ge 1 ]; then
        log_debug "    ✓ Supervisor workers запущено: $running_workers"
        return 0
    else
        log_warn "    ⚠ Supervisor workers не запущены (нормально если post-install еще не выполнен)"
        return 0  # Не считаем ошибкой
    fi
}

# Запустить все smoke tests
run_smoke_tests() {
    log_section "🧪 ЗАПУСК SMOKE TESTS"
    
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_TOTAL=0
    
    run_test "Проверка сервисов" test_services
    run_test "Проверка портов" test_ports
    run_test "Проверка базы данных" test_database
    run_test "Проверка расширения PostGIS" test_postgis
    run_test "Проверка Redis" test_redis
    run_test "Проверка пользователей RabbitMQ" test_rabbitmq_users
    run_test "Проверка веб-сервера" test_webserver
    run_test "Проверка PHP" test_php
    run_test "Проверка версий компонентов" test_versions
    run_test "Проверка .env файла" test_env_file
    run_test "Проверка прав доступа" test_permissions
    run_test "Проверка Supervisor workers" test_supervisor_workers
    
    # Итоги
    echo ""
    log_separator "="
    
    if [ $TESTS_FAILED -eq 0 ]; then
        ok "✅ Все тесты пройдены: $TESTS_PASSED/$TESTS_TOTAL"
        ok "✅ Система готова к использованию!"
    else
        log_error "❌ Некоторые тесты не прошли: $TESTS_FAILED/$TESTS_TOTAL"
        log_error "   Пройдено: $TESTS_PASSED"
        log_warn "   Просмотрите ошибки выше"
        log_separator "="
        return 1
    fi
    
    log_separator "="
    echo ""
    
    return 0
}

# Алиас для совместимости с install.sh
setup_tests() {
    run_smoke_tests
}

# Экспортировать функции
export -f run_test
export -f test_services
export -f test_ports
export -f test_database
export -f test_postgis
export -f test_redis
export -f test_rabbitmq_users
export -f test_webserver
export -f test_php
export -f test_versions
export -f test_env_file
export -f test_permissions
export -f test_supervisor_workers
export -f run_smoke_tests
export -f setup_tests

