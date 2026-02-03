"""
ISAC Memory Service 権限テスト

認証有効環境（REQUIRE_AUTH=true）で実行する権限関連のテスト

実行方法:
    cd memory-service
    docker compose -f docker-compose.test.yml up -d --build
    cd ..
    pytest tests/test_permission.py -v
"""

import pytest
from conftest import APIClient, UserInfo


class TestAuthRequired:
    """認証必須のテスト"""

    def test_anonymous_access_denied(self, anonymous_client: APIClient):
        """認証なしでのアクセスは拒否される"""
        response = anonymous_client.post("/store", json={
            "content": "匿名テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "anon-test"
        })
        assert response.status_code == 401

    def test_authenticated_access_allowed(self, user_a_client: APIClient, project_with_user_a: str):
        """認証ありでのアクセスは許可される（プロジェクトメンバーとして）"""
        response = user_a_client.post("/store", json={
            "content": "認証済みテスト",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_user_a
        })
        assert response.status_code == 200


class TestSupersedersPermission:
    """supersedes の権限テスト"""

    def test_can_supersede_own_memory(self, user_a_client: APIClient, project_with_user_a: str):
        """自分が作成した記憶は廃止できる"""
        # User A が記憶を作成
        old_response = user_a_client.post("/store", json={
            "content": "User A の古い記憶",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_user_a
        })
        assert old_response.status_code == 200, f"Failed to create memory: {old_response.text}"
        old_id = old_response.json()["id"]

        # User A が自分の記憶を廃止
        new_response = user_a_client.post("/store", json={
            "content": "User A の新しい記憶",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_user_a,
            "supersedes": [old_id]
        })
        assert new_response.status_code == 200
        data = new_response.json()
        assert old_id in data["superseded_ids"]
        assert len(data["skipped_supersedes"]) == 0

    def test_cannot_supersede_others_memory(
        self,
        user_a_client: APIClient,
        user_b_client: APIClient,
        project_with_both_users: str
    ):
        """他人が作成した記憶は廃止できない"""
        # User A が記憶を作成
        old_response = user_a_client.post("/store", json={
            "content": "User A の記憶（他人は廃止不可）",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_both_users
        })
        assert old_response.status_code == 200, f"Failed to create memory: {old_response.text}"
        old_id = old_response.json()["id"]

        # User B が User A の記憶を廃止しようとする
        new_response = user_b_client.post("/store", json={
            "content": "User B の記憶",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_both_users,
            "supersedes": [old_id]
        })
        assert new_response.status_code == 200
        data = new_response.json()

        # 廃止されず、スキップされる
        assert old_id not in data["superseded_ids"]
        assert any(
            s["id"] == old_id and s["reason"] == "permission_denied"
            for s in data["skipped_supersedes"]
        )

        # 元の記憶が廃止されていないことを確認
        memory = user_a_client.get(f"/memory/{old_id}").json()
        assert memory["deprecated"] is False

    def test_admin_can_supersede_others_memory(
        self,
        user_a_client: APIClient,
        admin_client: APIClient,
        project_with_user_a: str
    ):
        """Admin は他人の記憶も廃止できる"""
        # User A が記憶を作成
        old_response = user_a_client.post("/store", json={
            "content": "User A の記憶（Admin は廃止可能）",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_user_a
        })
        assert old_response.status_code == 200, f"Failed to create memory: {old_response.text}"
        old_id = old_response.json()["id"]

        # Admin が User A の記憶を廃止
        new_response = admin_client.post("/store", json={
            "content": "Admin の記憶",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_user_a,
            "supersedes": [old_id]
        })
        assert new_response.status_code == 200
        data = new_response.json()
        assert old_id in data["superseded_ids"]


class TestDeprecatePermission:
    """手動廃止 API の権限テスト"""

    def test_can_deprecate_own_memory(self, user_a_client: APIClient, project_with_user_a: str):
        """自分が作成した記憶は手動廃止できる"""
        # User A が記憶を作成
        create_response = user_a_client.post("/store", json={
            "content": "手動廃止テスト（自分）",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_user_a
        })
        assert create_response.status_code == 200, f"Failed to create memory: {create_response.text}"
        memory_id = create_response.json()["id"]

        # User A が自分の記憶を廃止
        response = user_a_client.patch(
            f"/memory/{memory_id}/deprecate",
            json={"deprecated": True}
        )
        assert response.status_code == 200
        assert response.json()["deprecated"] is True

    def test_cannot_deprecate_others_memory(
        self,
        user_a_client: APIClient,
        user_b_client: APIClient,
        project_with_both_users: str
    ):
        """他人が作成した記憶は手動廃止できない"""
        # User A が記憶を作成
        create_response = user_a_client.post("/store", json={
            "content": "手動廃止テスト（他人は不可）",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_both_users
        })
        assert create_response.status_code == 200, f"Failed to create memory: {create_response.text}"
        memory_id = create_response.json()["id"]

        # User B が User A の記憶を廃止しようとする
        response = user_b_client.patch(
            f"/memory/{memory_id}/deprecate",
            json={"deprecated": True}
        )
        assert response.status_code == 403

    def test_admin_can_deprecate_others_memory(
        self,
        user_a_client: APIClient,
        admin_client: APIClient,
        project_with_user_a: str
    ):
        """Admin は他人の記憶も手動廃止できる"""
        # User A が記憶を作成
        create_response = user_a_client.post("/store", json={
            "content": "手動廃止テスト（Admin は可能）",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_user_a
        })
        assert create_response.status_code == 200, f"Failed to create memory: {create_response.text}"
        memory_id = create_response.json()["id"]

        # Admin が User A の記憶を廃止
        response = admin_client.patch(
            f"/memory/{memory_id}/deprecate",
            json={"deprecated": True}
        )
        assert response.status_code == 200
        assert response.json()["deprecated"] is True


class TestDeletePermission:
    """削除 API の権限テスト"""

    def test_can_delete_own_memory(self, user_a_client: APIClient, project_with_user_a: str):
        """自分が作成した記憶は削除できる"""
        # User A が記憶を作成
        create_response = user_a_client.post("/store", json={
            "content": "削除テスト（自分）",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_user_a
        })
        assert create_response.status_code == 200, f"Failed to create memory: {create_response.text}"
        memory_id = create_response.json()["id"]

        # User A が自分の記憶を削除
        response = user_a_client.delete(f"/memory/{memory_id}")
        assert response.status_code == 200

        # 削除後は取得できない
        get_response = user_a_client.get(f"/memory/{memory_id}")
        assert get_response.status_code == 404

    def test_cannot_delete_others_memory(
        self,
        user_a_client: APIClient,
        user_b_client: APIClient,
        project_with_both_users: str
    ):
        """他人が作成した記憶は削除できない"""
        # User A が記憶を作成
        create_response = user_a_client.post("/store", json={
            "content": "削除テスト（他人は不可）",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_both_users
        })
        assert create_response.status_code == 200, f"Failed to create memory: {create_response.text}"
        memory_id = create_response.json()["id"]

        # User B が User A の記憶を削除しようとする
        response = user_b_client.delete(f"/memory/{memory_id}")
        assert response.status_code == 403

        # 元の記憶がまだ存在することを確認
        get_response = user_a_client.get(f"/memory/{memory_id}")
        assert get_response.status_code == 200

    def test_admin_can_delete_others_memory(
        self,
        user_a_client: APIClient,
        admin_client: APIClient,
        project_with_user_a: str
    ):
        """Admin は他人の記憶も削除できる"""
        # User A が記憶を作成
        create_response = user_a_client.post("/store", json={
            "content": "削除テスト（Admin は可能）",
            "type": "work",
            "scope": "project",
            "scope_id": project_with_user_a
        })
        assert create_response.status_code == 200, f"Failed to create memory: {create_response.text}"
        memory_id = create_response.json()["id"]

        # Admin が User A の記憶を削除
        response = admin_client.delete(f"/memory/{memory_id}")
        assert response.status_code == 200
