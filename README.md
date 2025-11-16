# PostgreSQL EXPLAIN + INDEX 設計学習プロジェクト【中級完全版】

1000 万件のデータで INDEX の効果を体感し、EXPLAIN の読み方をマスターし、実務で即戦力となるクエリ最適化スキルを習得するプロジェクトです。

## 📁 プロジェクト構成

```
postgres-explain-index/
├── docker-compose.yml          # PostgreSQL環境定義
├── README.md                   # 基礎編
├── README_ADVANCED.md          # このファイル（中級編）
├── init/
│   └── 01_init_all.sql        # テーブル作成 + 1000万件データ自動生成
└── scripts/
    ├── benchmark.sh           # INDEX効果比較（自動測定）
    ├── explain_queries.sql    # EXPLAIN学習用クエリ集
    ├── advanced_queries.sql   # 中級クエリ集（NEW）
    └── index_maintenance.sql  # INDEX保守スクリプト（NEW）
```

## 🚀 使い方（3 ステップ）

### 1. PostgreSQL コンテナ起動 + データ自動生成

```bash
docker compose up -d
```

**これだけで以下が自動実行されます:**

- PostgreSQL 起動
- テーブル作成（users, purchases）
- 1000 万件のユーザーデータ生成
- 2000 万件の購入履歴生成

**所要時間**: 初回起動時 約 5〜10 分

### 2. 初期化完了を確認

```bash
# ログで進捗確認
docker compose logs -f postgres

# 「初期セットアップ完了！」が表示されたらOK
```

または直接データ確認：

```bash
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "SELECT COUNT(*) FROM users;"
```

### 3. INDEX 効果のベンチマーク

```bash
./scripts/benchmark.sh
```

---

## 📊 実測結果から学ぶ INDEX 設計の真実

### 検証結果サマリー（1000 万件データ）

| クエリ種類                               | INDEX 無し | INDEX 有り | 結果              | 理由                                                |
| ---------------------------------------- | ---------- | ---------- | ----------------- | --------------------------------------------------- |
| **等価検索** `age = 95`                  | 191ms      | 299ms      | ❌ **1.6 倍遅い** | 低選択性（62,500 件ヒット）でランダム I/O 大量発生  |
| **範囲検索** `age BETWEEN 95-99`         | 223ms      | 366ms      | ❌ **1.6 倍遅い** | 低選択性（312,500 件ヒット）でランダム I/O 大量発生 |
| **国別検索** `country = 'Singapore'`     | 201ms      | 295ms      | ❌ **1.5 倍遅い** | 低選択性（100,000 件ヒット）でランダム I/O 大量発生 |
| **Email 検索** `email = 'xxx'`           | 138ms      | 3ms        | ✅ **43 倍高速**  | 超高選択性（1 件）で Index Scan 直撃                |
| **COUNT 集計** `COUNT(*) WHERE age > 90` | 119ms      | 16ms       | ✅ **7.5 倍高速** | Index Only Scan で実テーブル不要                    |
| **LIMIT 検索** `age = 95 LIMIT 10`       | 1.8ms      | 1.7ms      | ✅ わずかに改善   | 早期終了可能なクエリ                                |

### 💡 重要な学び

1. **INDEX は万能ではない**

   - 該当件数が多い（全体の 1%以上）場合、INDEX は逆効果になることがある
   - PostgreSQL は賢く、「Seq Scan の方が速い」と判断すれば INDEX を使わない

2. **SELECT \* は遅い**

   - INDEX で行を特定しても、全カラム取得のためテーブル本体へランダムアクセス（Heap Fetch）が大量発生
   - 必要なカラムだけ取得する方が高速

3. **超高選択性クエリで INDEX は劇的効果**

   - Email、ユニークキー検索は 100 倍以上の改善も
   - Index Scan で即座に目的の行を特定

4. **COUNT(\*)は Index Only Scan で高速化**
   - 実テーブルへのアクセス不要（Heap Fetches: 0）
   - INDEX だけで集計完了

---

## 📖 EXPLAIN 出力の読み方（実務必須）

### 基本的な出力例

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM users WHERE age = 95;
```

```
Bitmap Heap Scan on users  (cost=656.40..66091.08 rows=58835 width=67)
                           (actual time=18.978..250.270 rows=62500 loops=1)
  Recheck Cond: (age = 95)
  Heap Blocks: exact=62492
  Buffers: shared hit=168 read=62379
  ->  Bitmap Index Scan on idx_users_age  (cost=0.00..641.70 rows=58835 width=0)
        Index Cond: (age = 95)
        Buffers: shared read=55
Planning Time: 0.815 ms
Execution Time: 252.887 ms
```

### 主要項目の意味

| 項目                       | 意味                     | 見るべきポイント               |
| -------------------------- | ------------------------ | ------------------------------ |
| **cost=開始..終了**        | 推定コスト               | 低いほど良い                   |
| **rows=**                  | 推定行数                 | actual rows と比較して精度確認 |
| **actual time=開始..終了** | 実際の実行時間（ms）     | 実測値（最重要）               |
| **Execution Time**         | クエリ全体の実行時間     | **最も重要な指標**             |
| **Buffers: shared hit**    | キャッシュヒット数       | 多いほど高速                   |
| **Buffers: shared read**   | ディスク I/O 数          | 少ないほど高速                 |
| **Heap Blocks**            | テーブル本体へのアクセス | 多いとランダム I/O 大量発生    |
| **Heap Fetches: 0**        | Index Only Scan 成功     | 実テーブル不要で超高速         |

### 【中級】EXPLAIN 出力の詳細解析

#### cost の計算式を理解する

PostgreSQL の cost は以下の要素で計算されます：

```
cost = (seq_page_cost × ページ数) + (cpu_tuple_cost × 行数) + (random_page_cost × ランダムアクセス数)
```

**デフォルト値:**

- `seq_page_cost = 1.0` （連続読み込み）
- `random_page_cost = 4.0` （ランダム読み込み）
- `cpu_tuple_cost = 0.01` （行処理コスト）

**SSD の場合の最適化:**

```sql
-- ランダムアクセスとシーケンシャルアクセスの差が小さい
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_cache_size = '8GB';  -- 物理メモリの50-75%
ALTER SYSTEM SET shared_buffers = '2GB';        -- 物理メモリの25%
SELECT pg_reload_conf();
```

#### rows と actual rows のズレを解消する

**統計情報の精度を上げる:**

```sql
-- デフォルトの統計サンプル数を増やす
ALTER TABLE users ALTER COLUMN age SET STATISTICS 1000;  -- デフォルト100

-- 統計情報を手動更新
ANALYZE users;

-- 統計情報の確認
SELECT
    attname AS column_name,
    n_distinct,
    correlation
FROM pg_stats
WHERE tablename = 'users' AND schemaname = 'public';
```

**n_distinct の意味:**

- `-1` = すべてユニーク
- `0.5` = 全体の 50%がユニーク
- `100` = 約 100 種類の値

**correlation の意味:**

- `1.0` = 物理的な並び順とカラムの値が完全一致（INDEX スキャンが超高速）
- `0.0` = ランダム（INDEX スキャンが遅い）
- `-1.0` = 完全逆順

#### Buffers の詳細分析

```
Buffers: shared hit=1000 read=500 dirtied=10 written=5
         temp read=100 written=100
```

| 項目                  | 意味                 | 対策                                        |
| --------------------- | -------------------- | ------------------------------------------- |
| **shared hit**        | キャッシュヒット     | 高いほど良い                                |
| **shared read**       | ディスク I/O         | 少ないほど良い。再実行で hit に変わるか確認 |
| **dirtied**           | 更新されたページ     | UPDATE/DELETE で発生                        |
| **written**           | ディスクへの書き込み | WAL（Write-Ahead Log）関連                  |
| **temp read/written** | 一時ファイル使用     | **work_mem を増やす必要あり**               |

**work_mem の最適化（重要）:**

```sql
-- クエリごとに使えるメモリ（デフォルト4MB）
SET work_mem = '256MB';  -- 大規模ソート・ハッシュジョインで効果大

-- 一時ファイル使用を検出
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users ORDER BY age, username;

-- temp read/writtenが出たらwork_memを増やす
```

---

## 🔍 実務で覚えるべきスキャン方式（優先度順）

### 1. Seq Scan（全件スキャン）⚠️

```
Seq Scan on users  (actual time=0.019..110.034 rows=20833 loops=3)
  Filter: (age = 95)
  Rows Removed by Filter: 1645833
```

**特徴:**

- テーブル全体を先頭から順番に読む
- INDEX 無し、または INDEX が使えない場合
- 大量の行を削除（Rows Removed）している場合は非効率

**【中級】Seq Scan が選ばれる条件:**

```sql
-- 1. 大半の行がヒットする（20%以上）
SELECT * FROM users WHERE age > 20;  -- ほぼ全員

-- 2. INDEXがあっても統計情報が古い
-- → ANALYZE実行で改善

-- 3. WHERE句でカラムに関数を使用
SELECT * FROM users WHERE LOWER(username) LIKE 'user%';
-- 対策: 関数INDEXを作成
CREATE INDEX idx_users_username_lower ON users(LOWER(username));
```

---

### 2. Index Scan（INDEX スキャン）✅

```
Index Scan using idx_users_email on users  (actual time=0.034..0.035 rows=1 loops=1)
  Index Cond: (email = 'user_5000000@example.com')
  Buffers: shared hit=1 read=4
```

**特徴:**

- INDEX を使って行を特定し、テーブル本体から取得
- 少数行（1%未満）を取得する場合に最適
- ランダムアクセスが少ないため高速

**【中級】Index Scan の最適化:**

```sql
-- 1. ORDER BYと組み合わせて最速化
CREATE INDEX idx_users_age_id ON users(age, id);

SELECT * FROM users WHERE age > 90 ORDER BY age, id LIMIT 10;
-- → Index Scanで即座に最初の10件取得（Early Termination）

-- 2. WHERE + ORDER BYの複合INDEX最適化
CREATE INDEX idx_users_country_created ON users(country, created_at DESC);

SELECT * FROM users
WHERE country = 'Japan'
ORDER BY created_at DESC
LIMIT 100;
-- → Index Scanで最新100件を即取得
```

---

### 3. Index Only Scan（INDEX のみスキャン）🚀

```
Parallel Index Only Scan using idx_users_age  (actual time=0.072..11.643 rows=187500 loops=3)
  Index Cond: (age > 90)
  Heap Fetches: 0
```

**特徴:**

- **実テーブルへのアクセス不要**（最速）
- INDEX に必要な全カラムが含まれている場合のみ
- `Heap Fetches: 0` が表示されれば成功

**【中級】Index Only Scan を実現するテクニック:**

#### 方法 1: INCLUDE 句（PostgreSQL 11 以降）

```sql
-- カバリングINDEX（最強）
CREATE INDEX idx_users_age_inc
ON users(age)
INCLUDE (username, email, country);

-- これでIndex Only Scan成功
SELECT age, username, email, country
FROM users
WHERE age = 95;
```

#### 方法 2: 複合 INDEX で代用

```sql
CREATE INDEX idx_users_age_username_email ON users(age, username, email);

SELECT age, username, email
FROM users
WHERE age = 95;
```

#### 方法 3: VACUUM で Visibility Map 更新

```sql
-- Heap Fetches > 0 の場合はVACUUM実行
VACUUM ANALYZE users;

-- 自動VACUUM設定確認
SHOW autovacuum;
```

**Heap Fetches が 0 にならない原因:**

1. VACUUM が実行されていない → 手動 VACUUM 実行
2. 更新頻度が高い → autovacuum の頻度を上げる
3. INDEX に必要なカラムが含まれていない → INCLUDE 句追加

---

### 4. Bitmap Index Scan + Bitmap Heap Scan 📦

```
Bitmap Heap Scan on users  (actual time=18.978..250.270 rows=62500 loops=1)
  Heap Blocks: exact=62492
  ->  Bitmap Index Scan on idx_users_age  (actual time=9.068..9.069 rows=62500 loops=1)
        Index Cond: (age = 95)
```

**特徴:**

- 中程度の件数（1%〜10%）を取得する場合
- INDEX で該当行をビットマップ化してから、まとめてテーブルアクセス
- ランダム I/O を減らす工夫

**【中級】Bitmap Scan が選ばれる理由:**

```sql
-- 複数INDEXのOR条件で威力発揮
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users
WHERE age = 95 OR country = 'Singapore';

-- 実行計画:
-- BitmapOr
--   -> Bitmap Index Scan on idx_users_age
--   -> Bitmap Index Scan on idx_users_country
-- -> Bitmap Heap Scan
```

**Bitmap Scan の問題点と対策:**

```sql
-- Heap Blocksが多い = ランダムI/O多発
-- 対策1: 複合INDEXで1回のスキャンに
CREATE INDEX idx_users_age_country ON users(age, country);

-- 対策2: 部分INDEXで該当データを絞る
CREATE INDEX idx_users_active_age
ON users(age)
WHERE status = 'active';
```

---

### 5. Parallel Seq Scan（並列全件スキャン）⚡

```
Gather  (actual time=0.239..118.368 rows=62500 loops=1)
  Workers Launched: 2
  ->  Parallel Seq Scan on users  (actual time=0.019..110.034 rows=20833 loops=3)
        Filter: (age = 95)
```

**特徴:**

- 複数ワーカーで並列処理
- 大量データの Seq Scan を高速化
- INDEX 無しでもそこそこ速い

**【中級】並列処理の最適化:**

```sql
-- 並列ワーカー数の設定
SET max_parallel_workers_per_gather = 4;  -- デフォルト2

-- 並列処理の最小テーブルサイズ
SET min_parallel_table_scan_size = '8MB';  -- デフォルト8MB

-- 並列処理の強制/無効化
SET parallel_setup_cost = 0;      -- 並列処理を積極的に使う
SET parallel_tuple_cost = 0;      -- 並列処理を積極的に使う
SET max_parallel_workers_per_gather = 0;  -- 並列処理を無効化

-- 並列INDEX作成（PostgreSQL 11以降）
CREATE INDEX CONCURRENTLY idx_users_age ON users(age);
-- max_parallel_maintenance_workers の設定が効く
```

**並列処理が効く場合・効かない場合:**

| ケース     | 並列処理    | 理由                       |
| ---------- | ----------- | -------------------------- |
| COUNT(\*)  | ✅ 有効     | 集約処理は並列化しやすい   |
| GROUP BY   | ✅ 有効     | Partial Aggregate が可能   |
| ORDER BY   | ⚠️ 制限あり | 最後に Sort 必要           |
| LIMIT      | ❌ 無効     | 早期終了で並列化の意味なし |
| サブクエリ | ✅ 有効     | 各サブクエリで並列化       |

---

### 6. Index Scan Backward（逆順スキャン）🔄

```sql
-- ORDER BY DESC でINDEXを逆順に読む
EXPLAIN (ANALYZE)
SELECT * FROM users ORDER BY age DESC LIMIT 10;

-- 実行計画:
-- Limit
--   -> Index Scan Backward using idx_users_age on users
```

**活用シーン:**

- 最新/最大値の取得
- ランキングの下位取得

---

### 7. Nested Loop Join / Hash Join / Merge Join 🔗

#### Nested Loop Join（ネステッドループ結合）

```sql
EXPLAIN (ANALYZE)
SELECT u.username, p.amount
FROM users u
JOIN purchases p ON u.id = p.user_id
WHERE u.id = 12345;

-- 実行計画:
-- Nested Loop
--   -> Index Scan on users (1 row)
--   -> Index Scan on purchases (N rows)
```

**特徴:**

- 小さいテーブル × 大きいテーブルの JOIN に最適
- INDEX があれば超高速
- 該当行が少ない場合に選ばれる

---

#### Hash Join（ハッシュ結合）

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.username, COUNT(*)
FROM users u
JOIN purchases p ON u.id = p.user_id
GROUP BY u.username;

-- 実行計画:
-- HashAggregate
--   -> Hash Join
--        Hash Cond: (p.user_id = u.id)
--        -> Seq Scan on purchases
--        -> Hash
--             -> Seq Scan on users
```

**特徴:**

- 中〜大規模なテーブル同士の JOIN に最適
- work_mem に依存（足りないと temp read/written 発生）
- 等価結合（=）でのみ使用可能

**最適化:**

```sql
-- work_memを増やしてHash表をメモリ内に収める
SET work_mem = '512MB';

-- 統計情報を更新してHashのサイズを正確に
ANALYZE users, purchases;
```

---

#### Merge Join（マージ結合）

```sql
EXPLAIN (ANALYZE)
SELECT u.username, p.amount
FROM users u
JOIN purchases p ON u.id = p.user_id
ORDER BY u.id;

-- 実行計画:
-- Merge Join
--   Merge Cond: (u.id = p.user_id)
--   -> Index Scan on users
--   -> Index Scan on purchases
```

**特徴:**

- 両方のテーブルがソート済みの場合に最速
- INDEX があれば自動的にソート済み
- 範囲結合（BETWEEN）でも使用可能

---

## 🎯 INDEX を作るべきケース・作らないケース

### ✅ INDEX を作るべきケース

#### 1. 超高選択性（該当行が少ない）

```sql
-- 1件だけヒット
SELECT * FROM users WHERE email = 'user_5000000@example.com';
-- 改善: 138ms → 3ms (43倍)

-- UNIQUE制約で自動的にINDEX作成
ALTER TABLE users ADD CONSTRAINT users_email_unique UNIQUE (email);
```

#### 2. COUNT 集計、集約クエリ

```sql
SELECT COUNT(*) FROM users WHERE age > 90;
-- 改善: 119ms → 16ms (7.5倍)
-- Index Only Scanで実テーブル不要

-- 部分INDEXでさらに高速化
CREATE INDEX idx_users_age_over_90 ON users(age) WHERE age > 90;
SELECT COUNT(*) FROM users WHERE age > 90;
-- → Index Only Scanで超高速
```

#### 3. ORDER BY、GROUP BY 頻出カラム

```sql
SELECT * FROM users WHERE country = 'USA' ORDER BY age;
-- 複合INDEX: (country, age)
CREATE INDEX idx_users_country_age ON users(country, age);

-- GROUP BYもINDEXで高速化
SELECT country, COUNT(*) FROM users GROUP BY country;
CREATE INDEX idx_users_country ON users(country);
```

#### 4. JOIN 条件の外部キー

```sql
SELECT * FROM purchases JOIN users ON purchases.user_id = users.id;
-- user_idにINDEX必須
CREATE INDEX idx_purchases_user_id ON purchases(user_id);

-- 外部キー制約で自動的にINDEX作成（PostgreSQLは作成しない！）
ALTER TABLE purchases ADD CONSTRAINT fk_user
FOREIGN KEY (user_id) REFERENCES users(id);
-- 手動でINDEX作成必須
CREATE INDEX idx_purchases_user_id ON purchases(user_id);
```

#### 5. LIMIT 付き検索

```sql
SELECT * FROM users WHERE age = 95 LIMIT 10;
-- INDEXで最初の10件を即座に取得
CREATE INDEX idx_users_age ON users(age);
```

#### 6. 【中級】部分 INDEX（Partial Index）

```sql
-- アクティブユーザーだけINDEX化
CREATE INDEX idx_users_active_age
ON users(age)
WHERE status = 'active';

-- INDEXサイズ削減 & 高速化
SELECT * FROM users WHERE status = 'active' AND age = 95;

-- 論理削除システムで有効
CREATE INDEX idx_users_not_deleted
ON users(id, username)
WHERE deleted_at IS NULL;
```

#### 7. 【中級】式 INDEX（Expression Index）

```sql
-- 関数を使った検索を高速化
CREATE INDEX idx_users_username_lower
ON users(LOWER(username));

SELECT * FROM users WHERE LOWER(username) = 'john';
-- → Index Scanが使える

-- 計算結果でINDEX
CREATE INDEX idx_users_total_amount
ON users((profile->>'total_amount')::numeric);

SELECT * FROM users
WHERE (profile->>'total_amount')::numeric > 1000;
```

#### 8. 【中級】複合 INDEX の列順最適化

```sql
-- ❌ 悪い例: 選択性の低い列が先
CREATE INDEX idx_users_age_email ON users(age, email);
-- age=95 で 62,500件ヒット → 非効率

-- ✅ 良い例: 選択性の高い列が先
CREATE INDEX idx_users_email_age ON users(email, age);
-- emailで1件に絞ってからageでフィルタ

-- 【黄金ルール】
-- 1. WHERE句の等価条件（=）を先に
-- 2. WHERE句の範囲条件（>, <, BETWEEN）を次に
-- 3. ORDER BY句のカラムを最後に

-- 実例
CREATE INDEX idx_users_country_age_created
ON users(country, age, created_at);

SELECT * FROM users
WHERE country = 'Japan'    -- 等価条件（先頭）
  AND age BETWEEN 20 AND 30  -- 範囲条件（中間）
ORDER BY created_at DESC;    -- ソート（最後）
```

---

### ❌ INDEX を作らない方がいいケース

#### 1. 低選択性（該当行が多い）

```sql
-- 62,500件ヒット（全体の0.6%）でも遅くなった
SELECT * FROM users WHERE age = 95;
-- 結果: 191ms → 299ms (1.6倍遅い)
```

#### 2. 大半の行がヒットする条件

```sql
-- 90%以上ヒット
SELECT * FROM users WHERE age > 20;
-- Seq Scanの方が確実に速い
```

#### 3. 小さなテーブル（数千行以下）

```sql
-- 1000行のテーブルにINDEXは不要
-- Seq Scanの方が速い
```

#### 4. 頻繁に INSERT/UPDATE されるテーブル

```sql
-- INDEXが多いと書き込み性能が劣化
-- 目安: 1テーブルあたり5〜10個まで

-- 未使用INDEXを定期的に削除
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public' AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- 削除
DROP INDEX IF EXISTS idx_users_unused;
```

#### 5. カラムに関数や演算を使う検索

```sql
-- ❌ INDEXが使えない
SELECT * FROM users WHERE age * 2 = 60;
SELECT * FROM users WHERE UPPER(username) = 'USER_100';

-- ✅ 式INDEXで対応
CREATE INDEX idx_users_age_doubled ON users((age * 2));
CREATE INDEX idx_users_username_upper ON users(UPPER(username));
```

---

## 🛠️ 実務での INDEX 設計フロー

### ステップ 1: スロークエリを特定

```sql
-- pg_stat_statements拡張を有効化（postgresql.conf）
shared_preload_libraries = 'pg_stat_statements'

-- 再起動後に拡張作成
CREATE EXTENSION pg_stat_statements;

-- スロークエリTOP10
SELECT
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    max_exec_time,
    stddev_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- 統計リセット
SELECT pg_stat_statements_reset();
```

### ステップ 2: EXPLAIN ANALYZE で分析

```bash
docker exec -it postgres-explain-demo psql -U demouser -d explaindb
```

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT * FROM users WHERE age = 95;
```

**確認ポイント:**

- Seq Scan になっていないか？
- Execution Time は許容範囲か？
- rows（推定）と actual rows が大きくずれていないか？
- Buffers で temp read/written が出ていないか？

### ステップ 3: INDEX 作成を検討

```sql
-- 条件カラムにINDEX作成
CREATE INDEX idx_users_age ON users(age);

-- 統計情報更新
ANALYZE users;

-- INDEX作成の進捗確認（大きいテーブル）
SELECT
    now()::time,
    query,
    state,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE query LIKE 'CREATE INDEX%';
```

### ステップ 4: 効果測定

```sql
-- 再度EXPLAIN ANALYZE実行
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users WHERE age = 95;

-- 統計情報確認
SELECT
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE tablename = 'users' AND attname = 'age';
```

**確認ポイント:**

- Index Scan または Index Only Scan に変わったか？
- Execution Time が改善したか？
- もし遅くなったら INDEX を削除

### ステップ 5: 本番適用

```sql
-- INDEXを本番環境に適用
-- CONCURRENTLYオプションでロック回避
CREATE INDEX CONCURRENTLY idx_users_age ON users(age);

-- 失敗時の対処
-- CONCURRENTLY失敗時はINVALID状態になる
SELECT indexrelid::regclass, indisvalid
FROM pg_index
WHERE indisvalid = false;

-- INVALID INDEXを削除
DROP INDEX CONCURRENTLY idx_users_age;

-- 再作成
CREATE INDEX CONCURRENTLY idx_users_age ON users(age);
```

---

## 🎓 中級レベルの INDEX 設計テクニック

### 1. 複合 INDEX のカーディナリティ最適化

```sql
-- カーディナリティ（ユニーク値の数）を確認
SELECT
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE tablename = 'users';

-- 結果例:
-- country:  n_distinct = 100    (低カーディナリティ)
-- age:      n_distinct = 100    (低カーディナリティ)
-- email:    n_distinct = -1     (高カーディナリティ、-1 = 100%ユニーク)

-- ❌ 悪い例: 低カーディナリティを先頭に
CREATE INDEX idx_users_age_email ON users(age, email);

-- ✅ 良い例: 高カーディナリティを先頭に
CREATE INDEX idx_users_email_age ON users(email, age);

-- ただしWHERE句の条件次第で逆転する場合も
-- WHERE country = 'Japan' AND age BETWEEN 20 AND 30
-- この場合は country を先頭に（等価条件優先）
```

### 2. カバリング INDEX（INCLUDE 句）の活用

```sql
-- PostgreSQL 11以降
CREATE INDEX idx_users_age_inc
ON users(age)
INCLUDE (username, email, country, created_at);

-- これでIndex Only Scan成功
SELECT age, username, email, country, created_at
FROM users
WHERE age = 95;

-- 【重要】INCLUDE句のカラムはソートできない
-- ソートが必要ならINDEX列に含める
CREATE INDEX idx_users_age_created
ON users(age, created_at DESC)
INCLUDE (username, email);
```

### 3. 部分 INDEX（Partial Index）の戦略的活用

```sql
-- アクティブユーザーだけINDEX化
CREATE INDEX idx_users_active
ON users(age, country)
WHERE status = 'active' AND deleted_at IS NULL;

-- INDEXサイズが1/10に削減
-- 検索速度も向上

-- 使えるクエリ
SELECT * FROM users
WHERE status = 'active'
  AND deleted_at IS NULL
  AND age = 95;

-- 使えないクエリ（WHERE句が完全一致しない）
SELECT * FROM users WHERE age = 95;  -- status条件がない
```

### 4. 式 INDEX（Expression Index）の実践例

```sql
-- JSONB型のフィールド検索を高速化
CREATE INDEX idx_users_profile_total
ON users(((profile->>'total_amount')::numeric));

SELECT * FROM users
WHERE (profile->>'total_amount')::numeric > 1000;

-- 日付の年月でGROUP BY
CREATE INDEX idx_purchases_month
ON purchases(DATE_TRUNC('month', purchased_at));

SELECT DATE_TRUNC('month', purchased_at), COUNT(*)
FROM purchases
GROUP BY DATE_TRUNC('month', purchased_at);

-- 全文検索INDEX
CREATE INDEX idx_articles_content_fts
ON articles USING GIN (to_tsvector('english', content));

SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('postgresql & performance');
```

### 5. マルチカラム統計の作成

```sql
-- 相関のある複数カラムの統計を作成
CREATE STATISTICS stats_users_country_age
ON country, age
FROM users;

ANALYZE users;

-- これでWHERE country = 'Japan' AND age = 95 の推定精度向上
```

### 6. INDEX-Only Scan を実現するテクニック

```sql
-- 方法1: INCLUDE句
CREATE INDEX idx_users_age_inc
ON users(age)
INCLUDE (username, email);

-- 方法2: 複合INDEX
CREATE INDEX idx_users_age_username_email
ON users(age, username, email);

-- 方法3: VACUUMでVisibility Map更新
VACUUM ANALYZE users;

-- 自動VACUUM設定の確認
SELECT
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
WHERE tablename = 'users';

-- 自動VACUUMの頻度を上げる
ALTER TABLE users SET (
    autovacuum_vacuum_scale_factor = 0.05,  -- デフォルト0.2
    autovacuum_analyze_scale_factor = 0.05  -- デフォルト0.1
);
```

### 7. Bloom Filter INDEX の活用

```sql
-- PostgreSQL 9.6以降
CREATE EXTENSION bloom;

-- 複数カラムのOR条件で効果的
CREATE INDEX idx_users_bloom
ON users USING bloom (age, country, status);

SELECT * FROM users
WHERE age = 95 OR country = 'Japan' OR status = 'active';
-- → Bloom Filter INDEXが使える
```

### 8. BRIN INDEX（Block Range Index）

```sql
-- 時系列データで超高速（INDEXサイズが1/100）
CREATE INDEX idx_purchases_created_brin
ON purchases USING BRIN (created_at);

-- 適用条件:
-- 1. データが物理的にソートされている
-- 2. 範囲検索が多い
-- 3. テーブルサイズが巨大（数億行以上）

-- correlation確認
SELECT attname, correlation
FROM pg_stats
WHERE tablename = 'purchases' AND attname = 'created_at';
-- correlation が 1.0 に近いほど効果的
```

### 9. GiST/GININDEX の使い分け

```sql
-- GiST: 幾何データ、全文検索
CREATE INDEX idx_locations_gist
ON locations USING GIST (coordinates);

SELECT * FROM locations
WHERE coordinates && ST_MakeEnvelope(0, 0, 10, 10);

-- GIN: JSONB、配列、全文検索
CREATE INDEX idx_tags_gin
ON articles USING GIN (tags);

SELECT * FROM articles WHERE tags @> ARRAY['postgresql'];
```

---

## 💻 便利なコマンド

### PostgreSQL に接続

```bash
docker exec -it postgres-explain-demo psql -U demouser -d explaindb
```

### INDEX 一覧確認

```sql
\di

-- 詳細版
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
```

### INDEX 使用状況確認

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
```

### 未使用 INDEX の検出

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public' AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- 削除前に確認
-- DROP INDEX IF EXISTS indexname;
```

### テーブル・INDEX サイズ確認

```sql
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(tablename::regclass)) AS total_size,
    pg_size_pretty(pg_relation_size(tablename::regclass)) AS table_size,
    pg_size_pretty(pg_total_relation_size(tablename::regclass) - pg_relation_size(tablename::regclass)) AS indexes_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(tablename::regclass) DESC;
```

### INDEX 肥大化の検出

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan,
    CASE
        WHEN idx_scan = 0 THEN 'UNUSED'
        WHEN pg_relation_size(indexrelid) > 100 * 1024 * 1024 THEN 'LARGE'
        ELSE 'OK'
    END AS status
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### INDEX 再構築（肥大化解消）

```sql
-- 通常のREINDEX（ロックあり）
REINDEX INDEX idx_users_age;

-- CONCURRENTLY（ロックなし、PostgreSQL 12以降）
REINDEX INDEX CONCURRENTLY idx_users_age;

-- テーブル全体のINDEX再構築
REINDEX TABLE CONCURRENTLY users;
```

### 統計情報の確認と更新

```sql
-- 統計情報の確認
SELECT
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation,
    most_common_vals,
    most_common_freqs
FROM pg_stats
WHERE tablename = 'users'
ORDER BY attname;

-- 統計情報の更新
ANALYZE users;

-- 特定カラムの統計精度を上げる
ALTER TABLE users ALTER COLUMN age SET STATISTICS 1000;
ANALYZE users;
```

### キャッシュヒット率の確認

```sql
-- テーブルごとのキャッシュヒット率
SELECT
    schemaname,
    tablename,
    heap_blks_read,
    heap_blks_hit,
    CASE
        WHEN heap_blks_hit + heap_blks_read = 0 THEN 0
        ELSE ROUND(100.0 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 2)
    END AS cache_hit_ratio
FROM pg_statio_user_tables
WHERE schemaname = 'public'
ORDER BY heap_blks_read DESC;

-- 全体のキャッシュヒット率
SELECT
    ROUND(100.0 * sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)), 2) AS cache_hit_ratio
FROM pg_statio_user_tables;
```

---

## ❓ よくある質問（中級編）

### Q1: INDEX を作成したのに使われない

**原因と対策:**

#### 1. 統計情報が古い

```sql
ANALYZE users;

-- 自動ANALYZE設定確認
SELECT
    tablename,
    last_analyze,
    last_autoanalyze,
    analyze_count,
    autoanalyze_count
FROM pg_stat_user_tables
WHERE tablename = 'users';
```

#### 2. 選択性が低い（該当行が多すぎる）

```sql
-- PostgreSQLが「Seq Scanの方が速い」と判断
-- 正常な動作

-- 統計情報で確認
SELECT
    attname,
    n_distinct,
    most_common_vals,
    most_common_freqs
FROM pg_stats
WHERE tablename = 'users' AND attname = 'age';
```

#### 3. WHERE 句でカラムに演算している

```sql
-- ❌ INDEXが使えない
WHERE age + 1 = 30
WHERE LOWER(username) = 'john'

-- ✅ INDEXが使える
WHERE age = 29
CREATE INDEX idx_users_username_lower ON users(LOWER(username));
```

#### 4. 複合 INDEX の列順が合わない

```sql
-- INDEX: (country, age)
CREATE INDEX idx_users_country_age ON users(country, age);

-- ✅ 使える
WHERE country = 'Japan' AND age = 95

-- ⚠️ 部分的に使える（countryのみ）
WHERE country = 'Japan'

-- ❌ 使えない
WHERE age = 95
```

#### 5. データ型の不一致

```sql
-- カラム: age INTEGER
-- ❌ INDEXが使えない
WHERE age = '95'  -- 文字列

-- ✅ INDEXが使える
WHERE age = 95    -- 整数
```

---

### Q2: INDEX 有りの方が遅くなった

**これは正常です。**

#### 原因 1: 該当件数が多い

```sql
-- 全体の1%以上ヒットする場合、Seq Scanの方が速い
SELECT * FROM users WHERE age BETWEEN 20 AND 80;
-- → ランダムI/Oのオーバーヘッド > Seq Scanの連続I/O
```

#### 原因 2: SELECT \* で全カラム取得

```sql
-- ❌ Heap Fetch大量発生
SELECT * FROM users WHERE age = 95;

-- ✅ 必要なカラムだけ取得
SELECT id, username, email FROM users WHERE age = 95;
-- → Index Only Scanの可能性
```

#### 原因 3: correlation が低い

```sql
-- 物理的な並び順とINDEXの並び順が一致しない
SELECT correlation FROM pg_stats
WHERE tablename = 'users' AND attname = 'age';

-- correlation = 0.1 の場合、ランダムI/O多発
-- 対策: CLUSTER（一度だけ有効）
CLUSTER users USING idx_users_age;
ANALYZE users;
```

---

### Q3: どのカラムに INDEX を作ればいい？

**優先順位:**

#### 1. 外部キー（JOIN 条件）

```sql
CREATE INDEX idx_purchases_user_id ON purchases(user_id);
```

#### 2. WHERE 句で頻繁に使うカラム（高選択性）

```sql
-- 選択性を確認
SELECT
    attname,
    n_distinct,
    CASE
        WHEN n_distinct = -1 THEN '100% unique'
        WHEN n_distinct > 0 THEN n_distinct || ' distinct values'
        ELSE (ABS(n_distinct) * 100)::text || '% of table'
    END AS selectivity
FROM pg_stats
WHERE tablename = 'users';

-- n_distinct が大きいほど選択性が高い
```

#### 3. ORDER BY、GROUP BY 頻出カラム

```sql
CREATE INDEX idx_users_created_at ON users(created_at DESC);
```

#### 4. ユニーク制約カラム

```sql
ALTER TABLE users ADD CONSTRAINT users_email_unique UNIQUE (email);
-- 自動的にINDEX作成される
```

---

### Q4: INDEX はいくつまで作っていい？

**目安:**

- 1 テーブルあたり **5〜10 個まで**
- それ以上は INSERT/UPDATE 性能に影響

**検証方法:**

```sql
-- INDEXの数を確認
SELECT
    tablename,
    COUNT(*) AS index_count,
    pg_size_pretty(SUM(pg_relation_size(indexrelid))) AS total_index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
GROUP BY tablename
ORDER BY COUNT(*) DESC;

-- INSERT性能を測定
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO users (username, email, age, country)
VALUES ('test', 'test@example.com', 30, 'Japan');
```

**未使用 INDEX は定期的に削除:**

```sql
-- 未使用INDEXを検出
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public' AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- 削除
DROP INDEX IF EXISTS idx_users_unused;
```

---

### Q5: 複合 INDEX の列順はどう決める？

**黄金ルール:**

1. **WHERE 句の等価条件（=）を先頭に**
2. **WHERE 句の範囲条件（>, <, BETWEEN）を次に**
3. **ORDER BY 句のカラムを最後に**

**実例:**

```sql
-- クエリ
SELECT * FROM users
WHERE country = 'Japan'        -- 等価条件
  AND age BETWEEN 20 AND 30    -- 範囲条件
ORDER BY created_at DESC;      -- ソート

-- 最適なINDEX
CREATE INDEX idx_users_country_age_created
ON users(country, age, created_at DESC);
```

**例外: カーディナリティ優先**

```sql
-- country: 100種類（低カーディナリティ）
-- email: 1000万種類（高カーディナリティ）

-- ✅ 高カーディナリティを先頭に
CREATE INDEX idx_users_email_country ON users(email, country);

-- WHERE email = 'xxx' AND country = 'Japan'
-- → emailで1件に絞ってからcountryでフィルタ
```

---

### Q6: INDEX のメンテナンスはどうすればいい？

#### 定期的な VACUUM

```sql
-- 手動VACUUM
VACUUM ANALYZE users;

-- 自動VACUUM設定確認
SELECT
    tablename,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
WHERE tablename = 'users';

-- 自動VACUUMの頻度を上げる
ALTER TABLE users SET (
    autovacuum_vacuum_scale_factor = 0.05,
    autovacuum_analyze_scale_factor = 0.05
);
```

#### INDEX 再構築

```sql
-- INDEX肥大化の検出
SELECT
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE tablename = 'users'
ORDER BY pg_relation_size(indexrelid) DESC;

-- 再構築
REINDEX INDEX CONCURRENTLY idx_users_age;
```

#### 統計情報の更新

```sql
-- 手動ANALYZE
ANALYZE users;

-- 特定カラムの統計精度を上げる
ALTER TABLE users ALTER COLUMN age SET STATISTICS 1000;
ANALYZE users;
```

---

## 🎓 実務レベルのチェックリスト（中級編）

### ✅ 習得すべき知識

- [x] **EXPLAIN の詳細な読み方**

  - cost 計算式の理解
  - rows と actual rows のズレ解消
  - Buffers の詳細分析（temp read/written 検出）

- [x] **主要なスキャン方式の完全理解**

  - Seq Scan、Index Scan、Index Only Scan
  - Bitmap Index Scan、Parallel Seq Scan
  - Nested Loop、Hash Join、Merge Join

- [x] **INDEX が効くケース・効かないケースの判断**

  - 選択性（n_distinct）の確認方法
  - correlation の意味と影響
  - COUNT(\*)や LIMIT での INDEX 効果

- [x] **INDEX が逆効果になるケースの理解**

  - 低選択性クエリでのランダム I/O 問題
  - Heap Blocks 大量発生による性能劣化

- [x] **実務フローの完全理解**

  - pg_stat_statements でスロークエリ特定
  - EXPLAIN ANALYZE 分析
  - INDEX 作成（CONCURRENTLY）
  - 効果測定と統計情報更新

- [x] **中級 INDEX テクニック**

  - 複合 INDEX の列順最適化
  - カバリング INDEX（INCLUDE 句）
  - 部分 INDEX（Partial Index）
  - 式 INDEX（Expression Index）

- [x] **INDEX メンテナンス**
  - VACUUM、ANALYZE、REINDEX
  - 未使用 INDEX 検出と削除
  - INDEX 肥大化の検出と対処

### 🚀 さらに上を目指すなら（上級編）

以下は大規模システムで必要になる知識です：

- [ ] **パーティショニング**

  - 範囲パーティション（RANGE）
  - リストパーティション（LIST）
  - ハッシュパーティション（HASH）

- [ ] **レプリケーションと INDEX**

  - ストリーミングレプリケーション
  - ロジカルレプリケーション
  - スタンバイサーバーでの INDEX 作成

- [ ] **高度な INDEX**

  - BRIN INDEX（Block Range Index）
  - Bloom Filter INDEX
  - GiST/GIN INDEX（幾何データ、JSONB）

- [ ] **クエリプランナーのチューニング**

  - random_page_cost の最適化
  - effective_cache_size の調整
  - work_mem の動的設定

- [ ] **大規模データの最適化**
  - テーブルパーティショニング
  - CLUSTER（物理的ソート）
  - FILLFACTOR 調整

---

## 📚 参考資料

- [PostgreSQL 公式ドキュメント - EXPLAIN](https://www.postgresql.org/docs/current/sql-explain.html)
- [PostgreSQL 公式ドキュメント - INDEX](https://www.postgresql.org/docs/current/indexes.html)
- [PostgreSQL 公式ドキュメント - 性能チューニング](https://www.postgresql.org/docs/current/performance-tips.html)
- [PostgreSQL 公式ドキュメント - 統計情報](https://www.postgresql.org/docs/current/planner-stats.html)
- [Use The Index, Luke!](https://use-the-index-luke.com/)

---

## 🎉 まとめ

この中級編で学んだ知識があれば、**実務での高度な EXPLAIN 分析と INDEX 設計が可能**です。

**重要なポイント:**

1. EXPLAIN で実行計画を詳細に読めること
2. INDEX は万能ではなく、適切に使い分けること
3. 選択性（n_distinct）と correlation を理解すること
4. 複合 INDEX の列順を最適化できること
5. 部分 INDEX、式 INDEX、カバリング INDEX を使いこなすこと
6. 定期的なメンテナンス（VACUUM、ANALYZE、REINDEX）を実施すること
7. 実測（EXPLAIN ANALYZE）で効果を必ず確認すること

Happy Learning! 🎉
