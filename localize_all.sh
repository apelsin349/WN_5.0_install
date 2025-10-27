#!/bin/bash
# localize_all.sh - Автоматическая локализация всех bash скриптов на русский
# WorkerNet Installer v5.0

echo "🌍 Начало локализации на русский язык..."

# Директория с библиотеками
LIB_DIR="lib"

# Счетчик замен
TOTAL_REPLACEMENTS=0

# Функция замены текста в файле
replace_in_file() {
    local file=$1
    local english=$2
    local russian=$3
    
    if grep -q "$english" "$file" 2>/dev/null; then
        sed -i.bak "s/${english}/${russian}/g" "$file"
        echo "  ✅ $file: '$english' → '$russian'"
        ((TOTAL_REPLACEMENTS++))
    fi
}

# Карта переводов (английский → русский)
declare -A TRANSLATIONS=(
    # Общие фразы
    ["already installed, skipping"]="уже установлен, пропускаем"
    ["installed successfully"]="установлен успешно"
    ["configured successfully"]="настроен успешно"
    ["created successfully"]="создан успешно"
    ["installation failed"]="установка не удалась"
    ["configuration failed"]="настройка не удалась"
    ["is not running"]="не запущен"
    ["is running"]="запущен"
    ["is accessible"]="доступен"
    ["is not accessible"]="не доступен"
    ["responds"]="отвечает"
    ["does NOT respond"]="НЕ отвечает"
    
    # Действия (для log_info)
    ["Installing PostgreSQL"]="Установка PostgreSQL"
    ["Installing Redis"]="Установка Redis"
    ["Installing RabbitMQ"]="Установка RabbitMQ"
    ["Installing PHP"]="Установка PHP"
    ["Installing Python"]="Установка Python"
    ["Installing Supervisor"]="Установка Supervisor"
    ["Installing Apache"]="Установка Apache"
    ["Installing NGINX"]="Установка NGINX"
    ["Installing Erlang"]="Установка Erlang"
    
    ["Configuring PostgreSQL"]="Настройка PostgreSQL"
    ["Configuring Redis"]="Настройка Redis"
    ["Configuring RabbitMQ"]="Настройка RabbitMQ"
    ["Configuring PHP"]="Настройка PHP"
    ["Configuring Python"]="Настройка Python"
    ["Configuring Apache"]="Настройка Apache"
    ["Configuring NGINX"]="Настройка NGINX"
    
    ["Verifying PostgreSQL"]="Проверка PostgreSQL"
    ["Verifying Redis"]="Проверка Redis"
    ["Verifying RabbitMQ"]="Проверка RabbitMQ"
    ["Verifying web server"]="Проверка веб-сервера"
    
    ["Creating PostgreSQL user"]="Создание пользователя PostgreSQL"
    ["Creating database"]="Создание базы данных"
    ["Creating admin user"]="Создание администратора"
    ["Creating workernet user"]="Создание пользователя workernet"
    ["Creating WebSocket user"]="Создание WebSocket пользователя"
    ["Creating RabbitMQ users"]="Создание пользователей RabbitMQ"
    
    ["Enabling RabbitMQ plugins"]="Включение плагинов RabbitMQ"
    ["Setting up iptables"]="Настройка iptables"
    ["Applying iptables rules"]="Применение правил iptables"
    ["Creating .env file"]="Создание .env файла"
    ["Setting permissions"]="Установка прав доступа"
    ["Downloading WorkerNet installer"]="Загрузка установщика WorkerNet"
    ["Running WorkerNet phar installer"]="Запуск установщика WorkerNet phar"
    
    # Ошибки
    ["Unsupported OS"]="Неподдерживаемая ОС"
    ["Cannot connect to database"]="Не удается подключиться к базе данных"
    ["Failed to download"]="Не удалось загрузить"
    ["authentication failed"]="аутентификация не удалась"
    ["authentication successful"]="аутентификация успешна"
    
    # Статусы
    ["service is not running"]="сервис не запущен"
    ["service is running"]="сервис запущен"
    ["is accessible"]="доступен"
    ["NOT accessible"]="НЕ доступен"
    ["User already exists"]="Пользователь уже существует"
    ["Database already exists"]="База данных уже существует"
    ["extension already installed"]="расширение уже установлено"
    ["Phar file already exists"]="Phar файл уже существует"
    
    # Проверки
    ["Checking services"]="Проверка сервисов"
    ["Checking ports"]="Проверка портов"
    ["Checking database"]="Проверка базы данных"
    ["Checking Redis"]="Проверка Redis"
    ["Checking RabbitMQ users"]="Проверка пользователей RabbitMQ"
    ["Checking web server"]="Проверка веб-сервера"
    ["Checking PHP"]="Проверка PHP"
    ["Checking permissions"]="Проверка прав доступа"
    ["Checking Supervisor workers"]="Проверка Supervisor workers"
    
    # Информационные сообщения
    ["Select the web server"]="Выберите веб-сервер"
    ["Database credentials"]="Параметры подключения к БД"
    ["Redis credentials"]="Параметры подключения Redis"
    ["RabbitMQ credentials"]="Параметры подключения RabbitMQ"
    ["Database name"]="Имя базы данных"
    ["Database user"]="Пользователь БД"
    ["Database password"]="Пароль БД"
    ["Admin user"]="Администратор"
    ["Admin password"]="Пароль администратора"
    
    # Секции
    ["PRE-FLIGHT CHECKS"]="ПРЕДВАРИТЕЛЬНЫЕ ПРОВЕРКИ"
    ["INSTALLING POSTGRESQL"]="УСТАНОВКА POSTGRESQL"
    ["INSTALLING REDIS"]="УСТАНОВКА REDIS"
    ["INSTALLING RABBITMQ"]="УСТАНОВКА RABBITMQ"
    ["INSTALLING PHP"]="УСТАНОВКА PHP"
    ["INSTALLING PYTHON"]="УСТАНОВКА PYTHON"
    ["INSTALLING SUPERVISOR"]="УСТАНОВКА SUPERVISOR"
    ["INSTALLING APACHE"]="УСТАНОВКА APACHE"
    ["INSTALLING NGINX"]="УСТАНОВКА NGINX"
    ["CONFIGURING FIREWALL"]="НАСТРОЙКА FIREWALL"
    ["RUNNING SMOKE TESTS"]="ЗАПУСК SMOKE TESTS"
    ["INSTALLATION SUMMARY"]="ИТОГИ УСТАНОВКИ"
)

# Применить переводы ко всем файлам
for file in $LIB_DIR/*.sh; do
    echo "Обработка $file..."
    
    for english in "${!TRANSLATIONS[@]}"; do
        russian="${TRANSLATIONS[$english]}"
        
        # Экранировать специальные символы для sed
        english_escaped=$(printf '%s\n' "$english" | sed 's/[[\.*^$()+?{|]/\\&/g')
        russian_escaped=$(printf '%s\n' "$russian" | sed 's/[[\.*^$()+?{|]/\\&/g')
        
        # Заменить в файле
        sed -i.tmp "s/${english_escaped}/${russian_escaped}/g" "$file" 2>/dev/null
    done
    
    # Удалить временные файлы
    rm -f "$file.tmp" "$file.bak"
done

echo ""
echo "✅ Локализация завершена!"
echo "Обработано файлов: $(ls -1 $LIB_DIR/*.sh | wc -l)"
echo ""
echo "Проверьте файлы вручную на корректность перевода"

