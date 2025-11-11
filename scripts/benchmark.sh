#!/bin/bash

echo "========================================="
echo "  PostgreSQL INDEX効果検証ベンチマーク"
echo "  データ件数: 1000万件"
echo "========================================="
echo ""

# INDEXの効果が見やすいクエリに変更
QUERIES=(
    "SELECT id, age FROM users WHERE age = 95;"
    "SELECT id, age FROM users WHERE age BETWEEN 95 AND 99;"
    "SELECT id, country FROM users WHERE country = 'Singapore';"
    "SELECT id, email FROM users WHERE email = 'user_5000000@example.com';"
    "SELECT COUNT(*) FROM users WHERE age > 90;"
    "SELECT id, username FROM users WHERE age = 95 LIMIT 10;"
)

QUERY_NAMES=(
    "等価検索 (age = 95) - カラム指定"
    "範囲検索 (age BETWEEN 95 AND 99) - カラム指定"
    "国別検索 (country = 'Singapore') - カラム指定"
    "Email検索 - 超高選択性"
    "COUNT集計 (age > 90) - INDEX使用"
    "LIMIT付き検索 - INDEX効果大"
)

# キャッシュクリア関数
clear_cache() {
    docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DISCARD ALL;" > /dev/null 2>&1
    sleep 1
}

# INDEX無しでの実行
echo "========================================="
echo " [Phase 1] INDEX無しで実行"
echo "========================================="
echo ""

for i in "${!QUERIES[@]}"; do
    echo "【クエリ $((i+1))】 ${QUERY_NAMES[$i]}"
    echo "----------------------------------------"
    clear_cache
    docker exec postgres-explain-demo psql -U demouser -d explaindb -c "\timing on" -c "${QUERIES[$i]}" 2>&1 | grep "Time:"
    echo ""
done

# INDEX作成
echo "========================================="
echo " [Phase 2] INDEX作成中..."
echo "========================================="
echo ""

docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_users_age ON users(age);"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_users_country ON users(country);"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_users_email ON users(email);"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_purchases_user_id ON purchases(user_id);"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "ANALYZE purchases;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "SELECT 'INDEX作成完了' AS status;"

echo ""

# INDEX有りでの実行
echo "========================================="
echo " [Phase 3] INDEX有りで実行"
echo "========================================="
echo ""

for i in "${!QUERIES[@]}"; do
    echo "【クエリ $((i+1))】 ${QUERY_NAMES[$i]}"
    echo "----------------------------------------"
    clear_cache
    docker exec postgres-explain-demo psql -U demouser -d explaindb -c "\timing on" -c "${QUERIES[$i]}" 2>&1 | grep "Time:"
    echo ""
done

# EXPLAIN ANALYZE詳細比較
echo "========================================="
echo " [Phase 4] EXPLAIN ANALYZE 詳細比較"
echo "========================================="
echo ""

# 比較1: 等価検索 (age = 95)
echo "【比較1】等価検索 (age = 95) - カラム指定"
echo "----------------------------------------"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_users_age; ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT * FROM users WHERE age = 95;"
echo ""
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_users_age ON users(age); ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT * FROM users WHERE age = 95;"
echo ""

# 比較2: 範囲検索 (age BETWEEN 95 AND 99)
echo "【比較2】範囲検索 (age BETWEEN 95 AND 99) - カラム指定"
echo "----------------------------------------"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_users_age; ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT * FROM users WHERE age BETWEEN 95 AND 99;"
echo ""
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_users_age ON users(age); ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT * FROM users WHERE age BETWEEN 95 AND 99;"
echo ""

# 比較3: 国別検索 (country = 'Singapore')
echo "【比較3】国別検索 (country = 'Singapore') - カラム指定"
echo "----------------------------------------"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_users_country; ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT * FROM users WHERE country = 'Singapore';"
echo ""
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_users_country ON users(country); ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT * FROM users WHERE country = 'Singapore';"
echo ""

# 比較4: Email検索 (email = 'user_5000000@example.com')
echo "【比較4】Email検索 - 超高選択性"
echo "----------------------------------------"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_users_email; ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT * FROM users WHERE email = 'user_5000000@example.com';"
echo ""
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_users_email ON users(email); ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT * FROM users WHERE email = 'user_5000000@example.com';"
echo ""

# 比較5: COUNT集計 (age > 90)
echo "【比較5】COUNT集計 (age > 90) - INDEX使用"
echo "----------------------------------------"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_users_age; ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT COUNT(*) FROM users WHERE age > 90;"
echo ""
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_users_age ON users(age); ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT COUNT(*) FROM users WHERE age > 90;"
echo ""

# 比較6: LIMIT付き検索 (age = 95 LIMIT 10)
echo "【比較6】LIMIT付き検索 (age = 95 LIMIT 10) - INDEX効果大"
echo "----------------------------------------"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_users_age; ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT id, username FROM users WHERE age = 95 LIMIT 10;"
echo ""
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "CREATE INDEX idx_users_age ON users(age); ANALYZE users;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) SELECT id, username FROM users WHERE age = 95 LIMIT 10;"
echo ""


echo ""
echo "========================================="
echo " [Phase 5] INDEX情報表示"
echo "========================================="
echo ""

docker exec postgres-explain-demo psql -U demouser -d explaindb -c "SELECT tablename, indexname, pg_size_pretty(pg_relation_size(indexrelid)) AS index_size FROM pg_stat_user_indexes WHERE schemaname = 'public' ORDER BY pg_relation_size(indexrelid) DESC;"

echo ""
echo "========================================="
echo " [Phase 6] INDEX削除中..."
echo "========================================="
echo ""

docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_users_age;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_users_country;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_users_email;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "DROP INDEX IF EXISTS idx_purchases_user_id;"
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "SELECT 'INDEX削除完了 - 次回の測定準備OK' AS status;"

echo ""
echo "========================================="
echo "  ベンチマーク完了！"
echo "========================================="
echo ""
echo "💡 学んだこと："
echo "  - SELECT * はINDEXがあっても遅い（Heap Fetch大量発生）"
echo "  - 必要なカラムだけ取得するとINDEX効果絶大"
echo "  - COUNT(*)やLIMITはINDEXで高速化"
echo "  - Email検索は超高選択性なので劇的改善"
echo ""