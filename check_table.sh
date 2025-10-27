cat > /tmp/check_table.sh << 'EOF'
#!/bin/bash
echo "========================================="
echo "ПРОВЕРКА ТАБЛИЦЫ pbl_conf"
echo "========================================="
echo ""

# 1. Проверка с public.
echo "1. Проверка с схемой public:"
sudo -u postgres psql -d workernet -tAc "SELECT to_regclass('public.pbl_conf');"
echo ""

# 2. Проверка без схемы
echo "2. Проверка без схемы:"
sudo -u postgres psql -d workernet -tAc "SELECT to_regclass('pbl_conf');"
echo ""

# 3. Все таблицы с conf в названии
echo "3. Таблицы содержащие 'conf':"
sudo -u postgres psql -d workernet -tAc "SELECT schemaname, tablename FROM pg_tables WHERE tablename LIKE '%conf%' ORDER BY tablename;"
echo ""

# 4. Проверка существования данных WebSocket
echo "4. Проверка данных WebSocket (если таблица существует):"
sudo -u postgres psql -d workernet -tAc "SELECT option_name, option_value FROM pbl_conf WHERE option_name LIKE '%WEB_SOCKET%' ORDER BY option_name;" 2>&1
echo ""

# 5. Первые 50 таблиц
echo "5. Первые 50 таблиц в БД workernet:"
sudo -u postgres psql -d workernet -tAc "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename LIMIT 50;"
echo ""

echo "========================================="
EOF