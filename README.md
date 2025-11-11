# PostgreSQL EXPLAIN + INDEX 設計学習プロジェクト

1000 万件のデータで INDEX の効果を体感し、EXPLAIN の読み方をマスターするプロジェクトです。

## 📁 プロジェクト構成

```
postgres-explain-index/
├── docker-compose.yml          # PostgreSQL環境定義
├── README.md                   # このファイル
├── init/
│   └── 01_init_all.sql        # テーブル作成 + 1000万件データ自動生成
└── scripts/
    ├── benchmark.sh           # INDEX効果比較（自動測定）
    └── explain_queries.sql    # EXPLAIN学習用クエリ集
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

**このスクリプトが自動で実行:**

1. INDEX 無しでクエリ実行（6 種類）
2. INDEX 作成
3. INDEX 有りでクエリ実行
4. EXPLAIN ANALYZE で実行計画詳細比較
5. INDEX 情報表示
6. INDEX 削除（次回測定のため）

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

4. **COUNT(\*)は INDEX Only Scan で高速化**
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

**対策:**

- 適切な INDEX を作成
- WHERE 句の条件を見直し

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

**最適なケース:**

- ユニークキー検索
- 超高選択性の条件

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

**最適なケース:**

- `COUNT(*)`
- `SELECT id, indexed_column`
- カバリング INDEX 使用時

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

**注意点:**

- `Heap Blocks` が多い = ランダム I/O 大量発生
- 該当件数が多すぎると Seq Scan より遅くなる

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

**見るべきポイント:**

- `Workers Launched: 2` = 2 つのワーカーで並列実行
- loops=3 = メイン+ワーカー 2 の合計 3 プロセス

---

## 🎯 INDEX を作るべきケース・作らないケース

### ✅ INDEX を作るべきケース

1. **超高選択性（該当行が少ない）**

```sql
   -- 1件だけヒット
   SELECT * FROM users WHERE email = 'user_5000000@example.com';
   -- 改善: 138ms → 3ms (43倍)
```

2. **COUNT 集計、集約クエリ**

```sql
   SELECT COUNT(*) FROM users WHERE age > 90;
   -- 改善: 119ms → 16ms (7.5倍)
   -- Index Only Scanで実テーブル不要
```

3. **ORDER BY、GROUP BY 頻出カラム**

```sql
   SELECT * FROM users WHERE country = 'USA' ORDER BY age;
   -- 複合INDEX: (country, age)
```

4. **JOIN 条件の外部キー**

```sql
   SELECT * FROM purchases JOIN users ON purchases.user_id = users.id;
   -- user_idにINDEX必須
```

5. **LIMIT 付き検索**

```sql
   SELECT * FROM users WHERE age = 95 LIMIT 10;
   -- INDEXで最初の10件を即座に取得
```

---

### ❌ INDEX を作らない方がいいケース

1. **低選択性（該当行が多い）**

```sql
   -- 62,500件ヒット（全体の0.6%）でも遅くなった
   SELECT * FROM users WHERE age = 95;
   -- 結果: 191ms → 299ms (1.6倍遅い)
```

2. **大半の行がヒットする条件**

```sql
   -- 90%以上ヒット
   SELECT * FROM users WHERE age > 20;
   -- Seq Scanの方が確実に速い
```

3. **小さなテーブル（数千行以下）**

   - INDEX のオーバーヘッドの方が大きい

4. **頻繁に INSERT/UPDATE されるテーブル**

   - INDEX 更新コストが高い

5. **カラムに関数や演算を使う検索**

```sql
   -- INDEXが使えない
   SELECT * FROM users WHERE age * 2 = 60;
   SELECT * FROM users WHERE UPPER(username) = 'USER_100';
```

---

## 🛠️ 実務での INDEX 設計フロー

### ステップ 1: スロークエリを特定

```sql
-- 実行時間が遅いクエリをログから特定
-- または pg_stat_statements拡張を使用
```

### ステップ 2: EXPLAIN ANALYZE で分析

```bash
docker exec -it postgres-explain-demo psql -U demouser -d explaindb
```

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users WHERE age = 95;
```

**確認ポイント:**

- Seq Scan になっていないか？
- Execution Time は許容範囲か？
- rows（推定）と actual rows が大きくずれていないか？

### ステップ 3: INDEX 作成を検討

```sql
-- 条件カラムにINDEX作成
CREATE INDEX idx_users_age ON users(age);

-- 統計情報更新
ANALYZE users;
```

### ステップ 4: 効果測定

```sql
-- 再度EXPLAIN ANALYZE実行
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users WHERE age = 95;
```

**確認ポイント:**

- Index Scan または Index Only Scan に変わったか？
- Execution Time が改善したか？
- もし遅くなったら INDEX を削除

### ステップ 5: 本番適用

```sql
-- INDEXを本番環境に適用
-- CONCURRENTLY オプションでロック回避
CREATE INDEX CONCURRENTLY idx_users_age ON users(age);
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
```

### INDEX 使用状況確認

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
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
```

### テーブル・INDEX サイズ確認

```sql
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(tablename::regclass)) AS total_size,
    pg_size_pretty(pg_relation_size(tablename::regclass)) AS table_size,
    pg_size_pretty(pg_total_relation_size(tablename::regclass) - pg_relation_size(tablename::regclass)) AS indexes_size
FROM pg_tables
WHERE schemaname = 'public';
```

---

## 🎓 実務レベルのチェックリスト

このプロジェクトで以下を習得すれば、**実務での EXPLAIN+INDEX 設計は十分対応可能**です：

### ✅ 習得すべき知識

- [x] **EXPLAIN の基本的な読み方**

  - cost、rows、actual time、Execution Time の意味
  - Buffers（キャッシュヒット/ディスク I/O）の見方

- [x] **主要なスキャン方式の理解**

  - Seq Scan、Index Scan、Index Only Scan、Bitmap Index Scan
  - Parallel Seq Scan の仕組み

- [x] **INDEX が効くケース・効かないケースの判断**

  - 選択性（該当件数の割合）の重要性
  - COUNT(\*) や LIMIT での INDEX 効果

- [x] **INDEX が逆効果になるケースの理解**

  - 低選択性クエリでのランダム I/O 問題
  - Heap Blocks 大量発生による性能劣化

- [x] **実務フローの理解**
  - スロークエリ特定 → EXPLAIN 分析 → INDEX 作成 → 効果測定

### 🚀 さらに上を目指すなら

以下は実務で遭遇する頻度は低いですが、知っておくと役立ちます：

- [ ] **複合 INDEX の列順最適化**

```sql
  -- 選択性の高い列を左に
  CREATE INDEX idx_users_country_age ON users(country, age);
```

- [ ] **部分 INDEX**

```sql
  -- 条件付きINDEX（INDEXサイズ削減）
  CREATE INDEX idx_active_users ON users(age) WHERE status = 'active';
```

- [ ] **カバリング INDEX（INCLUDE 句）**

```sql
  -- PostgreSQL 11以降
  CREATE INDEX idx_users_age_inc ON users(age) INCLUDE (username, email);
  -- Index Only Scanが可能に
```

- [ ] **JSONB 型の GIN インデックス**

```sql
  CREATE INDEX idx_data_gin ON documents USING GIN (data);
```

- [ ] **全文検索 INDEX**

```sql
  CREATE INDEX idx_content_fts ON articles USING GIN (to_tsvector('english', content));
```

- [ ] **パーティショニング**
  - 大規模テーブルの分割管理

---

## 🧹 クリーンアップ

### コンテナ停止

```bash
docker compose down
```

### データも含めて完全削除

```bash
docker compose down -v
```

### データを再生成したい場合

```bash
docker compose down -v
docker compose up -d
```

---

## ❓ よくある質問

### Q1: INDEX を作成したのに使われない

**原因と対策:**

1. **統計情報が古い**

```sql
   ANALYZE users;
```

2. **選択性が低い（該当行が多すぎる）**

   - PostgreSQL が「Seq Scan の方が速い」と判断
   - 正常な動作

3. **WHERE 句でカラムに演算している**

```sql
   -- ❌ INDEXが使えない
   WHERE age + 1 = 30

   -- ✅ INDEXが使える
   WHERE age = 29
```

### Q2: INDEX 有りの方が遅くなった

**これは正常です。**

- 該当件数が多い場合（全体の 1%以上）
- ランダム I/O のオーバーヘッド > Seq Scan の連続 I/O
- その INDEX は削除して OK

### Q3: どのカラムに INDEX を作ればいい？

**優先順位:**

1. **外部キー（JOIN 条件）**
2. **WHERE 句で頻繁に使うカラム**（高選択性）
3. **ORDER BY、GROUP BY 頻出カラム**
4. **ユニーク制約カラム**

### Q4: INDEX はいくつまで作っていい？

**目安:**

- 1 テーブルあたり **5〜10 個まで**
- それ以上は INSERT/UPDATE 性能に影響
- **未使用 INDEX は定期的に削除**

---

## 📚 参考資料

- [PostgreSQL 公式ドキュメント - EXPLAIN](https://www.postgresql.org/docs/current/sql-explain.html)
- [PostgreSQL 公式ドキュメント - INDEX](https://www.postgresql.org/docs/current/indexes.html)
- [PostgreSQL 公式ドキュメント - 性能チューニング](https://www.postgresql.org/docs/current/performance-tips.html)

---

## 🎉 まとめ

このプロジェクトで学んだ知識があれば、**実務での EXPLAIN 分析と INDEX 設計は十分対応可能**です。

**重要なポイント:**

1. EXPLAIN で実行計画を読めること
2. INDEX は万能ではなく、逆効果になることもある
3. 選択性（該当件数の割合）が最重要
4. 実測（EXPLAIN ANALYZE）で効果を必ず確認

Happy Learning! 🎉
