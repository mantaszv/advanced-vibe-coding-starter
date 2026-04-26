# CLAUDE.md. Projekto smegenys (v3.0.1)

Šis failas yra pirmas dalykas, kurį Claude Code skaito prieš kiekvieną užduotį.

> **v3.0.1 naujovė.** Integruota CWK 4 etapų pipeline (`/create-prd`, `/generate-tasks`, `/process-tasks`, `/process-tasks-batch`) ir automatinis stack'o aptikimas (Node, Python, Django, Rust, Go). Žr. §3.5.

---

## 1. Karpathy principai (visada aktyvūs)

LLM klaidų antidotas. Kiekvienas principas. Privalomas.

### 1.1 Think Before Coding
- Prieš rašant kodą. Deklaruok prielaidas. Jei nežinai, **klausk**.
- Dvi interpretacijos. Pateik abi, nepasirink tyliai.
- Matai paprastesnį sprendimą. Pasakyk. Ne bijok nesutikti.
- Nesupranti. Sustok. Įvardink, kas neaišku. Klausk.

### 1.2 Simplicity First
- Minimalus kodas, sprendžiantis užduotį. Nieko spekuliacinio.
- Jokių "ateities lankstumo" abstrakcijų vienetiniam kodui.
- Jokio error handling'o neįmanomiems scenarijams.
- 200 eilutės, kai užtenka 50. **Perrašai**.

### 1.3 Surgical Changes
- Lieti tik tai, ko reikia. Esamo stiliaus nelaužyk.
- Nerefaktorink gretimo kodo "prabėgomis".
- Tavo pakeitimai sukūrė orfanų (nebenaudojami imports, vars). pašalink TIK savuosius.
- Ne tavo mesas. Palik ramybėje. Paminėk, bet netrink.

### 1.4 Goal-Driven Execution
Kiekviena užduotis. Verifikuojamas tikslas:
- "Pridėk validaciją" → "Parašyk testus neteisingam įvedimui, tada juos praverčiam"
- "Pataisyk bug'ą" → "Parašyk testą, kuris reprodukuoja bug'ą, tada pravertį"
- "Refactor X" → "Testai pravertinti prieš ir po"

---

## 2. Projekto kontekstas

**Projekto tipas:** <!-- pvz., Next.js 15 + Supabase + Stripe -->
**Tech stack:** <!-- TypeScript, Tailwind, shadcn/ui, Playwright -->
**Production URL:** <!-- https://example.com -->
**Staging URL:** <!-- https://staging.example.com -->

### 2.1 Direktorijos
- `src/`. aplikacijos kodas
- `supabase/migrations/`. DB migracijos (niekada netrink be rollback!)
- `docs/requirements/`. REQ-*.md failai (Pipeline fazė 1)
- `docs/tasks/`. TASK-*.md failai (Pipeline fazė 2)
- `wiki/`. Memoriki generuojama žinių bazė (**neredaguok rankomis**)
- `raw/`. šaltiniai Memoriki'ui ingestuoti

### 2.2 Konvencijos
- **Komitai**: `feat|fix|chore|docs|refactor: <subject>` + DoD eilutė
- **Failų dydis**: ≤ 300 LOC/failas, ≤ 50 LOC/funkcija
- **Testai**: Vitest (unit) + Playwright (E2E), coverage ≥ 80% paveiktiems failams
- **Migracijos**: visada su `UP` + `DOWN` (rollback)

---

## 3. Memoriki wiki protokolas

Kai naudotojas prašo "atnaujink wiki" arba sesijos pabaigoje:

### 3.1 Šaltinių įkėlimas (`raw/*.md` → `wiki/`)
1. Skaitai naujus failus iš `raw/`
2. Suskaičiai entities (žmonės, kompanijos) → `wiki/entities/<name>.md`
3. Suskaičiai concepts (idėjos, frameworks) → `wiki/concepts/<concept>.md`
4. Sukuri šaltinio santrauką → `wiki/sources/<source-id>.md`
5. Atnaujini `wiki/index.md` ir `wiki/log.md`

### 3.2 Užklausos metu
1. Skaitai `wiki/index.md`, kad rastum relevant puslapius
2. Sintezuoji atsakymą su citations (`[[wiki/entities/alice.md]]`)
3. Jei rastas konfliktas tarp šaltinių. Pažymi `wiki/synthesis/conflicts.md`

### 3.3 Sesijos pabaigoje
1. `mempalace mine .`. reindeksuoti naują turinį
2. `wiki/log.md` → pridedamas įrašas: kas buvo ingestuota, ką sužinojo

### 3.4 Lint (kai naudotojas prašo "patikrink wiki" arba "wiki health check")
1. Surasti **kontradikcijas** tarp puslapių (vienas šaltinis sako X, kitas non-X). žymėti `wiki/synthesis/conflicts.md`
2. Identifikuoti **orphan puslapius**. neturi nė vienos įeinančios `[[wiki-link]]` nuorodos
3. Rasti **concepts paminėtus tekste, bet neturinčius savo puslapio** → kandidatai į `wiki/concepts/`
4. Patikrinti **stale informaciją** (frontmatter `updated` > 90 dienų ir tema sparčiai keičiasi)
5. Pasiūlyti **naujus šaltinius**, kurie užpildytų žinių spragas
6. Įrašyti lint pass į `wiki/log.md`

**Wiki frontmatter privalomas** (atitinka upstream Memoriki spec. Leidžia Obsidian-style backlinks):
```yaml
---
title: Page Title
type: entity | concept | source | synthesis
sources: [raw/paper-001.md]
related: [[wiki/concepts/foo]], [[wiki/entities/bar]]
created: 2026-04-25
updated: 2026-04-25
---
```

**Atvaizdai:** įmesti į `raw/assets/` (LLM nemodifikuoja). Wiki puslapiuose nuorodos relatyvios: `![](../../raw/assets/diagram.png)`.

### 3.5 CWK 4 etapų pipeline (v3.0.1)

Šis starter kit integruoja [CWK](https://github.com/ponasObuolys/claude-workflow-kit) feature kūrimo pipeline su keturiais etapais. Komandos pasiekiamos kataloge `.claude/commands/`. Jas sugeneruoja `setup.sh` iš `_templates/`, pakeisdamas placeholderius pagal aptiktą stack'ą.

| Komanda | Paskirtis | Output |
|---|---|---|
| `/create-prd "<aprašymas>"` | Sugeneruoja PRD su Orchestration Hints ir Risk Assessment skiltimis | `docs/requirements/REQ-YYYY-MM-DD-NNN-{slug}.md` |
| `/generate-tasks <REQ-failas>` | Iš PRD sukuria užduotis su pagrindinėmis bei sub-užduotimis ir Orchestration blokais | `docs/tasks/TASK-{slug}.md` |
| `/process-tasks <TASK-failas>` | Vykdo vieną sub-užduotį ir sustoja patvirtinimui | užduočių progresas faile |
| `/process-tasks-batch <TASK-failas>` | Vykdo visą pagrindinę užduotį be sustojimo | užduočių progresas faile |
| `/status` | Rodo užduočių progresą | stdout |

**Guard'ų atitikmenys.** CWK pipeline kviečia guard'us pagal LT vardus iš `.claude/agents/`, ne CWK originalius EN vardus. Pilną lentelę rasite `docs/CWK-AGENT-MAPPING.md`.

**Konfigūracija.** `.claude/.cwk-config.json` (auto-generated) saugo aptiktą stack'ą ir komandų default'us (`build_cmd`, `lint_cmd`, `test_cmd`). Pakartotinis `setup.sh` paleidimas atnaujina šį failą pagal naujausią stack'ą.

---

## 4. Guard agentai (.claude/agents/)

Prieš commit. Pre-commit hook iškviečia visus guardus. Jei bent vienas grąžina `BLOCKED`. commit sustabdomas.

| Agentas | Trigger |
|---|---|
| `db-migration-guard` | Keičiasi `supabase/migrations/**` |
| `payment-guard` | Keičiasi `**/stripe/**` ar `**/checkout/**` |
| `risk-assessor` | Kiekvienas PR (išduoda low/medium/high) |
| `language-guard` | `**/*.tsx`, `**/*.md` (LT/EN konvencijos) |
| `file-size-guard` | Bet koks `src/**/*` |
| `test-coverage-guard` | Kiekvienas PR su logic pakeitimais |
| `security-guard` | `.env*`, `supabase/**`, auth kodas |

---

## 5. MCP serveriai (iš `.mcp.json`)

Kai užduotis liečia DB. Naudok **Supabase** MCP. Kai mokėjimus. **Stripe**. Kai dokumentaciją. **Context7** (ne atmintį!). Naršyklės testai. **Playwright** arba **Chrome DevTools**. Deploy. **Vercel**. Atmintis tarp sesijų. **MemPalace**.

---

## 6. Verifikacija prieš commit'ą

Privalomai kiekvienam PR. Konkrečios komandos priklauso nuo stack'o, kurį aptiko `setup.sh` ir įrašė į `.claude/.cwk-config.json` (`build_cmd`, `lint_cmd`, `test_cmd`).

**Pavyzdžiai pagal stack'ą:**

| Stack'as | build | lint | test |
|---|---|---|---|
| Next.js, Vite-React | `npm run build` | `npm run lint` | `npx vitest run` arba `npm run test` |
| Django | `python manage.py check` | `ruff check .` | `pytest` |
| Rust | `cargo build` | `cargo clippy` | `cargo test` |
| Go | `go build ./...` | `golangci-lint run` | `go test ./...` |

**Privalomas paskutinis žingsnis** (visiems stack'ams):

```bash
.claude/hooks/pre-commit.sh  # Guard agentų apklausa
```

Jei bet kuris žingsnis nepavyksta, grįžkite atgal, ištaisykite ir paleiskite iš naujo.

---

## 7. Kada kreiptis į naudotoją

- Žr. 1.1. jei yra dvi interpretacijos.
- Jei Guard Gap Analysis rodo "nė vienas guardas nesustabdytų klaidos šiame feature'e".
- Jei tektų pažeisti 1.3 (chirurginiai pakeitimai). pvz., liesti 10+ failų, kurie nėra scope'e.
- Jei reikalavimas prieštarauja production duomenims (pvz., "pridėk kolonėlę, bet migracija bus destruktyvi").

---

**Šis failas = projekto konstitucija. Jei kyla konfliktas tarp šio failo ir ad-hoc prompt'o. Šis failas pirmesnis.**
