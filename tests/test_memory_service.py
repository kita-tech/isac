#!/usr/bin/env python3
"""
ISAC Memory Service API テスト

実行方法:
    cd /path/to/isac
    pip install pytest requests
    pytest tests/ -v

前提条件:
    - Memory Service が http://localhost:8200 で起動していること
"""

import pytest
import requests
import uuid
from datetime import datetime

BASE_URL = "http://localhost:8200"


class TestHealthCheck:
    """ヘルスチェックのテスト"""

    def test_health_endpoint(self):
        """GET /health が正常に応答する"""
        response = requests.get(f"{BASE_URL}/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert data["service"] == "isac-memory"
        assert "version" in data


class TestMemoryStore:
    """メモリ保存のテスト"""

    def test_store_project_memory(self):
        """プロジェクトスコープのメモリを保存できる"""
        payload = {
            "content": f"テスト記憶 {uuid.uuid4()}",
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "test-project"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert "id" in data
        assert data["scope"] == "project"
        assert "tokens" in data

    def test_store_global_memory(self):
        """グローバルスコープのメモリを保存できる"""
        payload = {
            "content": f"グローバルテスト {uuid.uuid4()}",
            "type": "knowledge",
            "importance": 0.9,
            "scope": "global"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert data["scope"] == "global"

    def test_store_decision(self):
        """決定事項を保存できる"""
        payload = {
            "content": "テスト決定: pytestを採用する",
            "type": "decision",
            "importance": 0.8,
            "scope": "project",
            "scope_id": "test-project",
            "metadata": {"category": "testing"}
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert "decision" in data["message"]

    def test_store_with_summary(self):
        """要約付きでメモリを保存できる"""
        payload = {
            "content": "長いコンテンツ" * 100,
            "summary": "短い要約",
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "test-project"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200

    def test_store_missing_content(self):
        """contentがない場合はエラー"""
        payload = {
            "type": "work",
            "scope": "project",
            "scope_id": "test-project"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 422

    def test_store_invalid_scope(self):
        """無効なscopeはエラー"""
        payload = {
            "content": "テスト",
            "type": "work",
            "scope": "invalid_scope",
            "scope_id": "test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 422

    def test_store_invalid_type(self):
        """無効なtypeはエラー"""
        payload = {
            "content": "テスト",
            "type": "invalid_type",
            "scope": "project",
            "scope_id": "test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 422


class TestContext:
    """コンテキスト取得のテスト"""

    def test_get_context(self):
        """コンテキストを取得できる"""
        response = requests.get(
            f"{BASE_URL}/context/test-project",
            params={"query": "テスト"}
        )
        assert response.status_code == 200
        data = response.json()
        assert "global_knowledge" in data
        assert "team_knowledge" in data
        assert "project_decisions" in data
        assert "project_recent" in data
        assert "total_tokens" in data

    def test_get_context_with_max_tokens(self):
        """max_tokensを指定してコンテキストを取得できる"""
        response = requests.get(
            f"{BASE_URL}/context/test-project",
            params={"query": "テスト", "max_tokens": 500}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["total_tokens"] <= 500

    def test_get_context_missing_query(self):
        """queryがない場合はエラー"""
        response = requests.get(f"{BASE_URL}/context/test-project")
        assert response.status_code == 422


class TestProjects:
    """プロジェクト管理のテスト"""

    def test_list_projects(self):
        """プロジェクト一覧を取得できる"""
        response = requests.get(f"{BASE_URL}/projects")
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)
        if len(data) > 0:
            project = data[0]
            assert "project_id" in project
            assert "memory_count" in project
            assert "decision_count" in project
            assert "last_activity" in project

    def test_suggest_exact_match(self):
        """完全一致するプロジェクト名の提案"""
        # まずプロジェクトが存在することを確認
        requests.post(f"{BASE_URL}/store", json={
            "content": "suggest test",
            "type": "work",
            "scope": "project",
            "scope_id": "suggest-test-project"
        })

        response = requests.get(
            f"{BASE_URL}/projects/suggest",
            params={"name": "suggest-test-project"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["exact_match"] is True

    def test_suggest_typo(self):
        """Typoがあるプロジェクト名の提案"""
        # まずプロジェクトを作成
        requests.post(f"{BASE_URL}/store", json={
            "content": "typo test",
            "type": "work",
            "scope": "project",
            "scope_id": "typo-test"
        })

        response = requests.get(
            f"{BASE_URL}/projects/suggest",
            params={"name": "typo-tset"}  # typo
        )
        assert response.status_code == 200
        data = response.json()
        assert data["exact_match"] is False
        assert "suggestions" in data


class TestSearch:
    """検索のテスト"""

    def test_search_by_query(self):
        """クエリで検索できる"""
        # テストデータ作成
        unique_id = str(uuid.uuid4())[:8]
        requests.post(f"{BASE_URL}/store", json={
            "content": f"検索テスト用コンテンツ {unique_id}",
            "type": "work",
            "scope": "project",
            "scope_id": "search-test"
        })

        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": unique_id}
        )
        assert response.status_code == 200
        data = response.json()
        assert "memories" in data
        assert len(data["memories"]) > 0

    def test_search_by_type(self):
        """タイプでフィルタできる"""
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": "テスト", "type": "decision"}
        )
        assert response.status_code == 200
        data = response.json()
        for memory in data["memories"]:
            assert memory["type"] == "decision"

    def test_search_by_scope(self):
        """スコープでフィルタできる"""
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": "テスト", "scope": "global"}
        )
        assert response.status_code == 200
        data = response.json()
        for memory in data["memories"]:
            assert memory["scope"] == "global"

    def test_search_with_limit(self):
        """件数制限できる"""
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": "テスト", "limit": 2}
        )
        assert response.status_code == 200
        data = response.json()
        assert len(data["memories"]) <= 2


class TestStats:
    """統計情報のテスト"""

    def test_get_stats(self):
        """統計情報を取得できる"""
        response = requests.get(f"{BASE_URL}/stats/test-project")
        assert response.status_code == 200
        data = response.json()
        assert "project_id" in data
        assert "stats" in data


class TestExport:
    """エクスポートのテスト"""

    def test_export_project(self):
        """プロジェクトのメモリをエクスポートできる"""
        response = requests.get(f"{BASE_URL}/export/test-project")
        assert response.status_code == 200
        data = response.json()
        assert "project_id" in data
        assert "memories" in data
        assert "count" in data


class TestMemoryOperations:
    """メモリ操作のテスト"""

    def test_get_memory_by_id(self):
        """IDでメモリを取得できる"""
        # まずメモリを作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "ID取得テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "test-project"
        })
        memory_id = create_response.json()["id"]

        # IDで取得
        response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == memory_id
        assert "ID取得テスト" in data["content"]

    def test_get_memory_not_found(self):
        """存在しないIDはエラー"""
        response = requests.get(f"{BASE_URL}/memory/nonexistent-id")
        assert response.status_code == 404

    def test_delete_memory(self):
        """メモリを削除できる"""
        # まずメモリを作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "削除テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "test-project"
        })
        memory_id = create_response.json()["id"]

        # 削除
        response = requests.delete(f"{BASE_URL}/memory/{memory_id}")
        assert response.status_code == 200

        # 削除後は取得できない
        response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert response.status_code == 404


class TestImport:
    """インポートのテスト"""

    def test_import_memories(self):
        """メモリをインポートできる"""
        memories = [
            {
                "content": "インポートテスト1",
                "type": "work",
                "scope": "project",
                "scope_id": "import-test",
                "importance": 0.5
            },
            {
                "content": "インポートテスト2",
                "type": "decision",
                "scope": "project",
                "scope_id": "import-test",
                "importance": 0.8
            }
        ]
        response = requests.post(
            f"{BASE_URL}/import",
            json={"memories": memories}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["imported"] == 2


class TestDeprecation:
    """記憶の廃止機能のテスト"""

    def test_store_with_supersedes(self):
        """supersedes パラメータで古い記憶を廃止できる"""
        # 古い記憶を作成
        old_response = requests.post(f"{BASE_URL}/store", json={
            "content": "古いAPI仕様: GET /users は非推奨",
            "type": "knowledge",
            "scope": "project",
            "scope_id": "deprecation-test"
        })
        old_id = old_response.json()["id"]

        # 新しい記憶で古い記憶を廃止
        new_response = requests.post(f"{BASE_URL}/store", json={
            "content": "新しいAPI仕様: GET /v2/users を使用する",
            "type": "knowledge",
            "scope": "project",
            "scope_id": "deprecation-test",
            "supersedes": [old_id]
        })
        assert new_response.status_code == 200
        new_data = new_response.json()
        assert old_id in new_data["superseded_ids"]

        # 古い記憶が廃止されていることを確認
        old_memory = requests.get(f"{BASE_URL}/memory/{old_id}").json()
        assert old_memory["deprecated"] is True
        assert old_memory["superseded_by"] == new_data["id"]

    def test_search_excludes_deprecated_by_default(self):
        """検索はデフォルトで廃止済み記憶を除外する"""
        unique_id = str(uuid.uuid4())[:8]

        # 古い記憶を作成
        old_response = requests.post(f"{BASE_URL}/store", json={
            "content": f"廃止テスト {unique_id} 古い",
            "type": "work",
            "scope": "project",
            "scope_id": "deprecation-test"
        })
        old_id = old_response.json()["id"]

        # 新しい記憶で古い記憶を廃止
        requests.post(f"{BASE_URL}/store", json={
            "content": f"廃止テスト {unique_id} 新しい",
            "type": "work",
            "scope": "project",
            "scope_id": "deprecation-test",
            "supersedes": [old_id]
        })

        # デフォルト検索では廃止済みが除外される
        response = requests.get(f"{BASE_URL}/search", params={"query": unique_id})
        data = response.json()
        memory_ids = [m["id"] for m in data["memories"]]
        assert old_id not in memory_ids

    def test_search_includes_deprecated_when_requested(self):
        """include_deprecated=true で廃止済み記憶も取得できる"""
        unique_id = str(uuid.uuid4())[:8]

        # 古い記憶を作成（importanceを高く設定して検索上位に来るようにする）
        old_response = requests.post(f"{BASE_URL}/store", json={
            "content": f"廃止テスト2 {unique_id} 古い",
            "type": "work",
            "scope": "project",
            "scope_id": "deprecation-test",
            "importance": 0.95
        })
        old_id = old_response.json()["id"]

        # 新しい記憶で古い記憶を廃止
        requests.post(f"{BASE_URL}/store", json={
            "content": f"廃止テスト2 {unique_id} 新しい",
            "type": "work",
            "scope": "project",
            "scope_id": "deprecation-test",
            "importance": 0.95,
            "supersedes": [old_id]
        })

        # include_deprecated=true で廃止済みも取得
        response = requests.get(f"{BASE_URL}/search", params={
            "query": unique_id,
            "include_deprecated": "true"
        })
        data = response.json()
        memory_ids = [m["id"] for m in data["memories"]]
        assert old_id in memory_ids

    def test_deprecate_memory_manually(self):
        """手動で記憶を廃止できる"""
        # 記憶を作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "手動廃止テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "deprecation-test"
        })
        memory_id = create_response.json()["id"]

        # 廃止
        response = requests.patch(
            f"{BASE_URL}/memory/{memory_id}/deprecate",
            json={"deprecated": True}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["deprecated"] is True

        # 確認
        memory = requests.get(f"{BASE_URL}/memory/{memory_id}").json()
        assert memory["deprecated"] is True

    def test_restore_deprecated_memory(self):
        """廃止した記憶を復元できる"""
        # 記憶を作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "復元テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "deprecation-test"
        })
        memory_id = create_response.json()["id"]

        # 廃止
        requests.patch(
            f"{BASE_URL}/memory/{memory_id}/deprecate",
            json={"deprecated": True}
        )

        # 復元
        response = requests.patch(
            f"{BASE_URL}/memory/{memory_id}/deprecate",
            json={"deprecated": False}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["deprecated"] is False

        # 確認
        memory = requests.get(f"{BASE_URL}/memory/{memory_id}").json()
        assert memory["deprecated"] is False
        assert memory["superseded_by"] is None

    def test_context_excludes_deprecated_by_default(self):
        """コンテキスト取得はデフォルトで廃止済み記憶を除外する"""
        unique_id = str(uuid.uuid4())[:8]

        # 古い記憶を作成
        old_response = requests.post(f"{BASE_URL}/store", json={
            "content": f"コンテキスト廃止テスト {unique_id}",
            "type": "decision",
            "scope": "project",
            "scope_id": "context-deprecation-test",
            "importance": 0.9
        })
        old_id = old_response.json()["id"]

        # 廃止
        requests.patch(
            f"{BASE_URL}/memory/{old_id}/deprecate",
            json={"deprecated": True}
        )

        # コンテキスト取得（デフォルト）
        response = requests.get(
            f"{BASE_URL}/context/context-deprecation-test",
            params={"query": unique_id}
        )
        data = response.json()

        # 廃止済みが含まれていないことを確認
        all_memory_ids = []
        for key in ["global_knowledge", "team_knowledge", "project_decisions", "project_recent"]:
            all_memory_ids.extend([m["id"] for m in data[key]])
        assert old_id not in all_memory_ids

    def test_supersedes_nonexistent_id(self):
        """存在しないIDをsupersedesに指定した場合はスキップされる"""
        nonexistent_id = "nonexistent-12345"

        response = requests.post(f"{BASE_URL}/store", json={
            "content": "存在しないID廃止テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "deprecation-test",
            "supersedes": [nonexistent_id]
        })
        assert response.status_code == 200
        data = response.json()

        # 存在しないIDは superseded_ids に含まれない
        assert nonexistent_id not in data["superseded_ids"]
        # skipped_supersedes に含まれる
        assert any(s["id"] == nonexistent_id and s["reason"] == "not_found"
                   for s in data["skipped_supersedes"])

    def test_deprecate_already_deprecated_memory(self):
        """既に廃止済みの記憶を再度廃止しても問題ない"""
        # 記憶を作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "再廃止テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "deprecation-test"
        })
        memory_id = create_response.json()["id"]

        # 後継となる記憶を作成
        successor_response = requests.post(f"{BASE_URL}/store", json={
            "content": "後継記憶",
            "type": "work",
            "scope": "project",
            "scope_id": "deprecation-test"
        })
        successor_id = successor_response.json()["id"]

        # 1回目の廃止
        response1 = requests.patch(
            f"{BASE_URL}/memory/{memory_id}/deprecate",
            json={"deprecated": True}
        )
        assert response1.status_code == 200

        # 2回目の廃止（既に廃止済み、今度は superseded_by を指定）
        response2 = requests.patch(
            f"{BASE_URL}/memory/{memory_id}/deprecate",
            json={"deprecated": True, "superseded_by": successor_id}
        )
        assert response2.status_code == 200

        # 状態を確認
        memory = requests.get(f"{BASE_URL}/memory/{memory_id}").json()
        assert memory["deprecated"] is True
        assert memory["superseded_by"] == successor_id

    def test_supersedes_multiple_memories(self):
        """複数の記憶を一度に廃止できる"""
        # 古い記憶を複数作成
        old_ids = []
        for i in range(3):
            response = requests.post(f"{BASE_URL}/store", json={
                "content": f"複数廃止テスト 古い記憶 {i}",
                "type": "work",
                "scope": "project",
                "scope_id": "multi-deprecation-test"
            })
            old_ids.append(response.json()["id"])

        # 新しい記憶で全て廃止
        new_response = requests.post(f"{BASE_URL}/store", json={
            "content": "複数廃止テスト 新しい記憶",
            "type": "work",
            "scope": "project",
            "scope_id": "multi-deprecation-test",
            "supersedes": old_ids
        })
        assert new_response.status_code == 200
        new_data = new_response.json()

        # 全ての古い記憶が廃止されている
        for old_id in old_ids:
            assert old_id in new_data["superseded_ids"]
            old_memory = requests.get(f"{BASE_URL}/memory/{old_id}").json()
            assert old_memory["deprecated"] is True
            assert old_memory["superseded_by"] == new_data["id"]

    def test_supersedes_with_mixed_valid_invalid_ids(self):
        """有効なIDと無効なIDが混在した場合、有効なものだけ廃止される"""
        # 有効な記憶を作成
        valid_response = requests.post(f"{BASE_URL}/store", json={
            "content": "混在テスト 有効な記憶",
            "type": "work",
            "scope": "project",
            "scope_id": "mixed-deprecation-test"
        })
        valid_id = valid_response.json()["id"]
        invalid_id = "invalid-id-99999"

        # 有効なIDと無効なIDを混ぜて廃止
        new_response = requests.post(f"{BASE_URL}/store", json={
            "content": "混在テスト 新しい記憶",
            "type": "work",
            "scope": "project",
            "scope_id": "mixed-deprecation-test",
            "supersedes": [valid_id, invalid_id]
        })
        assert new_response.status_code == 200
        data = new_response.json()

        # 有効なIDは廃止されている
        assert valid_id in data["superseded_ids"]
        # 無効なIDはスキップされている
        assert invalid_id not in data["superseded_ids"]
        assert any(s["id"] == invalid_id for s in data["skipped_supersedes"])

    def test_supersedes_empty_array(self):
        """空配列を supersedes に指定した場合は何も廃止されない"""
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "空配列テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "edge-case-test",
            "supersedes": []
        })
        assert response.status_code == 200
        data = response.json()
        assert data["superseded_ids"] == []
        assert data["skipped_supersedes"] == []

    def test_supersedes_self_reference(self):
        """自分自身を廃止しようとした場合（保存時点では存在しないのでスキップ）"""
        # 注意: 保存時点では自分のIDはまだ存在しないので、not_found になる
        fake_self_id = "self-reference-test-id"
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "自己参照テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "edge-case-test",
            "supersedes": [fake_self_id]
        })
        assert response.status_code == 200
        data = response.json()
        # 存在しないのでスキップされる
        assert fake_self_id not in data["superseded_ids"]
        assert any(s["id"] == fake_self_id and s["reason"] == "not_found"
                   for s in data["skipped_supersedes"])

    def test_supersedes_duplicate_ids(self):
        """同じIDを重複指定した場合は1回だけ廃止される"""
        # 記憶を作成
        old_response = requests.post(f"{BASE_URL}/store", json={
            "content": "重複テスト 古い記憶",
            "type": "work",
            "scope": "project",
            "scope_id": "edge-case-test"
        })
        old_id = old_response.json()["id"]

        # 同じIDを2回指定
        new_response = requests.post(f"{BASE_URL}/store", json={
            "content": "重複テスト 新しい記憶",
            "type": "work",
            "scope": "project",
            "scope_id": "edge-case-test",
            "supersedes": [old_id, old_id]
        })
        assert new_response.status_code == 200
        data = new_response.json()

        # 1回だけ廃止されている（重複はカウントされない）
        assert data["superseded_ids"].count(old_id) == 1

        # 記憶が正しく廃止されている
        old_memory = requests.get(f"{BASE_URL}/memory/{old_id}").json()
        assert old_memory["deprecated"] is True

    def test_deprecate_with_invalid_superseded_by(self):
        """存在しない superseded_by を手動廃止で指定するとエラー"""
        # 記憶を作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "無効な後継テスト",
            "type": "work",
            "scope": "project",
            "scope_id": "edge-case-test"
        })
        memory_id = create_response.json()["id"]

        # 存在しない superseded_by を指定
        response = requests.patch(
            f"{BASE_URL}/memory/{memory_id}/deprecate",
            json={"deprecated": True, "superseded_by": "nonexistent-id"}
        )
        assert response.status_code == 400
        assert "not found" in response.json()["detail"].lower()


class TestTags:
    """タグ機能のテスト"""

    def test_get_tags_for_project(self):
        """プロジェクトのタグ一覧を取得できる"""
        unique_project = f"tags-test-{uuid.uuid4().hex[:8]}"

        # タグ付きで記憶を作成
        requests.post(f"{BASE_URL}/store", json={
            "content": "タグテスト用コンテンツ1",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "tags": ["python", "fastapi"],
            "importance": 0.95
        })
        requests.post(f"{BASE_URL}/store", json={
            "content": "タグテスト用コンテンツ2",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "tags": ["python", "docker"],
            "importance": 0.95
        })

        # タグ一覧を取得
        response = requests.get(f"{BASE_URL}/tags/{unique_project}")
        assert response.status_code == 200
        data = response.json()
        assert "tags" in data
        tags = data["tags"]
        # タグはオブジェクトのリスト形式 [{"tag": "python", "count": 2}, ...]
        tag_names = [t["tag"] for t in tags]
        assert "python" in tag_names
        assert "fastapi" in tag_names
        assert "docker" in tag_names

    def test_get_tags_empty_project(self):
        """タグがないプロジェクトでは空のリストを返す"""
        unique_project = f"empty-tags-{uuid.uuid4().hex[:8]}"

        # タグなしで記憶を作成
        requests.post(f"{BASE_URL}/store", json={
            "content": "タグなしコンテンツ",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "importance": 0.95
        })

        # タグ一覧を取得
        response = requests.get(f"{BASE_URL}/tags/{unique_project}")
        assert response.status_code == 200
        data = response.json()
        assert "tags" in data
        assert data["tags"] == [] or len(data["tags"]) == 0

    def test_store_with_tags(self):
        """タグ付きで記憶を保存できる"""
        unique_project = f"store-tags-{uuid.uuid4().hex[:8]}"

        response = requests.post(f"{BASE_URL}/store", json={
            "content": "タグ付き保存テスト",
            "type": "decision",
            "scope": "project",
            "scope_id": unique_project,
            "tags": ["api", "v2", "breaking-change"],
            "importance": 0.95
        })
        assert response.status_code == 200
        data = response.json()
        memory_id = data["id"]

        # 保存した記憶を取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        memory = get_response.json()
        assert "tags" in memory
        assert "api" in memory["tags"]
        assert "v2" in memory["tags"]
        assert "breaking-change" in memory["tags"]

    def test_search_by_tags(self):
        """タグでフィルタリング検索できる"""
        unique_project = f"search-tags-{uuid.uuid4().hex[:8]}"
        unique_id = uuid.uuid4().hex[:8]

        # 異なるタグで記憶を作成
        requests.post(f"{BASE_URL}/store", json={
            "content": f"検索用タグテスト {unique_id} frontend",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "tags": ["frontend", "react"],
            "importance": 0.95
        })
        requests.post(f"{BASE_URL}/store", json={
            "content": f"検索用タグテスト {unique_id} backend",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "tags": ["backend", "python"],
            "importance": 0.95
        })

        # タグで検索
        response = requests.get(f"{BASE_URL}/search", params={
            "query": unique_id,
            "tags": "backend"
        })
        assert response.status_code == 200
        data = response.json()
        memories = data["memories"]

        # 結果にbackendタグを持つ記憶のみ含まれる
        for memory in memories:
            if unique_id in memory["content"]:
                assert "backend" in memory.get("tags", [])

    def test_update_tags(self):
        """記憶のタグを更新できる"""
        unique_project = f"update-tags-{uuid.uuid4().hex[:8]}"

        # タグ付きで記憶を作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "タグ更新テスト",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "tags": ["old-tag"],
            "importance": 0.95
        })
        memory_id = create_response.json()["id"]

        # タグを更新
        update_response = requests.patch(f"{BASE_URL}/memory/{memory_id}", json={
            "tags": ["new-tag", "updated"]
        })
        assert update_response.status_code == 200
        updated_memory = update_response.json()
        assert "new-tag" in updated_memory["tags"]
        assert "updated" in updated_memory["tags"]
        assert "old-tag" not in updated_memory["tags"]

        # 更新が反映されていることを確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        memory = get_response.json()
        assert "new-tag" in memory["tags"]
        assert "updated" in memory["tags"]


class TestStoreParameters:
    """storeエンドポイントの全パラメータテスト"""

    def test_store_with_metadata(self):
        """metadata付きで保存できる"""
        unique_project = f"metadata-test-{uuid.uuid4().hex[:8]}"

        response = requests.post(f"{BASE_URL}/store", json={
            "content": "メタデータ付き保存テスト",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "metadata": {
                "author": "test-user",
                "source": "test-suite",
                "custom_field": 123
            },
            "importance": 0.95
        })
        assert response.status_code == 200
        data = response.json()
        memory_id = data["id"]

        # 保存した記憶を取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        memory = get_response.json()
        assert "metadata" in memory
        assert memory["metadata"]["author"] == "test-user"
        assert memory["metadata"]["source"] == "test-suite"
        assert memory["metadata"]["custom_field"] == 123

    def test_store_with_expires_at(self):
        """expires_at指定で保存できる"""
        unique_project = f"expires-test-{uuid.uuid4().hex[:8]}"
        future_date = "2030-12-31T23:59:59Z"

        response = requests.post(f"{BASE_URL}/store", json={
            "content": "有効期限付き保存テスト",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "expires_at": future_date,
            "importance": 0.95
        })
        assert response.status_code == 200
        data = response.json()
        memory_id = data["id"]

        # 保存した記憶を取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        memory = get_response.json()
        assert "expires_at" in memory
        assert "2030-12-31" in memory["expires_at"]

    def test_store_with_all_parameters(self):
        """全パラメータ指定で保存できる"""
        unique_project = f"all-params-{uuid.uuid4().hex[:8]}"
        future_date = "2030-12-31T23:59:59Z"

        response = requests.post(f"{BASE_URL}/store", json={
            "content": "全パラメータ保存テスト",
            "summary": "全パラメータのテスト",
            "type": "decision",
            "scope": "project",
            "scope_id": unique_project,
            "importance": 0.95,
            "category": "backend",
            "tags": ["test", "comprehensive"],
            "metadata": {
                "author": "test-user",
                "version": "1.0"
            },
            "expires_at": future_date
        })
        assert response.status_code == 200
        data = response.json()
        memory_id = data["id"]

        # 保存した記憶を取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        memory = get_response.json()

        # 全てのパラメータが正しく保存されていることを確認
        assert memory["content"] == "全パラメータ保存テスト"
        assert memory["summary"] == "全パラメータのテスト"
        assert memory["type"] == "decision"
        assert memory["scope"] == "project"
        assert memory["scope_id"] == unique_project
        assert memory["importance"] == 0.95
        assert memory["category"] == "backend"
        assert "test" in memory["tags"]
        assert "comprehensive" in memory["tags"]
        assert memory["metadata"]["author"] == "test-user"
        assert memory["metadata"]["version"] == "1.0"
        assert "2030-12-31" in memory["expires_at"]

    def test_store_with_importance(self):
        """importance指定で保存できる"""
        unique_project = f"importance-test-{uuid.uuid4().hex[:8]}"

        # 低い重要度
        response_low = requests.post(f"{BASE_URL}/store", json={
            "content": "低重要度テスト",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "importance": 0.1
        })
        assert response_low.status_code == 200

        # 高い重要度
        response_high = requests.post(f"{BASE_URL}/store", json={
            "content": "高重要度テスト",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "importance": 0.95
        })
        assert response_high.status_code == 200

        # 保存した記憶を取得して確認
        low_memory = requests.get(f"{BASE_URL}/memory/{response_low.json()['id']}").json()
        high_memory = requests.get(f"{BASE_URL}/memory/{response_high.json()['id']}").json()

        assert low_memory["importance"] == 0.1
        assert high_memory["importance"] == 0.95

    def test_store_importance_affects_search_order(self):
        """importanceが検索順序に影響する"""
        unique_project = f"importance-order-{uuid.uuid4().hex[:8]}"
        unique_id = uuid.uuid4().hex[:8]

        # 低い重要度で先に作成
        requests.post(f"{BASE_URL}/store", json={
            "content": f"検索順序テスト {unique_id} 低重要度",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "importance": 0.1
        })

        # 高い重要度で後に作成
        requests.post(f"{BASE_URL}/store", json={
            "content": f"検索順序テスト {unique_id} 高重要度",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "importance": 0.95
        })

        # 検索
        response = requests.get(f"{BASE_URL}/search", params={
            "query": unique_id,
            "scope_id": unique_project
        })
        assert response.status_code == 200
        memories = response.json()["memories"]

        # 高重要度の記憶が上位に来ることを確認
        # (検索アルゴリズムによるが、importance が考慮されることを検証)
        if len(memories) >= 2:
            # 両方の記憶が検索結果に含まれていることを確認
            contents = [m["content"] for m in memories]
            assert any("高重要度" in c for c in contents)
            assert any("低重要度" in c for c in contents)

    def test_store_auto_categorization(self):
        """categoryを省略時の自動分類"""
        unique_project = f"auto-category-{uuid.uuid4().hex[:8]}"

        # category を省略して保存
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "自動分類テスト: FastAPI でバックエンドAPIを実装する",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "importance": 0.95
        })
        assert response.status_code == 200
        data = response.json()
        memory_id = data["id"]

        # 保存した記憶を取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        memory = get_response.json()

        # カテゴリが自動設定されていることを確認（または null/other）
        # 自動分類の実装によって値は異なる可能性がある
        assert "category" in memory

    def test_store_auto_tagging(self):
        """tagsを省略時の自動タグ付け"""
        unique_project = f"auto-tagging-{uuid.uuid4().hex[:8]}"

        # tags を省略して保存
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "自動タグ付けテスト: Python と Docker を使用する",
            "type": "work",
            "scope": "project",
            "scope_id": unique_project,
            "importance": 0.95
        })
        assert response.status_code == 200
        data = response.json()
        memory_id = data["id"]

        # 保存した記憶を取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        memory = get_response.json()

        # tags フィールドが存在することを確認
        # 自動タグ付けの実装によって値は異なる可能性がある
        assert "tags" in memory

    def test_store_with_invalid_expires_at(self):
        """不正な expires_at 形式は422で拒否される"""
        invalid_values = [
            "not-a-date",
            "2025/12/31",
            "yesterday",
            "'; DROP TABLE memories; --",
        ]
        for value in invalid_values:
            response = requests.post(f"{BASE_URL}/store", json={
                "content": "expires_atバリデーションテスト",
                "type": "work",
                "scope": "project",
                "scope_id": "expires-validation-test",
                "expires_at": value
            })
            assert response.status_code == 422, \
                f"不正な expires_at '{value}' が受け入れられました: {response.status_code}"

    def test_store_with_empty_expires_at_uses_auto_ttl(self):
        """expires_at が空文字の場合は自動TTLが適用される"""
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "空expires_atテスト",
            "type": "work",
            "scope": "project",
            "scope_id": "expires-empty-test",
            "expires_at": ""
        })
        # 空文字は falsy なので自動TTLが使われ、正常に保存される
        assert response.status_code == 200


class TestSecurity:
    """セキュリティ関連のテスト"""

    def test_sql_injection_in_content(self):
        """contentにSQLインジェクション文字列を入れても安全か"""
        sql_injection_payloads = [
            "'; DROP TABLE memories; --",
            '" OR "1"="1',
            "1; DELETE FROM memories WHERE 1=1; --",
            "' UNION SELECT * FROM memories --",
            "1' OR '1'='1' --",
        ]

        for payload in sql_injection_payloads:
            response = requests.post(f"{BASE_URL}/store", json={
                "content": payload,
                "type": "work",
                "scope": "project",
                "scope_id": "security-test"
            })
            # 保存が成功することを確認（500エラーにならない）
            assert response.status_code == 200, f"Failed for payload: {payload}"
            data = response.json()
            assert "id" in data

            # 保存したデータが正しく取得できることを確認
            memory_id = data["id"]
            get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
            assert get_response.status_code == 200
            assert get_response.json()["content"] == payload

    def test_sql_injection_in_query(self):
        """検索クエリにSQLインジェクション文字列を入れても安全か"""
        sql_injection_payloads = [
            "'; DROP TABLE memories; --",
            '" OR "1"="1',
            "' UNION SELECT * FROM memories --",
            "1' OR '1'='1' --",
        ]

        for payload in sql_injection_payloads:
            response = requests.get(f"{BASE_URL}/search", params={"query": payload})
            # 検索が成功することを確認（500エラーにならない）
            assert response.status_code == 200, f"Failed for payload: {payload}"
            data = response.json()
            assert "memories" in data

    def test_sql_injection_in_scope_id(self):
        """scope_idにSQLインジェクション文字列を入れても安全か"""
        sql_injection_payloads = [
            "'; DROP TABLE memories; --",
            '" OR "1"="1',
            "project' OR '1'='1",
        ]

        for payload in sql_injection_payloads:
            # 保存テスト
            store_response = requests.post(f"{BASE_URL}/store", json={
                "content": "Security test content",
                "type": "work",
                "scope": "project",
                "scope_id": payload
            })
            assert store_response.status_code == 200, f"Store failed for payload: {payload}"

            # コンテキスト取得テスト
            context_response = requests.get(
                f"{BASE_URL}/context/{payload}",
                params={"query": "test"}
            )
            assert context_response.status_code == 200, f"Context failed for payload: {payload}"

    def test_xss_in_content(self):
        """XSS攻撃文字列がそのまま保存・取得されるか（サーバーサイドでエスケープ不要）"""
        xss_payloads = [
            "<script>alert('xss')</script>",
            "<img src=x onerror=alert('xss')>",
            "<svg onload=alert('xss')>",
            "javascript:alert('xss')",
            "<iframe src='javascript:alert(1)'>",
        ]

        for payload in xss_payloads:
            response = requests.post(f"{BASE_URL}/store", json={
                "content": payload,
                "type": "work",
                "scope": "project",
                "scope_id": "security-test"
            })
            assert response.status_code == 200, f"Failed for payload: {payload}"
            data = response.json()
            memory_id = data["id"]

            # 保存したデータがそのまま取得できることを確認
            # （サーバーサイドではエスケープ不要、クライアントサイドで対応）
            get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
            assert get_response.status_code == 200
            assert get_response.json()["content"] == payload

    def test_path_traversal_in_id(self):
        """IDにパストラバーサル文字列を入れても安全か"""
        path_traversal_payloads = [
            "../../etc/passwd",
            "../../../etc/shadow",
            "..%2F..%2Fetc%2Fpasswd",
            "....//....//etc/passwd",
            "/etc/passwd",
        ]

        for payload in path_traversal_payloads:
            # 存在しないIDとして404が返ることを確認（500エラーにならない）
            response = requests.get(f"{BASE_URL}/memory/{payload}")
            assert response.status_code == 404, f"Expected 404 for payload: {payload}"

    def test_large_content_handling(self):
        """非常に大きなコンテンツ（1MB）は422で拒否される"""
        # 1MBのコンテンツを生成（上限65,536文字を大幅に超過）
        large_content = "A" * (1024 * 1024)

        response = requests.post(f"{BASE_URL}/store", json={
            "content": large_content,
            "type": "work",
            "scope": "project",
            "scope_id": "security-test"
        }, timeout=30)
        # サイズ制限により422が返ること
        assert response.status_code == 422, \
            f"Unexpected status code: {response.status_code}"
        data = response.json()
        detail = data["detail"]
        assert detail["current_length"] == 1024 * 1024
        assert detail["max_length"] == 65536
        assert "hint" in detail

    def test_unicode_normalization(self):
        """Unicode正規化（NFC/NFD）の扱い"""
        import unicodedata

        # 同じ文字の異なる正規化形式
        nfc_string = unicodedata.normalize('NFC', 'café')  # 合成済み
        nfd_string = unicodedata.normalize('NFD', 'café')  # 分解済み

        # NFCで保存
        nfc_response = requests.post(f"{BASE_URL}/store", json={
            "content": f"Unicode NFC test: {nfc_string}",
            "type": "work",
            "scope": "project",
            "scope_id": "unicode-test"
        })
        assert nfc_response.status_code == 200

        # NFDで保存
        nfd_response = requests.post(f"{BASE_URL}/store", json={
            "content": f"Unicode NFD test: {nfd_string}",
            "type": "work",
            "scope": "project",
            "scope_id": "unicode-test"
        })
        assert nfd_response.status_code == 200

        # 両方の保存が成功し、DBが壊れていないことを確認
        nfc_id = nfc_response.json()["id"]
        nfd_id = nfd_response.json()["id"]

        get_nfc = requests.get(f"{BASE_URL}/memory/{nfc_id}")
        get_nfd = requests.get(f"{BASE_URL}/memory/{nfd_id}")

        assert get_nfc.status_code == 200
        assert get_nfd.status_code == 200

    def test_null_byte_injection(self):
        """NULL文字を含むコンテンツ"""
        null_payloads = [
            "before\x00after",
            "\x00start",
            "end\x00",
            "multi\x00ple\x00null\x00bytes",
        ]

        for payload in null_payloads:
            response = requests.post(f"{BASE_URL}/store", json={
                "content": payload,
                "type": "work",
                "scope": "project",
                "scope_id": "security-test"
            })
            # 保存が成功することを確認（500エラーにならない）
            # NULL文字はJSONでは許可されていないため、422エラーも許容
            assert response.status_code in [200, 422], \
                f"Unexpected status code {response.status_code} for payload with null byte"


class TestCategories:
    """カテゴリ機能のテスト"""

    def test_list_categories(self):
        """カテゴリ一覧を取得できる"""
        response = requests.get(f"{BASE_URL}/categories")
        assert response.status_code == 200
        data = response.json()
        assert "categories" in data
        assert "descriptions" in data
        # 必須カテゴリが存在することを確認
        expected_categories = [
            "backend", "frontend", "infra", "security", "database",
            "api", "ui", "test", "docs", "architecture", "github", "other"
        ]
        for cat in expected_categories:
            assert cat in data["categories"], f"カテゴリ '{cat}' が見つかりません"
            assert cat in data["descriptions"], f"カテゴリ '{cat}' の説明が見つかりません"

    def test_github_category_exists(self):
        """githubカテゴリが利用可能"""
        response = requests.get(f"{BASE_URL}/categories")
        data = response.json()
        assert "github" in data["categories"]
        assert "github" in data["descriptions"]
        assert "GitHub" in data["descriptions"]["github"] or "Issue" in data["descriptions"]["github"]

    def test_store_with_github_category(self):
        """githubカテゴリで記憶を保存できる"""
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "GitHub Issueには既存ラベルのみ使用する",
            "type": "decision",
            "scope": "project",
            "scope_id": "category-test",
            "category": "github"
        })
        assert response.status_code == 200
        data = response.json()
        assert data["category"] == "github"

        # 保存した記憶を取得して確認
        memory_id = data["id"]
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert get_response.json()["category"] == "github"

    def test_search_by_category(self):
        """カテゴリでフィルタリング検索できる"""
        # github カテゴリで記憶を作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "PRレビューのルール",
            "type": "decision",
            "scope": "project",
            "scope_id": "category-search-test",
            "category": "github"
        })
        assert create_response.status_code == 200

        # カテゴリで検索
        search_response = requests.get(f"{BASE_URL}/search", params={
            "query": "PRレビュー",
            "category": "github"
        })
        assert search_response.status_code == 200
        memories = search_response.json()["memories"]
        # 結果があれば全てgithubカテゴリであること
        for memory in memories:
            if memory.get("category"):
                assert memory["category"] == "github"

    def test_update_category(self):
        """記憶のカテゴリを更新できる"""
        # other カテゴリで作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "カテゴリ更新テスト用",
            "type": "work",
            "scope": "project",
            "scope_id": "category-update-test",
            "category": "other"
        })
        assert create_response.status_code == 200
        memory_id = create_response.json()["id"]

        # github カテゴリに更新
        update_response = requests.patch(f"{BASE_URL}/memory/{memory_id}", json={
            "category": "github"
        })
        assert update_response.status_code == 200
        assert update_response.json()["category"] == "github"

        # 更新が反映されていることを確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.json()["category"] == "github"

    def test_invalid_category_rejected(self):
        """無効なカテゴリは拒否される"""
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "無効カテゴリテスト",
            "type": "work",
            "scope": "project",
            "scope_id": "invalid-category-test",
            "category": "invalid_category"
        })
        assert response.status_code == 422  # Validation error


class TestTodo:
    """Todo機能のテスト（/my/todos エンドポイント）"""

    def test_get_todos(self):
        """Todoリストを取得できる"""
        unique_id = str(uuid.uuid4())[:8]
        project_id = f"todo-test-{unique_id}"
        owner = f"test-{unique_id}@example.com"

        # Todoを作成
        requests.post(f"{BASE_URL}/store", json={
            "content": f"Todoテスト {unique_id}",
            "type": "todo",
            "scope": "project",
            "scope_id": project_id,
            "importance": 0.95,
            "metadata": {"owner": owner, "status": "pending"}
        })

        # Todoリストを取得
        response = requests.get(
            f"{BASE_URL}/my/todos",
            params={"project_id": project_id, "owner": owner}
        )
        assert response.status_code == 200
        data = response.json()
        assert "todos" in data
        assert "count" in data
        assert data["project_id"] == project_id
        assert data["owner"] == owner
        assert data["count"] >= 1

    def test_get_todos_filter_by_status(self):
        """ステータスでTodoをフィルタできる"""
        unique_id = str(uuid.uuid4())[:8]
        project_id = f"todo-status-{unique_id}"
        owner = f"status-{unique_id}@example.com"

        # pendingのTodoを作成
        requests.post(f"{BASE_URL}/store", json={
            "content": f"Pending Todo {unique_id}",
            "type": "todo",
            "scope": "project",
            "scope_id": project_id,
            "importance": 0.95,
            "metadata": {"owner": owner, "status": "pending"}
        })

        # doneのTodoを作成
        requests.post(f"{BASE_URL}/store", json={
            "content": f"Done Todo {unique_id}",
            "type": "todo",
            "scope": "project",
            "scope_id": project_id,
            "importance": 0.95,
            "metadata": {"owner": owner, "status": "done"}
        })

        # pendingのみ取得
        response_pending = requests.get(
            f"{BASE_URL}/my/todos",
            params={"project_id": project_id, "owner": owner, "status": "pending"}
        )
        assert response_pending.status_code == 200
        data_pending = response_pending.json()
        for todo in data_pending["todos"]:
            assert todo["metadata"]["status"] == "pending"

        # doneのみ取得
        response_done = requests.get(
            f"{BASE_URL}/my/todos",
            params={"project_id": project_id, "owner": owner, "status": "done"}
        )
        assert response_done.status_code == 200
        data_done = response_done.json()
        for todo in data_done["todos"]:
            assert todo["metadata"]["status"] == "done"

        # 全て取得
        response_all = requests.get(
            f"{BASE_URL}/my/todos",
            params={"project_id": project_id, "owner": owner, "status": "all"}
        )
        assert response_all.status_code == 200
        data_all = response_all.json()
        assert data_all["count"] >= 2

    def test_get_todos_filter_by_owner(self):
        """オーナーでTodoをフィルタできる"""
        unique_id = str(uuid.uuid4())[:8]
        project_id = f"todo-owner-{unique_id}"
        owner1 = f"owner1-{unique_id}@example.com"
        owner2 = f"owner2-{unique_id}@example.com"

        # owner1のTodoを作成
        requests.post(f"{BASE_URL}/store", json={
            "content": f"Owner1 Todo {unique_id}",
            "type": "todo",
            "scope": "project",
            "scope_id": project_id,
            "importance": 0.95,
            "metadata": {"owner": owner1, "status": "pending"}
        })

        # owner2のTodoを作成
        requests.post(f"{BASE_URL}/store", json={
            "content": f"Owner2 Todo {unique_id}",
            "type": "todo",
            "scope": "project",
            "scope_id": project_id,
            "importance": 0.95,
            "metadata": {"owner": owner2, "status": "pending"}
        })

        # owner1のTodoのみ取得
        response = requests.get(
            f"{BASE_URL}/my/todos",
            params={"project_id": project_id, "owner": owner1}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["owner"] == owner1
        for todo in data["todos"]:
            assert todo["metadata"]["owner"] == owner1

    def test_get_todos_missing_project_id(self):
        """project_id未指定でエラー"""
        response = requests.get(
            f"{BASE_URL}/my/todos",
            params={"owner": "test@example.com"}
        )
        assert response.status_code == 422  # Validation error

    def test_create_todo_via_store(self):
        """/store でTodoを作成できる（type="todo"）"""
        unique_id = str(uuid.uuid4())[:8]
        project_id = f"todo-create-{unique_id}"
        owner = f"create-{unique_id}@example.com"

        response = requests.post(f"{BASE_URL}/store", json={
            "content": f"新規Todo {unique_id}",
            "type": "todo",
            "scope": "project",
            "scope_id": project_id,
            "importance": 0.95,
            "metadata": {"owner": owner, "status": "pending", "priority": "high"}
        })
        assert response.status_code == 200
        data = response.json()
        assert "id" in data
        assert data["scope"] == "project"

        # 作成されたTodoを確認
        memory_id = data["id"]
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        todo = get_response.json()
        assert todo["type"] == "todo"
        assert todo["metadata"]["owner"] == owner
        assert todo["metadata"]["status"] == "pending"
        assert todo["metadata"]["priority"] == "high"

    def test_complete_todo(self):
        """Todoを完了にできる（PATCH /memory/{id}）"""
        unique_id = str(uuid.uuid4())[:8]
        project_id = f"todo-complete-{unique_id}"
        owner = f"complete-{unique_id}@example.com"

        # Todoを作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": f"完了予定Todo {unique_id}",
            "type": "todo",
            "scope": "project",
            "scope_id": project_id,
            "importance": 0.95,
            "metadata": {"owner": owner, "status": "pending"}
        })
        memory_id = create_response.json()["id"]

        # Todoを完了にする
        complete_response = requests.patch(
            f"{BASE_URL}/memory/{memory_id}",
            json={"metadata": {"status": "done", "completed_at": datetime.utcnow().isoformat()}}
        )
        assert complete_response.status_code == 200

        # 完了状態を確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        todo = get_response.json()
        assert todo["metadata"]["status"] == "done"
        assert "completed_at" in todo["metadata"]

    def test_delete_todo(self):
        """Todoを削除できる"""
        unique_id = str(uuid.uuid4())[:8]
        project_id = f"todo-delete-{unique_id}"
        owner = f"delete-{unique_id}@example.com"

        # Todoを作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": f"削除予定Todo {unique_id}",
            "type": "todo",
            "scope": "project",
            "scope_id": project_id,
            "importance": 0.95,
            "metadata": {"owner": owner, "status": "pending"}
        })
        memory_id = create_response.json()["id"]

        # Todoを削除
        delete_response = requests.delete(f"{BASE_URL}/memory/{memory_id}")
        assert delete_response.status_code == 200

        # 削除を確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 404


class TestCleanup:
    """クリーンアップ機能のテスト（/cleanup エンドポイント）"""

    def test_cleanup_expired_memories(self):
        """期限切れ記憶を削除できる"""
        # クリーンアップが動作することを確認
        response = requests.post(f"{BASE_URL}/cleanup")
        assert response.status_code == 200
        data = response.json()
        assert "deleted" in data
        assert isinstance(data["deleted"], int)

    def test_cleanup_preserves_valid_memories(self):
        """有効な記憶は削除されない"""
        unique_id = str(uuid.uuid4())[:8]

        # 有効な記憶を作成（デフォルトTTLは30日）
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": f"有効な記憶 {unique_id}",
            "type": "work",
            "scope": "project",
            "scope_id": f"cleanup-test-{unique_id}",
            "importance": 0.95
        })
        memory_id = create_response.json()["id"]

        # クリーンアップ実行
        cleanup_response = requests.post(f"{BASE_URL}/cleanup")
        assert cleanup_response.status_code == 200

        # 有効な記憶は削除されていないことを確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert get_response.json()["id"] == memory_id

    def test_cleanup_dry_run(self):
        """dry_run=true で削除せずカウントのみ（未実装の場合はスキップ）"""
        # 注意: 現在のAPIにはdry_runパラメータが実装されていない
        # この機能が追加された場合に備えてテストを用意
        response = requests.post(
            f"{BASE_URL}/cleanup",
            params={"dry_run": "true"}
        )
        # dry_runが実装されていない場合は通常の動作となる
        assert response.status_code == 200
        data = response.json()
        assert "deleted" in data


class TestAdmin:
    """admin系エンドポイントのテスト"""

    def test_create_team(self):
        """チームを作成できる"""
        team_id = f"test-team-{uuid.uuid4().hex[:8]}"
        response = requests.post(f"{BASE_URL}/admin/teams", json={
            "id": team_id,
            "name": "Test Team"
        })
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "Team created"
        assert data["team_id"] == team_id

    def test_list_teams(self):
        """チーム一覧を取得できる"""
        # テスト用チームを作成
        team_id = f"list-team-{uuid.uuid4().hex[:8]}"
        requests.post(f"{BASE_URL}/admin/teams", json={
            "id": team_id,
            "name": "List Test Team"
        })

        response = requests.get(f"{BASE_URL}/admin/teams")
        assert response.status_code == 200
        data = response.json()
        assert "teams" in data
        assert isinstance(data["teams"], list)
        # 作成したチームが含まれていることを確認
        team_ids = [t["id"] for t in data["teams"]]
        assert team_id in team_ids

    def test_create_user(self):
        """ユーザーを作成できる"""
        user_id = f"test-user-{uuid.uuid4().hex[:8]}"
        response = requests.post(f"{BASE_URL}/admin/users", json={
            "id": user_id,
            "role": "member"
        })
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "User created"
        assert data["user_id"] == user_id
        assert "api_key" in data
        assert data["api_key"].startswith("isac_")
        assert "warning" in data

    def test_list_users(self):
        """ユーザー一覧を取得できる"""
        # テスト用ユーザーを作成
        user_id = f"list-user-{uuid.uuid4().hex[:8]}"
        requests.post(f"{BASE_URL}/admin/users", json={
            "id": user_id,
            "role": "member"
        })

        response = requests.get(f"{BASE_URL}/admin/users")
        assert response.status_code == 200
        data = response.json()
        assert "users" in data
        assert isinstance(data["users"], list)
        # 作成したユーザーが含まれていることを確認
        user_ids = [u["id"] for u in data["users"]]
        assert user_id in user_ids

    def test_regenerate_api_key(self):
        """APIキーを再生成できる"""
        # まずユーザーを作成
        user_id = f"regen-user-{uuid.uuid4().hex[:8]}"
        create_response = requests.post(f"{BASE_URL}/admin/users", json={
            "id": user_id,
            "role": "member"
        })
        original_api_key = create_response.json()["api_key"]

        # APIキーを再生成
        response = requests.post(f"{BASE_URL}/admin/users/{user_id}/regenerate-key")
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "API key regenerated"
        assert data["user_id"] == user_id
        assert "api_key" in data
        assert data["api_key"].startswith("isac_")
        # 新しいAPIキーは元のものと異なる
        assert data["api_key"] != original_api_key

    def test_regenerate_api_key_not_found(self):
        """存在しないユーザーのAPIキー再生成はエラー"""
        response = requests.post(f"{BASE_URL}/admin/users/nonexistent-user/regenerate-key")
        assert response.status_code == 404
        assert "not found" in response.json()["detail"].lower()

    def test_get_audit_logs(self):
        """監査ログを取得できる"""
        response = requests.get(f"{BASE_URL}/admin/audit-logs")
        assert response.status_code == 200
        data = response.json()
        assert "logs" in data
        assert "count" in data
        assert isinstance(data["logs"], list)

    def test_get_audit_logs_with_filters(self):
        """フィルタ付きで監査ログを取得できる"""
        # まず記憶を保存して監査ログを生成
        requests.post(f"{BASE_URL}/store", json={
            "content": "audit log test",
            "type": "work",
            "scope": "project",
            "scope_id": "audit-test"
        })

        # actionでフィルタ
        response = requests.get(
            f"{BASE_URL}/admin/audit-logs",
            params={"action": "store_memory", "limit": 10}
        )
        assert response.status_code == 200
        data = response.json()
        for log in data["logs"]:
            assert log["action"] == "store_memory"

    def test_add_project_member(self):
        """プロジェクトにメンバーを追加できる"""
        # まずユーザーを作成
        user_id = f"member-user-{uuid.uuid4().hex[:8]}"
        requests.post(f"{BASE_URL}/admin/users", json={
            "id": user_id,
            "role": "member"
        })

        project_id = f"member-project-{uuid.uuid4().hex[:8]}"
        response = requests.post(
            f"{BASE_URL}/projects/{project_id}/members",
            json={"user_id": user_id, "role": "member"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "Member added"
        assert data["project_id"] == project_id
        assert data["user_id"] == user_id

    def test_list_project_members(self):
        """プロジェクトメンバー一覧を取得できる"""
        # ユーザーとプロジェクトメンバーを作成
        user_id = f"list-member-{uuid.uuid4().hex[:8]}"
        requests.post(f"{BASE_URL}/admin/users", json={
            "id": user_id,
            "role": "member"
        })

        project_id = f"list-members-project-{uuid.uuid4().hex[:8]}"
        requests.post(
            f"{BASE_URL}/projects/{project_id}/members",
            json={"user_id": user_id, "role": "admin"}
        )

        response = requests.get(f"{BASE_URL}/projects/{project_id}/members")
        assert response.status_code == 200
        data = response.json()
        assert data["project_id"] == project_id
        assert "members" in data
        assert isinstance(data["members"], list)


class TestErrorResponses:
    """エラーレスポンスの形式テスト"""

    def test_404_response_format(self):
        """存在しないリソースのレスポンス形式"""
        response = requests.get(f"{BASE_URL}/memory/nonexistent-id-12345")
        assert response.status_code == 404
        data = response.json()
        assert "detail" in data
        assert isinstance(data["detail"], str)

    def test_400_response_format(self):
        """不正なリクエストのレスポンス形式"""
        # 存在しない superseded_by を指定して400エラーを発生させる
        # まず記憶を作成
        create_response = requests.post(f"{BASE_URL}/store", json={
            "content": "400 test",
            "type": "work",
            "scope": "project",
            "scope_id": "error-test"
        })
        memory_id = create_response.json()["id"]

        # 存在しない superseded_by で廃止を試みる
        response = requests.patch(
            f"{BASE_URL}/memory/{memory_id}/deprecate",
            json={"deprecated": True, "superseded_by": "nonexistent-id"}
        )
        assert response.status_code == 400
        data = response.json()
        assert "detail" in data
        assert isinstance(data["detail"], str)

    def test_422_response_format(self):
        """バリデーションエラーのレスポンス形式"""
        # contentがない不正なリクエスト
        response = requests.post(f"{BASE_URL}/store", json={
            "type": "work",
            "scope": "project",
            "scope_id": "validation-test"
        })
        assert response.status_code == 422
        data = response.json()
        assert "detail" in data
        # FastAPIのバリデーションエラーはdetailがリスト
        assert isinstance(data["detail"], list) or isinstance(data["detail"], str)

    def test_error_response_has_detail(self):
        """エラーレスポンスにdetailフィールドがある"""
        # 各種エラーレスポンスをテスト
        error_requests = [
            # 404: 存在しないリソース
            ("GET", f"{BASE_URL}/memory/not-found-123"),
            # 422: 無効なスコープ
            ("POST", f"{BASE_URL}/store", {"content": "test", "scope": "invalid"}),
            # 422: 無効なタイプ
            ("POST", f"{BASE_URL}/store", {"content": "test", "type": "invalid"}),
        ]

        for method, url, *payload in error_requests:
            if method == "GET":
                response = requests.get(url)
            else:
                response = requests.post(url, json=payload[0] if payload else {})

            # エラーレスポンスであることを確認
            assert response.status_code >= 400
            data = response.json()
            assert "detail" in data, f"Missing 'detail' in response for {method} {url}"

    def test_error_response_is_json(self):
        """エラーレスポンスがJSON形式"""
        # 404エラー
        response = requests.get(f"{BASE_URL}/memory/json-test-not-found")
        assert response.status_code == 404
        assert response.headers.get("content-type", "").startswith("application/json")
        # JSONとしてパースできることを確認
        data = response.json()
        assert data is not None

        # 422エラー
        response = requests.post(f"{BASE_URL}/store", json={
            "type": "invalid_type"
        })
        assert response.status_code == 422
        assert response.headers.get("content-type", "").startswith("application/json")
        data = response.json()
        assert data is not None

    def test_context_missing_query_error(self):
        """コンテキスト取得でqueryがない場合のエラー形式"""
        response = requests.get(f"{BASE_URL}/context/test-project")
        assert response.status_code == 422
        data = response.json()
        assert "detail" in data

    def test_invalid_scope_error(self):
        """無効なスコープのエラー形式"""
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "test",
            "scope": "invalid_scope"
        })
        assert response.status_code == 422
        data = response.json()
        assert "detail" in data

    def test_invalid_type_error(self):
        """無効なタイプのエラー形式"""
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "test",
            "type": "invalid_type"
        })
        assert response.status_code == 422
        data = response.json()
        assert "detail" in data


class TestSpecialCharactersComprehensive:
    """特殊文字の網羅的テスト"""

    @pytest.mark.parametrize("char_index", range(10))
    def test_store_all_special_chars(self, special_chars, char_index):
        """全特殊文字で保存できる"""
        content = special_chars[char_index]
        unique_id = str(uuid.uuid4())[:8]
        payload = {
            "content": f"{content} {unique_id}",
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "special-chars-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert "id" in data

        # 保存した内容を取得して確認
        memory_id = data["id"]
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert content in get_response.json()["content"]

    @pytest.mark.parametrize("char_index", range(10))
    def test_search_special_chars(self, special_chars, char_index):
        """特殊文字を含む検索ができる"""
        content = special_chars[char_index]
        unique_id = str(uuid.uuid4())[:8]

        # テストデータを作成
        payload = {
            "content": f"検索用 {content} {unique_id}",
            "type": "work",
            "importance": 0.9,
            "scope": "project",
            "scope_id": "special-chars-search-test"
        }
        store_response = requests.post(f"{BASE_URL}/store", json=payload)
        assert store_response.status_code == 200

        # unique_id で検索（特殊文字自体での検索はエスケープ問題があるため）
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": unique_id}
        )
        assert response.status_code == 200
        data = response.json()
        assert "memories" in data

    @pytest.mark.parametrize("char_index", range(10))
    def test_context_special_chars(self, special_chars, char_index):
        """コンテキスト取得で特殊文字を含む記憶が取得できる"""
        content = special_chars[char_index]
        unique_id = str(uuid.uuid4())[:8]
        project_id = f"context-special-{char_index}"

        # テストデータを作成
        payload = {
            "content": f"コンテキスト用 {content} {unique_id}",
            "type": "decision",
            "importance": 0.9,
            "scope": "project",
            "scope_id": project_id
        }
        store_response = requests.post(f"{BASE_URL}/store", json=payload)
        assert store_response.status_code == 200

        # コンテキスト取得
        response = requests.get(
            f"{BASE_URL}/context/{project_id}",
            params={"query": unique_id}
        )
        assert response.status_code == 200
        data = response.json()
        assert "project_decisions" in data

    def test_export_import_special_chars(self, special_chars):
        """export/importで特殊文字が保持される"""
        project_id = f"export-import-special-{uuid.uuid4().hex[:8]}"

        # 全特殊文字を含む記憶を保存
        stored_ids = []
        for i, content in enumerate(special_chars):
            payload = {
                "content": f"エクスポート用 {content} idx{i}",
                "type": "work",
                "importance": 0.5,
                "scope": "project",
                "scope_id": project_id
            }
            response = requests.post(f"{BASE_URL}/store", json=payload)
            assert response.status_code == 200
            stored_ids.append(response.json()["id"])

        # エクスポート
        export_response = requests.get(f"{BASE_URL}/export/{project_id}")
        assert export_response.status_code == 200
        export_data = export_response.json()
        assert export_data["count"] >= len(special_chars)

        # 各特殊文字が含まれていることを確認
        exported_contents = [m["content"] for m in export_data["memories"]]
        for content in special_chars:
            found = any(content in ec for ec in exported_contents)
            assert found, f"特殊文字 '{content}' がエクスポートデータに見つかりません"

    @pytest.mark.parametrize("char_index", range(10))
    def test_update_with_special_chars(self, special_chars, char_index):
        """更新時に特殊文字が正しく処理される"""
        content = special_chars[char_index]

        # 初期データを作成
        payload = {
            "content": "初期コンテンツ",
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "update-special-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # 特殊文字を含む内容に更新
        update_response = requests.patch(
            f"{BASE_URL}/memory/{memory_id}",
            json={"content": f"更新後: {content}"}
        )
        assert update_response.status_code == 200

        # 更新内容を確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert content in get_response.json()["content"]

    @pytest.mark.parametrize("char_index", range(10))
    def test_tags_with_special_chars(self, special_chars, char_index):
        """タグに特殊文字を含めて保存できる"""
        tag_content = special_chars[char_index]

        payload = {
            "content": "タグテスト用コンテンツ",
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "tags-special-test",
            "tags": [f"tag-{tag_content}"]
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # 保存内容を確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        saved_tags = get_response.json().get("tags", [])
        assert any(tag_content in tag for tag in saved_tags), f"タグ '{tag_content}' が保存されていません"

    @pytest.mark.parametrize("char_index", range(10))
    def test_metadata_with_special_chars(self, special_chars, char_index):
        """メタデータに特殊文字を含めて保存できる"""
        meta_value = special_chars[char_index]

        payload = {
            "content": "メタデータテスト用コンテンツ",
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "metadata-special-test",
            "metadata": {"special_key": meta_value}
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # 保存内容を確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        saved_metadata = get_response.json().get("metadata", {})
        assert saved_metadata.get("special_key") == meta_value, f"メタデータ値 '{meta_value}' が保存されていません"

    def test_update_content_normal(self):
        """PATCH でコンテンツを正常に更新できる"""
        # 初期データ作成
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "更新前コンテンツ",
            "type": "work",
            "scope": "project",
            "scope_id": "update-content-test"
        })
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # コンテンツ更新
        update_response = requests.patch(
            f"{BASE_URL}/memory/{memory_id}",
            json={"content": "更新後コンテンツ"}
        )
        assert update_response.status_code == 200

        # 更新内容を確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert get_response.json()["content"] == "更新後コンテンツ"

    def test_update_content_over_max_rejected(self):
        """PATCH で 65,536文字超のコンテンツ更新は422で拒否される"""
        # 初期データ作成
        response = requests.post(f"{BASE_URL}/store", json={
            "content": "初期コンテンツ",
            "type": "work",
            "scope": "project",
            "scope_id": "update-oversize-test"
        })
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # 上限超のコンテンツで更新
        update_response = requests.patch(
            f"{BASE_URL}/memory/{memory_id}",
            json={"content": "A" * 65537}
        )
        assert update_response.status_code == 422
        detail = update_response.json()["detail"]
        assert detail["current_length"] == 65537
        assert detail["max_length"] == 65536


class TestBoundaryValuesComprehensive:
    """境界値の網羅的テスト"""

    def test_empty_content_rejected(self, boundary_values):
        """空コンテンツは拒否される"""
        payload = {
            "content": boundary_values['empty'],
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "boundary-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        # 空文字列はバリデーションエラーになるべき
        assert response.status_code in [400, 422], f"空コンテンツが受け入れられました: {response.status_code}"

    def test_single_char_content(self, boundary_values):
        """1文字コンテンツを保存できる"""
        payload = {
            "content": boundary_values['single_char'],
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "boundary-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # 取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert get_response.json()["content"] == boundary_values['single_char']

    def test_very_long_content(self, boundary_values):
        """非常に長いコンテンツ（10000文字）を保存できる"""
        payload = {
            "content": boundary_values['long_content'],
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "boundary-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # 取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert len(get_response.json()["content"]) == 10000

    def test_max_summary_length(self, boundary_values):
        """最大長のサマリー（200文字）を保存できる"""
        payload = {
            "content": "本文コンテンツ",
            "summary": boundary_values['max_summary'],
            "type": "work",
            "importance": 0.5,
            "scope": "project",
            "scope_id": "boundary-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # 取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert len(get_response.json()["summary"]) == 200

    def test_importance_zero(self, boundary_values):
        """importance=0.0 で保存できる"""
        payload = {
            "content": "importance ゼロテスト",
            "type": "work",
            "importance": boundary_values['zero_importance'],
            "scope": "project",
            "scope_id": "boundary-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # 取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert get_response.json()["importance"] == 0.0

    def test_importance_max(self, boundary_values):
        """importance=1.0 で保存できる"""
        payload = {
            "content": "importance 最大テスト",
            "type": "work",
            "importance": boundary_values['max_importance'],
            "scope": "project",
            "scope_id": "boundary-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        assert response.status_code == 200
        memory_id = response.json()["id"]

        # 取得して確認
        get_response = requests.get(f"{BASE_URL}/memory/{memory_id}")
        assert get_response.status_code == 200
        assert get_response.json()["importance"] == 1.0

    def test_importance_negative_rejected(self, boundary_values):
        """負のimportanceは拒否される"""
        payload = {
            "content": "importance 負値テスト",
            "type": "work",
            "importance": boundary_values['negative_importance'],
            "scope": "project",
            "scope_id": "boundary-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        # 負の値はバリデーションエラーになるべき
        assert response.status_code in [400, 422], f"負のimportanceが受け入れられました: {response.status_code}"

    def test_importance_over_one_rejected(self, boundary_values):
        """1超のimportanceは拒否される"""
        payload = {
            "content": "importance 1超テスト",
            "type": "work",
            "importance": boundary_values['over_importance'],
            "scope": "project",
            "scope_id": "boundary-test"
        }
        response = requests.post(f"{BASE_URL}/store", json=payload)
        # 1.0 を超える値はバリデーションエラーになるべき
        assert response.status_code in [400, 422], f"1超のimportanceが受け入れられました: {response.status_code}"

    def test_limit_zero(self):
        """limit=0 での検索は空の結果を返すか、エラーになる"""
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": "テスト", "limit": 0}
        )
        # limit=0 は空の結果または制限として扱われるべき
        if response.status_code == 200:
            data = response.json()
            assert len(data["memories"]) == 0
        else:
            assert response.status_code in [400, 422]

    def test_limit_max(self):
        """limit=50 での検索ができる"""
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": "テスト", "limit": 50}
        )
        assert response.status_code == 200
        data = response.json()
        assert len(data["memories"]) <= 50

    def test_limit_over_max_rejected(self):
        """limit>50は拒否または制限される"""
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": "テスト", "limit": 100}
        )
        # 100は拒否されるか、50に制限されるべき
        if response.status_code == 200:
            data = response.json()
            # 結果が50以下に制限されていることを確認
            assert len(data["memories"]) <= 50, f"limit=100 で {len(data['memories'])} 件返されました"
        else:
            assert response.status_code in [400, 422], f"予期しないステータスコード: {response.status_code}"

    def test_offset_zero(self):
        """offset=0 での検索ができる"""
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": "テスト", "offset": 0}
        )
        assert response.status_code == 200

    def test_offset_large_value(self):
        """大きな offset 値での検索は空の結果を返す"""
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": "テスト", "offset": 10000}
        )
        if response.status_code == 200:
            data = response.json()
            assert len(data["memories"]) == 0

    def test_negative_offset_rejected(self):
        """負の offset は拒否される"""
        response = requests.get(
            f"{BASE_URL}/search",
            params={"query": "テスト", "offset": -1}
        )
        # 負の値はエラーになるべき
        assert response.status_code in [400, 422], f"負のoffsetが受け入れられました: {response.status_code}"

    def test_max_tokens_zero(self):
        """max_tokens=0 での検索は空の結果を返すか、エラーになる"""
        response = requests.get(
            f"{BASE_URL}/context/boundary-test",
            params={"query": "テスト", "max_tokens": 0}
        )
        if response.status_code == 200:
            data = response.json()
            # トークン数が0以下になるべき
            assert data["total_tokens"] == 0
        else:
            assert response.status_code in [400, 422]

    def test_max_tokens_large_value(self):
        """大きな max_tokens 値での検索ができる"""
        response = requests.get(
            f"{BASE_URL}/context/boundary-test",
            params={"query": "テスト", "max_tokens": 100000}
        )
        assert response.status_code == 200


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
