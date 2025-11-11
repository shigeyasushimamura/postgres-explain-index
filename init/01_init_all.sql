-- テーブル作成
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    age INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    country VARCHAR(50),
    status VARCHAR(20)
);

CREATE TABLE purchases (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    product_name VARCHAR(100),
    amount DECIMAL(10, 2),
    purchase_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

\echo 'テーブル作成完了'

-- 500万件のユーザーデータ生成（選択性を高める）
\echo '========================================='
\echo '  500万件のユーザーデータを生成中...'
\echo '  ※数分かかります'
\echo '========================================='

INSERT INTO users (username, email, age, country, status)
SELECT
    'user_' || i AS username,
    'user_' || i || '@example.com' AS email,
    20 + (i % 80) AS age,  -- 20〜99歳（より分散）
    CASE (i % 50)  -- 50カ国に分散（選択性を高める）
        WHEN 0 THEN 'Japan'
        WHEN 1 THEN 'USA'
        WHEN 2 THEN 'UK'
        WHEN 3 THEN 'China'
        WHEN 4 THEN 'Korea'
        WHEN 5 THEN 'France'
        WHEN 6 THEN 'Germany'
        WHEN 7 THEN 'Canada'
        WHEN 8 THEN 'Australia'
        WHEN 9 THEN 'Brazil'
        WHEN 10 THEN 'Mexico'
        WHEN 11 THEN 'India'
        WHEN 12 THEN 'Russia'
        WHEN 13 THEN 'Italy'
        WHEN 14 THEN 'Spain'
        WHEN 15 THEN 'Netherlands'
        WHEN 16 THEN 'Sweden'
        WHEN 17 THEN 'Norway'
        WHEN 18 THEN 'Finland'
        WHEN 19 THEN 'Denmark'
        WHEN 20 THEN 'Poland'
        WHEN 21 THEN 'Belgium'
        WHEN 22 THEN 'Austria'
        WHEN 23 THEN 'Switzerland'
        WHEN 24 THEN 'Portugal'
        WHEN 25 THEN 'Greece'
        WHEN 26 THEN 'Turkey'
        WHEN 27 THEN 'Thailand'
        WHEN 28 THEN 'Vietnam'
        WHEN 29 THEN 'Singapore'
        WHEN 30 THEN 'Malaysia'
        WHEN 31 THEN 'Indonesia'
        WHEN 32 THEN 'Philippines'
        WHEN 33 THEN 'Taiwan'
        WHEN 34 THEN 'Hong Kong'
        WHEN 35 THEN 'New Zealand'
        WHEN 36 THEN 'Argentina'
        WHEN 37 THEN 'Chile'
        WHEN 38 THEN 'Colombia'
        WHEN 39 THEN 'Peru'
        WHEN 40 THEN 'Egypt'
        WHEN 41 THEN 'South Africa'
        WHEN 42 THEN 'Nigeria'
        WHEN 43 THEN 'Kenya'
        WHEN 44 THEN 'Morocco'
        WHEN 45 THEN 'UAE'
        WHEN 46 THEN 'Saudi Arabia'
        WHEN 47 THEN 'Israel'
        WHEN 48 THEN 'Pakistan'
        ELSE 'Bangladesh'
    END AS country,
    CASE (i % 3)
        WHEN 0 THEN 'active'
        WHEN 1 THEN 'inactive'
        ELSE 'pending'
    END AS status
FROM generate_series(1, 5000000) AS i;

\echo '✓ ユーザーデータ生成完了'

-- 1000万件の購入履歴生成
\echo '========================================='
\echo '  1000万件の購入履歴を生成中...'
\echo '  ※数分かかります'
\echo '========================================='

INSERT INTO purchases (user_id, product_name, amount, purchase_date)
SELECT
    (random() * 9999999 + 1)::INTEGER AS user_id,
    'Product_' || (i % 1000) AS product_name,  -- 商品種類を増やす
    (random() * 10000)::DECIMAL(10, 2) AS amount,
    CURRENT_TIMESTAMP - (floor(random() * 730)::INTEGER || ' days')::INTERVAL AS purchase_date
FROM generate_series(1, 10000000) AS i;

\echo '✓ 購入履歴生成完了'

-- 統計表示
SELECT 'users' AS table_name, COUNT(*) AS record_count FROM users
UNION ALL
SELECT 'purchases', COUNT(*) FROM purchases;

\echo '========================================='
\echo '  初期セットアップ完了！'
\echo '========================================='