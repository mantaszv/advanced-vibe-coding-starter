#!/usr/bin/env bash
# .claude/hooks/pre-commit.sh
# Paleidžia visus guard agentus prieš commit'ą.
# Jei bet kuris grąžina BLOCKED — commit'as sustabdomas.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

# Pakeitimų diff, kurį duodame guardams
DIFF=$(git diff --cached --unified=3)
CHANGED_FILES=$(git diff --cached --name-only)

if [ -z "$CHANGED_FILES" ]; then
  echo "Nėra staged pakeitimų — praleidžiama."
  exit 0
fi

BLOCKED=0
AGENTS_DIR=".claude/agents"

# Guard triggerių žemėlapis — kurie agentai paleisti pagal failų pattern'us.
# Parašyta be `declare -A`, kad veiktų macOS default bash 3.2.
trigger_pattern() {
  case "$1" in
    db-migration-guard)   echo "^supabase/migrations/" ;;
    payment-guard)        echo "stripe|checkout|payment|refund" ;;
    language-guard)       echo "\\.(tsx|ts|md)$" ;;
    file-size-guard)      echo "^src/" ;;
    test-coverage-guard)  echo "^src/.*\\.(ts|tsx)$" ;;
    security-guard)       echo "\\.env|supabase/|auth|middleware" ;;
  esac
}

TRIGGER_GUARDS="db-migration-guard payment-guard language-guard file-size-guard test-coverage-guard security-guard"

# risk-assessor paleidžiamas VISADA
ALWAYS_RUN="risk-assessor"

run_guard() {
  agent="$1"
  agent_file="$AGENTS_DIR/${agent}.md"

  if [ ! -f "$agent_file" ]; then
    echo "  [WARN] Guard $agent nerastas ($agent_file) -- praleidziama"
    return 0
  fi

  echo "=== $agent ==="

  # Surenkame prompt'ą į tmp failą (išvengiame bash 3.2 heredoc quirks)
  tmp_prompt=$(mktemp -t guard-prompt.XXXXXX)
  {
    cat "$agent_file"
    printf '\n---\n\n# Pakeitimai peržiūrai (git diff --cached)\n\n```diff\n'
    printf '%s\n' "$DIFF"
    printf '```\n\n---\n\n# Paveikti failai\n\n%s\n\n---\n\n' "$CHANGED_FILES"
    printf 'INSTRUKCIJA: Įvertinkite pakeitimus pagal guard taisykles. Pirmoje eilutėje grąžinkite TIKSLIAI vieną iš:\n'
    printf -- '- VERDICT: OK -- jei pakeitimai saugūs\n'
    printf -- '- VERDICT: WARN -- jei yra rizikų, bet commitas galimas\n'
    printf -- '- VERDICT: BLOCKED -- jei commitas turi būti sustabdytas\n\n'
    printf 'Po to -- iki 10 eilučių paaiškinimo.\n'
  } > "$tmp_prompt"

  result=$(claude --print < "$tmp_prompt" 2>/dev/null || echo "VERDICT: WARN")
  rm -f "$tmp_prompt"

  echo "$result" | head -12

  if echo "$result" | head -1 | grep -q "VERDICT: BLOCKED"; then
    BLOCKED=$((BLOCKED + 1))
  fi
}

# Visada paleidžiami
for agent in $ALWAYS_RUN; do
  run_guard "$agent"
done

# Trigger-based
for agent in $TRIGGER_GUARDS; do
  pattern=$(trigger_pattern "$agent")
  if echo "$CHANGED_FILES" | grep -qE "$pattern"; then
    run_guard "$agent"
  fi
done

echo ""
if [ "$BLOCKED" -gt 0 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "❌ COMMIT SUSTABDYTAS — $BLOCKED guard(ai) grąžino BLOCKED"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Pataisykite problemas arba naudokite --no-verify (NE REKOMENDUOJAMA)"
  exit 1
fi

echo "✅ Visi guardai praėjo"
exit 0
