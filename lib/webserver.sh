#!/bin/bash
# webserver.sh - Установка Apache/NGINX
# WorkerNet Installer v5.0

# Выбор веб-сервера
select_webserver() {
    if [ -n "$WEBSERVER" ] && [ "$WEBSERVER" != "auto" ]; then
        log_info "Веб-сервер предварительно выбран: $WEBSERVER"
        return 0
    fi
    
    log_info "Выберите веб-сервер для установки:"
    log_info "  1) Apache (recommended for ease)"
    log_info "  2) NGINX (recommended for performance)"
    
    select webserver in "Apache" "NGINX"; do
        case $webserver in
            "Apache")
                WEBSERVER="apache"
                log_info "Выбран: Apache"
                break
                ;;
            "NGINX")
                WEBSERVER="nginx"
                log_info "Выбран: NGINX"
                break
                ;;
            *)
                log_warn "Неверный ввод, пожалуйста выберите 1 or 2"
                ;;
        esac
    done
}

# Установка Apache
install_apache() {
    log_section "🌐 УСТАНОВКА APACHE"
    
    show_progress "Установка Apache"
    
    # Проверка idempotent
    if command_exists apache2 || command_exists httpd; then
        ok "Apache уже установлен, пропускаем"
        return 0
    fi
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            timed_run "Установка Apache2" \
                "apt install -y apache2"
            INSTALLED_PACKAGES+=("apache2")
            STARTED_SERVICES+=("apache2")
            
            # Включить модули
            a2enmod rewrite
            a2enconf php8.3-fpm
            a2enmod proxy_fcgi setenvif
            a2enmod proxy proxy_wstunnel
            ;;
        almalinux)
            timed_run "Установка Apache (httpd)" \
                "dnf install -y httpd"
            INSTALLED_PACKAGES+=("httpd")
            
            run_cmd "systemctl enable httpd"
            run_cmd "systemctl start httpd"
            STARTED_SERVICES+=("httpd")
            ;;
    esac
    
    ok "Apache установлен успешно"
    return 0
}

# Настройка Apache
configure_apache() {
    log_info "Настройка Apache..."
    
    local os_type=$(get_os_type)
    local docroot="${INSTALL_DIR}/public"
    local domain_name="$DOMAIN"
    
    if [ "$domain_name" = "_" ]; then
        domain_name="_"
    fi
    
    # Путь к конфигурации
    local apache_conf
    local php_socket
    local log_dir
    
    if [ "$os_type" = "almalinux" ]; then
        apache_conf="/etc/httpd/conf.d/workernet.conf"
        php_socket="unix:/var/opt/remi/php83/run/php-fpm/www.sock|fcgi://localhost"
        log_dir="/var/log/httpd"
    else
        apache_conf="/etc/apache2/sites-available/workernet.conf"
        php_socket="unix:/run/php/php8.3-fpm.sock|fcgi://localhost"
        log_dir="/var/log/apache2"
    fi
    
    # Проверить существующий конфиг и спросить о перезаписи
    if [ -f "$apache_conf" ]; then
        log_warn "⚠️  Конфигурация Apache уже существует: $apache_conf"
        
        # Если флаг --force-webserver-config - перезаписать без вопросов
        if [ "${FORCE_WEBSERVER_CONFIG:-false}" = "true" ]; then
            local backup_name="${apache_conf}.backup.$(date +%Y%m%d_%H%M%S)"
            log_warn "Флаг --force-webserver-config: создаём backup и перезаписываем"
            cp "$apache_conf" "$backup_name"
            log_info "Backup создан: $backup_name"
        # Иначе - спросить пользователя
        else
            echo ""
            log_warn "ВНИМАНИЕ: Текущая конфигурация будет перезаписана!"
            log_info "Ваши изменения могут быть потеряны."
            echo ""
            
            read -p "Перезаписать конфигурацию Apache? (y/n): " -n 1 -r
            echo ""
            echo ""
            
            if [[ ! $REPLY =~ ^[YyДд]$ ]]; then
                log_info "Конфигурация Apache оставлена без изменений"
                log_info "Используется существующий файл: $apache_conf"
                
                # Запустить Apache если он остановлен (важно при переустановке)
                local apache_service=$([ "$os_type" = "almalinux" ] && echo "httpd" || echo "apache2")
                if ! systemctl is-active --quiet "$apache_service" 2>/dev/null; then
                    log_info "Запуск $apache_service..."
                    systemctl start "$apache_service" 2>/dev/null || true
                fi
                
                ok "Apache настроен успешно"
                return 0
            fi
            
            # Создать backup
            local backup_name="${apache_conf}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$apache_conf" "$backup_name"
            log_info "Backup создан: $backup_name"
        fi
    fi
    
    # Создать VirtualHost
    log_info "Создание конфигурации Apache: $apache_conf"
    cat > "$apache_conf" <<EOF
<VirtualHost *:80>
    DocumentRoot "$docroot"
    ServerName "$domain_name"
    
    ErrorLog "$log_dir/workernet.error.log"
    CustomLog "$log_dir/workernet.access.log" common
    
    LimitRequestBody 104857600
    AddDefaultCharset UTF-8
    
    <Directory "$docroot">
        Options -Indexes
        AllowOverride All
        Require all granted
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        
        RewriteRule ^index\.php$ - [L]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule . /index.php [L]
        RedirectMatch 403 ^/\..*$
    </Directory>
    
    <FilesMatch "\.php$">
        SetHandler "proxy:$php_socket"
    </FilesMatch>
    
    <IfModule mod_proxy.c>
        <IfModule mod_proxy_wstunnel.c>
            RewriteCond %{HTTP:Upgrade} =websocket [NC]
            RewriteCond %{HTTP:Connection} upgrade [NC]
            ProxyPass /ws ws://127.0.0.1:15674/ws
            ProxyPassReverse /ws ws://127.0.0.1:15674/ws
        </IfModule>
    </IfModule>
    
    <FilesMatch "^\.ht">
        Require all denied
    </FilesMatch>
    
    RedirectMatch 200 ^/(favicon.ico|robots.txt)$
</VirtualHost>
EOF
    
    CREATED_FILES+=("$apache_conf")
    
    # Включить сайт (для Debian/Ubuntu)
    if [ "$os_type" != "almalinux" ]; then
        a2dissite 000-default 2>/dev/null || true
        a2ensite workernet
    fi
    
    # Создать тестовый index.php
    mkdir -p "$docroot"
    echo '<?php phpinfo(); ?>' > "$docroot/index.php"
    CREATED_DIRS+=("$INSTALL_DIR" "$docroot")
    CREATED_FILES+=("$docroot/index.php")
    
    # Перезапустить Apache
    local apache_service="apache2"
    if [ "$os_type" = "almalinux" ]; then
        apache_service="httpd"
    fi
    
    run_cmd "systemctl restart $apache_service"
    
    ok "Apache настроен успешно"
}

# Установка NGINX
install_nginx() {
    log_section "🌐 УСТАНОВКА NGINX"
    
    show_progress "Установка NGINX"
    
    # Проверка idempotent
    if command_exists nginx; then
        ok "NGINX уже установлен, пропускаем"
        return 0
    fi
    
    local os_type=$(get_os_type)
    
    case $os_type in
        ubuntu|debian)
            # Удалить apache2 если был установлен
            apt remove -y nginx-common apache2 2>/dev/null || true
            run_cmd "apt update"
            
            timed_run "Установка NGINX" \
                "apt-get install -y nginx"
            INSTALLED_PACKAGES+=("nginx")
            STARTED_SERVICES+=("nginx")
            ;;
        almalinux)
            timed_run "Установка NGINX" \
                "dnf install -y nginx"
            INSTALLED_PACKAGES+=("nginx")
            
            run_cmd "systemctl enable nginx"
            run_cmd "systemctl start nginx"
            STARTED_SERVICES+=("nginx")
            ;;
    esac
    
    ok "NGINX установлен успешно"
    return 0
}

# Настройка NGINX
configure_nginx() {
    log_info "Настройка NGINX..."
    
    local os_type=$(get_os_type)
    local docroot="${INSTALL_DIR}/public"
    local domain_name="$DOMAIN"
    
    if [ "$domain_name" = "_" ]; then
        domain_name="_"
    fi
    
    # Путь к конфигурации
    local nginx_conf
    local php_socket
    
    if [ "$os_type" = "almalinux" ]; then
        nginx_conf="/etc/nginx/conf.d/workernet.conf"
        php_socket="unix:/var/opt/remi/php83/run/php-fpm/www.sock"
    else
        nginx_conf="/etc/nginx/sites-available/workernet.conf"
        php_socket="unix:/run/php/php8.3-fpm.sock"
    fi
    
    # Проверить существующий конфиг и спросить о перезаписи
    if [ -f "$nginx_conf" ]; then
        log_warn "⚠️  Конфигурация NGINX уже существует: $nginx_conf"
        
        # Если флаг --force-webserver-config - перезаписать без вопросов
        if [ "${FORCE_WEBSERVER_CONFIG:-false}" = "true" ]; then
            local backup_name="${nginx_conf}.backup.$(date +%Y%m%d_%H%M%S)"
            log_warn "Флаг --force-webserver-config: создаём backup и перезаписываем"
            cp "$nginx_conf" "$backup_name"
            log_info "Backup создан: $backup_name"
        # Иначе - спросить пользователя
        else
            echo ""
            log_warn "ВНИМАНИЕ: Текущая конфигурация будет перезаписана!"
            log_info "Ваши изменения (SSL, редиректы, и т.д.) могут быть потеряны."
            echo ""
            
            read -p "Перезаписать конфигурацию NGINX? (y/n): " -n 1 -r
            echo ""
            echo ""
            
            if [[ ! $REPLY =~ ^[YyДд]$ ]]; then
                log_info "Конфигурация NGINX оставлена без изменений"
                log_info "Используется существующий файл: $nginx_conf"
                
                # Запустить NGINX если он остановлен (важно при переустановке)
                if ! systemctl is-active --quiet nginx 2>/dev/null; then
                    log_info "Запуск NGINX..."
                    systemctl start nginx 2>/dev/null || true
                fi
                
                ok "NGINX настроен успешно"
                return 0
            fi
            
            # Создать backup
            local backup_name="${nginx_conf}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$nginx_conf" "$backup_name"
            log_info "Backup создан: $backup_name"
        fi
    fi
    
    # Создать Server Block
    log_info "Создание конфигурации NGINX: $nginx_conf"
    cat > "$nginx_conf" <<EOF
server {
    listen       80 default_server;
    server_name  $domain_name;
    charset      utf-8;
    client_max_body_size 100M;
    set \$root_path "$docroot";
    
    access_log  /var/log/nginx/workernet.access.log;
    error_log   /var/log/nginx/workernet.error.log;
    
    root \$root_path;
    index  index.php;
    
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    
    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }
    
    location ~ \.php$ {
        try_files     \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass  $php_socket;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$root_path\$fastcgi_script_name;
        fastcgi_read_timeout 600;
        include       fastcgi_params;
    }
    
    location /ws {
        proxy_pass http://127.0.0.1:15674/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }
    
    location ~ /\.ht { 
        deny  all; 
    }
}
EOF
    
    CREATED_FILES+=("$nginx_conf")
    
    # Создать симлинк (для Debian/Ubuntu)
    if [ "$os_type" != "almalinux" ]; then
        ln -sf "$nginx_conf" /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
    fi
    
    # Создать тестовый index.php
    mkdir -p "$docroot"
    echo '<?php phpinfo(); ?>' > "$docroot/index.php"
    CREATED_DIRS+=("$INSTALL_DIR" "$docroot")
    CREATED_FILES+=("$docroot/index.php")
    
    # Перезапустить NGINX
    run_cmd "systemctl restart nginx"
    
    ok "NGINX настроен успешно"
}

# Проверка веб-сервера
verify_webserver() {
    log_info "Проверка установки веб-сервера..."
    
    local service_name
    
    if [ "$WEBSERVER" = "apache" ]; then
        service_name="apache2"
        if [ "$(get_os_type)" = "almalinux" ]; then
            service_name="httpd"
        fi
    else
        service_name="nginx"
    fi
    
    # Проверка сервиса
    if ! is_service_active "$service_name"; then
        log_error "Сервис веб-сервера не запущен"
        return 1
    fi
    ok "Сервис веб-сервера запущен"
    
    # Проверка HTTP
    sleep 2  # Дать время на запуск
    
    if curl -f -s http://localhost/ > /dev/null; then
        ok "Веб-сервер отвечает on http://localhost/"
    else
        log_warn "Веб-сервер не отвечает (may need additional configuration)"
    fi
    
    return 0
}

# Главная функция установки веб-сервера
setup_webserver() {
    # При переустановке: остановить веб-сервер если запущен
    local webserver_services=("apache2" "httpd" "nginx")
    local stopped=false
    
    for service in "${webserver_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Обнаружен запущенный $service (переустановка)"
            log_info "Остановка $service перед переустановкой..."
            
            systemctl stop "$service" 2>/dev/null || true
            pkill -9 "$service" 2>/dev/null || true
            sleep 1
            
            ok "$service остановлен для переустановки"
            stopped=true
        fi
    done
    
    [ "$stopped" = true ] && sleep 2
    
    select_webserver
    
    if [ "$WEBSERVER" = "apache" ]; then
        install_apache || return 1
        configure_apache || return 1
    else
        install_nginx || return 1
        configure_nginx || return 1
    fi
    
    verify_webserver || return 1
    
    return 0
}

# Экспортировать функции
export -f select_webserver
export -f install_apache
export -f configure_apache
export -f install_nginx
export -f configure_nginx
export -f verify_webserver
export -f setup_webserver

