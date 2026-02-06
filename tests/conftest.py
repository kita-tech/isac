"""
ISAC Memory Service テスト用 pytest 設定

テスト実行前に必要な環境:
    cd memory-service
    docker compose -f docker-compose.test.yml up -d --build
"""

import os
import pytest
import requests
from dataclasses import dataclass
from typing import Optional

# テスト設定
BASE_URL = os.getenv("ISAC_TEST_URL", "http://localhost:8200")
ADMIN_API_KEY = os.getenv("ISAC_TEST_ADMIN_KEY", "isac_test_admin_key_12345")
DEFAULT_TIMEOUT = 30  # 全リクエストのデフォルトタイムアウト（秒）


@pytest.fixture(autouse=True, scope="session")
def _set_default_timeout():
    """全テストの requests 呼び出しにデフォルトタイムアウトを設定"""
    original_send = requests.Session.send

    def patched_send(self, request, **kwargs):
        kwargs.setdefault("timeout", DEFAULT_TIMEOUT)
        return original_send(self, request, **kwargs)

    requests.Session.send = patched_send
    yield
    requests.Session.send = original_send


@dataclass
class UserInfo:
    """テストユーザー情報"""
    user_id: str
    api_key: str
    role: str = "member"


class APIClient:
    """テスト用 API クライアント"""

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key
        self.base_url = BASE_URL

    def _headers(self) -> dict:
        if self.api_key:
            return {"X-API-Key": self.api_key, "Content-Type": "application/json"}
        return {"Content-Type": "application/json"}

    def post(self, path: str, json: dict, timeout: int = DEFAULT_TIMEOUT) -> requests.Response:
        return requests.post(f"{self.base_url}{path}", json=json, headers=self._headers(), timeout=timeout)

    def get(self, path: str, params: dict = None, timeout: int = DEFAULT_TIMEOUT) -> requests.Response:
        return requests.get(f"{self.base_url}{path}", params=params, headers=self._headers(), timeout=timeout)

    def patch(self, path: str, json: dict, timeout: int = DEFAULT_TIMEOUT) -> requests.Response:
        return requests.patch(f"{self.base_url}{path}", json=json, headers=self._headers(), timeout=timeout)

    def delete(self, path: str, timeout: int = DEFAULT_TIMEOUT) -> requests.Response:
        return requests.delete(f"{self.base_url}{path}", headers=self._headers(), timeout=timeout)


@pytest.fixture(scope="session")
def admin_client() -> APIClient:
    """Admin 権限を持つ API クライアント"""
    return APIClient(api_key=ADMIN_API_KEY)


@pytest.fixture(scope="session")
def test_users(admin_client: APIClient) -> dict[str, UserInfo]:
    """
    テスト用ユーザーを作成

    Returns:
        dict with keys:
            - "user_a": 通常テスト用ユーザー
            - "user_b": 権限テスト用ユーザー（他人の記憶にアクセス試行）
    """
    users = {}

    for user_id in ["test-user-a", "test-user-b"]:
        # ユーザー作成
        response = admin_client.post("/admin/users", json={
            "id": user_id,
            "role": "member"
        })

        if response.status_code == 200:
            data = response.json()
            users[user_id.replace("test-", "").replace("-", "_")] = UserInfo(
                user_id=user_id,
                api_key=data["api_key"],
                role="member"
            )
        elif response.status_code == 409:
            # 既に存在する場合は API キーを再生成
            regen_response = admin_client.post(f"/admin/users/{user_id}/regenerate-key", json={})
            if regen_response.status_code == 200:
                data = regen_response.json()
                users[user_id.replace("test-", "").replace("-", "_")] = UserInfo(
                    user_id=user_id,
                    api_key=data["api_key"],
                    role="member"
                )
            else:
                pytest.fail(f"Failed to regenerate API key for {user_id}: {regen_response.text}")
        else:
            pytest.fail(f"Failed to create user {user_id}: {response.text}")

    return users


@pytest.fixture
def project_with_user_a(admin_client: APIClient, test_users: dict[str, UserInfo], unique_scope_id: str) -> str:
    """
    User A がメンバーとして登録されたプロジェクトを作成

    Returns:
        project_id (scope_id)
    """
    project_id = unique_scope_id

    # User A をプロジェクトメンバーとして追加
    response = admin_client.post(f"/projects/{project_id}/members", json={
        "user_id": test_users["user_a"].user_id,
        "role": "member"
    })
    # 既に存在する場合も OK
    assert response.status_code in [200, 409], f"Failed to add user_a to project: {response.text}"

    return project_id


@pytest.fixture
def project_with_both_users(admin_client: APIClient, test_users: dict[str, UserInfo], unique_scope_id: str) -> str:
    """
    User A と User B の両方がメンバーとして登録されたプロジェクト

    Returns:
        project_id (scope_id)
    """
    project_id = unique_scope_id

    for user_key in ["user_a", "user_b"]:
        response = admin_client.post(f"/projects/{project_id}/members", json={
            "user_id": test_users[user_key].user_id,
            "role": "member"
        })
        assert response.status_code in [200, 409], f"Failed to add {user_key} to project: {response.text}"

    return project_id


@pytest.fixture(scope="session")
def user_a_client(test_users: dict[str, UserInfo]) -> APIClient:
    """User A の API クライアント（通常テスト用）"""
    return APIClient(api_key=test_users["user_a"].api_key)


@pytest.fixture(scope="session")
def user_b_client(test_users: dict[str, UserInfo]) -> APIClient:
    """User B の API クライアント（権限テスト用 - 他人の記憶にアクセス試行）"""
    return APIClient(api_key=test_users["user_b"].api_key)


@pytest.fixture(scope="session")
def anonymous_client() -> APIClient:
    """認証なしの API クライアント（認証必須環境ではエラーになる）"""
    return APIClient(api_key=None)


@pytest.fixture
def unique_scope_id() -> str:
    """テストごとにユニークな scope_id を生成"""
    import uuid
    return f"test-{uuid.uuid4().hex[:8]}"


@pytest.fixture
def special_chars():
    """特殊文字テスト用データ"""
    return [
        'テスト with "double quotes"',
        "テスト with 'single quotes'",
        'テスト with <brackets> & ampersand',
        'テスト with backslash \\ here',
        'テスト with backtick ` here',
        'テスト with dollar $VAR sign',
        'テスト with tab\there',
        'テスト with newline\nhere',
        'テスト with emoji 😀🎉',
        'テスト with japanese 日本語テスト',
    ]


@pytest.fixture
def boundary_values():
    """境界値テスト用データ"""
    return {
        'empty': '',
        'single_char': 'a',
        'max_summary': 'a' * 200,
        'long_content': 'a' * 10000,
        'zero_importance': 0.0,
        'max_importance': 1.0,
        'negative_importance': -0.1,
        'over_importance': 1.1,
    }
