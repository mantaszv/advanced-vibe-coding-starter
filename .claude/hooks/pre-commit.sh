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

# Guard triggerių žemėlapis — kurie agentai paleisti pagal failų pattern'us
declare -A TRIGGERS=(
  ["db-migration-guard"]="^supabase/migrations/"
  ["payment-guard"]="stripe|checkout|payment|refund"
  ["language-guard"]="\\.(tsx|ts|md)$"
  ["file-size-guard"]="^src/"
  ["test-coverage-guard"]="^src/.*\\.(ts|tsx)$"
  ["security-guard"]="\\.env|supabase/|auth|middleware"
)

# risk-assessor paleidžiamas VISADA
ALWAYS_RUN=("risk-assessor")

run_guard() {
  local agent="$1"
  local agent_file="$AGENTS_DIR/${agent}.md"

  if [ ! -f "$agent_file" ]; then
    echo "  ⚠️  Guard $agent nerastas ($agent_file) — praleidžiama"
    return 0
  fi

  echo "━━━ $agent ━━━"

  # Klaudui paduodam agent'o sistem prompt'ą + diff'ą ir laukiam verdikto
  local prompt
  prompt=$(cat <<EOF
$(cat "$agent_file")

---

# Pakeitimai peržiūrai (git diff --cached)

\`\`\`diff
$DIFF
\`\`\`

---

# Paveikti failai

$CHANGED_FILES

---

INSTRUKCIJA: Įvertinkite pakeitimus pagal šio guard'o taisykles. Pirmoje eilutėje grąžinkite TIKSLIAI:
- \`VERDICT: OK\` — jei pakeitimai saugūs
- \`VERDICT: WARN\` — jei yra rizikų, bet commit galimas
- \`VERDICT: BLOCKED\` — jei commit turi būti sustabdytas

Po to — iki 10 eilučių paaiškinimo.
EOF
)

  local result
  result=$(echo "$prompt" | claude --print --max-tokens 500 2>/dev/null || echo "VERDICT: WARN\n(claude CLI klaida — guard praleistas)")

  echo "$result" | head -12

  if echo "$result" | head -1 | grep -q "VERDICT: BLOCKED"; then
    BLOCKED=$((BLOCKED + 1))
  fi
}

# Visada paleidžiami
for agent in "${ALWAYS_RUN[@]}"; do
  run_guard "$agent"
done

# Trigger-based
for agent in "${!TRIGGERS[@]}"; do
  pattern="${TRIGGERS[$agent]}"
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
