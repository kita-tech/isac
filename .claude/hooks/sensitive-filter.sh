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
    "private_key:-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"

    # JWT
    "jwt:eyJ[A-Za-z0-9_-]+\\.eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"

    # Context7 API Key
    "context7_api_key:ctx7sk-[0-9a-f-]{36}"

    # Generic secrets（8文字以上）
    "secret:secret[[:space:]]*[=:][[:space:]]*['\"]?[^[:space:]'\"]{8,}['\"]?"
    "credential:credential[[:space:]]*[=:][[:space:]]*['\"]?[^[:space:]'\"]{8,}['\"]?"
)

# 検出結果
DETECTED=()
FILTERED_TEXT="$INPUT_TEXT"
IS_SENSITIVE="false"

# 各パターンでチェック・マスキング
for pattern_def in "${PATTERNS[@]}"; do
    PATTERN_NAME="${pattern_def%%:*}"
    PATTERN_REGEX="${pattern_def#*:}"

    # 大文字小文字を無視してマッチ
    if echo "$INPUT_TEXT" | grep -iE "$PATTERN_REGEX" > /dev/null 2>&1; then
        DETECTED+=("$PATTERN_NAME")
        IS_SENSITIVE="true"

        # マスキング（sedで置換）
        FILTERED_TEXT=$(echo "$FILTERED_TEXT" | sed -E "s/$PATTERN_REGEX/[MASKED:$PATTERN_NAME]/gi" 2>/dev/null || echo "$FILTERED_TEXT")
    fi
done

# JSON出力用に配列を整形
DETECTED_JSON="[]"
if [ ${#DETECTED[@]} -gt 0 ]; then
    DETECTED_JSON=$(printf '%s\n' "${DETECTED[@]}" | jq -R . | jq -s .)
fi

# 結果をJSON出力
jq -n \
    --arg filtered "$FILTERED_TEXT" \
    --argjson detected "$DETECTED_JSON" \
    --argjson is_sensitive "$IS_SENSITIVE" \
    '{filtered: $filtered, detected: $detected, is_sensitive: $is_sensitive}'
