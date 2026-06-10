# Symphony-as-Director — План A: knowledge-каркас + sym-plugin skeleton

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Это инфраструктурный план (файлы/каталоги/git), не Elixir-код; «тесты» здесь — команды проверки с ожидаемым выводом.

**Goal:** Создать durable knowledge-слой `~/sym/` (единый git-репо) и `sym-plugin` (Claude Code плагин со скиллами и skeleton-ролями) — фундамент для Планов B–E. Движок Symphony не трогаем.

**Architecture:** Knowledge-центричная топология (V3 из спеки): `~/sym/{engine→symlink, knowledge(git), workspaces}`. Knowledge содержит `global/`, `projects/<p>/`, `inbox/`, и `sym-plugin/` (плагин с `agents/` = роли-субагенты и `skills/` = перенос наших скиллов). GitHub-репо `sym-knowledge` — облачный бэкап.

**Tech Stack:** WSL2 Ubuntu, git, GitHub API (токен из `.env`), Claude Code plugin format (`manifest.json` + `agents/` + `skills/`), YAML. Всё в WSL по путям `~/sym/...`; правки файлов — через UNC `\\wsl.localhost\Ubuntu\home\dsevruk\...`, git/проверки — через `wsl -d Ubuntu -- bash`.

**Базовые факты окружения:** инженер (engine) Symphony уже лежит в `~/code/symphony` (ветка `claude-integration`). Linear: team `HAP`, проект «Turbo Wedge». Скиллы (commit/push/pull/land/linear/debug) уже есть в `~/code/symphony/.claude/skills/`.

---

## Структура файлов (что создаём)

```
~/sym/
├── engine -> ~/code/symphony            # symlink на существующий движок
├── workspaces/                          # пусто (Symphony workspace.root)
└── knowledge/                           # НОВЫЙ git-репо (origin = GitHub sym-knowledge)
    ├── README.md
    ├── CLAUDE.md                        # память: указатели на global/owner-profile, methods
    ├── global/
    │   ├── owner-profile.md
    │   ├── glossary.md
    │   └── methods/pipeline.md
    ├── projects/turbo-wedge/
    │   ├── project.yaml
    │   ├── overview.md
    │   ├── status.md
    │   ├── decisions/.gitkeep
    │   ├── retrospectives/.gitkeep
    │   └── artifacts/.gitkeep
    ├── inbox/telegram/.gitkeep
    └── sym-plugin/
        ├── manifest.json
        ├── agents/
        │   ├── director.md  analyst.md  architect.md  developer.md
        │   └── reviewer/tech.md  reviewer/product.md
        └── skills/                      # копия из ~/code/symphony/.claude/skills
```

---

## Task 1: Каркас `~/sym/` + symlink движка + workspaces

**Files:** каталоги `~/sym/`, `~/sym/workspaces/`, symlink `~/sym/engine`.

- [ ] **Step 1: Создать каркас**

Run (WSL):
```bash
mkdir -p ~/sym/workspaces
ln -sfn ~/code/symphony ~/sym/engine
ls -la ~/sym
```
Expected: видно `workspaces/` и `engine -> /home/dsevruk/code/symphony`.

- [ ] **Step 2: Проверка симлинка**

Run: `test -f ~/sym/engine/SPEC.md && echo ENGINE_OK`
Expected: `ENGINE_OK`.

---

## Task 2: Инициализировать knowledge-репо со структурой

**Files:** `~/sym/knowledge/` (git), все каталоги + `.gitkeep`.

- [ ] **Step 1: git init + скелет каталогов**

Run (WSL):
```bash
mkdir -p ~/sym/knowledge && cd ~/sym/knowledge
git init -b main
mkdir -p global/methods projects/turbo-wedge/{decisions,retrospectives,artifacts} inbox/telegram sym-plugin/agents/reviewer sym-plugin/skills
touch projects/turbo-wedge/decisions/.gitkeep projects/turbo-wedge/retrospectives/.gitkeep projects/turbo-wedge/artifacts/.gitkeep inbox/telegram/.gitkeep
git config user.name "Дмитрий Севрук" && git config user.email "d.sevruk@rit.va"
find . -path ./.git -prune -o -type d -print | sort
```
Expected: дерево каталогов как в «Структуре файлов».

- [ ] **Step 2: Коммит-плейсхолдер (пустой скелет)**

Run:
```bash
cd ~/sym/knowledge && git add -A && git commit -q -m "chore: init knowledge skeleton" && git log --oneline -1
```
Expected: один коммит.

---

## Task 3: README + CLAUDE.md knowledge-репо

**Files:** Create `~/sym/knowledge/README.md`, `~/sym/knowledge/CLAUDE.md`.

- [ ] **Step 1: README.md**

Содержимое `~/sym/knowledge/README.md`:
```markdown
# Symphony Knowledge

Durable «мозг» Symphony-как-директора: knowledge, решения, ретроспективы и
артефакты ролей. Код здесь НЕ хранится (он в эфемерных воркспейсах). См.
`docs/superpowers/specs/2026-06-10-symphony-director-architecture-design.md`
в репозитории движка.

- `global/` — кросс-проектное (профиль владельца, методики, глоссарий)
- `projects/<p>/` — бизнес-единицы (overview, status, decisions, retrospectives, artifacts)
- `inbox/` — сырой втекающий контекст до дистилляции
- `sym-plugin/` — Claude Code плагин: роли-субагенты (`agents/`) + скиллы (`skills/`)
```

- [ ] **Step 2: CLAUDE.md (память директора)**

Содержимое `~/sym/knowledge/CLAUDE.md`:
```markdown
# Knowledge — память для Claude Code

Это durable knowledge-слой. При работе над проектом считай авторитетными:

- Профиль владельца и стиль: @global/owner-profile.md
- Методика пайплайна (статусы/роли/артефакты): @global/methods/pipeline.md

Правила:
- Артефакты шагов пиши в `projects/<project>/artifacts/<issue>/<NN>-<role>.md`.
- Решения фиксируй ADR-стилем в `projects/<project>/decisions/`.
- Каждый MD начинается с frontmatter: project, type, status, source, date, links.
```

- [ ] **Step 3: Проверка**

Run: `cd ~/sym/knowledge && test -f README.md && test -f CLAUDE.md && echo DOCS_OK`
Expected: `DOCS_OK`.

---

## Task 4: global/ контент (owner-profile, glossary, methods/pipeline)

**Files:** Create `global/owner-profile.md`, `global/glossary.md`, `global/methods/pipeline.md`.

- [ ] **Step 1: owner-profile.md**

`~/sym/knowledge/global/owner-profile.md`:
```markdown
---
type: profile
status: active
date: 2026-06-10
---
# Owner Profile

- Владелец: Dimati (d.svrrt@outlook.com), org HappyAI.
- Среда: локально (WSL), git на диске + GitHub бэкап, solo.
- Подход: сценарный центр (решения выводятся из юзер-сценариев); обязателен
  research текущего состояния перед дизайном; ревью делится на технический и
  продуктовый (проверка интерфейса против всех сценариев).
- Стиль: без переусложнения; артефакты MD на каждом шаге.
```

- [ ] **Step 2: glossary.md**

`~/sym/knowledge/global/glossary.md`:
```markdown
---
type: glossary
status: active
date: 2026-06-10
---
# Glossary

- **Проект** — бизнес-единица; может включать несколько код-репозиториев.
- **Артефакт** — MD-выход шага роли в `artifacts/<issue>/`.
- **Workpad** — живой комментарий в Linear (индекс + статус), ссылается на артефакты.
- **Директор** — верхняя агент-сессия, оркеструющая роли-субагенты.
```

- [ ] **Step 3: methods/pipeline.md** (справочник пайплайна; источник правды для прозы WORKFLOW)

`~/sym/knowledge/global/methods/pipeline.md`:
```markdown
---
type: method
status: active
date: 2026-06-10
---
# Pipeline (статусы Linear ↔ роли ↔ артефакты)

| Статус | Роль | Обязательные артефакты |
|---|---|---|
| Todo | director | 00-brief.md |
| Discovery | analyst | 01a-research-current-state.md, 01b-scenarios.md, 01c-analysis.md |
| Design | architect | 02-design.md (выводится из сценариев) |
| In Progress | developer | код-PR + 03-impl-notes.md |
| Review | reviewer/tech, reviewer/product | 04a-tech-review.md, 04b-product-review.md |
| Waiting | director | NN-blocked-<topic>.md |
| Human Review | director | обновлённый status.md + workpad |
| Done | director | 05-retro.md + retrospectives/ |

Правило итерации: ревьюер либо возвращает статус назад (починка в рамках),
либо заводит новый тикет (`related`/`blockedBy`) для вне-scope.
Гранулярность: одна стадия = один turn.
```

- [ ] **Step 4: Проверка**

Run: `cd ~/sym/knowledge && for f in global/owner-profile.md global/glossary.md global/methods/pipeline.md; do test -f $f || echo "MISSING $f"; done; echo GLOBAL_OK`
Expected: `GLOBAL_OK` без `MISSING`.

---

## Task 5: projects/turbo-wedge — overview, status, project.yaml

**Files:** Create `projects/turbo-wedge/{overview.md,status.md,project.yaml}`.

- [ ] **Step 1: Получить Linear slugId проекта Turbo Wedge**

Run (WSL):
```bash
eval "$(grep '^export LINEAR_API_KEY=' ~/.bashrc | tail -1)"
curl -s -X POST https://api.linear.app/graphql -H "Content-Type: application/json" -H "Authorization: $LINEAR_API_KEY" \
  --data '{"query":"{ projects(first:10){ nodes { name slugId } } }"}'
```
Expected: JSON со `slugId` для «Turbo Wedge». Запомнить значение (далее `<SLUG>`).

- [ ] **Step 2: project.yaml**

`~/sym/knowledge/projects/turbo-wedge/project.yaml` (подставить `<SLUG>` из Step 1; URL код-репо заполнит владелец):
```yaml
project:
  key: turbo-wedge
  name: Turbo Wedge
  linear:
    team: HAP
    project_slug: "<SLUG>"
  repos: []          # заполнить: { name, url, default_branch, test }
  knowledge: projects/turbo-wedge
```

- [ ] **Step 3: overview.md и status.md**

`~/sym/knowledge/projects/turbo-wedge/overview.md`:
```markdown
---
project: turbo-wedge
type: overview
status: draft
date: 2026-06-10
---
# Turbo Wedge — Overview

> Заполнить: что это за продукт, цели, north star, ключевые сценарии.
Образовательный продукт (тесты по предметам — см. HAP-5). Детали — TODO владельца.
```

`~/sym/knowledge/projects/turbo-wedge/status.md`:
```markdown
---
project: turbo-wedge
type: status
status: active
date: 2026-06-10
---
# Turbo Wedge — Status

- Текущий фокус: —
- Активные тикеты: —
- Блокировки: —
(ведёт агент-директор)
```

- [ ] **Step 4: Проверка YAML**

Run (WSL): `python3 -c "import yaml,sys; yaml.safe_load(open('$HOME/sym/knowledge/projects/turbo-wedge/project.yaml')); print('YAML_OK')"`
Expected: `YAML_OK` (если python3-yaml нет — установить `pip3 install pyyaml` или пропустить с пометкой).

---

## Task 6: sym-plugin manifest

**Files:** Create `sym-plugin/manifest.json`.

- [ ] **Step 1: manifest.json**

`~/sym/knowledge/sym-plugin/manifest.json`:
```json
{
  "name": "sym",
  "version": "0.1.0",
  "description": "Symphony director roles (subagents) and workflow skills"
}
```

- [ ] **Step 2: Проверка валидности JSON**

Run (WSL): `python3 -c "import json; json.load(open('$HOME/sym/knowledge/sym-plugin/manifest.json')); print('JSON_OK')"`
Expected: `JSON_OK`.

---

## Task 7: Перенести скиллы в плагин

**Files:** Copy `~/code/symphony/.claude/skills/*` → `~/sym/knowledge/sym-plugin/skills/`.

- [ ] **Step 1: Копирование**

Run (WSL):
```bash
cp -r ~/code/symphony/.claude/skills/. ~/sym/knowledge/sym-plugin/skills/
find ~/sym/knowledge/sym-plugin/skills -name SKILL.md | sort
```
Expected: 6 SKILL.md (commit, debug, land, linear, pull, push) + `land/land_watch.py`.

- [ ] **Step 2: Проверка**

Run: `ls ~/sym/knowledge/sym-plugin/skills | sort`
Expected: `commit debug land linear pull push`.

---

## Task 8: Роли-субагенты (skeleton с реальными промптами)

**Files:** Create `sym-plugin/agents/{director,analyst,architect,developer}.md`, `sym-plugin/agents/reviewer/{tech,product}.md`.

- [ ] **Step 1: director.md**

`~/sym/knowledge/sym-plugin/agents/director.md`:
```markdown
---
name: director
description: Оркеструет пайплайн проекта; читает контекст, ставит задачи ролям, двигает статусы Linear, ведёт status.md и workpad.
tools: Read, Grep, Glob, Bash, Agent
---
Ты — директор проекта. По текущему статусу Linear-тикета выбери роль-субагента
(analyst/architect/developer/reviewer), дай ему задачу, прими его MD-артефакт,
обнови `projects/<project>/status.md` и workpad-комментарий, двинь статус.
Соблюдай методику @global/methods/pipeline.md. Решения — ADR в `decisions/`.
Если работа блокируется внешней зависимостью — оформи `NN-blocked-<topic>.md`,
поставь статус Waiting и опрашивай ответ. Out-of-scope находки — отдельным тикетом.
```

- [ ] **Step 2: analyst.md**

`~/sym/knowledge/sym-plugin/agents/analyst.md`:
```markdown
---
name: analyst
description: Discovery — исследует текущую реализацию, раскладывает все юзер-сценарии, фиксирует требования/критерии/риски.
tools: Read, Grep, Glob, Bash
---
Ты — аналитик. Произведи по порядку:
1. `01a-research-current-state.md` — как СЕЙЧАС реализовано то, что трогаем
   (исследуй реальный код в воркспейсе). Без этого дизайн запрещён.
2. `01b-scenarios.md` — ВСЕ пользовательские сценарии (центр всего дальнейшего).
3. `01c-analysis.md` — требования, критерии приёмки, риски, какие варианты
   рассматриваются/отвергаются.
Пиши файлы в `projects/<project>/artifacts/<issue>/`. Каждый — с frontmatter.
```

- [ ] **Step 3: architect.md**

`~/sym/knowledge/sym-plugin/agents/architect.md`:
```markdown
---
name: architect
description: Design — выводит техническое решение ИЗ пользовательских сценариев.
tools: Read, Grep, Glob, Bash
---
Ты — архитектор. На основе `01b-scenarios.md` и `01c-analysis.md` напиши
`02-design.md`: решение по сценариям (scenario-first), какие репо/аппы затронуты,
интерфейсы, риски, план проверки. Не начинай реализацию.
```

- [ ] **Step 4: developer.md**

`~/sym/knowledge/sym-plugin/agents/developer.md`:
```markdown
---
name: developer
description: In Progress — реализует решение в код-репо, пишет тесты, открывает PR.
tools: Read, Grep, Glob, Edit, Write, Bash
---
Ты — разработчик. Реализуй `02-design.md` в код-репозитории воркспейса; добавь
тесты; используй скиллы commit/push/pull. Напиши `03-impl-notes.md` (что сделано,
как проверено). Открой PR. Соблюдай конвенции репо (CLAUDE.md/AGENTS.md).
```

- [ ] **Step 5: reviewer/tech.md**

`~/sym/knowledge/sym-plugin/agents/reviewer/tech.md`:
```markdown
---
name: reviewer-tech
description: Технический ревьюер — соответствие архитектурным принципам и решению.
tools: Read, Grep, Glob, Bash
---
Ты — технический ревьюер. Проверь изменения против `02-design.md` и арх-принципов:
корректность, тесты, безопасность, простота. Запиши `04a-tech-review.md` с вердиктом
и списком обязательных правок.
```

- [ ] **Step 6: reviewer/product.md**

`~/sym/knowledge/sym-plugin/agents/reviewer/product.md`:
```markdown
---
name: reviewer-product
description: Продуктовый ревьюер — проверяет пользовательский интерфейс против всех сценариев.
tools: Read, Grep, Glob, Bash
---
Ты — продуктовый ревьюер. Зайди в интерфейс, с которым работает пользователь, и
проверь, что для КАЖДОГО сценария из `01b-scenarios.md` выполнены все требования.
Запиши `04b-product-review.md`: по каждому сценарию — pass/fail + что не покрыто.
```

- [ ] **Step 7: Проверка ролей**

Run (WSL): `find ~/sym/knowledge/sym-plugin/agents -name '*.md' | sort`
Expected: 6 файлов (director, analyst, architect, developer, reviewer/tech, reviewer/product).

---

## Task 9: Закоммитить knowledge и создать GitHub-бэкап

**Files:** GitHub repo `HappyAIConsult/sym-knowledge` (private) + push.

- [ ] **Step 1: Коммит всего содержимого**

Run (WSL):
```bash
cd ~/sym/knowledge && git add -A && git commit -q -m "feat: knowledge skeleton, plugin (roles+skills), turbo-wedge project" && git log --oneline
```
Expected: 2-й коммит поверх init.

- [ ] **Step 2: Создать приватный GitHub-репо и запушить (бэкап)**

Run (WSL):
```bash
TOKEN=$(grep '^GITHUB_TOKEN=' /mnt/c/xProjects/s_agent/.env | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r' | xargs)
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/user/repos -d '{"name":"sym-knowledge","private":true}' | grep -E '"full_name"|"message"' | head -2
cd ~/sym/knowledge
git remote add origin "https://x-access-token:${TOKEN}@github.com/HappyAIConsult/sym-knowledge.git"
GIT_TERMINAL_PROMPT=0 git push -u origin main 2>&1 | sed -E 's#x-access-token:[^@]*@#x-access-token:***@#g'
git remote set-url origin https://github.com/HappyAIConsult/sym-knowledge.git
```
Expected: репо создан (`full_name: HappyAIConsult/sym-knowledge`), push прошёл, токен зачищен из remote.

- [ ] **Step 3: Финальная проверка**

Run (WSL):
```bash
cd ~/sym/knowledge && git status --short && git remote -v | grep origin && echo PLAN_A_DONE
```
Expected: рабочее дерево чистое, origin без токена, `PLAN_A_DONE`.

---

## Самопроверка плана (выполнена при написании)

**Покрытие спеки:** §3 топология `~/sym/` → Task 1–2; §4 knowledge-структура+frontmatter → Task 2–5; §6 роли-субагенты (файловые) → Task 8; §6 скиллы в плагине → Task 7; §7 `project.yaml`-манифест → Task 5; «GitHub-бэкап» → Task 9. (Сами движковые инжекты `--plugin-dir`/`--add-dir` и Telegram — План B/D, вне объёма A; проза WORKFLOW — План C.)

**Плейсхолдеры:** `<SLUG>`/`<project>`/`<issue>` — шаблонные подстановки (slug добывается в Task 5 Step 1; репо-URL заполняет владелец — это конфиг-данные, не пропуск плана). Содержимое всех файлов приведено целиком.

**Согласованность:** имена ролей (director/analyst/architect/developer/reviewer-tech/reviewer-product) и пути артефактов (`artifacts/<issue>/<NN>-<role>.md`) совпадают между Task 4 (pipeline.md), Task 8 (роли) и спекой §6. Структура каталогов Task 2 совпадает с разделом «Структура файлов».

## Что дальше (вне Плана A)
- **План B:** `claude.plugin_dir`/`add_dirs` в схему движка + `Claude.AppServer` (TDD) — чтобы роли/скиллы реально инжектились в воркспейс.
- **План C:** `WORKFLOW.turbo-wedge.md` с прозой пайплайна.
- **План D:** Telegram-инструмент (`Claude.TelegramMcp`).
