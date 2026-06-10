# Symphony × Claude Code — дизайн интеграции (полная поведенческая эквивалентность)

**Дата:** 2026-06-10
**Автор:** d.svrrt@outlook.com (через Claude Code)
**Статус:** черновик на ревью

## 1. Цель

Заставить эталонную реализацию Symphony (Elixir/OTP) выполнять работу по задачам
**через Claude Code** вместо OpenAI Codex, сохранив **полную поведенческую
эквивалентность** всех функций Symphony. «Точь в точь» здесь означает: каждая
наблюдаемая функция (опрос Linear, изоляция воркспейсов, мультитёрн, стрим событий
в web-UI, инструмент `linear_graphql`, обработка ошибок, управление статусами) ведёт
себя идентично. Это **не** означает побайтового повторения JSON-RPC-протокола Codex
app-server — для другого движка это невозможно и не требуется.

### Среда и режим (зафиксировано)

- Платформа исполнения: **WSL2 (Ubuntu)** на машине пользователя (Windows 11).
- Трекер: **Linear** (есть/будет заведён, Personal API key).
- Аутентификация Claude: **подписка (OAuth)**, осторожный режим — стартуем с
  конкурентностью = 1 и аккуратной обработкой лимитов.
- Подход: **A — drop-in бэкенд** `Claude.AppServer` с тем же интерфейсом, что
  `Codex.AppServer`; выбор бэкенда по конфигу `agent.kind`.

## 2. Точка интеграции (исследовано по исходникам)

`SymphonyElixir.AgentRunner` (`elixir/lib/symphony_elixir/agent_runner.ex`) вызывает у
`SymphonyElixir.Codex.AppServer` ровно три функции:

- `start_session(workspace, opts) :: {:ok, session()} | {:error, term()}`
- `run_turn(session, prompt, issue, opts) :: {:ok, map()} | {:error, term()}`
  (opts содержит `:on_message` — колбэк стрима и `:tool_executor`)
- `stop_session(session) :: :ok`

`run_turn` возвращает `{:ok, %{result, session_id, thread_id, turn_id}}`, а через
`on_message` стримит события. `AgentRunner` оборачивает каждое событие в кортеж
`{:codex_worker_update, issue_id, message}` и шлёт оркестратору/подписчикам web-UI.

## 3. Поведенческий контракт для паритета

`Claude.AppServer` обязан воспроизвести всё поведение `Codex.AppServer`:

| Поведение Codex-бэкенда | Реализация в Claude-бэкенде |
|---|---|
| `start_session` валидирует cwd (containment через `PathSafety`), возвращает session-map | Та же валидация (общий вынесенный хелпер); session-map с теми же полями: `thread_id` = UUID сессии, `turn_id`, политики, `metadata`, `workspace`, `worker_host` |
| Мультитёрн: повторные `run_turn`, контекст треда сохраняется | `--session-id <uuid>` на первом turn'е, `--resume <uuid>` на последующих |
| Возврат `{:ok, %{result, session_id, thread_id, turn_id}}` | Тот же кортеж; `session_id` = `"<uuid>-<turn_number>"`, `turn_id` = номер turn'а |
| Стрим событий в `on_message`: `:session_started`, `:turn_completed`, `:turn_failed`, `:turn_cancelled`, `:tool_call_completed`, `:tool_call_failed`, `:unsupported_tool_call`, `:notification`, `:other_message`, `:malformed`, `:approval_auto_approved`, `:turn_input_required`, `:tool_input_auto_answered`, `:approval_required`, `:turn_ended_with_error`, `:startup_failed`; структура сообщения = `metadata ⊕ details ⊕ {event, timestamp}`; `metadata.usage` при наличии | `StreamMapper` маппит события `stream-json` Claude в **тот же** словарь и **ту же** структуру сообщения |
| Авто-approval при `approval_policy="never"` (`auto_approve_requests=true`) | Claude headless с `--permission-mode bypassPermissions` неинтерактивен по природе; ветки approval схлопываются в автономный режим; эквивалентные события (`:approval_auto_approved` и т.п.) эмитятся там, где есть смысловой аналог |
| sandbox-политики (`thread_sandbox`, `turn_sandbox_policy`) | Маппинг в права Claude: `--permission-mode`, `--allowedTools`/`--disallowedTools`, изоляция воркспейсом (cwd + `--add-dir`) |
| Клиентский инструмент `linear_graphql` (raw GraphQL passthrough под auth Symphony) | Тот же инструмент с **идентичной** input-schema через Linear MCP, хостимый из Elixir-приложения (см. §6), переиспользует `DynamicTool.execute` + `Linear.Client` |
| Таймауты `codex.turn_timeout_ms`, `codex.read_timeout_ms` | `claude.turn_timeout_ms`, `claude.read_timeout_ms` с той же семантикой |
| Ошибки: `{:error, {:port_exit, status}}`, `:turn_timeout` | Те же формы ошибок |

**Критично для паритета:** имя сообщения `{:codex_worker_update, …}` и существующие
подписчики web-UI **не переименовываются**. Claude-бэкенд шлёт ровно те же кортежи.

## 4. Архитектура

```
Orchestrator → Workspace → AgentRunner
                              │
                              ▼  (резолвер по agent.kind)
              ┌───────────────────────────────┐
              │ AgentBackend.for(kind)         │  ← НОВОЕ
              └──────────┬──────────┬──────────┘
                         │          │
              Codex.AppServer   Claude.AppServer  ← НОВОЕ
              (без изменений)        │
                                     ▼
                    claude -p --output-format stream-json --verbose
                    --permission-mode bypassPermissions
                    --mcp-config <linear-mcp.json> --strict-mcp-config
                    --allowedTools mcp__linear__linear_graphql[,…]
                    [--session-id <uuid> | --resume <uuid>] [--model …]
                    (cwd = воркспейс задачи; bash -lc локально / SSH удалённо)
```

Вся оркестрация Symphony (опрос Linear, конкурентность, реконсиляция, web-UI,
изоляция воркспейсов, хуки) остаётся без изменений.

## 5. Компоненты

### 5.1 Конфиг (`config/schema.ex`, `config.ex`)
- `agent.kind: codex | claude` (дефолт `codex` — обратная совместимость).
- Новая секция `claude:` (зеркало `codex:`):
  - `bin` (дефолт `claude`)
  - `permission_mode` (дефолт `bypassPermissions`)
  - `model` (опц., напр. `opus`/`sonnet`)
  - `allowed_tools`, `disallowed_tools` (опц.)
  - `turn_timeout_ms`, `read_timeout_ms`
  - `auth: subscription | api_key` (дефолт `subscription`)
  - `max_budget_usd` (опц., страховка)
  - `fallback_model` (опц.)
  - `extra_args` (escape hatch — список доп. аргументов)
- `Config.claude_runtime_settings(workspace, opts)` — аналог `codex_runtime_settings`.

### 5.2 `SymphonyElixir.AgentBackend`
Резолвер: `for(:codex) → Codex.AppServer`, `for(:claude) → Claude.AppServer`. Оба
модуля реализуют один behaviour (`@callback start_session/2`, `run_turn/4`,
`stop_session/1`). `AgentRunner` правится минимально — заменяет жёсткий
`alias … Codex.AppServer` на `backend = AgentBackend.for(Config.settings!().agent.kind)`.

### 5.3 `SymphonyElixir.Claude.AppServer`
- `start_session/2`: общая валидация cwd (вынести `validate_workspace_cwd` в общий
  модуль, напр. `SymphonyElixir.AgentWorkspaceGuard`); генерит UUID; собирает
  session-map; пишет MCP-конфиг для запуска (см. §6). Долгоживущего процесса нет —
  Claude запускается на каждый turn.
- `run_turn/4`: строит argv (см. диаграмму), запускает через переиспользуемый
  `start_port` (`bash -lc` локально / SSH удалённо), читает построчно stdout
  (`stderr_to_stdout`), декодирует JSON, передаёт в `StreamMapper`, эмитит события,
  применяет `turn_timeout_ms`. На первом turn'е — `--session-id`, далее `--resume`.
  Возвращает `{:ok, %{result, session_id, thread_id, turn_id}}`.
- `stop_session/1`: гасит порт (если жив), иначе no-op.

### 5.4 `SymphonyElixir.Claude.StreamMapper` (чистый модуль, ядро паритета)
Маппинг декодированного события `stream-json` → событие(я) Symphony + `metadata`:
- `system`/`init` → захват реального session_id Claude (сверка с нашим `--session-id`);
  событие `:session_started`.
- `assistant` (текст/`tool_use`) → `:notification`; для `tool_use` фиксируем имя.
- `user`/`tool_result`: `is_error=false` → `:tool_call_completed`; `is_error=true` →
  `:tool_call_failed`.
- `result` (`subtype=success`) → `:turn_completed`, `metadata.usage` из `usage` +
  `total_cost_usd`.
- `result` (`subtype` = ошибка/лимит/`error_max_turns`) → `:turn_failed`
  (для лимитов — ретраибл-классификация, см. §7).
- ошибка декодирования → `:malformed`.

### 5.5 Linear MCP (из Elixir-приложения)
HTTP/SSE MCP-эндпоинт в Phoenix-слое (`symphony_elixir_web`), экспонирующий ровно один
инструмент `linear_graphql` с **той же** `inputSchema`, что в `Codex.DynamicTool`.
Обработчик переиспользует `DynamicTool.execute("linear_graphql", args)` +
`Linear.Client` — единый источник правды. `Claude.AppServer` прокидывает агенту
`--mcp-config` с URL этого эндпоинта и `--allowedTools mcp__linear__linear_graphql`.
Авторизация MCP-эндпоинта — локальный токен/loopback-биндинг (эндпоинт слушает только
localhost внутри WSL).

### 5.6 Claude-эквиваленты скиллов (в объёме работы)
Промпт `WORKFLOW.md` ссылается на `.codex/skills/`: `land`, `commit`, `push`, `pull`,
`linear`. Создать Claude-эквиваленты (skills/слэш-команды Claude Code) с тем же
поведением и положить так, чтобы агент Claude их находил в воркспейсе задачи. Промпт
`WORKFLOW.md` при необходимости адаптировать под механизм скиллов Claude, сохранив
смысл шагов.

## 6. Поток данных

`Orchestrator → AgentRunner.run → Workspace.create_for_issue → backend.start_session
→ цикл backend.run_turn(prompt, on_message=codex_message_handler) → StreamMapper
эмитит события → send(recipient, {:codex_worker_update, issue_id, msg}) → web-UI и
оркестратор потребляют без изменений → continue_with_issue? управляет мультитёрном по
статусу Linear → stop_session`. Поток идентичен Codex-пути; различается только источник
событий внутри `run_turn`.

## 7. Ошибки и лимиты (осторожный режим подписки)

- Ненулевой выход процесса → `{:error, {:port_exit, status}}`.
- Таймаут turn'а → `{:error, :turn_timeout}`.
- Не залогинен / нет OAuth-токена → ошибка в stderr → `:startup_failed`.
- **Лимиты подписки**: `result` с подтипом лимита/rate-limit → `:turn_ended_with_error`
  + **ретраибл-ошибка**, чтобы оркестратор делал backoff (а не долбил лимит).
- Дефолты осторожного режима: `agent.max_concurrent_agents: 1`; опционально
  `claude.max_budget_usd` и `claude.fallback_model`.
- **Запрещено**: флаг `--bare` (отключает чтение OAuth/keychain → ломает подписку) и
  `--no-session-persistence` (ломает `--resume`).

## 8. Тестирование

- Юнит `StreamMapper`: записанные фикстуры `stream-json` → проверка точного словаря
  событий Symphony и `metadata.usage`.
- Юнит `Claude.AppServer`: фейковый `claude` (стаб-скрипт, отдающий канонический
  `stream-json`, через настраиваемый `claude.bin`) → session-map, аргументы `--resume`
  при мультитёрне, возвратный кортеж, формы ошибок.
- Юнит паритета `linear_graphql`: та же `inputSchema`; переиспользовать тесты
  `DynamicTool`.
- Контракт: `AgentRunner` на фейковом бэкенде → поток `{:codex_worker_update, …}`
  идентичен по форме Codex-пути.
- Интеграция (вручную, WSL): одна реальная задача Linear end-to-end под подпиской,
  конкурентность = 1.

## 9. Развёртывание (WSL2)

1. Установить WSL2 + Ubuntu; внутри: `git`, `mise`, `claude` (Claude Code CLI).
2. Один раз интерактивно залогинить `claude` подпиской (OAuth) внутри WSL.
3. Завести Linear Personal API key → `LINEAR_API_KEY`.
4. `git clone` форка Symphony; `mise trust && mise install`;
   `mise exec -- mix setup && mix build`.
5. Настроить `WORKFLOW.md`: `agent.kind: claude`, секция `claude:`, при необходимости
   `tracker`/`workspace`.
6. Запуск: `mise exec -- ./bin/symphony ./WORKFLOW.md`.

Рекомендация: вести работу в **собственном форке** репозитория (не в апстриме
openai/symphony), чтобы изменения были версионируемы и обновляемы.

## 10. Явно вне объёма

- Поддержка трекеров кроме Linear.
- Побайтовая совместимость с протоколом Codex app-server.
- Параллелизм > 1 на старте (включается после валидации лимитов подписки).
- Удалённые SSH-воркеры (механизм переиспользуется, но не цель первой итерации).

## 11. Открытые риски

- Условия использования подписки при автоматическом непрерывном прогоне — следить за
  лимитами; при упоре переключаться на `auth: api_key`.
- Точное соответствие схемы событий `stream-json` Claude версии CLI — зафиксировать
  фикстуры под конкретную версию `claude` и проверять при обновлении.
- MCP-эндпоинт из Phoenix добавляет связанность web-слоя и рантайма агента — держать
  на localhost, покрыть тестами авторизации.
