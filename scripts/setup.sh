#!/usr/bin/env bash
# Advanced Vibe Coding Starter — setup script
# Paleidžia viską, ko reikia, kad dalyvis per 5 min turėtų veikiančią aplinką.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# --- 1. Reikalavimų patikra ---
info "Tikrinama Python 3.9+..."
command -v python3 >/dev/null || err "python3 nerastas. Įdiekite Python 3.9+."
PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
ok "Python $PY_VERSION"

info "Tikrinama Claude Code CLI..."
command -v claude >/dev/null || err "claude CLI nerastas. Diegimas: https://docs.claude.com/claude-code"
ok "Claude Code CLI: $(claude --version 2>/dev/null || echo 'versija nenustatyta')"

info "Tikrinama git..."
command -v git >/dev/null || err "git nerastas."
ok "git $(git --version | awk '{print $3}')"

# --- 2. MemPalace diegimas ---
info "Diegiamas MemPalace (pip install mempalace)..."
if python3 -c "import mempalace" 2>/dev/null; then
  ok "MemPalace jau įdiegtas"
else
  python3 -m pip install --user mempalace || err "Nepavyko įdiegti MemPalace"
  ok "MemPalace įdiegtas"
fi

# --- 3. MemPalace inicializacija ---
if [ ! -d ".mempalace" ]; then
  info "Inicializuojamas MemPalace šiame projekte..."
  mempalace init . || err "mempalace init nepavyko"
  ok "MemPalace inicializuotas (.mempalace/)"
else
  ok "MemPalace jau inicializuotas"
fi

# --- 4. Claude Code MCP prijungimas ---
info "Prijungiamas MemPalace MCP serveris prie Claude Code..."
if claude mcp list 2>/dev/null | grep -q "mempalace"; then
  ok "MemPalace MCP jau prijungtas"
else
  claude mcp add mempalace -- mempalace serve --stdio 2>/dev/null \
    && ok "MemPalace MCP prijungtas" \
    || warn "claude mcp add nepavyko automatiškai — pridėkite rankiniu būdu: claude mcp add mempalace -- mempalace serve --stdio"
fi

# --- 5. Hook'ų vykdomumo nustatymas ---
info "Nustatomas pre-commit hook..."
chmod +x .claude/hooks/pre-commit.sh
ok "pre-commit hook +x"

# --- 6. Git pre-commit nuoroda ---
if [ -d ".git" ]; then
  HOOK_PATH=".git/hooks/pre-commit"
  if [ ! -L "$HOOK_PATH" ] && [ ! -f "$HOOK_PATH" ]; then
    ln -s "../../.claude/hooks/pre-commit.sh" "$HOOK_PATH"
    ok "Git pre-commit hook prijungtas"
  else
    ok "Git pre-commit hook jau egzistuoja"
  fi
fi

# --- 7. MCP konfigūracijos priminimas ---
if [ ! -f ".mcp.json" ]; then
  warn "Nepamirškite: cp .mcp.json.example .mcp.json ir įrašykite savo raktus"
fi

# --- 8. Pradinis mine (jei raw/ nėra tuščias) ---
if [ -n "$(ls -A raw/ 2>/dev/null | grep -v .gitkeep || true)" ]; then
  info "raw/ turi failų — paleidžiama mempalace mine..."
  mempalace mine . || warn "mempalace mine nepavyko — galite paleisti vėliau"
fi

printf "\n\033[1;32m━━━ SETUP BAIGTAS ━━━\033[0m\n"
echo "Kiti žingsniai:"
echo "  1. cp .mcp.json.example .mcp.json && \$EDITOR .mcp.json"
echo "  2. bash scripts/verify.sh"
echo "  3. claude  # paleiskite Claude Code"
