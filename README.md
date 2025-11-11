# PostgreSQL EXPLAIN + INDEX 設計学習プロジェクト

100 万件のデータで INDEX の効果を体感し、EXPLAIN の読み方をマスターするプロジェクトです。

## 📁 プロジェクト構成

```
postgres-explain-index/
├── docker-compose.yml          # PostgreSQL環境定義
├── README.md                   # このファイル
├── init/
│   └── 01_init_all.sql        # テーブル作成 + 100万件データ自動生成
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
- 100 万件のユーザーデータ生成
- 200 万件の購入履歴生成

**所要時間**: 初回起動時 約 30 秒〜1 分

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

1. INDEX 無しでクエリ実行（5 種類）
2. INDEX 作成
3. INDEX 有りでクエリ実行
4. EXPLAIN ANALYZE で実行計画表示
5. INDEX 情報表示
6. INDEX 削除（次回測定のため）

## 📊 EXPLAIN の読み方

### 基本的な出力例

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age = 30;

Seq Scan on users  (cost=0.00..20000.00 rows=10000 width=100)
                    (actual time=0.050..250.123 rows=16667 loops=1)
  Filter: (age = 30)
  Rows Removed by Filter: 983333
Planning Time: 0.123 ms
Execution Time: 260.456 ms
```

### 主要項目の意味

| 項目                    | 意味                 | 補足                   |
| ----------------------- | -------------------- | ---------------------- |
| **Seq Scan**            | 全行スキャン         | INDEX 無し、遅い       |
| **Index Scan**          | INDEX スキャン       | INDEX 使用、速い       |
| **Bitmap Index Scan**   | ビットマップスキャン | 複数行を効率的に取得   |
| **cost=0.00..20000.00** | コスト推定値         | 開始コスト..終了コスト |
| **rows=10000**          | 推定行数             | オプティマイザの予測   |
| **actual time**         | 実際の時間（ms）     | 実測値                 |
| **Planning Time**       | 実行計画作成時間     | -                      |
| **Execution Time**      | 実行時間             | **この値が最重要**     |

### 良い実行計画 vs 悪い実行計画

| 項目         | 良い状態                | 悪い状態         |
| ------------ | ----------------------- | ---------------- |
| スキャン方法 | `Index Scan`            | `Seq Scan`       |
| コスト       | 低い（数百以下）        | 高い（数万以上） |
| 推定精度     | rows と実際の行数が近い | 大きくずれている |
| 実行時間     | 10ms 以下               | 100ms 以上       |

## 🎯 INDEX 効果の例（期待値）

| クエリ種類              | INDEX 無し | INDEX 有り | 改善率    |
| ----------------------- | ---------- | ---------- | --------- |
| `age = 30`              | 200ms      | 5ms        | **40 倍** |
| `age BETWEEN 25 AND 35` | 220ms      | 15ms       | **15 倍** |
| `country = 'Japan'`     | 180ms      | 8ms        | **22 倍** |
| `email = 'xxx@xxx.com'` | 210ms      | 3ms        | **70 倍** |
| `JOIN ... ON user_id`   | 500ms      | 50ms       | **10 倍** |

## 🔍 INDEX 作成の基本

```sql
-- 単一カラムINDEX
CREATE INDEX idx_users_age ON users(age);

-- 複合INDEX（検索条件が複数の場合）
CREATE INDEX idx_users_country_age ON users(country, age);

-- ユニークINDEX
CREATE UNIQUE INDEX idx_users_email ON users(email);
```

## 🧪 実験アイデア

### 実験 1: 複合 INDEX の列順による違い

```bash
# PostgreSQLに接続
docker exec -it postgres-explain-demo psql -U demouser -d explaindb
```

```sql
-- パターン1: (country, age)
CREATE INDEX idx_1 ON users(country, age);
EXPLAIN ANALYZE SELECT * FROM users WHERE country = 'Japan' AND age = 30;
DROP INDEX idx_1;

-- パターン2: (age, country)
CREATE INDEX idx_2 ON users(age, country);
EXPLAIN ANALYZE SELECT * FROM users WHERE country = 'Japan' AND age = 30;
DROP INDEX idx_2;

-- どちらが速い？コストは？
```

**学習ポイント**: 複合 INDEX は左側のカラムから使われる

### 実験 2: INDEX が使われないケース

```sql
-- ❌ INDEXが使われない例（カラムに演算）
EXPLAIN ANALYZE SELECT * FROM users WHERE age + 0 = 30;

-- ✅ INDEXが使われる例
EXPLAIN ANALYZE SELECT * FROM users WHERE age = 30;
```

**学習ポイント**: WHERE 句のカラムに演算を加えると INDEX 無効化

### 実験 3: 部分 INDEX

```sql
-- activeユーザーだけにINDEX（INDEXサイズを削減）
CREATE INDEX idx_users_active_age ON users(age) WHERE status = 'active';

-- このクエリでINDEXが使われる
EXPLAIN ANALYZE SELECT * FROM users WHERE age = 30 AND status = 'active';

-- このクエリではINDEXが使われない
EXPLAIN ANALYZE SELECT * FROM users WHERE age = 30 AND status = 'inactive';

DROP INDEX idx_users_active_age;
```

### 実験 4: LIKE 検索と INDEX

```sql
CREATE INDEX idx_users_username ON users(username);

-- ✅ 前方一致はINDEX使用可能
EXPLAIN ANALYZE SELECT * FROM users WHERE username LIKE 'user_100%';

-- ❌ 中間一致・後方一致はINDEX使用不可
EXPLAIN ANALYZE SELECT * FROM users WHERE username LIKE '%100%';

DROP INDEX idx_users_username;
```

## 🛠️ 便利なコマンド

### PostgreSQL に接続

```bash
docker exec -it postgres-explain-demo psql -U demouser -d explaindb
```

### INDEX 一覧確認

```sql
\di
```

### テーブルサイズ確認

```sql
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(tablename::regclass)) AS size
FROM pg_tables
WHERE schemaname = 'public';
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

### INDEX サイズ確認

```sql
SELECT
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### 未使用 INDEX の検出

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan
FROM pg_stat_user_indexes
WHERE schemaname = 'public' AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

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
# ボリューム削除して再起動
docker compose down -v
docker compose up -d

# 初期化スクリプトが再実行される
```

## 📚 学習ポイント

### INDEX が効果的なケース

✅ **効果大**

- 等価検索: `WHERE age = 30`
- 範囲検索: `WHERE age BETWEEN 25 AND 35`
- ソート: `ORDER BY age`
- JOIN 条件: `JOIN ON user_id`
- ユニーク制約の検索: `WHERE email = 'xxx@xxx.com'`
- 前方一致 LIKE: `WHERE username LIKE 'user_100%'`

❌ **効果薄/逆効果**

- 大半の行がヒット: `WHERE age > 10`（ほぼ全員該当）
- カラムに演算: `WHERE age * 2 = 60`
- 関数使用: `WHERE UPPER(username) = 'USER_1'`
- 中間/後方一致 LIKE: `WHERE username LIKE '%test%'`
- 小さなテーブル（数百〜数千行程度）
- カーディナリティが低い列（例: 性別カラムで男/女の 2 値のみ）

### EXPLAIN で注目すべき点

1. **スキャン方法**: Seq Scan → Index Scan に変わったか？
2. **コスト**: cost の値が大幅に下がったか？
3. **実行時間**: actual time / Execution Time が改善したか？
4. **推定精度**: rows（推定）と実際の行数が近いか？
5. **Buffers**: shared hit（キャッシュヒット）が多いか？

### INDEX 設計のベストプラクティス

1. **WHERE 句で頻繁に使う列に INDEX を作成**
2. **JOIN 条件の列に INDEX を作成**
3. **複合 INDEX は選択性の高い列を左に配置**
4. **INDEX の数は必要最小限に**（書き込み性能への影響）
5. **ANALYZE 定期実行で統計情報を最新に保つ**

## 🔧 トラブルシューティング

### Q: ベンチマークで INDEX の効果が見られない

```bash
# 統計情報を更新
docker exec postgres-explain-demo psql -U demouser -d explaindb -c "ANALYZE users; ANALYZE purchases;"

# 再度ベンチマーク実行
./scripts/benchmark.sh
```

### Q: ポート 15432 が既に使われている

`docker-compose.yml` のポート番号を変更：

```yaml
ports:
  - "15433:5432" # 別のポート番号に変更
```

`scripts/benchmark.sh` も同様に変更：

```bash
PGPORT="15433"  # 同じポート番号に変更
```

### Q: データ生成に失敗した

```bash
# 完全リセット
docker compose down -v
docker compose up -d

# ログで確認
docker compose logs -f postgres
```

## 💡 次のステップ

1. ✅ 基本的な INDEX の効果を理解
2. 🔄 複合 INDEX の列順による違いを実験
3. 🔄 部分 INDEX の活用
4. 🔄 JSONB 型の INDEX（GIN/GiST インデックス）
5. 🔄 フルテキスト検索 INDEX
6. 🔄 パーティショニングとの組み合わせ
7. 🔄 カバリング INDEX（INCLUDE 句）
8. 🔄 INDEX Only スキャンの活用

## 📖 参考資料

- [PostgreSQL 公式ドキュメント - EXPLAIN](https://www.postgresql.org/docs/current/sql-explain.html)
- [PostgreSQL 公式ドキュメント - INDEX](https://www.postgresql.org/docs/current/indexes.html)
- [PostgreSQL 公式ドキュメント - 性能チューニング](https://www.postgresql.org/docs/current/performance-tips.html)

---

Happy Learning! 🎉
