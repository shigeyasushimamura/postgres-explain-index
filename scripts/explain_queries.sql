-- EXPLAINの読み方を学ぶためのクエリ集
-- 実行方法: docker exec -i postgres-explain-demo psql -U demouser -d explaindb < scripts/explain_queries.sql

\timing on
\echo '========================================='
\echo '  EXPLAIN 実行サンプル'
\echo '========================================='

-- 1. 基本的なSELECT（フルスキャン）
\echo '\n[1] 基本SELECT（INDEX無し） - Seq Scan'
EXPLAIN ANALYZE
SELECT * FROM users WHERE age = 30;

-- 2. 範囲検索（INDEX無し）
\echo '\n[2] 範囲検索（INDEX無し） - Seq Scan'
EXPLAIN ANALYZE
SELECT * FROM users WHERE age BETWEEN 25 AND 35;

-- 3. 文字列検索（INDEX無し）
\echo '\n[3] 文字列検索（INDEX無し） - Seq Scan'
EXPLAIN ANALYZE
SELECT * FROM users WHERE country = 'Japan';

-- 4. COUNT集計
\echo '\n[4] COUNT集計'
EXPLAIN ANALYZE
SELECT country, COUNT(*) FROM users GROUP BY country;

-- 5. JOIN（INDEX無し）
\echo '\n[5] JOIN（INDEX無し）'
EXPLAIN ANALYZE
SELECT u.username, p.product_name, p.amount
FROM users u
JOIN purchases p ON u.id = p.user_id
WHERE u.age > 50
LIMIT 100;

-- 6. ORDER BY（INDEX無し）
\echo '\n[6] ORDER BY（INDEX無し）'
EXPLAIN ANALYZE
SELECT * FROM users WHERE country = 'Japan' ORDER BY age LIMIT 10;

\echo '\n========================================='
\echo '  INDEX作成後の比較は benchmark.sh を実行'
\echo '========================================='