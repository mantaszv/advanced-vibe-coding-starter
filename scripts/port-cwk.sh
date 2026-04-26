#!/usr/bin/env bash
# Port CWK 4-stage pipeline commands → starter kit's _templates/.
# VIENKARTINIS skriptas — paleidžiamas mano lokaliai prieš commit'inant
# `.claude/commands/_templates/`. Dalyviams jis NESVARBUS.
#
# Atlieka 2 transformacijų grupes:
#   1) Agent name remapping: 5 EN-stiliaus CWK guard'ai → LT-stiliaus starter'io guard'ai
#   2) Path remapping: /tasks/ → /docs/requirements/ (PRD) arba /docs/tasks/ (TASK)
#
# Likusius {{VAR}} placeholderius palieka — juos sub'ina setup.sh stack-aware
# atveju.

set -euo pipefail

CWK_SRC="${1:-/Users/auris/Documents/GitHub/claude-workflow-kit/commands}"
DST_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)/.claude/commands/_templates}"

if [ ! -d "$CWK_SRC" ]; then
  echo "ERR: CWK source dir nerastas: $CWK_SRC" >&2
  exit 1
fi

mkdir -p "$DST_DIR"

port_file() {
  local src="$1" dst="$2" name="$3"
  local tmp
  tmp=$(mktemp)
  cp "$src" "$tmp"

  # 1. Agent name remapping (4 EN vardai → LT atitikmenys; risk-assessor lieka).
  # Bash 3.2-suderinama: tiesioginės substitucijos, ne assoc. arrays.
  sed -i.bak \
    -e 's|payment-guardian|payment-guard|g' \
    -e 's|db-guardian|db-migration-guard|g' \
    -e 's|lang-reviewer|language-guard|g' \
    -e 's|file-splitter|file-size-guard|g' \
    "$tmp"
  rm -f "${tmp}.bak"

  # 2. Path remapping — task file refs PIRMA (siauresnis match), tada PRD refs.
  #    `tasks/tasks-prd-{slug}.md` → `docs/tasks/TASK-{slug}.md`
  sed -i.bak -E 's|tasks/tasks-prd-([a-zA-Z0-9_-]+)\.md|docs/tasks/TASK-\1.md|g' "$tmp"
  rm -f "${tmp}.bak"
  #    `tasks/prd-{slug}.md` → `docs/requirements/REQ-{slug}.md`
  sed -i.bak -E 's|tasks/prd-([a-zA-Z0-9_-]+)\.md|docs/requirements/REQ-\1.md|g' "$tmp"
  rm -f "${tmp}.bak"

  # 3. Bare "Location: /tasks/" — per-file (create-prd → requirements, generate-tasks → tasks)
  case "$name" in
    create-prd.md)
      sed -i.bak 's|Location:\*\* `/tasks/`|Location:** `/docs/requirements/`|g' "$tmp"
      sed -i.bak 's|Location:\*\* /tasks/|Location:** /docs/requirements/|g' "$tmp"
      rm -f "${tmp}.bak"
      ;;
    generate-tasks.md)
      sed -i.bak 's|Location:\*\* `/tasks/`|Location:** `/docs/tasks/`|g' "$tmp"
      sed -i.bak 's|Location:\*\* /tasks/|Location:** /docs/tasks/|g' "$tmp"
      rm -f "${tmp}.bak"
      ;;
  esac

  mv "$tmp" "$dst"
}

echo "Port'inama iš: $CWK_SRC"
echo "Tikslas:       $DST_DIR"
echo ""

for src in "$CWK_SRC"/*.md; do
  [ -f "$src" ] || continue
  name=$(basename "$src")
  dst="$DST_DIR/$name"
  port_file "$src" "$dst" "$name"
  src_lines=$(wc -l < "$src")
  dst_lines=$(wc -l < "$dst")
  printf "  %-30s  %4d → %4d eil.\n" "$name" "$src_lines" "$dst_lines"
done

echo ""
echo "Validacija:"

# Pipefail išjungiame šiems patikrinimams — grep be match'ų grąžina 1 (ne klaida).
set +o pipefail

guard_hits=$(grep -rE 'payment-guardian|db-guardian|lang-reviewer|file-splitter' "$DST_DIR" 2>/dev/null || true)
if [ -z "$guard_hits" ]; then
  echo "  ✓ Likę CWK guard vardai: 0"
else
  echo "  ✗ Liko CWK guard referencijų:"
  echo "$guard_hits"
  exit 1
fi

path_hits=$(grep -rE 'tasks/(prd-|tasks-prd-)' "$DST_DIR" 2>/dev/null || true)
if [ -z "$path_hits" ]; then
  echo "  ✓ Likę CWK path'ai: 0"
else
  echo "  ✗ Liko CWK path referencijų:"
  echo "$path_hits"
  exit 1
fi

vars=$(grep -rEho '\{\{[A-Z_]+\}\}' "$DST_DIR" 2>/dev/null | sort -u | tr '\n' ' ' || true)
echo "  ℹ Likę {{VAR}} placeholderiai (juos sub'ins setup.sh): ${vars:-(jokių)}"

set -o pipefail

echo ""
echo "Port'inimas baigtas. Failai: $DST_DIR/"
