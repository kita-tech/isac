"""
ISAC Memory Service - Cloud Edition
マルチテナント対応の長期記憶サービス
"""
from __future__ import annotations

import hashlib
import json
import os
import secrets
import sqlite3
from collections import defaultdict
from datetime import datetime, timedelta
from enum import Enum
from functools import wraps
from pathlib import Path
from typing import Optional
from contextlib import contextmanager

from fastapi import FastAPI, Query, HTTPException, Depends, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
import tiktoken

# ============================================================
# アプリケーション設定
# ============================================================

app = FastAPI(
    title="ISAC Memory Service",
    description="マルチテナント対応の長期記憶サービス（タグ・カテゴリ対応）",
    version="2.1.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer(auto_error=False)

# 設定
DATABASE_PATH = os.getenv("DATABASE_PATH", "/data/memory.db")
ADMIN_API_KEY = os.getenv("ADMIN_API_KEY", "")  # 管理者キー
REQUIRE_AUTH = os.getenv("REQUIRE_AUTH", "false").lower() == "true"
RATE_LIMIT_REQUESTS = int(os.getenv("RATE_LIMIT_REQUESTS", "100"))
RATE_LIMIT_WINDOW = int(os.getenv("RATE_LIMIT_WINDOW", "60"))  # seconds

DEFAULT_TTL_DAYS = {"decision": 365, "work": 30, "knowledge": 365}

# トークンカウンター
try:
    ENCODER = tiktoken.get_encoding("cl100k_base")
except Exception:
    ENCODER = None


# ============================================================
# Enums & Models
# ============================================================

class MemoryScope(str, Enum):
    GLOBAL = "global"      # 全体共有
    TEAM = "team"          # チーム共有
    PROJECT = "project"    # プロジェクト固有


class MemoryType(str, Enum):
    DECISION = "decision"  # 重要決定
    WORK = "work"          # 作業履歴
    KNOWLEDGE = "knowledge"  # 一般知識
    TODO = "todo"          # 個人タスク（翌日持ち越し用）


class MemoryCategory(str, Enum):
    BACKEND = "backend"        # サーバーサイド
    FRONTEND = "frontend"      # クライアントサイド
    INFRA = "infra"            # インフラ・DevOps
    SECURITY = "security"      # セキュリティ
    DATABASE = "database"      # データベース
    API = "api"                # API設計
    UI = "ui"                  # UI/UX
    TEST = "test"              # テスト
    DOCS = "docs"              # ドキュメント
    ARCHITECTURE = "architecture"  # アーキテクチャ
    OTHER = "other"            # その他


# カテゴリ一覧（APIレスポンス用）
CATEGORIES = [c.value for c in MemoryCategory]


class UserRole(str, Enum):
    ADMIN = "admin"
    MEMBER = "member"
    VIEWER = "viewer"


class MemoryEntry(BaseModel):
    content: str
    type: MemoryType = MemoryType.WORK
    scope: MemoryScope = MemoryScope.PROJECT
    scope_id: Optional[str] = None  # team_id or project_id
    importance: float = Field(default=0.5, ge=0.0, le=1.0)
    summary: Optional[str] = None
    metadata: dict = Field(default_factory=dict)
    category: Optional[MemoryCategory] = None  # カテゴリ（任意）
    tags: list[str] = Field(default_factory=list)  # タグ（複数可）
    supersedes: list[str] = Field(default_factory=list)  # 廃止対象の記憶IDリスト


class MemoryResponse(BaseModel):
    id: str
    scope: MemoryScope
    scope_id: Optional[str]
    type: MemoryType
    content: str
    summary: Optional[str]
    importance: float
    metadata: dict
    category: Optional[str]
    tags: list[str]
    created_by: Optional[str]
    created_at: str
    tokens: int
    deprecated: bool = False
    superseded_by: Optional[str] = None


class ContextResponse(BaseModel):
    global_knowledge: list[MemoryResponse]
    team_knowledge: list[MemoryResponse]
    project_decisions: list[MemoryResponse]
    project_recent: list[MemoryResponse]
    total_tokens: int


class StoreResponse(BaseModel):
    id: str
    tokens: int
    scope: MemoryScope
    scope_id: Optional[str]
    category: Optional[str]
    tags: list[str]
    message: str
    superseded_ids: list[str] = Field(default_factory=list)  # 廃止された記憶のIDリスト
    skipped_supersedes: list[dict] = Field(default_factory=list)  # スキップされた廃止対象（理由付き）


class TeamCreate(BaseModel):
    id: str
    name: str


class UserCreate(BaseModel):
    id: str
    team_id: Optional[str] = None
    role: UserRole = UserRole.MEMBER


class ProjectMemberAdd(BaseModel):
    user_id: str
    role: UserRole = UserRole.MEMBER


class MemoryUpdate(BaseModel):
    """記憶の更新リクエスト"""
    category: Optional[MemoryCategory] = Field(None, description="新しいカテゴリ")
    tags: Optional[list[str]] = Field(None, description="新しいタグ（上書き）")
    add_tags: Optional[list[str]] = Field(None, description="追加するタグ")
    remove_tags: Optional[list[str]] = Field(None, description="削除するタグ")
    importance: Optional[float] = Field(None, ge=0.0, le=1.0, description="新しい重要度")
    summary: Optional[str] = Field(None, description="新しい要約")
    metadata: Optional[dict] = Field(None, description="メタデータの更新（マージ）")


# ============================================================
# ユーティリティ
# ============================================================

def count_tokens(text: str) -> int:
    """トークン数をカウント"""
    if ENCODER:
        return len(ENCODER.encode(text))
    return len(text) // 4


def generate_id() -> str:
    """ユニークIDを生成"""
    import uuid
    return str(uuid.uuid4())[:8]


def generate_api_key() -> str:
    """APIキーを生成"""
    return f"isac_{secrets.token_urlsafe(32)}"


def hash_api_key(api_key: str) -> str:
    """APIキーをハッシュ化"""
    return hashlib.sha256(api_key.encode()).hexdigest()


def create_summary(content: str, max_length: int = 100) -> str:
    """コンテンツから要約を生成"""
    first_line = content.split("\n")[0].strip()
    if len(first_line) <= max_length:
        return first_line
    return first_line[:max_length-3] + "..."


def auto_detect_category(content: str, file_path: Optional[str] = None) -> Optional[str]:
    """コンテンツやファイルパスからカテゴリを自動推定"""
    content_lower = content.lower()
    path_lower = (file_path or "").lower()

    # ファイルパスからの推定
    if file_path:
        # テスト
        if '/test' in path_lower or '_test.' in path_lower or 'test_' in path_lower or '.test.' in path_lower:
            return "test"
        # ドキュメント
        if path_lower.endswith('.md') or '/docs/' in path_lower or 'readme' in path_lower:
            return "docs"
        # フロントエンド
        if any(x in path_lower for x in ['/components/', '/pages/', '/views/', '/src/app/']):
            return "frontend"
        if any(path_lower.endswith(x) for x in ['.tsx', '.jsx', '.vue', '.svelte']):
            return "frontend"
        # バックエンド
        if any(x in path_lower for x in ['/api/', '/server/', '/backend/', '/routes/']):
            return "backend"
        # インフラ
        if any(x in path_lower for x in ['docker', 'kubernetes', 'k8s', '.yml', '.yaml', 'terraform', 'ansible']):
            if 'docker' in path_lower or 'compose' in path_lower:
                return "infra"

    # コンテンツからの推定
    # セキュリティ
    if any(x in content_lower for x in ['セキュリティ', 'security', '認証', 'authentication', 'auth', '暗号', 'encrypt', 'jwt', 'oauth']):
        return "security"
    # データベース
    if any(x in content_lower for x in ['データベース', 'database', 'db', 'sql', 'postgres', 'mysql', 'mongodb', 'redis', 'マイグレーション']):
        return "database"
    # API
    if any(x in content_lower for x in ['api', 'エンドポイント', 'endpoint', 'rest', 'graphql', 'grpc']):
        return "api"
    # アーキテクチャ
    if any(x in content_lower for x in ['アーキテクチャ', 'architecture', '設計', 'design', 'パターン', 'pattern']):
        return "architecture"
    # UI
    if any(x in content_lower for x in ['ui', 'ux', 'デザイン', 'レイアウト', 'スタイル', 'css']):
        return "ui"
    # テスト
    if any(x in content_lower for x in ['テスト', 'test', 'testing', 'pytest', 'jest', 'unittest']):
        return "test"
    # インフラ
    if any(x in content_lower for x in ['インフラ', 'infrastructure', 'deploy', 'デプロイ', 'ci/cd', 'pipeline']):
        return "infra"
    # フロントエンド
    if any(x in content_lower for x in ['フロントエンド', 'frontend', 'react', 'vue', 'angular', 'next.js', 'コンポーネント']):
        return "frontend"
    # バックエンド
    if any(x in content_lower for x in ['バックエンド', 'backend', 'サーバー', 'server', 'fastapi', 'django', 'flask']):
        return "backend"

    return None


def auto_extract_tags(content: str, file_path: Optional[str] = None) -> list[str]:
    """コンテンツやファイルパスからタグを自動抽出"""
    tags = set()
    content_lower = content.lower()

    # ファイル名をタグに
    if file_path:
        # ファイル名（拡張子なし）
        import re
        filename = file_path.split('/')[-1]
        name_without_ext = filename.rsplit('.', 1)[0] if '.' in filename else filename
        # スネークケースやケバブケースを分割
        parts = re.split(r'[-_]', name_without_ext.lower())
        for part in parts:
            if len(part) >= 3 and part not in ['the', 'and', 'for', 'test', 'spec']:
                tags.add(part)

    # キーワードマッチング
    keyword_patterns = [
        # 技術スタック
        ('python', 'python'), ('javascript', 'javascript'), ('typescript', 'typescript'),
        ('react', 'react'), ('vue', 'vue'), ('next.js', 'nextjs'), ('nuxt', 'nuxt'),
        ('fastapi', 'fastapi'), ('django', 'django'), ('flask', 'flask'),
        ('postgresql', 'postgresql'), ('postgres', 'postgresql'), ('mysql', 'mysql'),
        ('mongodb', 'mongodb'), ('redis', 'redis'), ('sqlite', 'sqlite'),
        ('docker', 'docker'), ('kubernetes', 'kubernetes'), ('k8s', 'kubernetes'),
        ('aws', 'aws'), ('gcp', 'gcp'), ('azure', 'azure'),
        # 概念
        ('jwt', 'jwt'), ('oauth', 'oauth'), ('api', 'api'), ('rest', 'rest'),
        ('graphql', 'graphql'), ('websocket', 'websocket'),
        ('認証', 'auth'), ('authentication', 'auth'), ('authorization', 'auth'),
        ('キャッシュ', 'cache'), ('cache', 'cache'),
        ('ログ', 'logging'), ('logging', 'logging'),
        ('エラー', 'error'), ('error', 'error'),
        ('パフォーマンス', 'performance'), ('performance', 'performance'),
    ]

    for pattern, tag in keyword_patterns:
        if pattern in content_lower:
            tags.add(tag)

    # 最大10個まで
    return sorted(list(tags))[:10]


def select_within_budget(
    memories: list[MemoryResponse],
    max_tokens: int
) -> list[MemoryResponse]:
    """トークン予算内で記憶を選択"""
    selected = []
    total = 0
    for memory in memories:
        if total + memory.tokens > max_tokens:
            break
        selected.append(memory)
        total += memory.tokens
    return selected


# ============================================================
# データベース
# ============================================================

@contextmanager
def get_db():
    """データベース接続を取得"""
    Path(DATABASE_PATH).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def init_db():
    """データベースを初期化"""
    with get_db() as conn:
        # スキーママイグレーション: 旧スキーマ(project_id)から新スキーマ(scope)への移行
        cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='memories'")
        if cursor.fetchone():
            # memoriesテーブルが存在する場合、スキーマをチェック
            cursor = conn.execute("PRAGMA table_info(memories)")
            columns = {row[1] for row in cursor.fetchall()}
            if "project_id" in columns and "scope" not in columns:
                # 旧スキーマ: マイグレーション実行
                print("Migrating database from v1 to v2...")
                conn.execute("ALTER TABLE memories RENAME TO memories_old")
                conn.commit()

        # チーム
        conn.execute("""
            CREATE TABLE IF NOT EXISTS teams (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)

        # ユーザー
        conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                team_id TEXT REFERENCES teams(id),
                api_key_hash TEXT UNIQUE,
                role TEXT DEFAULT 'member',
                created_at TEXT NOT NULL,
                last_accessed_at TEXT
            )
        """)

        # プロジェクトメンバー
        conn.execute("""
            CREATE TABLE IF NOT EXISTS project_members (
                project_id TEXT NOT NULL,
                user_id TEXT REFERENCES users(id),
                role TEXT DEFAULT 'member',
                created_at TEXT NOT NULL,
                PRIMARY KEY (project_id, user_id)
            )
        """)

        # 記憶
        conn.execute("""
            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY,
                scope TEXT NOT NULL,
                scope_id TEXT,
                type TEXT NOT NULL,
                content TEXT NOT NULL,
                summary TEXT,
                importance REAL DEFAULT 0.5,
                metadata TEXT,
                category TEXT,
                tags TEXT,
                created_by TEXT,
                created_at TEXT NOT NULL,
                expires_at TEXT,
                access_count INTEGER DEFAULT 0,
                last_accessed_at TEXT
            )
        """)

        # category, tags カラムの追加（既存DBへのマイグレーション）
        try:
            conn.execute("ALTER TABLE memories ADD COLUMN category TEXT")
        except sqlite3.OperationalError:
            pass  # カラムが既に存在する場合は無視
        try:
            conn.execute("ALTER TABLE memories ADD COLUMN tags TEXT")
        except sqlite3.OperationalError:
            pass  # カラムが既に存在する場合は無視

        # deprecated, superseded_by カラムの追加（記憶の廃止機能）
        try:
            conn.execute("ALTER TABLE memories ADD COLUMN deprecated BOOLEAN DEFAULT FALSE")
        except sqlite3.OperationalError:
            pass  # カラムが既に存在する場合は無視
        try:
            conn.execute("ALTER TABLE memories ADD COLUMN superseded_by TEXT")
        except sqlite3.OperationalError:
            pass  # カラムが既に存在する場合は無視

        # 監査ログ
        conn.execute("""
            CREATE TABLE IF NOT EXISTS audit_logs (
                id TEXT PRIMARY KEY,
                user_id TEXT,
                action TEXT NOT NULL,
                resource_type TEXT,
                resource_id TEXT,
                details TEXT,
                ip_address TEXT,
                created_at TEXT NOT NULL
            )
        """)

        # インデックス
        conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_scope ON memories(scope, scope_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(type)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_created ON memories(created_at)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_importance ON memories(importance)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_deprecated ON memories(deprecated)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at)")

        # 旧データのマイグレーション
        cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='memories_old'")
        if cursor.fetchone():
            print("Migrating old memories to new schema...")
            conn.execute("""
                INSERT INTO memories (id, scope, scope_id, type, content, summary, importance, metadata, created_at, access_count, last_accessed_at)
                SELECT id, 'project', project_id, type, content, summary, importance, metadata, created_at, access_count, last_accessed_at
                FROM memories_old
            """)
            conn.execute("DROP TABLE memories_old")
            print("Migration completed!")

        conn.commit()


init_db()


# ============================================================
# レート制限
# ============================================================

rate_limit_store: dict[str, list[float]] = defaultdict(list)


def check_rate_limit(identifier: str) -> bool:
    """レート制限をチェック"""
    now = datetime.utcnow().timestamp()
    window_start = now - RATE_LIMIT_WINDOW

    # 古いエントリを削除
    rate_limit_store[identifier] = [
        t for t in rate_limit_store[identifier] if t > window_start
    ]

    # 制限チェック
    if len(rate_limit_store[identifier]) >= RATE_LIMIT_REQUESTS:
        return False

    rate_limit_store[identifier].append(now)
    return True


# ============================================================
# 認証・認可
# ============================================================

class CurrentUser:
    def __init__(self, user_id: str, team_id: Optional[str], role: str, is_admin: bool = False):
        self.user_id = user_id
        self.team_id = team_id
        self.role = role
        self.is_admin = is_admin
        self._project_roles: dict[str, str] = {}

    def load_project_roles(self):
        """プロジェクト権限をロード"""
        with get_db() as conn:
            cursor = conn.execute(
                "SELECT project_id, role FROM project_members WHERE user_id = ?",
                (self.user_id,)
            )
            self._project_roles = {row["project_id"]: row["role"] for row in cursor.fetchall()}

    def can_access_project(self, project_id: str) -> bool:
        """プロジェクトへのアクセス権を確認"""
        if self.is_admin:
            return True
        if not self._project_roles:
            self.load_project_roles()
        return project_id in self._project_roles

    def can_write_project(self, project_id: str) -> bool:
        """プロジェクトへの書き込み権を確認"""
        if self.is_admin:
            return True
        if not self._project_roles:
            self.load_project_roles()
        role = self._project_roles.get(project_id)
        return role in ("admin", "member")


async def get_current_user(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    x_api_key: Optional[str] = Header(None, alias="X-API-Key")
) -> Optional[CurrentUser]:
    """現在のユーザーを取得"""

    # APIキーを取得（Bearerトークン or X-API-Keyヘッダー）
    api_key = None
    if credentials:
        api_key = credentials.credentials
    elif x_api_key:
        api_key = x_api_key

    # 認証が不要な場合
    if not REQUIRE_AUTH and not api_key:
        return CurrentUser(user_id="anonymous", team_id=None, role="member", is_admin=True)

    if not api_key:
        if REQUIRE_AUTH:
            raise HTTPException(status_code=401, detail="API key required")
        return None

    # 管理者キーチェック
    if ADMIN_API_KEY and api_key == ADMIN_API_KEY:
        return CurrentUser(user_id="admin", team_id=None, role="admin", is_admin=True)

    # ユーザー検索
    api_key_hash = hash_api_key(api_key)
    with get_db() as conn:
        cursor = conn.execute(
            "SELECT id, team_id, role FROM users WHERE api_key_hash = ?",
            (api_key_hash,)
        )
        row = cursor.fetchone()

        if not row:
            raise HTTPException(status_code=401, detail="Invalid API key")

        # 最終アクセス更新
        conn.execute(
            "UPDATE users SET last_accessed_at = ? WHERE id = ?",
            (datetime.utcnow().isoformat(), row["id"])
        )
        conn.commit()

        return CurrentUser(
            user_id=row["id"],
            team_id=row["team_id"],
            role=row["role"],
            is_admin=row["role"] == "admin"
        )


def require_auth(func):
    """認証必須デコレータ"""
    @wraps(func)
    async def wrapper(*args, **kwargs):
        user = kwargs.get("current_user")
        if not user:
            raise HTTPException(status_code=401, detail="Authentication required")
        return await func(*args, **kwargs)
    return wrapper


def require_admin(func):
    """管理者権限必須デコレータ"""
    @wraps(func)
    async def wrapper(*args, **kwargs):
        user = kwargs.get("current_user")
        if not user or not user.is_admin:
            raise HTTPException(status_code=403, detail="Admin access required")
        return await func(*args, **kwargs)
    return wrapper


# ============================================================
# 監査ログ
# ============================================================

def log_audit(
    user_id: Optional[str],
    action: str,
    resource_type: Optional[str] = None,
    resource_id: Optional[str] = None,
    details: Optional[dict] = None,
    ip_address: Optional[str] = None
):
    """監査ログを記録"""
    with get_db() as conn:
        conn.execute("""
            INSERT INTO audit_logs (id, user_id, action, resource_type, resource_id, details, ip_address, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            generate_id(),
            user_id,
            action,
            resource_type,
            resource_id,
            json.dumps(details) if details else None,
            ip_address,
            datetime.utcnow().isoformat()
        ))
        conn.commit()


# ============================================================
# ヘルパー関数
# ============================================================

def row_to_memory(row: sqlite3.Row) -> MemoryResponse:
    """DBの行をMemoryResponseに変換"""
    content = row["content"]
    # tagsはJSON配列として保存されている
    tags_raw = row["tags"] if "tags" in row.keys() else None
    tags = json.loads(tags_raw) if tags_raw else []
    return MemoryResponse(
        id=row["id"],
        scope=MemoryScope(row["scope"]),
        scope_id=row["scope_id"],
        type=MemoryType(row["type"]),
        content=content,
        summary=row["summary"],
        importance=row["importance"],
        metadata=json.loads(row["metadata"] or "{}"),
        category=row["category"] if "category" in row.keys() else None,
        tags=tags,
        created_by=row["created_by"],
        created_at=row["created_at"],
        tokens=count_tokens(content),
        deprecated=bool(row["deprecated"]) if "deprecated" in row.keys() else False,
        superseded_by=row["superseded_by"] if "superseded_by" in row.keys() else None
    )


# ============================================================
# API エンドポイント: ヘルスチェック
# ============================================================

@app.get("/health")
async def health():
    """ヘルスチェック"""
    return {
        "status": "healthy",
        "service": "isac-memory",
        "version": "2.1.0",
        "auth_required": REQUIRE_AUTH
    }


# ============================================================
# API エンドポイント: 記憶管理
# ============================================================

@app.post("/store", response_model=StoreResponse)
async def store_memory(
    entry: MemoryEntry,
    request: Request,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """記憶を保存"""
    user_id = current_user.user_id if current_user else None

    # レート制限
    client_ip = request.client.host if request.client else "unknown"
    if not check_rate_limit(user_id or client_ip):
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    # スコープに応じた権限チェック
    if entry.scope == MemoryScope.PROJECT and entry.scope_id:
        if current_user and not current_user.can_write_project(entry.scope_id):
            raise HTTPException(status_code=403, detail="No write access to this project")

    if entry.scope == MemoryScope.TEAM:
        if current_user and current_user.team_id:
            entry.scope_id = entry.scope_id or current_user.team_id
        elif entry.scope_id is None:
            raise HTTPException(status_code=400, detail="team scope requires scope_id")

    memory_id = generate_id()
    now = datetime.utcnow().isoformat()

    # TTL計算
    ttl_days = DEFAULT_TTL_DAYS.get(entry.type.value, 30)
    expires_at = (datetime.utcnow() + timedelta(days=ttl_days)).isoformat()

    # 要約生成
    summary = entry.summary or create_summary(entry.content)

    # カテゴリ・タグの処理
    # メタデータからファイルパスを取得（自動推定用）
    file_path = entry.metadata.get("file")

    # カテゴリ: 指定がなければ自動推定
    category = entry.category.value if entry.category else auto_detect_category(entry.content, file_path)

    # タグ: 指定されたタグ + 自動抽出タグをマージ
    auto_tags = auto_extract_tags(entry.content, file_path)
    all_tags = list(set(entry.tags + auto_tags))[:10]  # 最大10個

    superseded_ids = []
    with get_db() as conn:
        conn.execute("""
            INSERT INTO memories (id, scope, scope_id, type, content, summary, importance, metadata, category, tags, created_by, created_at, expires_at, deprecated)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, FALSE)
        """, (
            memory_id,
            entry.scope.value,
            entry.scope_id,
            entry.type.value,
            entry.content,
            summary,
            entry.importance,
            json.dumps(entry.metadata),
            category,
            json.dumps(all_tags),
            user_id,
            now,
            expires_at
        ))

        # supersedes で指定された記憶を廃止（重複を除外）
        skipped_ids = []
        processed_ids = set()  # 重複チェック用
        if entry.supersedes:
            for old_id in entry.supersedes:
                if old_id in processed_ids:
                    continue  # 重複はスキップ
                processed_ids.add(old_id)
                cursor = conn.execute("SELECT id, created_by FROM memories WHERE id = ?", (old_id,))
                row = cursor.fetchone()
                if not row:
                    skipped_ids.append({"id": old_id, "reason": "not_found"})
                    continue

                # 権限チェック: 作成者または管理者のみ廃止可能
                if current_user and not current_user.is_admin:
                    if row["created_by"] and row["created_by"] != user_id:
                        skipped_ids.append({"id": old_id, "reason": "permission_denied"})
                        continue

                conn.execute("""
                    UPDATE memories
                    SET deprecated = TRUE, superseded_by = ?
                    WHERE id = ?
                """, (memory_id, old_id))
                superseded_ids.append(old_id)

        conn.commit()

    # 監査ログ
    log_audit(
        user_id=user_id,
        action="store_memory",
        resource_type="memory",
        resource_id=memory_id,
        details={"scope": entry.scope.value, "type": entry.type.value, "superseded": superseded_ids, "skipped": skipped_ids},
        ip_address=client_ip
    )

    return StoreResponse(
        id=memory_id,
        tokens=count_tokens(entry.content),
        scope=entry.scope,
        scope_id=entry.scope_id,
        category=category,
        tags=all_tags,
        message=f"Memory stored ({entry.scope.value}/{entry.type.value})",
        superseded_ids=superseded_ids,
        skipped_supersedes=skipped_ids
    )


@app.get("/context/{project_id}", response_model=ContextResponse)
async def get_context(
    project_id: str,
    query: str = Query(..., description="検索クエリ"),
    max_tokens: int = Query(2000, description="最大トークン数"),
    category: Optional[MemoryCategory] = Query(None, description="カテゴリで優先フィルタ"),
    include_deprecated: bool = Query(False, description="廃止済み記憶を含めるか"),
    request: Request = None,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """階層化されたコンテキストを取得"""
    user_id = current_user.user_id if current_user else None
    team_id = current_user.team_id if current_user else None

    # 権限チェック
    if current_user and not current_user.can_access_project(project_id):
        raise HTTPException(status_code=403, detail="No access to this project")

    # トークン予算を分配
    global_budget = int(max_tokens * 0.15)   # 15%
    team_budget = int(max_tokens * 0.15)     # 15%
    decision_budget = int(max_tokens * 0.30) # 30%
    recent_budget = int(max_tokens * 0.40)   # 40%

    now = datetime.utcnow().isoformat()
    query_words = set(query.lower().split())

    def filter_by_query(memories: list[MemoryResponse]) -> list[MemoryResponse]:
        """クエリに関連する記憶をフィルタリング（カテゴリ・タグ考慮）"""
        scored = []
        for m in memories:
            score = 0
            content_words = set(m.content.lower().split())
            tag_words = set(t.lower() for t in m.tags)

            # クエリとのマッチング
            content_match = len(query_words & content_words)
            tag_match = len(query_words & tag_words)
            score = content_match + (tag_match * 2)  # タグマッチは重み付け

            # カテゴリが指定されている場合、一致するものを優先
            if category and m.category == category.value:
                score += 5

            if score > 0:
                scored.append((score, m))

        # スコア順にソート
        scored.sort(key=lambda x: x[0], reverse=True)
        matched = [m for _, m in scored]

        return matched if matched else memories[:5]

    # deprecated フィルタ条件
    deprecated_filter = "" if include_deprecated else "AND (deprecated IS NULL OR deprecated = FALSE)"

    with get_db() as conn:
        # Global knowledge
        cursor = conn.execute(f"""
            SELECT * FROM memories
            WHERE scope = 'global'
            AND (expires_at IS NULL OR expires_at > ?)
            {deprecated_filter}
            ORDER BY importance DESC, created_at DESC
            LIMIT 20
        """, (now,))
        global_raw = [row_to_memory(row) for row in cursor.fetchall()]
        global_knowledge = select_within_budget(filter_by_query(global_raw), global_budget)

        # Team knowledge
        team_knowledge = []
        if team_id:
            cursor = conn.execute(f"""
                SELECT * FROM memories
                WHERE scope = 'team' AND scope_id = ?
                AND (expires_at IS NULL OR expires_at > ?)
                {deprecated_filter}
                ORDER BY importance DESC, created_at DESC
                LIMIT 20
            """, (team_id, now))
            team_raw = [row_to_memory(row) for row in cursor.fetchall()]
            team_knowledge = select_within_budget(filter_by_query(team_raw), team_budget)

        # Project decisions
        cursor = conn.execute(f"""
            SELECT * FROM memories
            WHERE scope = 'project' AND scope_id = ? AND type = 'decision'
            AND (expires_at IS NULL OR expires_at > ?)
            {deprecated_filter}
            ORDER BY importance DESC, created_at DESC
            LIMIT 20
        """, (project_id, now))
        decisions_raw = [row_to_memory(row) for row in cursor.fetchall()]
        project_decisions = select_within_budget(filter_by_query(decisions_raw), decision_budget)

        # Project recent work
        cursor = conn.execute(f"""
            SELECT * FROM memories
            WHERE scope = 'project' AND scope_id = ? AND type IN ('work', 'knowledge')
            AND (expires_at IS NULL OR expires_at > ?)
            {deprecated_filter}
            ORDER BY created_at DESC
            LIMIT 20
        """, (project_id, now))
        recent_raw = [row_to_memory(row) for row in cursor.fetchall()]
        project_recent = select_within_budget(filter_by_query(recent_raw), recent_budget)

        # アクセス記録更新
        all_memories = global_knowledge + team_knowledge + project_decisions + project_recent
        memory_ids = [m.id for m in all_memories]
        if memory_ids:
            placeholders = ",".join("?" * len(memory_ids))
            conn.execute(f"""
                UPDATE memories
                SET access_count = access_count + 1, last_accessed_at = ?
                WHERE id IN ({placeholders})
            """, [now] + memory_ids)
            conn.commit()

    total_tokens = sum(m.tokens for m in all_memories)

    return ContextResponse(
        global_knowledge=global_knowledge,
        team_knowledge=team_knowledge,
        project_decisions=project_decisions,
        project_recent=project_recent,
        total_tokens=total_tokens
    )


@app.get("/search")
async def search_memories(
    query: str = Query(...),
    scope: Optional[MemoryScope] = Query(None),
    scope_id: Optional[str] = Query(None),
    type: Optional[MemoryType] = Query(None),
    category: Optional[MemoryCategory] = Query(None, description="カテゴリでフィルタ"),
    tags: Optional[str] = Query(None, description="タグでフィルタ（カンマ区切り）"),
    include_deprecated: bool = Query(False, description="廃止済み記憶を含めるか"),
    limit: int = Query(10, le=50),
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """記憶を検索"""
    now = datetime.utcnow().isoformat()

    with get_db() as conn:
        sql = """
            SELECT * FROM memories
            WHERE (expires_at IS NULL OR expires_at > ?)
        """
        params: list = [now]

        # デフォルトで廃止済み記憶を除外
        if not include_deprecated:
            sql += " AND (deprecated IS NULL OR deprecated = FALSE)"

        if scope:
            sql += " AND scope = ?"
            params.append(scope.value)

        if scope_id:
            sql += " AND scope_id = ?"
            params.append(scope_id)

        if type:
            sql += " AND type = ?"
            params.append(type.value)

        if category:
            sql += " AND category = ?"
            params.append(category.value)

        sql += " ORDER BY importance DESC, created_at DESC LIMIT ?"
        params.append(limit * 5)  # タグフィルタ用に多めに取得

        cursor = conn.execute(sql, params)
        all_memories = [row_to_memory(row) for row in cursor.fetchall()]

    # タグでフィルタ（指定されている場合）
    if tags:
        filter_tags = set(t.strip().lower() for t in tags.split(","))
        all_memories = [
            m for m in all_memories
            if filter_tags & set(t.lower() for t in m.tags)
        ]

    # キーワードマッチング
    query_words = set(query.lower().split())
    matched = []
    for m in all_memories:
        content_words = set(m.content.lower().split())
        # タグもマッチング対象に含める
        tag_words = set(t.lower() for t in m.tags)
        all_words = content_words | tag_words
        score = len(query_words & all_words)
        if score > 0:
            matched.append((score, m))

    matched.sort(key=lambda x: x[0], reverse=True)
    results = [m for _, m in matched[:limit]]

    if not results:
        results = all_memories[:limit]

    return {"memories": results, "count": len(results)}


@app.get("/memory/{memory_id}")
async def get_memory(
    memory_id: str,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """特定の記憶を取得"""
    with get_db() as conn:
        cursor = conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,))
        row = cursor.fetchone()

        if not row:
            raise HTTPException(status_code=404, detail="Memory not found")

        now = datetime.utcnow().isoformat()
        conn.execute("""
            UPDATE memories SET access_count = access_count + 1, last_accessed_at = ?
            WHERE id = ?
        """, (now, memory_id))
        conn.commit()

        return row_to_memory(row)


@app.patch("/memory/{memory_id}")
async def update_memory(
    memory_id: str,
    update: MemoryUpdate,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """記憶のタグ、カテゴリ、重要度を更新"""
    with get_db() as conn:
        # 記憶を取得
        cursor = conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,))
        row = cursor.fetchone()

        if not row:
            raise HTTPException(status_code=404, detail="Memory not found")

        # 作成者または管理者のみ編集可能
        if current_user and not current_user.is_admin:
            if row["created_by"] != current_user.user_id:
                raise HTTPException(status_code=403, detail="Cannot edit others' memories")

        # 更新内容を構築
        updates = []
        params = []

        # カテゴリの更新
        if update.category is not None:
            updates.append("category = ?")
            params.append(update.category.value)

        # 重要度の更新
        if update.importance is not None:
            updates.append("importance = ?")
            params.append(update.importance)

        # 要約の更新
        if update.summary is not None:
            updates.append("summary = ?")
            params.append(update.summary)

        # タグの処理
        current_tags = json.loads(row["tags"]) if row["tags"] else []
        new_tags = None

        if update.tags is not None:
            # タグを完全に置き換え
            new_tags = list(set(t.lower().strip() for t in update.tags if t.strip()))
        else:
            # 追加/削除の処理
            if update.add_tags:
                current_tags.extend(t.lower().strip() for t in update.add_tags if t.strip())
                new_tags = list(set(current_tags))
            if update.remove_tags:
                remove_set = set(t.lower().strip() for t in update.remove_tags)
                if new_tags is None:
                    new_tags = current_tags
                new_tags = [t for t in new_tags if t not in remove_set]

        if new_tags is not None:
            # タグ数制限（最大10個）
            new_tags = new_tags[:10]
            updates.append("tags = ?")
            params.append(json.dumps(new_tags))

        # メタデータの更新（既存のメタデータにマージ）
        if update.metadata is not None:
            current_metadata = json.loads(row["metadata"] or "{}")
            current_metadata.update(update.metadata)
            updates.append("metadata = ?")
            params.append(json.dumps(current_metadata))

        if not updates:
            raise HTTPException(status_code=400, detail="No updates provided")

        # 更新実行
        params.append(memory_id)
        sql = f"UPDATE memories SET {', '.join(updates)} WHERE id = ?"
        conn.execute(sql, params)
        conn.commit()

        # 更新後の記憶を取得
        cursor = conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,))
        updated_row = cursor.fetchone()

        log_audit(
            user_id=current_user.user_id if current_user else None,
            action="update_memory",
            resource_type="memory",
            resource_id=memory_id,
            details={"updates": updates}
        )

        return {
            "id": memory_id,
            "message": "Memory updated",
            "category": updated_row["category"],
            "tags": json.loads(updated_row["tags"]) if updated_row["tags"] else [],
            "importance": updated_row["importance"]
        }


@app.delete("/memory/{memory_id}")
async def delete_memory(
    memory_id: str,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """記憶を削除"""
    with get_db() as conn:
        # 記憶を取得して権限チェック
        cursor = conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,))
        row = cursor.fetchone()

        if not row:
            raise HTTPException(status_code=404, detail="Memory not found")

        # 作成者または管理者のみ削除可能
        if current_user and not current_user.is_admin:
            if row["created_by"] != current_user.user_id:
                raise HTTPException(status_code=403, detail="Cannot delete others' memories")

        conn.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
        conn.commit()

        log_audit(
            user_id=current_user.user_id if current_user else None,
            action="delete_memory",
            resource_type="memory",
            resource_id=memory_id
        )

        return {"message": "Memory deleted", "id": memory_id}


class DeprecateRequest(BaseModel):
    """記憶の廃止/復元リクエスト"""
    deprecated: bool = Field(..., description="廃止する場合はTrue、復元する場合はFalse")
    superseded_by: Optional[str] = Field(None, description="後継の記憶ID（廃止時のみ）")


@app.patch("/memory/{memory_id}/deprecate")
async def deprecate_memory(
    memory_id: str,
    request: DeprecateRequest,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """記憶を廃止または復元"""
    with get_db() as conn:
        # 記憶を取得
        cursor = conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,))
        row = cursor.fetchone()

        if not row:
            raise HTTPException(status_code=404, detail="Memory not found")

        # 作成者または管理者のみ操作可能
        if current_user and not current_user.is_admin:
            if row["created_by"] != current_user.user_id:
                raise HTTPException(status_code=403, detail="Cannot modify others' memories")

        # 廃止/復元を実行
        if request.deprecated:
            # superseded_by が指定されている場合、存在確認
            if request.superseded_by:
                cursor = conn.execute("SELECT id FROM memories WHERE id = ?", (request.superseded_by,))
                if not cursor.fetchone():
                    raise HTTPException(status_code=400, detail="Superseding memory not found")

            conn.execute("""
                UPDATE memories
                SET deprecated = TRUE, superseded_by = ?
                WHERE id = ?
            """, (request.superseded_by, memory_id))
            action = "deprecate_memory"
            message = "Memory deprecated"
        else:
            conn.execute("""
                UPDATE memories
                SET deprecated = FALSE, superseded_by = NULL
                WHERE id = ?
            """, (memory_id,))
            action = "restore_memory"
            message = "Memory restored"

        conn.commit()

        log_audit(
            user_id=current_user.user_id if current_user else None,
            action=action,
            resource_type="memory",
            resource_id=memory_id,
            details={"superseded_by": request.superseded_by} if request.deprecated else None
        )

        return {
            "id": memory_id,
            "message": message,
            "deprecated": request.deprecated,
            "superseded_by": request.superseded_by if request.deprecated else None
        }


# ============================================================
# API エンドポイント: チーム管理
# ============================================================

@app.post("/admin/teams")
async def create_team(
    team: TeamCreate,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """チームを作成（管理者のみ）"""
    if current_user and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    with get_db() as conn:
        try:
            conn.execute("""
                INSERT INTO teams (id, name, created_at)
                VALUES (?, ?, ?)
            """, (team.id, team.name, datetime.utcnow().isoformat()))
            conn.commit()
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Team already exists")

    log_audit(
        user_id=current_user.user_id if current_user else None,
        action="create_team",
        resource_type="team",
        resource_id=team.id
    )

    return {"message": "Team created", "team_id": team.id}


@app.get("/admin/teams")
async def list_teams(
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """チーム一覧（管理者のみ）"""
    if current_user and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    with get_db() as conn:
        cursor = conn.execute("SELECT * FROM teams ORDER BY created_at DESC")
        teams = [dict(row) for row in cursor.fetchall()]

    return {"teams": teams}


# ============================================================
# API エンドポイント: ユーザー管理
# ============================================================

@app.post("/admin/users")
async def create_user(
    user: UserCreate,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """ユーザーを作成してAPIキーを発行（管理者のみ）"""
    if current_user and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    api_key = generate_api_key()
    api_key_hash = hash_api_key(api_key)

    with get_db() as conn:
        try:
            conn.execute("""
                INSERT INTO users (id, team_id, api_key_hash, role, created_at)
                VALUES (?, ?, ?, ?, ?)
            """, (user.id, user.team_id, api_key_hash, user.role.value, datetime.utcnow().isoformat()))
            conn.commit()
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="User already exists")

    log_audit(
        user_id=current_user.user_id if current_user else None,
        action="create_user",
        resource_type="user",
        resource_id=user.id
    )

    return {
        "message": "User created",
        "user_id": user.id,
        "api_key": api_key,  # 一度だけ表示
        "warning": "Save this API key - it cannot be retrieved later"
    }


@app.get("/admin/users")
async def list_users(
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """ユーザー一覧（管理者のみ）"""
    if current_user and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    with get_db() as conn:
        cursor = conn.execute("""
            SELECT id, team_id, role, created_at, last_accessed_at
            FROM users ORDER BY created_at DESC
        """)
        users = [dict(row) for row in cursor.fetchall()]

    return {"users": users}


@app.post("/admin/users/{user_id}/regenerate-key")
async def regenerate_api_key(
    user_id: str,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """APIキーを再生成（管理者のみ）"""
    if current_user and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    api_key = generate_api_key()
    api_key_hash = hash_api_key(api_key)

    with get_db() as conn:
        cursor = conn.execute(
            "UPDATE users SET api_key_hash = ? WHERE id = ?",
            (api_key_hash, user_id)
        )
        conn.commit()

        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="User not found")

    log_audit(
        user_id=current_user.user_id if current_user else None,
        action="regenerate_api_key",
        resource_type="user",
        resource_id=user_id
    )

    return {
        "message": "API key regenerated",
        "user_id": user_id,
        "api_key": api_key,
        "warning": "Save this API key - it cannot be retrieved later"
    }


# ============================================================
# API エンドポイント: プロジェクトメンバー管理
# ============================================================

@app.post("/projects/{project_id}/members")
async def add_project_member(
    project_id: str,
    member: ProjectMemberAdd,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """プロジェクトにメンバーを追加"""
    # 管理者またはプロジェクト管理者のみ
    if current_user and not current_user.is_admin:
        current_user.load_project_roles()
        if current_user._project_roles.get(project_id) != "admin":
            raise HTTPException(status_code=403, detail="Project admin access required")

    with get_db() as conn:
        try:
            conn.execute("""
                INSERT INTO project_members (project_id, user_id, role, created_at)
                VALUES (?, ?, ?, ?)
            """, (project_id, member.user_id, member.role.value, datetime.utcnow().isoformat()))
            conn.commit()
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Member already exists")

    return {"message": "Member added", "project_id": project_id, "user_id": member.user_id}


@app.get("/projects/{project_id}/members")
async def list_project_members(
    project_id: str,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """プロジェクトのメンバー一覧"""
    if current_user and not current_user.can_access_project(project_id):
        raise HTTPException(status_code=403, detail="No access to this project")

    with get_db() as conn:
        cursor = conn.execute("""
            SELECT pm.user_id, pm.role, pm.created_at, u.team_id
            FROM project_members pm
            JOIN users u ON pm.user_id = u.id
            WHERE pm.project_id = ?
        """, (project_id,))
        members = [dict(row) for row in cursor.fetchall()]

    return {"project_id": project_id, "members": members}


# ============================================================
# API エンドポイント: プロジェクト一覧
# ============================================================

class ProjectInfo(BaseModel):
    """プロジェクト情報"""
    project_id: str
    memory_count: int
    decision_count: int
    last_activity: Optional[str]


# ============================================================
# API エンドポイント: カテゴリ・タグ
# ============================================================

@app.get("/categories")
async def list_categories():
    """利用可能なカテゴリ一覧を取得"""
    return {
        "categories": CATEGORIES,
        "descriptions": {
            "backend": "サーバーサイド開発",
            "frontend": "クライアントサイド開発",
            "infra": "インフラ・DevOps",
            "security": "セキュリティ",
            "database": "データベース",
            "api": "API設計",
            "ui": "UI/UX",
            "test": "テスト",
            "docs": "ドキュメント",
            "architecture": "アーキテクチャ設計",
            "other": "その他"
        }
    }


@app.get("/tags/{scope_id}")
async def list_tags(
    scope_id: str,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """プロジェクト/チームで使用されているタグ一覧を取得"""
    with get_db() as conn:
        cursor = conn.execute("""
            SELECT tags FROM memories
            WHERE scope_id = ? AND tags IS NOT NULL
        """, (scope_id,))

        all_tags: dict[str, int] = {}
        for row in cursor.fetchall():
            tags = json.loads(row["tags"] or "[]")
            for tag in tags:
                all_tags[tag] = all_tags.get(tag, 0) + 1

        # 使用頻度順にソート
        sorted_tags = sorted(all_tags.items(), key=lambda x: x[1], reverse=True)

        return {
            "scope_id": scope_id,
            "tags": [{"tag": t, "count": c} for t, c in sorted_tags],
            "total": len(sorted_tags)
        }


@app.get("/my/todos")
async def get_my_todos(
    project_id: str = Query(..., description="プロジェクトID"),
    owner: str = Query(..., description="オーナー（メールアドレス）"),
    status: str = Query("pending", description="ステータス（pending/done/all）"),
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """個人のTODOリストを取得"""
    now = datetime.utcnow().isoformat()

    with get_db() as conn:
        sql = """
            SELECT * FROM memories
            WHERE scope = 'project'
            AND scope_id = ?
            AND type = 'todo'
            AND (expires_at IS NULL OR expires_at > ?)
            AND (deprecated IS NULL OR deprecated = FALSE)
        """
        params: list = [project_id, now]

        cursor = conn.execute(sql, params)
        all_todos = []

        for row in cursor.fetchall():
            memory = row_to_memory(row)
            # ownerでフィルタ
            if memory.metadata.get("owner") != owner:
                continue
            # statusでフィルタ
            todo_status = memory.metadata.get("status", "pending")
            if status != "all" and todo_status != status:
                continue
            all_todos.append(memory)

        # 作成日順にソート（新しい順）
        all_todos.sort(key=lambda x: x.created_at, reverse=True)

        return {
            "project_id": project_id,
            "owner": owner,
            "todos": all_todos,
            "count": len(all_todos)
        }


@app.get("/projects", response_model=list[ProjectInfo])
async def list_projects(
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """登録されているプロジェクト一覧を取得"""
    with get_db() as conn:
        cursor = conn.execute("""
            SELECT
                scope_id as project_id,
                COUNT(*) as memory_count,
                SUM(CASE WHEN type = 'decision' THEN 1 ELSE 0 END) as decision_count,
                MAX(created_at) as last_activity
            FROM memories
            WHERE scope = 'project' AND scope_id IS NOT NULL
            GROUP BY scope_id
            ORDER BY last_activity DESC
        """)

        projects = []
        for row in cursor.fetchall():
            # 認証が有効な場合、アクセス権があるプロジェクトのみ返す
            if current_user and not current_user.can_access_project(row["project_id"]):
                continue
            projects.append(ProjectInfo(
                project_id=row["project_id"],
                memory_count=row["memory_count"],
                decision_count=row["decision_count"],
                last_activity=row["last_activity"]
            ))

        return projects


@app.get("/projects/suggest")
async def suggest_project(
    name: str = Query(..., description="入力されたプロジェクト名"),
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """類似プロジェクト名を提案（Typoチェック用）"""
    with get_db() as conn:
        cursor = conn.execute("""
            SELECT DISTINCT scope_id as project_id
            FROM memories
            WHERE scope = 'project' AND scope_id IS NOT NULL
        """)

        existing_projects = [row["project_id"] for row in cursor.fetchall()]

    # 完全一致チェック
    if name in existing_projects:
        return {
            "exact_match": True,
            "project_id": name,
            "suggestions": []
        }

    # 類似度計算（レーベンシュタイン距離の簡易版）
    def similarity(a: str, b: str) -> float:
        a, b = a.lower(), b.lower()
        if a == b:
            return 1.0
        # 前方一致
        if a.startswith(b) or b.startswith(a):
            return 0.8
        # 含まれている
        if a in b or b in a:
            return 0.6
        # 編集距離ベースの類似度
        len_a, len_b = len(a), len(b)
        if abs(len_a - len_b) > max(len_a, len_b) * 0.5:
            return 0.0
        # 共通文字数
        common = sum(1 for c in a if c in b)
        return common / max(len_a, len_b)

    # 類似プロジェクトを検索
    suggestions = []
    for project in existing_projects:
        score = similarity(name, project)
        if score >= 0.4:  # 閾値
            suggestions.append({
                "project_id": project,
                "similarity": round(score, 2)
            })

    # スコア順にソート
    suggestions.sort(key=lambda x: x["similarity"], reverse=True)

    return {
        "exact_match": False,
        "input": name,
        "suggestions": suggestions[:5]  # 上位5件
    }


# ============================================================
# API エンドポイント: 統計・管理
# ============================================================

@app.get("/stats/{project_id}")
async def get_stats(
    project_id: str,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """プロジェクトの統計情報"""
    with get_db() as conn:
        cursor = conn.execute("""
            SELECT
                scope,
                type,
                COUNT(*) as count,
                AVG(importance) as avg_importance
            FROM memories
            WHERE scope_id = ? OR scope = 'global'
            GROUP BY scope, type
        """, (project_id,))

        stats = {}
        for row in cursor.fetchall():
            key = f"{row['scope']}/{row['type']}"
            stats[key] = {
                "count": row["count"],
                "avg_importance": round(row["avg_importance"], 2) if row["avg_importance"] else 0
            }

        return {"project_id": project_id, "stats": stats}


@app.get("/admin/audit-logs")
async def get_audit_logs(
    limit: int = Query(100, le=1000),
    user_id: Optional[str] = Query(None),
    action: Optional[str] = Query(None),
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """監査ログを取得（管理者のみ）"""
    if current_user and not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    with get_db() as conn:
        sql = "SELECT * FROM audit_logs WHERE 1=1"
        params: list = []

        if user_id:
            sql += " AND user_id = ?"
            params.append(user_id)

        if action:
            sql += " AND action = ?"
            params.append(action)

        sql += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        cursor = conn.execute(sql, params)
        logs = []
        for row in cursor.fetchall():
            log = dict(row)
            if log.get("details"):
                log["details"] = json.loads(log["details"])
            logs.append(log)

        return {"logs": logs, "count": len(logs)}


@app.post("/cleanup")
async def cleanup_expired(
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """期限切れの記憶を削除"""
    with get_db() as conn:
        now = datetime.utcnow().isoformat()
        cursor = conn.execute("""
            DELETE FROM memories WHERE expires_at IS NOT NULL AND expires_at < ?
        """, (now,))
        conn.commit()

        log_audit(
            user_id=current_user.user_id if current_user else None,
            action="cleanup_expired",
            details={"deleted_count": cursor.rowcount}
        )

        return {"deleted": cursor.rowcount}


@app.get("/export/{project_id}")
async def export_memories(
    project_id: str,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """プロジェクトの記憶をエクスポート"""
    if current_user and not current_user.can_access_project(project_id):
        raise HTTPException(status_code=403, detail="No access to this project")

    with get_db() as conn:
        cursor = conn.execute("""
            SELECT * FROM memories
            WHERE scope_id = ? OR scope = 'global'
        """, (project_id,))

        memories = []
        for row in cursor.fetchall():
            memories.append({
                "id": row["id"],
                "scope": row["scope"],
                "scope_id": row["scope_id"],
                "type": row["type"],
                "content": row["content"],
                "summary": row["summary"],
                "importance": row["importance"],
                "metadata": json.loads(row["metadata"] or "{}"),
                "category": row["category"] if "category" in row.keys() else None,
                "tags": json.loads(row["tags"] or "[]") if "tags" in row.keys() else [],
                "created_by": row["created_by"],
                "created_at": row["created_at"]
            })

        return {"project_id": project_id, "memories": memories, "count": len(memories)}


@app.post("/import")
async def import_memories(
    data: dict,
    current_user: Optional[CurrentUser] = Depends(get_current_user)
):
    """記憶をインポート"""
    memories = data.get("memories", [])

    imported = 0
    user_id = current_user.user_id if current_user else None

    with get_db() as conn:
        for m in memories:
            try:
                memory_id = m.get("id", generate_id())
                now = datetime.utcnow().isoformat()
                scope = m.get("scope", "project")
                ttl_days = DEFAULT_TTL_DAYS.get(m.get("type", "work"), 30)
                expires_at = (datetime.utcnow() + timedelta(days=ttl_days)).isoformat()

                # タグはリストまたはJSON文字列として受け取る
                tags = m.get("tags", [])
                if isinstance(tags, str):
                    tags = json.loads(tags)

                conn.execute("""
                    INSERT OR REPLACE INTO memories
                    (id, scope, scope_id, type, content, summary, importance, metadata, category, tags, created_by, created_at, expires_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    memory_id,
                    scope,
                    m.get("scope_id"),
                    m.get("type", "work"),
                    m.get("content", ""),
                    m.get("summary"),
                    m.get("importance", 0.5),
                    json.dumps(m.get("metadata", {})),
                    m.get("category"),
                    json.dumps(tags),
                    m.get("created_by", user_id),
                    m.get("created_at", now),
                    expires_at
                ))
                imported += 1
            except Exception:
                continue

        conn.commit()

    log_audit(
        user_id=user_id,
        action="import_memories",
        details={"imported_count": imported}
    )

    return {"imported": imported}


# ============================================================
# メイン
# ============================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
