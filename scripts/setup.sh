#!/usr/bin/env bash
# Advanced Vibe Coding Starter. Setup script
# Paleidžia viską, ko reikia, kad dalyvis per 5 min turėtų veikiančią aplinką.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

# Single source of truth versijai. Paliekama .cwk-config.json + CLAUDE.md/README'e.
CWK_VERSION="3.0.1"

info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# Stack auto-detection (port'as iš CWK install.sh:40-147). AUTO mode. Neklausia
# dalyvio jokių klausimų, naudoja default'us pagal aptiktą stack'ą.
detect_project() {
  PROJECT_LANG=""
  PROJECT_FRAMEWORK=""
  PROJECT_DB=""
  PROJECT_PAYMENTS=""
  PROJECT_HOSTING=""
  PROJECT_TEST=""

  # Language / Runtime. Node prioritetas (monorepo Node+Python atveju Node laimi)
  if [ -f "package.json" ]; then
    PROJECT_LANG="node"
    if grep -q '"typescript"' package.json 2>/dev/null; then
      PROJECT_LANG="typescript"
    fi
  elif [ -f "manage.py" ] && { [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; }; then
    PROJECT_LANG="python"
    PROJECT_FRAMEWORK="django"
  elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    PROJECT_LANG="python"
  elif [ -f "go.mod" ]; then
    PROJECT_LANG="go"
  elif [ -f "Cargo.toml" ]; then
    PROJECT_LANG="rust"
  fi

  # Node frameworks. Pagal package.json
  if [ -f "package.json" ] && [ -z "$PROJECT_FRAMEWORK" ]; then
    if grep -q '"next"' package.json; then
      PROJECT_FRAMEWORK="nextjs"
    elif grep -q '"react"' package.json; then
      if grep -q '"vite"' package.json; then
        PROJECT_FRAMEWORK="vite-react"
      else
        PROJECT_FRAMEWORK="react"
      fi
    elif grep -q '"vue"' package.json; then
      PROJECT_FRAMEWORK="vue"
    elif grep -q '"svelte"' package.json; then
      PROJECT_FRAMEWORK="svelte"
    elif grep -q '"express"' package.json; then
      PROJECT_FRAMEWORK="express"
    fi
  fi

  # DB. Pagal package.json arba supabase/ dir
  if [ -f "package.json" ]; then
    if grep -q '"@supabase/supabase-js"' package.json; then
      PROJECT_DB="supabase"
    elif grep -q '"prisma"' package.json; then
      PROJECT_DB="prisma"
    elif grep -q '"drizzle-orm"' package.json; then
      PROJECT_DB="drizzle"
    elif grep -q '"mongoose"' package.json; then
      PROJECT_DB="mongodb"
    elif grep -q '"pg"' package.json; then
      PROJECT_DB="postgres"
    fi
  fi
  if [ -z "$PROJECT_DB" ] && [ -d "supabase" ]; then PROJECT_DB="supabase"; fi

  # Payments
  if [ -f "package.json" ] && grep -q '"stripe"' package.json 2>/dev/null; then PROJECT_PAYMENTS="stripe"; fi

  # Hosting
  if [ -f "vercel.json" ]; then PROJECT_HOSTING="vercel"
  elif [ -f "netlify.toml" ]; then PROJECT_HOSTING="netlify"
  elif [ -f "fly.toml" ]; then PROJECT_HOSTING="fly"
  elif [ -f "Dockerfile" ]; then PROJECT_HOSTING="docker"
  fi

  # Test framework
  if [ -f "package.json" ]; then
    if grep -q '"vitest"' package.json; then PROJECT_TEST="vitest"
    elif grep -q '"jest"' package.json; then PROJECT_TEST="jest"
    elif grep -q '"@playwright/test"' package.json; then PROJECT_TEST="playwright"
    fi
  fi
  if [ -z "$PROJECT_TEST" ]; then
    case "$PROJECT_LANG" in
      python) PROJECT_TEST="pytest" ;;
      go)     PROJECT_TEST="go-test" ;;
      rust)   PROJECT_TEST="cargo-test" ;;
    esac
  fi
}

# Default'ai komandų substitucijai pagal aptiktą stack'ą.
configure_project_auto() {
  COVERAGE_THRESHOLD="80"
  MAX_FILE_LINES="300"

  # UI_LANG: jei .cwk-config.json jau egzistuoja, paveldim ankstesnio paleidimo reikšmę.
  # Kitu atveju default'as `lt`. Dalyvis gali nustatyti rankomis prieš re-paleidžiant setup.sh.
  if [ -f .claude/.cwk-config.json ] && command -v jq >/dev/null 2>&1; then
    UI_LANG=$(jq -r '.config.ui_language // "lt"' .claude/.cwk-config.json 2>/dev/null || echo "lt")
  else
    UI_LANG="lt"
  fi

  case "$PROJECT_LANG" in
    python)
      if [ "$PROJECT_FRAMEWORK" = "django" ]; then
        BUILD_CMD="python manage.py check"
      else
        BUILD_CMD="python -m build"
      fi
      LINT_CMD="ruff check ."
      TEST_CMD="pytest"
      ;;
    rust)
      BUILD_CMD="cargo build"
      LINT_CMD="cargo clippy"
      TEST_CMD="cargo test"
      ;;
    go)
      BUILD_CMD="go build ./..."
      LINT_CMD="golangci-lint run"
      TEST_CMD="go test ./..."
      ;;
    node|typescript)
      BUILD_CMD="npm run build"
      LINT_CMD="npm run lint"
      case "$PROJECT_TEST" in
        vitest)     TEST_CMD="npx vitest run" ;;
        jest)       TEST_CMD="npx jest" ;;
        playwright) TEST_CMD="npx playwright test" ;;
        *)          TEST_CMD="npm run test" ;;
      esac
      ;;
    "")
      # Stack neaptiktas (jokio package.json / manage.py / Cargo.toml / go.mod).
      # Naudojam neutralius placeholder'ius. Dalyvis pats sukonfigūruos.
      # Speciali išimtis: jei egzistuoja `scripts/verify.sh`, jis tampa de facto test komanda.
      BUILD_CMD="(nesukonfigūruota)"
      LINT_CMD="(nesukonfigūruota)"
      if [ -x "scripts/verify.sh" ]; then
        TEST_CMD="bash scripts/verify.sh"
      else
        TEST_CMD="(nesukonfigūruota)"
      fi
      warn "Stack'as neaptiktas. Komandos paliekamos kaip placeholder'iai. Atnaujinkite .claude/.cwk-config.json arba pridėkite stack žymeklį (package.json / manage.py / Cargo.toml / go.mod)."
      ;;
    *)
      # Žinoma kalba, bet bez specifinio palaikymo (pvz. java, ruby).
      BUILD_CMD="(nesukonfigūruota: $PROJECT_LANG)"
      LINT_CMD="(nesukonfigūruota: $PROJECT_LANG)"
      TEST_CMD="(nesukonfigūruota: $PROJECT_LANG)"
      warn "Stack'as '$PROJECT_LANG' nepalaikomas auto-konfigūracijoje. Atnaujinkite .claude/.cwk-config.json rankomis."
      ;;
  esac
}

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
info "Diegiamas MemPalace..."
if command -v mempalace >/dev/null 2>&1; then
  ok "MemPalace jau įdiegtas ($(mempalace --version 2>/dev/null || echo 'versija nenustatyta'))"
else
  # macOS/Linux su Homebrew Python reikalauja pipx (PEP 668). Fallback. Venv.
  if command -v pipx >/dev/null 2>&1; then
    info "Naudojamas pipx..."
    pipx install mempalace || err "pipx install mempalace nepavyko"
    pipx ensurepath >/dev/null 2>&1 || true
    # pipx įdiegus reikia perkrauti PATH einamojoje sesijoje
    export PATH="$HOME/.local/bin:$PATH"
    ok "MemPalace įdiegtas per pipx"
  elif command -v brew >/dev/null 2>&1; then
    warn "pipx nerastas. Bandoma brew install pipx"
    brew install pipx >/dev/null 2>&1 && pipx ensurepath >/dev/null 2>&1 || err "Nepavyko įdiegti pipx per brew"
    export PATH="$HOME/.local/bin:$PATH"
    pipx install mempalace || err "pipx install mempalace nepavyko"
    ok "MemPalace įdiegtas per pipx (naujai)"
  else
    # Fallback: vietinis venv projekto kataloge
    warn "pipx ir brew nerasti. Kuriamas vietinis venv (.venv)"
    python3 -m venv .venv || err "venv kūrimas nepavyko"
    # shellcheck disable=SC1091
    source .venv/bin/activate
    python3 -m pip install --upgrade pip >/dev/null
    python3 -m pip install mempalace || err "pip install mempalace nepavyko venv'e"
    ok "MemPalace įdiegtas į .venv/ (aktyvuokite: source .venv/bin/activate)"
  fi
fi

# --- 3. MemPalace inicializacija ---
# `mempalace init . --yes` sukuria DU artefaktus projekto šaknyje:
#   - mempalace.yaml (config)
#   - entities.json (auto-detected entities)
# Re-run init'ą, jei trūksta bent vieno failo. Tai apsauga nuo partial-failure scenarijaus.
# Pavyzdžiui, procesas mirė tarp dviejų write operacijų. Arba dalyvis pats ištrynė vieną failą.
# `~/.mempalace/` yra globalus palace home, NE projekto init žymeklis.
if [ ! -f "mempalace.yaml" ] || [ ! -f "entities.json" ]; then
  if [ -f "mempalace.yaml" ] || [ -f "entities.json" ]; then
    warn "Aptiktas partial init state. Perinit'inama"
  else
    info "Inicializuojamas MemPalace šiame projekte..."
  fi
  mempalace init . --yes || err "mempalace init nepavyko"
  ok "MemPalace inicializuotas (mempalace.yaml + entities.json)"
else
  ok "MemPalace jau inicializuotas"
fi

# --- 4. Claude Code MCP prijungimas ---
# Aptikti tinkamą python, kuris turi `mempalace` modulį.
# pipx izoliuoja modulį venv'e. Todėl sistemos `python` arba `python3` paprastai jo neturi.
# Tvarka: plain python → pipx environment query → hardcoded pipx paths → .venv → shebang fallback.
detect_mempalace_python() {
  local cmd path candidate pipx_venvs python_subpath

  # 1. Sistemos python (jei mempalace įdiegtas globaliai per pip)
  for cmd in python python3; do
    if command -v "$cmd" >/dev/null 2>&1 && "$cmd" -c "import mempalace" >/dev/null 2>&1; then
      command -v "$cmd"
      return 0
    fi
  done

  # 2. Užklausti pipx, kur jis laiko venv'us (tvarko custom PIPX_HOME)
  if command -v pipx >/dev/null 2>&1; then
    pipx_venvs=$(pipx environment --value PIPX_LOCAL_VENVS 2>/dev/null || true)
    if [ -n "$pipx_venvs" ] && [ -d "$pipx_venvs/mempalace" ]; then
      for python_subpath in "bin/python" "bin/python3" "Scripts/python.exe"; do
        candidate="$pipx_venvs/mempalace/$python_subpath"
        if [ -x "$candidate" ] && "$candidate" -c "import mempalace" >/dev/null 2>&1; then
          printf "%s" "$candidate"
          return 0
        fi
      done
    fi
  fi

  # 3. Hardcoded pipx fallback'ai (jei pipx nepasiekiamas, bet venv'as ten kur tikimasi)
  for path in \
    "$HOME/.local/pipx/venvs/mempalace/bin/python" \
    "$HOME/.local/pipx/venvs/mempalace/Scripts/python.exe" \
    "$HOME/pipx/venvs/mempalace/bin/python" \
    "$HOME/pipx/venvs/mempalace/Scripts/python.exe"; do
    if [ -x "$path" ] && "$path" -c "import mempalace" >/dev/null 2>&1; then
      printf "%s" "$path"
      return 0
    fi
  done

  # 4. Projekto vietinis venv (setup.sh fallback diegimo path'e)
  if [ -x ".venv/bin/python" ] && .venv/bin/python -c "import mempalace" >/dev/null 2>&1; then
    printf "%s/.venv/bin/python" "$(pwd)"
    return 0
  fi

  # 5. Shebang parsing. Paskutinis šansas. Tinkamai apdoroja `#!/usr/bin/env python3`
  # (pirmas token = /usr/bin/env, antras = python3 → resolve per PATH).
  local mp_bin shebang_line first second python_path
  mp_bin=$(command -v mempalace 2>/dev/null) || return 1
  [ -f "$mp_bin" ] || return 1
  shebang_line=$(head -1 "$mp_bin" 2>/dev/null | sed -n 's|^#!\(.*\)|\1|p')
  [ -n "$shebang_line" ] || return 1

  read -r first second _ <<< "$shebang_line"
  case "$first" in
    */env|env)
      [ -n "$second" ] || return 1
      python_path=$(command -v "$second" 2>/dev/null) || return 1
      ;;
    *)
      python_path="$first"
      ;;
  esac

  if [ -x "$python_path" ] && "$python_path" -c "import mempalace" >/dev/null 2>&1; then
    printf "%s" "$python_path"
    return 0
  fi
  return 1
}

info "Prijungiamas MemPalace MCP serveris prie Claude Code..."
MEMPALACE_PY=""
if MEMPALACE_PY=$(detect_mempalace_python); then
  ok "MemPalace python interpretatorius: $MEMPALACE_PY"
else
  warn "Nepavyko aptikti python su 'mempalace' moduliu. MCP registracija praleidžiama"
  MEMPALACE_PY=""
fi

if [ -n "$MEMPALACE_PY" ]; then
  # Pašalinti seną sulūžusią registraciją (jei dalyvis paleido senesnę setup.sh versiją)
  EXISTING_CMD=$(claude mcp get mempalace 2>/dev/null | awk '/^  Command:/ {print $2}' || true)
  if [ -n "$EXISTING_CMD" ] && [ "$EXISTING_CMD" != "$MEMPALACE_PY" ]; then
    warn "Aptikta sena MemPalace MCP registracija ($EXISTING_CMD), perregistruojama"
    claude mcp remove mempalace -s local >/dev/null 2>&1 || true
  fi

  if claude mcp get mempalace >/dev/null 2>&1; then
    ok "MemPalace MCP jau prijungtas"
  else
    if claude mcp add mempalace -- "$MEMPALACE_PY" -m mempalace.mcp_server >/dev/null 2>&1; then
      ok "MemPalace MCP prijungtas"
    else
      warn "claude mcp add nepavyko. Pridėkite rankiniu būdu:"
      warn "  claude mcp add mempalace -- $MEMPALACE_PY -m mempalace.mcp_server"
    fi
  fi
fi

# --- 5. CWK 4-stage pipeline konfigūracija ---
# Aptikti stack'ą → sub'inti komandų templates → įrašyti .cwk-config.json
# → merge'inti Stop hook'ą į settings.json → generuoti .mcp.json.suggested.
info "Aptinkamas projekto stack'as (CWK pipeline)..."
detect_project
configure_project_auto

ok "Stack: lang=${PROJECT_LANG:-(nera)} framework=${PROJECT_FRAMEWORK:-(nera)} db=${PROJECT_DB:-(nera)} payments=${PROJECT_PAYMENTS:-(nera)} hosting=${PROJECT_HOSTING:-(nera)} test=${PROJECT_TEST:-(nera)}"
ok "Default'ai: build=\"$BUILD_CMD\" lint=\"$LINT_CMD\" test=\"$TEST_CMD\""

# Komandų generavimas iš _templates/ (idempotentiškai perrašoma)
TEMPLATES_DIR=".claude/commands/_templates"
COMMANDS_DIR=".claude/commands"

if [ ! -d "$TEMPLATES_DIR" ]; then
  warn "$TEMPLATES_DIR nerastas. CWK pipeline komandos neįdiegiamos"
else
  info "Generuojamos CWK pipeline komandos iš _templates/..."
  count=0
  for tpl in "$TEMPLATES_DIR"/*.md; do
    [ -f "$tpl" ] || continue
    out="$COMMANDS_DIR/$(basename "$tpl")"
    sed \
      -e "s|{{BUILD_CMD}}|${BUILD_CMD}|g" \
      -e "s|{{LINT_CMD}}|${LINT_CMD}|g" \
      -e "s|{{TEST_CMD}}|${TEST_CMD}|g" \
      -e "s|{{COVERAGE_THRESHOLD}}|${COVERAGE_THRESHOLD}|g" \
      -e "s|{{MAX_FILE_LINES}}|${MAX_FILE_LINES}|g" \
      -e "s|{{UI_LANG}}|${UI_LANG}|g" \
      "$tpl" > "$out"
    count=$((count + 1))
  done
  ok "Sugeneruota $count CWK komandų į $COMMANDS_DIR/"

  # Validacija: jokių likusių placeholderių
  set +o pipefail
  remaining=$(grep -rE '\{\{[A-Z_]+\}\}' "$COMMANDS_DIR" --exclude-dir=_templates 2>/dev/null || true)
  set -o pipefail
  if [ -n "$remaining" ]; then
    warn "Liko nesumažinti placeholderiai (perinit'inkite po update'o):"
    echo "$remaining"
  fi
fi

# .cwk-config.json. Single source of truth metadata
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg version "$CWK_VERSION" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg lang "${PROJECT_LANG:-}" \
    --arg fw "${PROJECT_FRAMEWORK:-}" \
    --arg db "${PROJECT_DB:-}" \
    --arg pay "${PROJECT_PAYMENTS:-}" \
    --arg host "${PROJECT_HOSTING:-}" \
    --arg test "${PROJECT_TEST:-}" \
    --arg build "$BUILD_CMD" \
    --arg lint "$LINT_CMD" \
    --arg testcmd "$TEST_CMD" \
    --argjson cov "$COVERAGE_THRESHOLD" \
    --argjson maxl "$MAX_FILE_LINES" \
    --arg uil "$UI_LANG" \
    '{
      version: $version,
      installed_at: $ts,
      starter_identity: {
        memPalace: true,
        memoriki: true,
        karpathy_principles: 4,
        lt_guards: ["payment-guard","db-migration-guard","language-guard","file-size-guard","risk-assessor","security-guard","test-coverage-guard"]
      },
      project: { language: $lang, framework: $fw, database: $db, payments: $pay, hosting: $host, test_framework: $test },
      config: { coverage_threshold: $cov, max_file_lines: $maxl, build_cmd: $build, lint_cmd: $lint, test_cmd: $testcmd, ui_language: $uil }
    }' > .claude/.cwk-config.json
  ok ".cwk-config.json (v$CWK_VERSION) sukurtas"
else
  warn "jq nerastas. .cwk-config.json praleidžiamas. Įdiekite: brew install jq (macOS) arba apt install jq (Linux)"
fi

# Stop hook'as primena po sesijos paleisti build, test, lint komandas.
# Mūsų hook'as pažymimas marker'iu CWK_STOP_HOOK_V1, kad re-run'as atnaujintų tik mūsų įrašą,
# o ne perrašytų dalyvio paties pridėtus Stop hook'us.
if command -v jq >/dev/null 2>&1 && [ -f .claude/settings.json ]; then
  STOP_MARKER="CWK_STOP_HOOK_V1"
  STOP_PROMPT="[${STOP_MARKER}] Prieš baigiant šią sesiją: jei buvo kodo pakeitimų, patvirtinkite, kad 1) Kompiliuoja (${BUILD_CMD}), 2) Testai praeina (${TEST_CMD}), 3) Be lint klaidų (${LINT_CMD}). Jei kuris žingsnis NEbuvo paleistas, įspėkite vartotoją. NEblokuoti, tik priminti."
  TMP_SETTINGS=$(mktemp)
  # Filtruojam senus CWK įrašus (pagal marker'į), tada pridedam šviežią. Kiti dalyvio Stop hook'ai išlieka.
  jq --arg prompt "$STOP_PROMPT" --arg marker "$STOP_MARKER" '
    .hooks = (.hooks // {}) |
    .hooks.Stop = (
      ((.hooks.Stop // []) | map(select(
        (.hooks // []) | map(.prompt // "") | any(contains($marker)) | not
      ))) +
      [{matcher: ".*", hooks: [{type: "prompt", prompt: $prompt, timeout: 10}]}]
    )
  ' .claude/settings.json > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" .claude/settings.json
  ok "Stop hook'as atnaujintas .claude/settings.json (kiti dalyvio hook'ai išsaugoti)"
fi

# .mcp.json.suggested. Filtruotas variantas pagal aptiktą stack'ą
if [ -f .mcp.json.example ] && command -v jq >/dev/null 2>&1; then
  KEEP_FILTER=$(jq -n \
    --arg db "$PROJECT_DB" \
    --arg pay "$PROJECT_PAYMENTS" \
    --arg host "$PROJECT_HOSTING" \
    --arg test "$PROJECT_TEST" \
    '{
      supabase: ($db == "supabase"),
      stripe:   ($pay == "stripe"),
      vercel:   ($host == "vercel"),
      playwright: ($test == "playwright"),
      context7: true,
      "chrome-devtools": true
    }')
  jq --argjson keep "$KEEP_FILTER" \
    '.mcpServers = (.mcpServers | with_entries(select($keep[.key] == true)))' \
    .mcp.json.example > .mcp.json.suggested
  ok ".mcp.json.suggested sugeneruotas (filtruotas pagal stack'ą)"
fi

# --- 6. Hook'ų vykdomumo nustatymas ---
info "Nustatomas pre-commit hook..."
chmod +x .claude/hooks/pre-commit.sh
ok "pre-commit hook +x"

# --- 7. Git pre-commit nuoroda ---
if [ -d ".git" ]; then
  HOOK_PATH=".git/hooks/pre-commit"
  if [ ! -L "$HOOK_PATH" ] && [ ! -f "$HOOK_PATH" ]; then
    ln -s "../../.claude/hooks/pre-commit.sh" "$HOOK_PATH"
    ok "Git pre-commit hook prijungtas"
  else
    ok "Git pre-commit hook jau egzistuoja"
  fi
fi

# --- 8. MCP konfigūracijos priminimas ---
if [ ! -f ".mcp.json" ]; then
  warn "Nepamirškite: cp .mcp.json.example .mcp.json ir įrašykite savo raktus"
fi

# --- 9. Pradinis mine (jei raw/ nėra tuščias) ---
if [ -n "$(ls -A raw/ 2>/dev/null | grep -v .gitkeep || true)" ]; then
  info "raw/ turi failų. Paleidžiama mempalace mine..."
  mempalace mine . || warn "mempalace mine nepavyko. Galite paleisti vėliau"
fi

printf "\n\033[1;32m━━━ SETUP BAIGTAS ━━━\033[0m\n"
echo "Kiti žingsniai:"
echo "  1. cp .mcp.json.example .mcp.json && \$EDITOR .mcp.json"
echo "  2. bash scripts/verify.sh"
echo "  3. claude  # paleiskite Claude Code"
