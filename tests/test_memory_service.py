#!/usr/bin/env python3
"""
ISAC Memory Service API テスト

実行方法:
    cd /path/to/isac
    pip install pytest requests
    pytest tests/ -v

前提条件:
    - Memory Service が http://localhost:8100 で起動していること
"""

import pytest
import requests
import uuid
from datetime import datetime

BASE_URL = "http://localhost:8100"


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


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
