#!/bin/bash
# sensitive-filter.sh
# 機密情報をマスキングするフィルター
#
# 使用方法:
#   echo "password=secret123" | ./sensitive-filter.sh
#   ./sensitive-filter.sh "api_key=abc123"
#
# 出力形式（JSON）:
# {
#   "filtered": "マスキング後のテキスト",
#   "detected": ["password", "api_key"],
#   "is_sensitive": true/false
# }

set -e

# 入力テキスト取得
if [ -n "$1" ]; then
    INPUT_TEXT="$1"
else
    INPUT_TEXT=$(cat)
fi

# マスキングパターン定義
# フォーマット: "パターン名:正規表現"
# Note: [[:space:]] for whitespace, extended regex for grep -E
PATTERNS=(
    # APIキー・トークン（16文字以上）
    "api_key:api[_-]?key[[:space:]]*[=:][[:space:]]*['\"]?[A-Za-z0-9_-]{16,}['\"]?"
    "api_token:api[_-]?token[[:space:]]*[=:][[:space:]]*['\"]?[A-Za-z0-9_-]{16,}['\"]?"
    "access_token:access[_-]?token[[:space:]]*[=:][[:space:]]*['\"]?[A-Za-z0-9_-]{16,}['\"]?"
    "secret_key:secret[_-]?key[[:space:]]*[=:][[:space:]]*['\"]?[A-Za-z0-9_-]{16,}['\"]?"
    "auth_token:auth[_-]?token[[:space:]]*[=:][[:space:]]*['\"]?[A-Za-z0-9_-]{16,}['\"]?"
    "bearer_token:bearer[[:space:]]+[A-Za-z0-9_-]{20,}"

    # パスワード（4文字以上）
    "password:password[[:space:]]*[=:][[:space:]]*['\"]?[^[:space:]'\"]{4,}['\"]?"
    "passwd:passwd[[:space:]]*[=:][[:space:]]*['\"]?[^[:space:]'\"]{4,}['\"]?"

    # AWS
    "aws_access_key:AKIA[0-9A-Z]{16}"
    "aws_secret:aws[_-]?secret[_-]?access[_-]?key[[:space:]]*[=:][[:space:]]*['\"]?[A-Za-z0-9/+=]{40}['\"]?"

    # Database URLs
    "database_url:postgres(ql)?://[^[:space:]]+"
    "database_url:mysql://[^[:space:]]+"
    "database_url:mongodb(\\+srv)?://[^[:space:]]+"

    # Private Keys
    # 1) PEM ブロック全体（見出し〜END までを複数行でマスク。[\s\S] で改行を跨ぐ）
    "private_key:-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----[\\s\\S]*?-----END (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"
    # 2) END が欠けた截断ケースの保険（見出し行だけでもマスク）
    "private_key:-----(BEGIN|END) (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"

    # JWT
    "jwt:eyJ[A-Za-z0-9_-]+\\.eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"

    # Context7 API Key
    "context7_api_key:ctx7sk-[0-9a-f-]{36}"

    # GitHub Token
    "github_token:ghp_[A-Za-z0-9]{36}"
    "github_token:gho_[A-Za-z0-9]{36}"
    "github_token:ghu_[A-Za-z0-9]{36}"
    "github_token:ghs_[A-Za-z0-9]{36}"
    "github_token:ghr_[A-Za-z0-9]{36}"

    # Slack Token
    "slack_token:xoxb-[0-9A-Za-z-]+"
    "slack_token:xoxp-[0-9A-Za-z-]+"
    "slack_token:xoxa-[0-9A-Za-z-]+"
    "slack_token:xoxr-[0-9A-Za-z-]+"

    # Notion Token
    "notion_token:ntn_[A-Za-z0-9]+"
    "notion_token:secret_[A-Za-z0-9]+"

    # Generic secrets（8文字以上）
    "secret:secret[[:space:]]*[=:][[:space:]]*['\"]?[^[:space:]'\"]{8,}['\"]?"
    "credential:credential[[:space:]]*[=:][[:space:]]*['\"]?[^[:space:]'\"]{8,}['\"]?"
)

# 検出結果
DETECTED=()
FILTERED_TEXT="$INPUT_TEXT"
IS_SENSITIVE="false"
MASK_ERROR="false"

# 検出とマスキングを perl で行う（理由）:
#  - sed の `s/.../.../` は区切り文字 `/` を使うため、正規表現に `//`（例: postgres://）が
#    含まれると構文エラーになり、旧実装は `|| echo 原文` で fail-open して資格情報を平文漏洩していた。
#    perl は正規表現を「変数展開」で渡すため区切り衝突が原理的に起きない。
#  - grep/sed は行単位のため PEM 秘密鍵の本体（複数行 base64）をマスクできなかった。
#    perl -0777（slurp）＋パターンの [\s\S]*? で複数行ブロックをまとめてマスクする。

# 1文字でもマッチするか（perl・slurp・大小無視）。マッチ=0, 非マッチ=1 を返す。
detect_match() {
    REGEX="$1" perl -0777 -ne 'exit(($_ =~ /$ENV{REGEX}/i) ? 0 : 1)'
}
# マスク適用（perl・slurp・大小無視・全置換）。区切り衝突なし・複数行対応。
apply_mask() {
    REGEX="$1" NAME="$2" perl -0777 -pe 's/$ENV{REGEX}/[MASKED:$ENV{NAME}]/gi'
}

# 各パターンでチェック・マスキング
for pattern_def in "${PATTERNS[@]}"; do
    PATTERN_NAME="${pattern_def%%:*}"
    PATTERN_REGEX="${pattern_def#*:}"

    if printf '%s' "$INPUT_TEXT" | detect_match "$PATTERN_REGEX"; then
        DETECTED+=("$PATTERN_NAME")
        IS_SENSITIVE="true"
        FILTERED_TEXT=$(printf '%s' "$FILTERED_TEXT" | apply_mask "$PATTERN_REGEX" "$PATTERN_NAME")
    fi
done

# fail-closed 検証: 検出したパターンがマスク後もまだ残っていれば「マスク失敗」。
# 旧実装は失敗時に原文を出していた（fail-open）。ここでは絶対に平文を出さず、
# 残存箇所を強制的に潰し、マスク不能なら全体を安全側で伏せる。
for pattern_def in "${PATTERNS[@]}"; do
    PATTERN_NAME="${pattern_def%%:*}"
    PATTERN_REGEX="${pattern_def#*:}"
    if printf '%s' "$FILTERED_TEXT" | detect_match "$PATTERN_REGEX"; then
        MASK_ERROR="true"
        RETRY=$(printf '%s' "$FILTERED_TEXT" | apply_mask "$PATTERN_REGEX" "$PATTERN_NAME")
        if printf '%s' "$RETRY" | detect_match "$PATTERN_REGEX"; then
            # それでも残る＝安全に潰せない。機密を絶対に漏らさないため全体を伏せる。
            FILTERED_TEXT="[MASKED:masking-failed]"
            break
        fi
        FILTERED_TEXT="$RETRY"
    fi
done

# JSON出力用に配列を整形（重複除去。database_url 等は複数パターンが同名のため）
DETECTED_JSON="[]"
if [ ${#DETECTED[@]} -gt 0 ]; then
    DETECTED_JSON=$(printf '%s\n' "${DETECTED[@]}" | jq -R . | jq -s 'unique')
fi

# 結果をJSON出力（masking_error は後方互換の追加フィールド。true ならマスク失敗を通知）
jq -n \
    --arg filtered "$FILTERED_TEXT" \
    --argjson detected "$DETECTED_JSON" \
    --argjson is_sensitive "$IS_SENSITIVE" \
    --argjson masking_error "$MASK_ERROR" \
    '{filtered: $filtered, detected: $detected, is_sensitive: $is_sensitive, masking_error: $masking_error}'
