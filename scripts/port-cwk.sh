#!/usr/bin/env bash
# Port CWK 4-stage pipeline commands → starter kit's _templates/.
# VIENKARTINIS skriptas. Paleidžiamas mano lokaliai prieš commit'inant
# `.claude/commands/_templates/`. Dalyviams jis NESVARBUS.
#
# Atlieka 2 transformacijų grupes:
#   1) Agent name remapping: 5 EN-stiliaus CWK guard'ai → LT-stiliaus starter'io guard'ai
#   2) Path remapping: /tasks/ → /docs/requirements/ (PRD) arba /docs/tasks/ (TASK)
#
# Likusius {{VAR}} placeholderius palieka. Juos sub'ina setup.sh stack-aware
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
  # Bash 3.2-suderinama: tiesioginės substitucijos, ne assoc. Arrays.
  sed -i.bak \
    -e 's|payment-guardian|payment-guard|g' \
    -e 's|db-guardian|db-migration-guard|g' \
    -e 's|lang-reviewer|language-guard|g' \
    -e 's|file-splitter|file-size-guard|g' \
    "$tmp"
  rm -f "${tmp}.bak"

  # 2. Path remapping. Task file refs PIRMA (siauresnis match), tada PRD refs.
  #    `tasks/tasks-prd-{slug}.md` → `docs/tasks/TASK-{slug}.md`
  sed -i.bak -E 's|tasks/tasks-prd-([a-zA-Z0-9_-]+)\.md|docs/tasks/TASK-\1.md|g' "$tmp"
  rm -f "${tmp}.bak"
  #    `tasks/prd-{slug}.md` → `docs/requirements/REQ-{slug}.md`
  sed -i.bak -E 's|tasks/prd-([a-zA-Z0-9_-]+)\.md|docs/requirements/REQ-\1.md|g' "$tmp"
  rm -f "${tmp}.bak"

  # 3. Bare path referencijos. Per failą skirtingai (create-prd rašo į requirements, generate-tasks į tasks).
  case "$name" in
    create-prd.md)
      sed -i.bak \
        -e 's|`/tasks/`|`docs/requirements/`|g' \
        -e 's|`prd-\[feature-name\]\.md`|`REQ-YYYY-MM-DD-NNN-[feature-name].md` (where YYYY-MM-DD is today, NNN is next 3-digit number in docs/requirements/)|g' \
        -e 's|inside the `/tasks` directory|inside the `docs/requirements/` directory|g' \
        -e 's|inside the /tasks directory|inside the docs/requirements/ directory|g' \
        "$tmp"
      rm -f "${tmp}.bak"
      ;;
    generate-tasks.md)
      sed -i.bak \
        -e 's|`/tasks/`|`docs/tasks/`|g' \
        -e 's|`tasks-prd-\[feature-name\]\.md`|`TASK-[feature-name].md`|g' \
        -e 's|inside the `/tasks` directory|inside the `docs/tasks/` directory|g' \
        -e 's|inside the /tasks directory|inside the docs/tasks/ directory|g' \
        "$tmp"
      rm -f "${tmp}.bak"
      ;;
    process-tasks.md|process-tasks-batch.md|status.md)
      sed -i.bak \
        -e 's|`/tasks/`|`docs/tasks/`|g' \
        -e 's|`tasks-\*\.md`|`TASK-*.md`|g' \
        -e 's|in the `/tasks` directory|in the `docs/tasks/` directory|g' \
        -e 's|in the /tasks directory|in the docs/tasks/ directory|g' \
        "$tmp"
      rm -f "${tmp}.bak"
      ;;
  esac

  # 4. Skill referencijos pažymimos kaip optional, kad dalyvis suprastų: jei plugin neįdiegtas, skip.
  sed -i.bak -E 's|(superpowers:[a-z-]+)|\1 (optional)|g' "$tmp"
  rm -f "${tmp}.bak"

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

# Pipefail išjungiame šiems patikrinimams. Grep be match'ų grąžina 1 (ne klaida).
set +o pipefail

guard_hits=$(grep -rE 'payment-guardian|db-guardian|lang-reviewer|file-splitter' "$DST_DIR" 2>/dev/null || true)
if [ -z "$guard_hits" ]; then
  echo "  ✓ Likę CWK guard vardai: 0"
else
  echo "  ✗ Liko CWK guard referencijų:"
  echo "$guard_hits"
  exit 1
fi

path_hits=$(grep -rE 'tasks/(prd-|tasks-prd-)|^[^a-zA-Z]/tasks[^a-zA-Z]|`/tasks/`|prd-\[feature-name\]|tasks-prd-\[feature-name\]' "$DST_DIR" 2>/dev/null || true)
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
