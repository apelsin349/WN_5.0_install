# 🚀 УСТАНОВКА WORKERNET PORTAL С GIT

> **Полное руководство по установке WorkerNet Portal из исходного кода**  
> **Для разработчиков и администраторов**

---

## 📋 СОДЕРЖАНИЕ

1. [Быстрый старт](#-быстрый-старт)
2. [Системные требования](#-системные-требования)
3. [Способы установки](#-способы-установки)
4. [Настройка окружения разработки](#-настройка-окружения-разработки)
5. [Конфигурация](#-конфигурация)
6. [Запуск и тестирование](#-запуск-и-тестирование)
7. [Отладка](#-отладка)
8. [Обновление](#-обновление)

---

## ⚡ БЫСТРЫЙ СТАРТ

### Установка за 5 минут

```bash
# 1. Клонировать репозиторий
git clone https://github.com/apelsin349/WN_5.0_install.git
cd WN_5.0_install

# 2. Установить права на выполнение
chmod +x install.sh

# 3. Запустить автоматическую установку
sudo ./install.sh

# 4. Открыть в браузере
open http://localhost:8000
```

**Готово!** WorkerNet Portal установлен и запущен.

---

## 🖥️ СИСТЕМНЫЕ ТРЕБОВАНИЯ

### Минимальные требования

| Компонент | Требование |
|-----------|------------|
| **ОС** | Ubuntu 24.04+ / Debian 12+ / AlmaLinux 9+ |
| **CPU** | 2 ядра |
| **RAM** | 4 GB |
| **Диск** | 50 GB свободного места |
| **Сеть** | Доступ в интернет |

### Рекомендуемые требования

| Компонент | Требование |
|-----------|------------|
| **ОС** | Ubuntu 24.04 LTS |
| **CPU** | 4+ ядра |
| **RAM** | 8+ GB |
| **Диск** | 100+ GB SSD |
| **Сеть** | Стабильное соединение |

### Необходимое ПО

```bash
# Проверить наличие Git
git --version

# Если Git не установлен
sudo apt update
sudo apt install -y git curl
```

---

## 🔄 СПОСОБЫ УСТАНОВКИ

### 1. Установка из основного репозитория

```bash
# Клонировать официальный репозиторий
git clone https://github.com/apelsin349/WN_5.0_install.git
cd WN_5.0_install

# Переключиться на стабильную ветку
git checkout main

# Запустить установку
sudo ./install.sh
```

### 2. Установка из форка

```bash
# Клонировать ваш форк
git clone https://github.com/ваш-username/WN_5.0_install.git
cd WN_5.0_install

# Добавить upstream репозиторий
git remote add upstream https://github.com/apelsin349/WN_5.0_install.git

# Синхронизировать с основным репозиторием
git fetch upstream
git checkout main
git merge upstream/main

# Запустить установку
sudo ./install.sh
```

### 3. Установка конкретной версии

```bash
# Клонировать репозиторий
git clone https://github.com/apelsin349/WN_5.0_install.git
cd WN_5.0_install

# Посмотреть доступные теги
git tag -l

# Переключиться на нужную версию
git checkout v5.0.0

# Запустить установку
sudo ./install.sh --version 5.0.0
```

### 4. Установка из релиза

```bash
# Скачать архив релиза
curl -L -O https://github.com/apelsin349/WN_5.0_install/archive/refs/tags/v5.0.0.tar.gz

# Распаковать
tar -xzf v5.0.0.tar.gz
cd WN_5.0_install-5.0.0

# Запустить установку
sudo ./install.sh
```

---

## 🛠️ НАСТРОЙКА ОКРУЖЕНИЯ РАЗРАБОТКИ

### Backend (Python/FastAPI)

```bash
# Создать виртуальное окружение
python3 -m venv venv
source venv/bin/activate

# Установить зависимости
pip install -r backend-react/requirements.txt

# Установить зависимости для разработки
pip install -r backend-react/requirements-dev.txt

# Настроить pre-commit hooks
pre-commit install
```

### Frontend (React/TypeScript)

```bash
# Установить Node.js (если не установлен)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Установить зависимости
cd frontend
npm install

# Установить зависимости для разработки
npm install --save-dev

# Настроить Husky hooks
npm run prepare
```

### База данных (PostgreSQL)

```bash
# Установить PostgreSQL
sudo apt install -y postgresql-16 postgresql-client-16

# Создать базу данных
sudo -u postgres createdb workernet

# Создать пользователя
sudo -u postgres createuser workernet

# Установить пароль
sudo -u postgres psql -c "ALTER USER workernet PASSWORD 'your_password';"

# Предоставить права
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE workernet TO workernet;"
```

### Кеш и очереди

```bash
# Установить Redis
sudo apt install -y redis-server

# Установить RabbitMQ
sudo apt install -y rabbitmq-server

# Включить веб-интерфейс RabbitMQ
sudo rabbitmq-plugins enable rabbitmq_management
```

---

## ⚙️ КОНФИГУРАЦИЯ

### Создание конфигурационного файла

```bash
# Скопировать пример конфигурации
cp install.conf.example.yml install.conf.yml

# Отредактировать конфигурацию
nano install.conf.yml
```

### Пример конфигурации для разработки

```yaml
# WorkerNet Portal Configuration
workernet:
  version: "5.0"
  environment: "development"
  domain: "localhost"
  webserver: "nginx"
  install_dir: "/var/www/workernet"

database:
  name: "workernet"
  user: "workernet"
  password: "dev_password"
  host: "localhost"
  port: 5432
  locale: "ru_RU.UTF-8"

redis:
  host: "localhost"
  port: 6379
  password: "dev_redis_password"

rabbitmq:
  host: "localhost"
  port: 5672
  user: "workernet"
  password: "dev_rabbitmq_password"
  vhost: "/workernet"

logging:
  level: "DEBUG"
  file: "/var/log/workernet/portal.log"

development:
  debug: true
  hot_reload: true
  auto_migrate: true
  seed_data: true
```

### Переменные окружения

```bash
# Создать файл .env
cat > .env << EOF
# Database
DATABASE_URL=postgresql://workernet:dev_password@localhost:5432/workernet

# Redis
REDIS_URL=redis://localhost:6379/0

# RabbitMQ
RABBITMQ_URL=amqp://workernet:dev_rabbitmq_password@localhost:5672/workernet

# Security
SECRET_KEY=your-secret-key-here
JWT_SECRET=your-jwt-secret-here

# Development
DEBUG=true
ENVIRONMENT=development
EOF
```

---

## 🚀 ЗАПУСК И ТЕСТИРОВАНИЕ

### Запуск Backend

```bash
# Активировать виртуальное окружение
source venv/bin/activate

# Запустить миграции
cd backend-react
alembic upgrade head

# Запустить сервер разработки
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Запуск Frontend

```bash
# В новом терминале
cd frontend

# Запустить сервер разработки
npm run dev

# Или запустить production build
npm run build
npm run start
```

### Запуск всех сервисов

```bash
# Использовать Docker Compose для разработки
docker-compose -f docker-compose.dev.yml up -d

# Или запустить через Supervisor
sudo supervisorctl start all
```

### Тестирование

```bash
# Backend тесты
cd backend-react
pytest -n auto

# Frontend тесты
cd frontend
npm test

# E2E тесты
npm run test:e2e

# Проверка качества кода
npm run lint
npm run type-check
```

---

## 🔍 ОТЛАДКА

### Просмотр логов

```bash
# Логи Backend
tail -f /var/log/workernet/backend.log

# Логи Frontend
tail -f /var/log/workernet/frontend.log

# Логи Nginx
tail -f /var/log/nginx/error.log

# Логи PostgreSQL
tail -f /var/log/postgresql/postgresql-16-main.log
```

### Проверка статуса сервисов

```bash
# Проверить статус всех сервисов
sudo systemctl status postgresql
sudo systemctl status redis
sudo systemctl status rabbitmq-server
sudo systemctl status nginx
sudo systemctl status supervisor

# Проверить порты
netstat -tlnp | grep -E ':(80|443|8000|5432|6379|5672)'
```

### Отладка базы данных

```bash
# Подключиться к PostgreSQL
sudo -u postgres psql workernet

# Проверить таблицы
\dt

# Проверить пользователей
\du

# Выйти
\q
```

### Отладка Frontend

```bash
# Проверить сборку
cd frontend
npm run build

# Проверить типы
npm run type-check

# Проверить линтер
npm run lint

# Проверить тесты
npm test
```

---

## 🔄 ОБНОВЛЕНИЕ

### Обновление из Git

```bash
# Сохранить изменения
git stash

# Получить обновления
git fetch origin
git pull origin main

# Применить сохраненные изменения
git stash pop

# Обновить зависимости
pip install -r backend-react/requirements.txt
npm install

# Запустить миграции
alembic upgrade head

# Перезапустить сервисы
sudo systemctl restart nginx
sudo supervisorctl restart all
```

### Обновление до новой версии

```bash
# Посмотреть доступные теги
git tag -l

# Переключиться на новую версию
git checkout v5.1.0

# Обновить зависимости
pip install -r backend-react/requirements.txt
npm install

# Запустить миграции
alembic upgrade head

# Перезапустить сервисы
sudo systemctl restart nginx
sudo supervisorctl restart all
```

---

## 📊 ДИАГРАММЫ ПРОЦЕССА

### Диаграмма установки с Git

```mermaid
flowchart TD
    Start[🚀 Начало установки] --> CheckGit{Git установлен?}
    
    CheckGit -->|Нет| InstallGit[📦 Установить Git]
    CheckGit -->|Да| CloneRepo[📥 Клонировать репозиторий]
    
    InstallGit --> CloneRepo
    CloneRepo --> CheckBranch{Выбрать ветку?}
    
    CheckBranch -->|main| MainBranch[🌿 Ветка main]
    CheckBranch -->|develop| DevBranch[🌿 Ветка develop]
    CheckBranch -->|tag| TagBranch[🏷️ Конкретный тег]
    
    MainBranch --> RunInstall[⚙️ Запустить install.sh]
    DevBranch --> RunInstall
    TagBranch --> RunInstall
    
    RunInstall --> CheckConfig{Есть конфиг?}
    
    CheckConfig -->|Да| UseConfig[📋 Использовать конфиг]
    CheckConfig -->|Нет| Interactive[💬 Интерактивная настройка]
    
    UseConfig --> InstallProcess[🔧 Процесс установки]
    Interactive --> InstallProcess
    
    InstallProcess --> Success[✅ Установка завершена]
    Success --> TestRun[🧪 Тестирование]
    TestRun --> Ready[🎉 Готово к работе]
```

### Диаграмма окружения разработки

```mermaid
graph TB
    subgraph "🖥️ Система"
        OS[Ubuntu 24.04+]
        Git[Git 2.40+]
        Node[Node.js 20+]
        Python[Python 3.11+]
    end
    
    subgraph "🗄️ База данных"
        PostgreSQL[PostgreSQL 16]
        Redis[Redis 7]
        RabbitMQ[RabbitMQ 3.x]
    end
    
    subgraph "🔧 Backend"
        FastAPI[FastAPI]
        Alembic[Alembic]
        Pytest[Pytest]
        PreCommit[Pre-commit]
    end
    
    subgraph "💻 Frontend"
        React[React 18]
        TypeScript[TypeScript 5]
        Jest[Jest]
        Husky[Husky]
    end
    
    subgraph "🌐 Веб-сервер"
        Nginx[Nginx]
        Supervisor[Supervisor]
    end
    
    OS --> Git
    OS --> Node
    OS --> Python
    
    PostgreSQL --> FastAPI
    Redis --> FastAPI
    RabbitMQ --> FastAPI
    
    FastAPI --> Alembic
    FastAPI --> Pytest
    FastAPI --> PreCommit
    
    React --> TypeScript
    React --> Jest
    React --> Husky
    
    FastAPI --> Nginx
    React --> Nginx
    Nginx --> Supervisor
```

### Диаграмма процесса обновления

```mermaid
sequenceDiagram
    participant Dev as 👨‍💻 Разработчик
    participant Git as 📦 Git Repository
    participant Local as 💻 Локальная копия
    participant DB as 🗄️ База данных
    participant Services as 🔧 Сервисы
    
    Dev->>Git: git fetch origin
    Git->>Local: Получить обновления
    
    Dev->>Local: git pull origin main
    Local->>Local: Применить изменения
    
    Dev->>Local: pip install -r requirements.txt
    Local->>Local: Обновить зависимости Python
    
    Dev->>Local: npm install
    Local->>Local: Обновить зависимости Node.js
    
    Dev->>DB: alembic upgrade head
    DB->>DB: Применить миграции
    
    Dev->>Services: sudo systemctl restart nginx
    Services->>Services: Перезапустить веб-сервер
    
    Dev->>Services: sudo supervisorctl restart all
    Services->>Services: Перезапустить все процессы
    
    Services->>Dev: ✅ Обновление завершено
```

---

## 🎯 ЧЕК-ЛИСТ УСТАНОВКИ

### Перед установкой

- [ ] **Проверить системные требования**
  - [ ] Ubuntu 24.04+ / Debian 12+ / AlmaLinux 9+
  - [ ] 4+ GB RAM
  - [ ] 50+ GB свободного места
  - [ ] Доступ в интернет

- [ ] **Установить необходимое ПО**
  - [ ] Git 2.40+
  - [ ] Node.js 20+
  - [ ] Python 3.11+
  - [ ] PostgreSQL 16+
  - [ ] Redis 7+
  - [ ] RabbitMQ 3.x+

### Процесс установки

- [ ] **Клонировать репозиторий**
  - [ ] `git clone https://github.com/apelsin349/WN_5.0_install.git`
  - [ ] `cd WN_5.0_install`

- [ ] **Установить права на выполнение**
  - [ ] `chmod +x install.sh`

- [ ] **Выбрать ветку/тег**
  - [ ] `git checkout main` (стабильная)
  - [ ] `git checkout develop` (разработка)
  - [ ] `git checkout v5.0.0` (конкретная версия)

- [ ] **Настроить конфигурацию**
  - [ ] `cp install.conf.example.yml install.conf.yml`
  - [ ] Отредактировать `install.conf.yml`
  - [ ] Создать `.env` файл

- [ ] **Запустить установку**
  - [ ] `chmod +x install.sh`
  - [ ] `sudo ./install.sh`

### После установки

- [ ] **Проверить сервисы**
  - [ ] PostgreSQL: `sudo systemctl status postgresql`
  - [ ] Redis: `sudo systemctl status redis`
  - [ ] RabbitMQ: `sudo systemctl status rabbitmq-server`
  - [ ] Nginx: `sudo systemctl status nginx`
  - [ ] Supervisor: `sudo systemctl status supervisor`

- [ ] **Проверить порты**
  - [ ] 80 (HTTP): `netstat -tlnp | grep :80`
  - [ ] 443 (HTTPS): `netstat -tlnp | grep :443`
  - [ ] 8000 (API): `netstat -tlnp | grep :8000`

- [ ] **Проверить веб-интерфейс**
  - [ ] Открыть `http://localhost` в браузере
  - [ ] Проверить API: `curl http://localhost:8000/api/health`

- [ ] **Запустить тесты**
  - [ ] Backend: `pytest -n auto`
  - [ ] Frontend: `npm test`
  - [ ] E2E: `npm run test:e2e`

### Окружение разработки

- [ ] **Настроить Backend**
  - [ ] `python3 -m venv venv`
  - [ ] `source venv/bin/activate`
  - [ ] `pip install -r backend-react/requirements-dev.txt`
  - [ ] `pre-commit install`

- [ ] **Настроить Frontend**
  - [ ] `cd frontend`
  - [ ] `npm install`
  - [ ] `npm run prepare` (Husky)

- [ ] **Проверить инструменты разработки**
  - [ ] Pre-commit hooks работают
  - [ ] Husky hooks работают
  - [ ] Линтеры настроены
  - [ ] Тесты запускаются

---

## 🆘 РЕШЕНИЕ ПРОБЛЕМ

### Частые проблемы

**Проблема:** install.sh: command not found
```bash
# Решение: установить права на выполнение
chmod +x install.sh
ls -la install.sh  # Проверить права
```

**Проблема:** Git не установлен
```bash
# Решение
sudo apt update
sudo apt install -y git
```

**Проблема:** Недостаточно прав для клонирования
```bash
# Решение
sudo chown -R $USER:$USER /var/www/
git clone https://github.com/apelsin349/WN_5.0_install.git /var/www/workernet
```

**Проблема:** Конфликт портов
```bash
# Решение
sudo netstat -tlnp | grep -E ':(80|443|8000)'
sudo systemctl stop apache2  # если нужно
```

**Проблема:** Ошибки миграций
```bash
# Решение
cd backend-react
alembic downgrade -1
alembic upgrade head
```

**Проблема:** Frontend не собирается
```bash
# Решение
cd frontend
rm -rf node_modules package-lock.json
npm install
npm run build
```

### Логи для отладки

```bash
# Основные логи
tail -f /var/log/workernet/install_*.log
tail -f /var/log/workernet/backend.log
tail -f /var/log/workernet/frontend.log

# Системные логи
tail -f /var/log/nginx/error.log
tail -f /var/log/postgresql/postgresql-16-main.log
tail -f /var/log/redis/redis-server.log
```

---

## 📞 ПОДДЕРЖКА

### Контакты

- 🌐 **Сайт:** https://workernet.online
- 📧 **Email:** support@workernet.online
- 📱 **Telegram:** @workernet_support
- 📚 **Документация:** https://docs.workernet.online
- 🐛 **Issues:** https://github.com/apelsin349/WN_5.0_install/issues

### Полезные ссылки

- 📖 [README.md](README.md) - Основная документация
- 🚀 [БЫСТРЫЙ_СТАРТ.md](БЫСТРЫЙ_СТАРТ.md) - Быстрое начало
- 👤 [ИНСТРУКЦИЯ_ПОЛЬЗОВАТЕЛЯ.md](ИНСТРУКЦИЯ_ПОЛЬЗОВАТЕЛЯ.md) - Руководство пользователя
- 🔧 [ПОСЛЕ_УСТАНОВКИ.md](ПОСЛЕ_УСТАНОВКИ.md) - Настройка после установки

---

## 📝 CHANGELOG

### v5.0 (2025-01-23)
- ✨ Добавлена инструкция по установке с Git
- ✨ Добавлены диаграммы процесса установки
- ✨ Добавлен чек-лист для проверки
- ✨ Добавлены инструкции по окружению разработки
- ✨ Добавлены примеры конфигурации
- ✨ Добавлены инструкции по отладке

---

**Версия инструкции:** 5.0  
**Обновлено:** 23 января 2025  
**Статус:** Production-ready  

**Удачной установки с Git! 🚀**
