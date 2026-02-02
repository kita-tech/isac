# ISAC Memory Service 詳細ドキュメント

> このドキュメントは10人の専門家による議論を経て作成されました。
> 最終更新: 2026-02-02 | バージョン: 2.1.0

---

## 目次

1. [概要](#概要)
2. [アーキテクチャ](#アーキテクチャ)
3. [データモデル](#データモデル)
4. [メモリタイプの決定方法](#メモリタイプの決定方法)
5. [スコープと階層構造](#スコープと階層構造)
6. [ユースケース](#ユースケース)
7. [API リファレンス](#api-リファレンス)
8. [デプロイメント](#デプロイメント)
9. [セキュリティ](#セキュリティ)
10. [運用ガイド](#運用ガイド)
11. [トラブルシューティング](#トラブルシューティング)
12. [FAQ](#faq)

---

## 概要

### Memory Serviceとは？

Memory Serviceは、ISACシステムの中核を担う**長期記憶管理サービス**です。AIエージェント（Claude Code CLI）が過去の決定事項、作業履歴、組織のナレッジを記憶・検索できるようにします。

```
┌─────────────────────────────────────────────────────────────┐
│                     Claude Code CLI                          │
│  「前回どんな決定をしたっけ？」                              │
│  「このプロジェクトの技術スタックは？」                      │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Memory Service                            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                     │
│  │ 決定事項 │  │作業履歴 │  │ナレッジ │  ← 3種類の記憶     │
│  └─────────┘  └─────────┘  └─────────┘                     │
│                                                              │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                     │
│  │ Global  │  │  Team   │  │ Project │  ← 3つのスコープ    │
│  └─────────┘  └─────────┘  └─────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

### なぜ必要か？

**田中（プロダクトマネージャー）の視点**:
> 「開発が進むにつれ、『なぜこの設計にしたのか』『前回何を決めたか』が分からなくなる。
> Memory Serviceがあれば、AIが過去の文脈を理解した上で提案してくれる」

**山田（シニアエンジニア）の視点**:
> 「新メンバーが入ってきたとき、プロジェクトの経緯を説明するのが大変。
> Memory Serviceに蓄積された決定事項を見れば、キャッチアップが格段に速くなる」

### 主な特徴

| 特徴 | 説明 |
|------|------|
| **階層化された記憶** | Global → Team → Project の3階層で情報を整理 |
| **自動TTL管理** | 記憶の種類に応じて自動的に有効期限を設定 |
| **トークン予算管理** | LLMのコンテキスト制限を考慮した記憶の取捨選択 |
| **マルチテナント対応** | 複数チーム・プロジェクトを1つのサービスで管理 |
| **認証・認可** | APIキーベースの認証とロールベースのアクセス制御 |
| **監査ログ** | 誰がいつ何を記録したかを追跡可能 |

---

## アーキテクチャ

### システム構成図

```
┌─────────────────────────────────────────────────────────────────────┐
│                           ユーザー環境                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │ プロジェクトA │  │ プロジェクトB │  │ プロジェクトC │                 │
│  │  .isac.yaml │  │  .isac.yaml │  │  .isac.yaml │                 │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                 │
│         │                │                │                        │
│         ▼                ▼                ▼                        │
│  ┌─────────────────────────────────────────────────────────┐      │
│  │                   Claude Code CLI                        │      │
│  │  ┌─────────────────────────────────────────────────┐    │      │
│  │  │ Hooks                                            │    │      │
│  │  │  • on-prompt.sh   → コンテキスト取得            │    │      │
│  │  │  • post-edit.sh   → 作業履歴保存                │    │      │
│  │  └─────────────────────────────────────────────────┘    │      │
│  └───────────────────────────┬─────────────────────────────┘      │
│                              │ HTTP REST API                       │
└──────────────────────────────┼─────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Docker Container                                  │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                   Memory Service                             │   │
│  │                   (FastAPI + Uvicorn)                        │   │
│  │                                                              │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐            │   │
│  │  │ Store API  │  │ Search API │  │ Context API│            │   │
│  │  └────────────┘  └────────────┘  └────────────┘            │   │
│  │                         │                                    │   │
│  │                         ▼                                    │   │
│  │  ┌──────────────────────────────────────────────────┐      │   │
│  │  │              SQLite Database                      │      │   │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐         │      │   │
│  │  │  │ memories │ │  users   │ │audit_logs│         │      │   │
│  │  │  └──────────┘ └──────────┘ └──────────┘         │      │   │
│  │  └──────────────────────────────────────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │           Docker Volume: isac-memory-data                    │   │
│  │                    /data/memory.db                           │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 技術スタック

| レイヤー | 技術 | 選定理由 |
|---------|------|----------|
| **言語** | Python 3.11 | 型ヒント対応、FastAPIとの親和性 |
| **フレームワーク** | FastAPI | 高速、自動ドキュメント生成、型安全 |
| **ASGI サーバー** | Uvicorn | 高パフォーマンス、非同期対応 |
| **データベース** | SQLite | 軽量、設定不要、ACID準拠 |
| **トークンカウント** | tiktoken | OpenAI互換の正確なトークン計算 |
| **コンテナ** | Docker | 環境の一貫性、デプロイの容易さ |

**佐藤（DevOpsエンジニア）のコメント**:
> 「SQLiteを選んだのは意図的。PostgreSQLやRedisは運用コストが高い。
> ISACの規模（チーム〜数十人）ならSQLiteで十分。必要になったら移行すればいい」

### データフロー

```
1. ユーザーがプロンプト入力
       │
       ▼
2. on-prompt.sh が発火
       │
       ├──→ resolve-project.sh でプロジェクトID取得
       │
       ▼
3. Memory Service の /context API をコール
       │
       ├──→ Global Knowledge を取得（15%）
       ├──→ Team Knowledge を取得（15%）
       ├──→ Project Decisions を取得（30%）
       └──→ Recent Work を取得（40%）
       │
       ▼
4. トークン予算内で記憶を選択
       │
       ▼
5. コンテキストとしてClaude Code CLIに注入
       │
       ▼
6. AIが過去の文脈を理解した上で回答
       │
       ▼
7. ファイル編集があれば post-edit.sh が発火
       │
       ▼
8. Memory Service の /store API で作業履歴を保存
```

---

## データモデル

### データベーススキーマ

```sql
-- メインテーブル: 記憶
CREATE TABLE memories (
    id TEXT PRIMARY KEY,              -- ユニークID（8文字）
    scope TEXT NOT NULL,              -- 'global' | 'team' | 'project'
    scope_id TEXT,                    -- チームID または プロジェクトID
    type TEXT NOT NULL,               -- 'decision' | 'work' | 'knowledge'
    content TEXT NOT NULL,            -- 記憶の本文
    summary TEXT,                     -- 要約（100文字以内）
    importance REAL DEFAULT 0.5,      -- 重要度（0.0〜1.0）
    metadata TEXT,                    -- JSON形式のメタデータ
    created_by TEXT,                  -- 作成者のユーザーID
    created_at TEXT NOT NULL,         -- 作成日時（ISO 8601）
    expires_at TEXT,                  -- 有効期限
    access_count INTEGER DEFAULT 0,   -- アクセス回数
    last_accessed_at TEXT             -- 最終アクセス日時
);

-- インデックス
CREATE INDEX idx_memories_scope ON memories(scope, scope_id);
CREATE INDEX idx_memories_type ON memories(type);
CREATE INDEX idx_memories_created ON memories(created_at);
CREATE INDEX idx_memories_importance ON memories(importance);
```

### 記憶のライフサイクル

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│ 作成    │ ──▶ │ 活性    │ ──▶ │ 非活性  │ ──▶ │ 期限切れ │
│         │     │         │     │         │     │ (削除)  │
└─────────┘     └─────────┘     └─────────┘     └─────────┘
    │               │               │
    │               │               │
    ▼               ▼               ▼
 TTL設定        アクセス時に     長期間未アクセス
 重要度設定     access_count++   で優先度低下
```

### TTL（Time To Live）設定

| タイプ | デフォルトTTL | 理由 |
|--------|-------------|------|
| decision | 365日 | 設計判断は長期間参照される |
| knowledge | 365日 | 組織ナレッジは蓄積が重要 |
| work | 30日 | 作業履歴は短期的な参照が中心 |

**鈴木（セキュリティエンジニア）のコメント**:
> 「TTLはデータ肥大化を防ぐだけでなく、古い情報による誤判断を防ぐ役割もある。
> 特にworkタイプは30日で十分。本当に重要ならdecisionに昇格させるべき」

---

## メモリタイプの決定方法

### 3つのタイプ

Memory Serviceは記憶を**3つのタイプ**に分類します。適切なタイプを選ぶことで、検索精度と保持期間が最適化されます。

```
┌─────────────────────────────────────────────────────────────────┐
│                     メモリタイプの選択フロー                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  この情報は...   │
                    └────────┬────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
          ▼                  ▼                  ▼
    ┌───────────┐     ┌───────────┐     ┌───────────┐
    │ 重要な判断 │     │ 作業の記録 │     │ 一般的な  │
    │ や決定か？ │     │ か？       │     │ 知識か？  │
    └─────┬─────┘     └─────┬─────┘     └─────┬─────┘
          │                  │                  │
          ▼                  ▼                  ▼
    ╔═══════════╗     ╔═══════════╗     ╔═══════════╗
    ║ DECISION  ║     ║   WORK    ║     ║ KNOWLEDGE ║
    ║ 重要度高め ║     ║ 重要度低め ║     ║ 重要度中  ║
    ║ TTL: 1年  ║     ║ TTL: 30日 ║     ║ TTL: 1年  ║
    ╚═══════════╝     ╚═══════════╝     ╚═══════════╝
```

### タイプ別詳細

#### 1. DECISION（決定事項）

**定義**: プロジェクトや組織の方向性を決める重要な判断

**使用する場面**:
- 技術スタックの選定（「認証にはJWTを採用する」）
- アーキテクチャの決定（「マイクロサービスではなくモノリスで進める」）
- 設計方針の確定（「DBはPostgreSQLを使用する」）
- ルールの制定（「コードレビューは2人以上の承認が必要」）

**推奨重要度**: 0.7〜1.0

**伊藤（テックリード）のコメント**:
> 「DECISIONは『なぜその選択をしたか』の理由も含めて記録すること。
> 後で『なんでこうなってるの？』と聞かれたとき、AIが答えられるようになる」

**例**:
```json
{
  "content": "テストフレームワークにはpytestを採用する。理由: Pythonのデファクトスタンダードで、fixtureが強力。unittestより記述が簡潔。",
  "type": "decision",
  "importance": 0.8,
  "metadata": {
    "category": "testing",
    "alternatives_considered": ["unittest", "nose2"],
    "decided_by": "tech-lead"
  }
}
```

#### 2. WORK（作業履歴）

**定義**: 日々の開発作業の記録

**使用する場面**:
- ファイルの作成・編集（「src/auth.py を作成した」）
- バグ修正（「ログインエラーを修正した」）
- リファクタリング（「認証ロジックを別モジュールに分離した」）
- 調査作業（「パフォーマンス問題を調査した」）

**推奨重要度**: 0.3〜0.6

**渡辺（バックエンドエンジニア）のコメント**:
> 「WORKは自動記録されることが多い（post-edit.shで）。
> 手動で記録する場合は、何を変更したかではなく、なぜ変更したかを書くと価値が高まる」

**例**:
```json
{
  "content": "src/api/auth.py を編集: JWTトークンの有効期限を1時間から24時間に変更。ユーザーからのセッション切れ報告が多かったため。",
  "type": "work",
  "importance": 0.4,
  "metadata": {
    "file": "src/api/auth.py",
    "action": "edit",
    "related_issue": "#123"
  }
}
```

#### 3. KNOWLEDGE（ナレッジ）

**定義**: プロジェクトや組織で共有すべき一般的な知識

**使用する場面**:
- 技術的なTips（「このライブラリはv2.0以上が必要」）
- 環境情報（「本番環境のDBはAWSのRDSを使用」）
- ベストプラクティス（「エラーハンドリングはこのパターンで統一」）
- 注意事項（「このAPIは1分間に100リクエストまで」）

**推奨重要度**: 0.5〜0.8

**例**:
```json
{
  "content": "組織全体でPython 3.11以上を使用する。3.10以下はセキュリティサポートが終了するため。",
  "type": "knowledge",
  "scope": "global",
  "importance": 0.9
}
```

### タイプ選択の判断基準表

| 質問 | Yes → | No → |
|------|-------|------|
| 将来の開発方針に影響するか？ | DECISION | 次の質問へ |
| 他のメンバーが知るべき一般的な情報か？ | KNOWLEDGE | 次の質問へ |
| 特定のファイルや機能に関する作業記録か？ | WORK | KNOWLEDGE |

### 重要度（importance）の設定ガイド

```
1.0 ┬─── 絶対に忘れてはいけない（セキュリティ要件、法的要件）
    │
0.9 ┼─── 非常に重要（アーキテクチャ決定、技術選定）
    │
0.8 ┼─── 重要（主要機能の設計方針）
    │
0.7 ┼─── やや重要（実装上の決定事項）
    │
0.6 ┼─── 参考情報として有用
    │
0.5 ┼─── 標準（デフォルト値）
    │
0.4 ┼─── 補足情報
    │
0.3 ┼─── 一時的な情報
    │
0.2 ┼─── 低優先度
    │
0.1 ┴─── ほぼ参照されない
```

### カテゴリとタグ（v2.1.0〜）

記憶には**カテゴリ**と**タグ**を付けることができます。これにより検索精度が向上し、トークン使用量を削減できます。

#### カテゴリ一覧

| カテゴリ | 説明 | 自動検出の例 |
|---------|------|-------------|
| backend | サーバーサイド開発 | FastAPI, Django, `/api/`パス |
| frontend | クライアントサイド開発 | React, Vue, `.tsx`ファイル |
| infra | インフラ・DevOps | Docker, Kubernetes, CI/CD |
| security | セキュリティ | 認証, JWT, OAuth |
| database | データベース | PostgreSQL, SQL, マイグレーション |
| api | API設計 | REST, GraphQL, エンドポイント |
| ui | UI/UX | デザイン, スタイル, CSS |
| test | テスト | pytest, Jest, テストファイル |
| docs | ドキュメント | README, .mdファイル |
| architecture | アーキテクチャ設計 | 設計, パターン, アーキテクチャ |
| other | その他 | 上記に該当しない |

#### カテゴリ・タグの付け方

```
┌─────────────────────────────────────────────────────────────┐
│                      記憶の保存                              │
└─────────────────────────────────────────────────────────────┘
                           │
            ┌──────────────┴──────────────┐
            │                             │
            ▼                             ▼
    ┌───────────────┐             ┌───────────────┐
    │ 手動記録      │             │ 自動記録      │
    │ (/decide等)   │             │ (post-edit)   │
    └───────┬───────┘             └───────┬───────┘
            │                             │
            ▼                             ▼
    ┌───────────────┐             ┌───────────────┐
    │ カテゴリ指定  │             │ 自動カテゴリ  │
    │ (任意)        │             │ 推定          │
    │               │             │               │
    │ タグ指定      │             │ 自動タグ      │
    │ (任意)        │             │ 抽出          │
    └───────────────┘             └───────────────┘
```

**自動推定の仕組み**:
- **カテゴリ**: ファイルパスとコンテンツのキーワードから推定
- **タグ**: ファイル名、技術スタック名、キーワードから抽出（最大10個）

**例**:
```json
{
  "content": "認証にはJWTを採用する。理由: ステートレスでスケールしやすい",
  "type": "decision",
  "scope": "project",
  "scope_id": "my-project",
  "metadata": {"file": "src/api/auth.py"}
}
```

**自動付与される結果**:
```json
{
  "category": "backend",
  "tags": ["auth", "jwt"]
}
```

#### カテゴリ・タグでの検索

```bash
# カテゴリで絞り込み
curl "http://localhost:8100/search?query=認証&category=security"

# タグで絞り込み（カンマ区切りで複数指定可）
curl "http://localhost:8100/search?query=認証&tags=jwt,auth"

# 使用されているタグ一覧を取得
curl "http://localhost:8100/tags/my-project"
```

---

## スコープと階層構造

### 3つのスコープ

Memory Serviceは記憶を**3つのスコープ**で管理します。これにより、適切な範囲で情報を共有できます。

```
╔═══════════════════════════════════════════════════════════════════╗
║                        GLOBAL (全体共有)                           ║
║  • 組織全体で共有すべき情報                                        ║
║  • 例: 「全プロジェクトでPython 3.11以上を使用」                   ║
║  • 全員がアクセス可能                                              ║
╠═══════════════════════════════════════════════════════════════════╣
║  ┌─────────────────────────────────────────────────────────────┐ ║
║  │                    TEAM (チーム共有)                         │ ║
║  │  • チーム固有のナレッジ                                      │ ║
║  │  • 例: 「バックエンドチームはFastAPIを標準採用」             │ ║
║  │  • 同じチームのメンバーがアクセス可能                        │ ║
║  │  ┌─────────────────────────────────────────────────────┐   │ ║
║  │  │                PROJECT (プロジェクト固有)             │   │ ║
║  │  │  • プロジェクト固有の決定・作業履歴                   │   │ ║
║  │  │  • 例: 「このプロジェクトはNext.jsを採用」            │   │ ║
║  │  │  • プロジェクトメンバーがアクセス可能                 │   │ ║
║  │  └─────────────────────────────────────────────────────┘   │ ║
║  └─────────────────────────────────────────────────────────────┘ ║
╚═══════════════════════════════════════════════════════════════════╝
```

### スコープ別詳細

| スコープ | scope_id | 用途 | 例 |
|---------|----------|------|-----|
| global | なし | 組織全体のナレッジ | コーディング規約、ツール標準 |
| team | team_id | チーム固有の情報 | チーム技術スタック、ワークフロー |
| project | project_id | プロジェクト固有 | 設計決定、作業履歴 |

### コンテキスト取得時のトークン配分

`/context` APIを呼び出すと、各スコープから記憶を取得します。トークン予算は以下のように配分されます：

```
max_tokens = 2000 の場合

┌────────────────────────────────────────────────────────────┐
│ Global Knowledge                              │ 300 tokens │
│ (15%)                                         │ (15%)      │
├────────────────────────────────────────────────────────────┤
│ Team Knowledge                                │ 300 tokens │
│ (15%)                                         │ (15%)      │
├────────────────────────────────────────────────────────────┤
│ Project Decisions                             │ 600 tokens │
│ (30%)                                         │ (30%)      │
├────────────────────────────────────────────────────────────┤
│ Project Recent Work                           │ 800 tokens │
│ (40%)                                         │ (40%)      │
└────────────────────────────────────────────────────────────┘
```

**高橋（QAエンジニア）のコメント**:
> 「この配分は経験則から来ている。プロジェクト固有の情報（決定+作業）が70%を占めるのは、
> 日々の開発で最も参照されるのがプロジェクトの文脈だから」

---

## ユースケース

### ユースケース1: 新規プロジェクトの立ち上げ

**シナリオ**: 新しいWebアプリケーションプロジェクトを開始する

```bash
# 1. プロジェクト初期化
cd ~/projects/new-webapp
isac init webapp

# 2. 技術選定を記録
curl -X POST "http://localhost:8100/store" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "フレームワークはNext.js 14を採用。理由: App Router対応、SSR/SSG両対応、Vercelとの親和性が高い",
    "type": "decision",
    "scope": "project",
    "scope_id": "webapp",
    "importance": 0.9,
    "metadata": {"category": "framework", "decided_by": "tech-lead"}
  }'

# 3. 以降、claudeコマンドで開発を開始
claude
```

**AIの挙動**:
- 新しいファイルを作成するとき、Next.js 14の規約に従った提案をする
- 「フレームワーク何使ってる？」と聞くと「Next.js 14です」と答える

### ユースケース2: チームナレッジの共有

**シナリオ**: バックエンドチームの標準技術スタックを共有する

```bash
# チームナレッジとして記録
curl -X POST "http://localhost:8100/store" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "バックエンドチームの標準スタック: Python 3.11, FastAPI, SQLAlchemy 2.0, PostgreSQL 15。新規プロジェクトはこれに従うこと。",
    "type": "knowledge",
    "scope": "team",
    "scope_id": "backend-team",
    "importance": 0.9
  }'
```

**効果**:
- 新メンバーがプロジェクトに参加したとき、AIが標準スタックを把握している
- 「新しいAPIを作りたい」と言うと、FastAPIベースのコードを提案する

### ユースケース3: 過去の決定事項の参照

**シナリオ**: 「なぜこの設計になっているか」を確認したい

```bash
# 検索
curl "http://localhost:8100/search?query=認証&scope_id=webapp&type=decision"
```

**レスポンス**:
```json
{
  "memories": [
    {
      "id": "abc123",
      "content": "認証にはJWTを採用する。理由: ステートレスでスケールしやすい、モバイルアプリとの共通化が容易",
      "type": "decision",
      "importance": 0.85,
      "created_at": "2026-01-15T10:30:00Z"
    }
  ]
}
```

### ユースケース4: プロジェクト切り替え

**シナリオ**: 複数プロジェクトを行き来しながら開発

```bash
# プロジェクトA で作業
cd ~/projects/project-a
isac switch project-a
claude
# → AIはproject-aの文脈を理解

# プロジェクトB に切り替え
cd ~/projects/project-b
isac switch project-b
claude
# → AIはproject-bの文脈を理解（project-aとは完全に別）
```

### ユースケース5: 組織全体のルール適用

**シナリオ**: 全プロジェクトに適用するコーディング規約を設定

```bash
# グローバルナレッジとして記録
curl -X POST "http://localhost:8100/store" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "すべてのPythonコードはBlackでフォーマット、isortでimportをソート、mypyで型チェックを行うこと。",
    "type": "knowledge",
    "scope": "global",
    "importance": 0.95
  }'
```

**効果**:
- どのプロジェクトでも、AIがこのルールを認識してコードを生成

### ユースケース6: 作業履歴の自動記録

**シナリオ**: ファイル編集が自動的に記録される

```
# post-edit.sh が自動的に発火

記録される内容:
{
  "content": "src/api/users.py を編集: ユーザー一覧APIにページネーションを追加",
  "type": "work",
  "scope": "project",
  "scope_id": "webapp",
  "importance": 0.4,
  "metadata": {
    "file": "src/api/users.py",
    "action": "edit"
  }
}
```

**効果**:
- 「最近何を変更した？」と聞くと、AIが作業履歴を参照して答える
- 「昨日の作業の続きをしたい」と言うと、前回の状態を把握している

### ユースケース7: AI自動分類による高精度タグ付け

**シナリオ**: タスク完了時にClaudeが作業内容を分析し、適切なタグを自動付与

```
# 方法1: /save-memory スキルで手動実行
> /save-memory

Claudeが今回の作業を分析して出力:
{
  "type": "decision",
  "category": "architecture",
  "tags": ["hooks", "ai-classification", "automation"],
  "summary": "Stop HookによるAI分類機能を実装",
  "importance": 0.9
}

# 方法2: Stop Hook (prompt type) で自動実行
# settings.yaml で設定すると、タスク完了時に自動で分類
```

**技術的な仕組み**:

```
┌─────────────────────────────────────────────────────────────┐
│                 タスク完了時のフロー                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. タスク完了 (Stop event)                                 │
│         │                                                    │
│         ▼                                                    │
│  2. on-stop.sh (prompt type)                                │
│     → Claudeに分類リクエストを送信                          │
│         │                                                    │
│         ▼                                                    │
│  3. Claude が作業内容を分析                                  │
│     → category, tags, importance を自動推定                 │
│         │                                                    │
│         ▼                                                    │
│  4. save-memory.sh で Memory Service に保存                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Hook Type の選択**:

| Hook Type | 特徴 | 用途 |
|-----------|------|------|
| command | 外部コマンド実行 | 軽量な処理（post-edit.sh） |
| prompt | Claudeに追加指示 | AI分類（on-stop.sh） |
| agent | サブエージェント起動 | 複雑な処理（将来拡張） |

**効果**:
- プロジェクト固有の技術スタックに適したタグ付け
- キーワードベースでは困難なコンテキスト理解
- 追加API呼び出しなし（既存のClaudeセッションを活用）

---

## API リファレンス

### エンドポイント一覧

| メソッド | パス | 説明 | 認証 |
|---------|------|------|------|
| GET | /health | ヘルスチェック | 不要 |
| POST | /store | 記憶を保存 | オプション |
| GET | /context/{project_id} | コンテキスト取得 | オプション |
| GET | /search | 記憶を検索 | オプション |
| GET | /memory/{id} | 特定の記憶を取得 | オプション |
| PATCH | /memory/{id} | 記憶のタグ・カテゴリを編集 | オプション |
| DELETE | /memory/{id} | 記憶を削除 | 必要 |
| GET | /categories | カテゴリ一覧 | 不要 |
| GET | /tags/{scope_id} | 使用中タグ一覧 | オプション |
| GET | /projects | プロジェクト一覧 | オプション |
| GET | /projects/suggest | 類似プロジェクト提案 | オプション |
| GET | /stats/{project_id} | 統計情報 | オプション |
| GET | /export/{project_id} | エクスポート | オプション |
| POST | /import | インポート | オプション |
| POST | /cleanup | 期限切れ削除 | オプション |
| POST | /admin/teams | チーム作成 | 管理者 |
| POST | /admin/users | ユーザー作成 | 管理者 |
| GET | /admin/audit-logs | 監査ログ | 管理者 |

### 主要API詳細

#### POST /store - 記憶を保存

**リクエスト**:
```json
{
  "content": "記憶の内容（必須）",
  "type": "decision",      // decision | work | knowledge
  "scope": "project",      // global | team | project
  "scope_id": "my-project", // team または project の場合に必要
  "importance": 0.8,       // 0.0〜1.0（デフォルト: 0.5）
  "summary": "短い要約",    // 省略時は自動生成
  "metadata": {},          // 任意のメタデータ
  "category": "backend",   // カテゴリ（任意、省略時は自動推定）
  "tags": ["jwt", "auth"]  // タグ（任意、自動抽出タグとマージ）
}
```

**レスポンス**:
```json
{
  "id": "abc12345",
  "tokens": 50,
  "scope": "project",
  "category": "backend",
  "tags": ["jwt", "auth"],
  "message": "Memory stored (project/decision)"
}
```

#### GET /context/{project_id} - コンテキスト取得

**パラメータ**:
- `query` (必須): 検索クエリ
- `max_tokens` (オプション): 最大トークン数（デフォルト: 2000）

**レスポンス**:
```json
{
  "global_knowledge": [...],
  "team_knowledge": [...],
  "project_decisions": [...],
  "project_recent": [...],
  "total_tokens": 1850
}
```

#### GET /search - 記憶を検索

**パラメータ**:
- `query` (必須): 検索キーワード
- `scope` (オプション): スコープでフィルタ
- `scope_id` (オプション): スコープIDでフィルタ
- `type` (オプション): タイプでフィルタ
- `category` (オプション): カテゴリでフィルタ
- `tags` (オプション): タグでフィルタ（カンマ区切りで複数指定可）
- `limit` (オプション): 最大件数（デフォルト: 10、最大: 50）

**レスポンス**:
```json
{
  "memories": [...],
  "count": 5
}
```

#### PATCH /memory/{id} - 記憶を編集

**リクエスト**:
```json
{
  "category": "backend",           // 新しいカテゴリ（任意）
  "tags": ["python", "api"],       // タグを完全に置き換え（任意）
  "add_tags": ["new-tag"],         // 既存タグに追加（任意）
  "remove_tags": ["old-tag"],      // タグを削除（任意）
  "importance": 0.8,               // 新しい重要度（任意）
  "summary": "新しい要約"           // 新しい要約（任意）
}
```

**注意**:
- `tags`と`add_tags`/`remove_tags`は同時に指定しないでください
- `tags`を指定すると既存のタグは完全に置き換わります
- 最大タグ数は10個です

**レスポンス**:
```json
{
  "id": "abc12345",
  "message": "Memory updated",
  "category": "backend",
  "tags": ["python", "api", "new-tag"],
  "importance": 0.8
}
```

#### GET /categories - カテゴリ一覧

**レスポンス**:
```json
{
  "categories": ["backend", "frontend", "infra", ...],
  "descriptions": {
    "backend": "サーバーサイド開発",
    ...
  }
}
```

#### GET /tags/{scope_id} - 使用中タグ一覧

**レスポンス**:
```json
{
  "scope_id": "my-project",
  "tags": [
    {"tag": "jwt", "count": 5},
    {"tag": "auth", "count": 3}
  ],
  "total": 10
}
```

---

## デプロイメント

### ローカル開発（Docker Compose）

```bash
cd memory-service
docker compose up -d
```

**ポート**: 8100（ホスト）→ 8000（コンテナ）

**データ永続化**: Docker Volume `isac-memory-data` に `/data/memory.db` を保存

### 本番環境へのデプロイ

#### オプション1: 共有サーバー（チーム開発向け）

```yaml
# docker-compose.prod.yml
version: '3.8'

services:
  memory:
    build: .
    ports:
      - "8100:8000"
    volumes:
      - /var/data/isac:/data
    environment:
      - DATABASE_PATH=/data/memory.db
      - REQUIRE_AUTH=true
      - ADMIN_API_KEY=${ADMIN_API_KEY}
    restart: always
```

#### オプション2: Kubernetes

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: isac-memory
spec:
  replicas: 1  # SQLiteのため1固定
  selector:
    matchLabels:
      app: isac-memory
  template:
    spec:
      containers:
        - name: memory
          image: isac-memory:2.0.0
          ports:
            - containerPort: 8000
          env:
            - name: REQUIRE_AUTH
              value: "true"
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: isac-memory-pvc
```

### 環境変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `DATABASE_PATH` | /data/memory.db | SQLiteファイルのパス |
| `REQUIRE_AUTH` | false | 認証を必須にするか |
| `ADMIN_API_KEY` | (なし) | 管理者APIキー |
| `CORS_ORIGINS` | * | 許可するオリジン |
| `RATE_LIMIT_REQUESTS` | 100 | レート制限（リクエスト数） |
| `RATE_LIMIT_WINDOW` | 60 | レート制限（秒） |

---

## セキュリティ

### 認証・認可

#### 認証フロー

```
クライアント                          Memory Service
    │                                      │
    │  Authorization: Bearer <api_key>     │
    │  または X-API-Key: <api_key>         │
    │─────────────────────────────────────▶│
    │                                      │
    │                            APIキーをハッシュ化
    │                            usersテーブルで検索
    │                                      │
    │◀─────────────────────────────────────│
    │         認証成功 / 401 Unauthorized   │
```

#### ロールと権限

| ロール | 読み取り | 書き込み | 削除 | 管理 |
|--------|---------|---------|------|------|
| admin | ✓ 全て | ✓ 全て | ✓ 全て | ✓ |
| member | ✓ 所属のみ | ✓ 所属のみ | ✓ 自分の記憶のみ | ✗ |
| viewer | ✓ 所属のみ | ✗ | ✗ | ✗ |

### 機密情報の保護

**sensitive-filter.sh** が以下のパターンを検出してマスキング:

- APIキー（`api_key=...`）
- パスワード（`password=...`）
- AWSアクセスキー（`AKIA...`）
- データベースURL（`postgres://...`）
- 機密ファイル（`.env`, `*.pem`, `credentials.*`）

**小林（インフラエンジニア）のコメント**:
> 「機密情報が誤ってMemory Serviceに保存されないよう、Hookレベルでフィルタリングしている。
> ただし、これは最後の砦。そもそも機密情報をプロンプトに含めないのがベストプラクティス」

### 監査ログ

すべての操作は監査ログに記録されます:

```sql
SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 10;
```

| カラム | 説明 |
|--------|------|
| user_id | 操作したユーザー |
| action | 操作の種類（store_memory, delete_memory, etc.） |
| resource_type | リソースタイプ（memory, user, team） |
| resource_id | リソースID |
| ip_address | クライアントIPアドレス |
| created_at | 操作日時 |

---

## 運用ガイド

### バックアップ

```bash
# SQLiteファイルをバックアップ
docker cp isac-memory:/data/memory.db ./backup/memory-$(date +%Y%m%d).db

# または Docker Volume から直接
cp /var/lib/docker/volumes/isac-memory-data/_data/memory.db ./backup/
```

### リストア

```bash
# サービス停止
docker compose down

# バックアップからリストア
docker cp ./backup/memory-20260201.db isac-memory:/data/memory.db

# サービス再開
docker compose up -d
```

### 期限切れデータのクリーンアップ

```bash
# 手動実行
curl -X POST "http://localhost:8100/cleanup"

# 定期実行（cron）
0 3 * * * curl -X POST "http://localhost:8100/cleanup"
```

### 監視

#### ヘルスチェック

```bash
curl http://localhost:8100/health
```

レスポンス:
```json
{
  "status": "healthy",
  "service": "isac-memory",
  "version": "2.0.0",
  "auth_required": false
}
```

#### メトリクス収集（推奨）

```bash
# プロジェクト統計
curl http://localhost:8100/stats/my-project

# 全プロジェクト一覧
curl http://localhost:8100/projects
```

---

## トラブルシューティング

### よくある問題

#### 1. Memory Serviceに接続できない

**症状**: `curl http://localhost:8100/health` がタイムアウト

**解決策**:
```bash
# コンテナ状態確認
docker ps | grep isac-memory

# 起動していない場合
cd memory-service && docker compose up -d

# ログ確認
docker logs isac-memory
```

#### 2. 記憶が保存されない

**症状**: `/store` API が 400 エラー

**確認ポイント**:
- `scope` が `team` の場合、`scope_id` は必須
- `type` は `decision`, `work`, `knowledge` のいずれか
- `importance` は 0.0〜1.0 の範囲

#### 3. コンテキストが取得できない

**症状**: `/context` API が空を返す

**確認ポイント**:
- `query` パラメータは必須
- プロジェクトIDが正しいか確認: `isac status`
- 記憶が存在するか確認: `curl "http://localhost:8100/search?query=*&scope_id=my-project"`

#### 4. 認証エラー（401）

**症状**: `Authentication required` エラー

**解決策**:
```bash
# 認証が有効になっているか確認
curl http://localhost:8100/health
# → "auth_required": true なら認証必須

# 認証を無効化（開発環境のみ）
# docker-compose.yml で REQUIRE_AUTH=false に設定
```

#### 5. データベースエラー

**症状**: 500エラー、`database is locked`

**解決策**:
```bash
# サービス再起動
docker compose restart

# それでも解決しない場合、DBファイルの権限確認
docker exec isac-memory ls -la /data/
```

---

## FAQ

### Q: Memory ServiceなしでもISACは使える？

**A**: はい。Memory Serviceが起動していない場合、Hooksは警告を出しますが、Claude Code CLIは通常通り動作します。ただし、過去の記憶を参照する機能は使えません。

### Q: 複数人で同時に書き込んでも大丈夫？

**A**: はい。SQLiteはACID準拠のため、複数人が同時に書き込んでもデータ整合性は保たれます。ただし、大規模チーム（50人以上）では、PostgreSQLへの移行を検討してください。

### Q: トークン数はどのように計算される？

**A**: OpenAIの `cl100k_base` エンコーディング（tiktoken）を使用しています。これはClaude APIでも近似的に有効です。

### Q: 記憶の重複を防ぐには？

**A**: 現状、自動的な重複検出はありません。同じ内容を複数回保存しないよう、アプリケーション側で制御してください。

### Q: オフラインでも使える？

**A**: Memory ServiceはローカルのDockerコンテナとして動作するため、インターネット接続がなくても使用できます（ローカル開発モード）。

### Q: データをエクスポートして他のツールで使える？

**A**: はい。`/export/{project_id}` APIでJSON形式でエクスポートできます。

```bash
curl "http://localhost:8100/export/my-project" > memories.json
```

### Q: どのくらいのデータ量まで対応できる？

**A**: SQLiteの制限は140TBですが、実用的には数万件の記憶までを推奨します。それ以上の場合は、PostgreSQLへの移行を検討してください。

### Q: 古い記憶は自動的に削除される？

**A**: はい。TTL（有効期限）が設定されており、`/cleanup` APIで期限切れの記憶を削除できます。

---

## 付録

### 参考リンク

- [ISAC README](../README.md)
- [CLAUDE.md](../CLAUDE.md)
- [テストガイド](../tests/README.md)

### 更新履歴

| バージョン | 日付 | 変更内容 |
|-----------|------|----------|
| 2.1.0 | 2026-02-02 | カテゴリ・タグ機能追加、自動タグ付け |
| 2.0.0 | 2026-02-02 | マルチテナント対応、スコープ追加 |
| 1.0.0 | 2026-01-01 | 初版リリース |

---

*このドキュメントは10人の専門家（田中、山田、佐藤、伊藤、鈴木、高橋、渡辺、中村、小林、加藤）による議論を経て作成されました。*
