#!/usr/bin/env bash
# Starter scaffolding diegimas į egzistuojantį projektą.
# Source'inkite iš setup.sh: source "$STARTER_ROOT/scripts/lib/install.sh"
#
# Reikalauja: STARTER_ROOT (absoliutus starter šaknies kelias),
#             info/ok/warn/err funkcijos iš setup.sh.
#
# Pagrindinė funkcija: install_starter_to(target_dir).
# Politika: esami target failai NEPERRAŠOMI. Konfliktai (CLAUDE.md, .gitignore)
# išsaugomi kaip ${file}.starter, kad dalyvis galėtų sumerge'inti rankomis.

# Kopijuoja katalogo turinį be esamų failų perrašymo.
# Naudoja rsync, nes BSD `cp -Rn` (macOS) grąžina exit 1 kai praleidžia esamą failą,
# o tai su `set -e` tyliai užmuša skriptą. rsync --ignore-existing turi tą patį elgesį,
# bet teisingai signalizuoja success.
_install_dir_safe() {
  local src="$1" dst="$2"
  [ -d "$src" ] || return 0
  if [ ! -d "$dst" ]; then
    cp -R "$src" "$dst"
    return 0
  fi
  command -v rsync >/dev/null || err "rsync nerastas (reikalingas saugiam katalogo merge'inimui)"
  rsync -a --ignore-existing "$src/" "$dst/"
}

# Įterpia starter failo turinį į target failą tarp marker'ių.
#   - Nėra failo                  → sukuriamas su marker'iais ir starter turiniu
#   - Yra failas, nėra marker'ių  → starter blokas pridedamas gale (user turinys nepaliestas)
#   - Yra failas su marker'iais   → blokas tarp marker'ių pakeičiamas (re-run idempotent)
#
# args: src dst mark_open mark_close
#   .gitignore stiliui: mark_open="#",    mark_close=""
#   CLAUDE.md stiliui : mark_open="<!--", mark_close="-->"
_install_file_merged() {
  local src="$1" dst="$2" mark_open="$3" mark_close="$4"
  local label marker_id begin_line end_line block
  label=$(basename "$dst")
  marker_id="STARTER (advanced-vibe-coding-starter)"
  if [ -n "$mark_close" ]; then
    begin_line="${mark_open} >>> ${marker_id} >>> ${mark_close}"
    end_line="${mark_open} <<< ${marker_id} <<< ${mark_close}"
  else
    begin_line="${mark_open} >>> ${marker_id} >>>"
    end_line="${mark_open} <<< ${marker_id} <<<"
  fi
  block=$(printf '%s\n%s\n%s' "$begin_line" "$(cat "$src")" "$end_line")

  if [ ! -f "$dst" ]; then
    printf '%s\n' "$block" > "$dst"
    ok "$label sukurtas su starter bloku"
    return 0
  fi

  if grep -qF -- "$begin_line" "$dst"; then
    awk -v begin="$begin_line" -v end="$end_line" -v block="$block" '
      $0 == begin           { print block; in_block = 1; next }
      in_block && $0 == end { in_block = 0; next }
      !in_block             { print }
    ' "$dst" > "${dst}.tmp" && mv "${dst}.tmp" "$dst"
    ok "$label: starter blokas atnaujintas (user turinys nepaliestas)"
    return 0
  fi

  printf '\n%s\n' "$block" >> "$dst"
  ok "$label: starter blokas pridėtas gale (user turinys nepaliestas)"
  return 0
}

# Skeleton'ai įdiegiami TIK jei target neturi katalogo.
# Naudojama raw/, wiki/, docs/{requirements,tasks}/ — jų turinys yra placeholder'iai.
_install_skeleton() {
  local src="$1" dst="$2"
  [ -d "$src" ] || return 0
  if [ -d "$dst" ]; then
    return 0
  fi
  cp -R "$src" "$dst"
  ok "$(basename "$dst")/ skeleton sukurtas"
}

# Pagrindinė funkcija. Kopijuoja viską, ko reikia, kad target taptų savarankiškas
# starter projektas (galėtų vėliau pats paleisti scripts/setup.sh, scripts/verify.sh).
install_starter_to() {
  local target="$1"
  info "Diegiama starter scaffolding į: $target"

  # 1. .claude/ — agentai, hooks, komandos, _templates, skills, settings.
  # .cwk-config.json bus regeneruotas pagal target stack'ą — pašaliname starter versiją.
  _install_dir_safe "$STARTER_ROOT/.claude" "$target/.claude"
  rm -f "$target/.claude/.cwk-config.json"
  ok ".claude/ įdiegtas (esami failai nepakeisti)"

  # 2. scripts/ — kad target galėtų pats paleisti setup.sh / verify.sh.
  _install_dir_safe "$STARTER_ROOT/scripts" "$target/scripts"
  ok "scripts/ įdiegtas"

  # 3. .mcp.json.example — template MCP serverių konfigūracijai.
  if [ ! -f "$target/.mcp.json.example" ]; then
    cp "$STARTER_ROOT/.mcp.json.example" "$target/.mcp.json.example"
    ok ".mcp.json.example sukurtas"
  fi

  # 4. CLAUDE.md — projekto konstitucija (Karpathy + Memoriki + Guards + MCP).
  # Merge'inama tarp marker'ių. Re-run pakeičia tik bloką, user turinys nepaliestas.
  _install_file_merged "$STARTER_ROOT/CLAUDE.md" "$target/CLAUDE.md" "<!--" "-->"

  # 5. .gitignore — starter įrašai (.mcp.json, .venv, mempalace.yaml ir kt.) tarp marker'ių.
  _install_file_merged "$STARTER_ROOT/.gitignore" "$target/.gitignore" "#" ""

  # 6. Skeleton katalogai (Memoriki + CWK pipeline).
  _install_skeleton "$STARTER_ROOT/raw"  "$target/raw"
  _install_skeleton "$STARTER_ROOT/wiki" "$target/wiki"
  mkdir -p "$target/docs"
  _install_skeleton "$STARTER_ROOT/docs/requirements" "$target/docs/requirements"
  _install_skeleton "$STARTER_ROOT/docs/tasks"        "$target/docs/tasks"

  ok "Scaffolding įdiegtas. Toliau — konfigūracija target'e."
}
