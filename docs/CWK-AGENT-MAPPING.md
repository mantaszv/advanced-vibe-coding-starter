# CWK Agent Mapping

CWK (Claude Workflow Kit) 4-stage pipeline komandos (`/create-prd`, `/generate-tasks`, `/process-tasks`, `/process-tasks-batch`) buvo port'intos į šį starter kit'ą. Originaliai CWK referencijavo savo guard agentus EN-stiliaus pavadinimais. **Šiame starter kit'e tie pavadinimai pakeisti į starter'io 7 LT-stiliaus guard'us** dar port'inimo metu (žr. `scripts/port-cwk.sh`).

Šis failas dokumentuoja mapping'ą, kad dalyvis nebūtų suklaidintas, jei grįš į originalų CWK.

## Guard pavadinimų mapping'as

| CWK originalus (EN) | Starter atitikmuo (LT) | Funkcija |
|---|---|---|
| `payment-guardian` | `payment-guard` | Stripe idempotency, kainų logika, webhook signatures |
| `db-guardian` | `db-migration-guard` | Destruktyvių migracijų blokavimas, rollback validacija |
| `lang-reviewer` | `language-guard` | LT/EN konvencijų atitikimas (UI — LT, kodas — EN) |
| `file-splitter` | `file-size-guard` | ≤ 300 LOC failai, ≤ 50 LOC funkcijos |
| `risk-assessor` | `risk-assessor` | (vienodi) Low/medium/high rizikos vertinimas PR'ams |

## Starter ekstra guardai (CWK neturi)

Starter kit'e dar du guard'ai, kurie CWK pipeline komandose tiesiogiai nereferencijuojami, bet veikia kaip `pre-commit` apsaugos sluoksnis:

| Starter guard | Funkcija |
|---|---|
| `security-guard` | Secret leaks (.env*, raktai), RLS trūkumai, CSP, open redirect, SSRF |
| `test-coverage-guard` | Testų coverage ≥ 80% paveiktiems failams, E2E privalomi kritiniam flow |

## CWK papildomi guard'ai (NEPORTAVAI)

CWK turėjo 8 guard'us. 5 (lentelė viršuje) sumapinti į starter'io LT atitikmenis. Likę 3 **NEbuvo importuoti** — jų funkcionalumas dengia kitus mechanizmus:

| CWK guard'as | Kodėl neportuotas |
|---|---|
| `pre-deploy` | Dengia `scripts/verify.sh` + `.github/workflows/self-heal.yml` |
| `dependency-guardian` | `npm audit` patikrinimai dengia `security-guard`'ą |
| `test-quality-guardian` | Persidengia su starter'io `test-coverage-guard` |

## Skills referencijos

CWK komandos kelis kartus referencijuoja `superpowers:test-driven-development` ir kitus skill'us. Šie skill'ai yra **opcionalūs**:

- Jei dalyvis turi įdiegtą `superpowers` plugin'ą — komandos juos automatiškai naudos.
- Jei ne — komandos veiks be skill'ų pagalbos. Tai NĖRA klaida.

## Path konvencijos

CWK numatė PRD/tasks failų vietas:
- `tasks/prd-{slug}.md` (PRD)
- `tasks/tasks-prd-{slug}.md` (task list)

**Starter kit'e** (port'avimo metu pakeista):
- `docs/requirements/REQ-YYYY-MM-DD-NNN-{slug}.md` (PRD)
- `docs/tasks/TASK-{slug}.md` (task list)

Šios path'ai atitinka starter'io `CLAUDE.md` §2.1 numatytą struktūrą.

## Kaip atnaujinti komandas po CWK release

Jei CWK upstream (`/Users/auris/Documents/GitHub/claude-workflow-kit/commands/`) atnaujinamas:

```bash
bash scripts/port-cwk.sh
# Sugeneruoja .claude/commands/_templates/ iš naujo.
# Patikrina, kad nėra likusių EN guard vardų ar tasks/ path'ų.
# Dalyvio setup.sh perkurs .claude/commands/*.md su nauja stack-aware substitucija.
```

`_templates/` turi būti commit'inta; `.claude/commands/*.md` — `.gitignore`'inami (generuojami).
