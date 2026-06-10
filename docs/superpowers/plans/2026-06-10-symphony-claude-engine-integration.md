# Symphony × Claude Code — План 1: движковая интеграция

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заставить Symphony выполнять задачи через Claude Code вместо Codex с полной поведенческой эквивалентностью, выбираемой конфигом `agent.kind: claude`.

**Architecture:** Drop-in бэкенд `Claude.AppServer` реализует тот же интерфейс, что `Codex.AppServer` (через общий behaviour `AgentBackend`). `AgentRunner` выбирает бэкенд по конфигу. Claude запускается headless (`claude -p --output-format stream-json`) на каждый turn с `--resume` для мультитёрна; события `stream-json` маппятся в существующий словарь событий Symphony чистым модулем `StreamMapper`. Инструмент `linear_graphql` отдаётся агенту через MCP-эндпоинт, хостимый в Phoenix-слое и переиспользующий `Codex.DynamicTool`.

**Tech Stack:** Elixir/OTP, Ecto (валидация конфига), Phoenix/Bandit (web/MCP), Jason, ExUnit (inline-моки через opts, фейковые бинари-скрипты). Claude Code CLI. Запуск тестов: `mise exec -- mix test`.

**Базовый каталог работы:** `C:\xProjects\s_agent\symphony\elixir` (ветка `claude-integration`). Все пути ниже — относительно него, если не сказано иное.

**Вне объёма этого плана (см. План 2):** порт Codex-скиллов `.codex/skills/{land,commit,push,pull,linear}` на Claude.

---

## Структура файлов

**Создаём:**
- `lib/symphony_elixir/uuid.ex` — генератор UUIDv4 (нет в зависимостях).
- `lib/symphony_elixir/agent_backend.ex` — behaviour + резолвер бэкенда по `agent.kind`.
- `lib/symphony_elixir/agent_workspace_guard.ex` — общая валидация cwd (вынесена из `Codex.AppServer`).
- `lib/symphony_elixir/claude/stream_mapper.ex` — чистый маппинг событий `stream-json` → словарь Symphony.
- `lib/symphony_elixir/claude/app_server.ex` — Claude-бэкенд (start_session/run_turn/stop_session/run).
- `lib/symphony_elixir/claude/linear_mcp.ex` — чистый обработчик MCP JSON-RPC (initialize/tools/list/tools/call → `DynamicTool`).
- `lib/symphony_elixir_web/controllers/mcp_controller.ex` — тонкий контроллер поверх `LinearMcp`.
- Тесты: `test/symphony_elixir/uuid_test.exs`, `test/symphony_elixir/agent_backend_test.exs`, `test/symphony_elixir/agent_workspace_guard_test.exs`, `test/symphony_elixir/claude/stream_mapper_test.exs`, `test/symphony_elixir/claude/app_server_test.exs`, `test/symphony_elixir/claude/linear_mcp_test.exs`.

**Модифицируем:**
- `lib/symphony_elixir/config/schema.ex` — поле `agent.kind`, новая секция `Claude`.
- `lib/symphony_elixir/config.ex` — `agent_kind/0`, `claude_runtime_settings/2`.
- `lib/symphony_elixir/codex/app_server.ex` — `@behaviour AgentBackend`; делегировать валидацию cwd в `AgentWorkspaceGuard`.
- `lib/symphony_elixir/agent_runner.ex` — `alias` → резолвер бэкенда (строки 7, 91, 95, 104).
- `lib/symphony_elixir_web/router.ex` — маршрут `POST /mcp`.
- `test/support/test_support.exs` — overrides `agent_kind`, `claude_*` + рендер секции `claude:`.
- `WORKFLOW.md` (корень репо) и/или `elixir/WORKFLOW.md` — пример секции `agent.kind: claude` + `claude:` (финальная задача).

Каждая задача — самодостаточный набор изменений, проходящий тесты и коммит.

---

## Task 1: UUIDv4 helper

`--session-id` Claude требует валидный UUID; библиотеки в проекте нет — генерим из `:crypto`.

**Files:**
- Create: `lib/symphony_elixir/uuid.ex`
- Test: `test/symphony_elixir/uuid_test.exs`

- [ ] **Step 1: Написать падающий тест**

```elixir
# test/symphony_elixir/uuid_test.exs
defmodule SymphonyElixir.UUIDTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.UUID

  test "v4/0 returns a canonical lowercase UUID v4 string" do
    uuid = UUID.v4()

    assert uuid =~
             ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  end

  test "v4/0 produces unique values" do
    refute UUID.v4() == UUID.v4()
  end
end
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/uuid_test.exs`
Expected: FAIL — `module SymphonyElixir.UUID is not available`.

- [ ] **Step 3: Реализовать модуль**

```elixir
# lib/symphony_elixir/uuid.ex
defmodule SymphonyElixir.UUID do
  @moduledoc """
  Минимальный генератор UUID версии 4 (без внешних зависимостей).
  """

  @spec v4() :: String.t()
  def v4 do
    <<u0::48, _ver::4, u1::12, _var::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<a::32, b::16, c::16, d::16, e::48>> = <<u0::48, 4::4, u1::12, 2::2, u2::62>>

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end
end
```

- [ ] **Step 4: Запустить тест — убедиться, что проходит**

Run: `mise exec -- mix test test/symphony_elixir/uuid_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Коммит**

```bash
git add lib/symphony_elixir/uuid.ex test/symphony_elixir/uuid_test.exs
git commit -m "feat: add UUIDv4 helper for Claude session ids"
```

---

## Task 2: Вынести валидацию workspace cwd в общий guard

`Codex.AppServer.validate_workspace_cwd/2` (app_server.ex:147-187) нужна и Claude-бэкенду. Выносим без изменения поведения (DRY).

**Files:**
- Create: `lib/symphony_elixir/agent_workspace_guard.ex`
- Modify: `lib/symphony_elixir/codex/app_server.ex:147-187` (заменить тело на делегирование)
- Test: `test/symphony_elixir/agent_workspace_guard_test.exs`

- [ ] **Step 1: Написать падающий тест**

```elixir
# test/symphony_elixir/agent_workspace_guard_test.exs
defmodule SymphonyElixir.AgentWorkspaceGuardTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.AgentWorkspaceGuard

  setup do
    root = Path.join(System.tmp_dir!(), "symphony-guard-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    {:ok, root: root}
  end

  test "accepts a directory inside the workspace root", %{root: root} do
    ws = Path.join(root, "ENG-1")
    File.mkdir_p!(ws)
    assert {:ok, canonical} = AgentWorkspaceGuard.validate(ws, root, nil)
    assert String.ends_with?(canonical, "ENG-1")
  end

  test "rejects the workspace root itself", %{root: root} do
    assert {:error, {:invalid_workspace_cwd, :workspace_root, _}} =
             AgentWorkspaceGuard.validate(root, root, nil)
  end

  test "rejects a path outside the workspace root", %{root: root} do
    outside = Path.join(System.tmp_dir!(), "symphony-outside-#{System.unique_integer([:positive])}")
    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf(outside) end)

    assert {:error, {:invalid_workspace_cwd, :outside_workspace_root, _, _}} =
             AgentWorkspaceGuard.validate(outside, root, nil)
  end

  test "passes remote workspaces through with basic validation" do
    assert {:ok, "/remote/ws"} = AgentWorkspaceGuard.validate("/remote/ws", "/ignored", "host-1")

    assert {:error, {:invalid_workspace_cwd, :empty_remote_workspace, "host-1"}} =
             AgentWorkspaceGuard.validate("   ", "/ignored", "host-1")
  end
end
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/agent_workspace_guard_test.exs`
Expected: FAIL — `module SymphonyElixir.AgentWorkspaceGuard is not available`.

- [ ] **Step 3: Реализовать guard (перенос логики из app_server.ex)**

```elixir
# lib/symphony_elixir/agent_workspace_guard.ex
defmodule SymphonyElixir.AgentWorkspaceGuard do
  @moduledoc """
  Общая проверка того, что рабочая директория агента содержится внутри
  настроенного workspace root. Вынесена из Codex.AppServer для переиспользования
  Claude-бэкендом.
  """

  alias SymphonyElixir.PathSafety

  @spec validate(Path.t(), Path.t(), String.t() | nil) :: {:ok, Path.t()} | {:error, term()}
  def validate(workspace, workspace_root, nil) when is_binary(workspace) and is_binary(workspace_root) do
    expanded_workspace = Path.expand(workspace)
    expanded_root = Path.expand(workspace_root)
    expanded_root_prefix = expanded_root <> "/"

    with {:ok, canonical_workspace} <- PathSafety.canonicalize(expanded_workspace),
         {:ok, canonical_root} <- PathSafety.canonicalize(expanded_root) do
      canonical_root_prefix = canonical_root <> "/"

      cond do
        canonical_workspace == canonical_root ->
          {:error, {:invalid_workspace_cwd, :workspace_root, canonical_workspace}}

        String.starts_with?(canonical_workspace <> "/", canonical_root_prefix) ->
          {:ok, canonical_workspace}

        String.starts_with?(expanded_workspace <> "/", expanded_root_prefix) ->
          {:error, {:invalid_workspace_cwd, :symlink_escape, expanded_workspace, canonical_root}}

        true ->
          {:error, {:invalid_workspace_cwd, :outside_workspace_root, canonical_workspace, canonical_root}}
      end
    else
      {:error, {:path_canonicalize_failed, path, reason}} ->
        {:error, {:invalid_workspace_cwd, :path_unreadable, path, reason}}
    end
  end

  def validate(workspace, _workspace_root, worker_host)
      when is_binary(workspace) and is_binary(worker_host) do
    cond do
      String.trim(workspace) == "" ->
        {:error, {:invalid_workspace_cwd, :empty_remote_workspace, worker_host}}

      String.contains?(workspace, ["\n", "\r", <<0>>]) ->
        {:error, {:invalid_workspace_cwd, :invalid_remote_workspace, worker_host, workspace}}

      true ->
        {:ok, workspace}
    end
  end
end
```

- [ ] **Step 4: Делегировать из Codex.AppServer**

В `lib/symphony_elixir/codex/app_server.ex` заменить обе приватные функции `validate_workspace_cwd/2` (строки 147-187) на:

```elixir
  defp validate_workspace_cwd(workspace, nil) when is_binary(workspace) do
    SymphonyElixir.AgentWorkspaceGuard.validate(workspace, Config.settings!().workspace.root, nil)
  end

  defp validate_workspace_cwd(workspace, worker_host)
       when is_binary(workspace) and is_binary(worker_host) do
    SymphonyElixir.AgentWorkspaceGuard.validate(workspace, Config.settings!().workspace.root, worker_host)
  end
```

(alias `SymphonyElixir.PathSafety` в app_server.ex больше не нужен для этих функций, но он используется в других местах — оставить как есть.)

- [ ] **Step 5: Запустить тесты guard + существующие тесты AppServer (регрессия)**

Run: `mise exec -- mix test test/symphony_elixir/agent_workspace_guard_test.exs test/symphony_elixir/app_server_test.exs`
Expected: PASS — новые тесты guard зелёные, существующие тесты Codex.AppServer не сломаны.

- [ ] **Step 6: Коммит**

```bash
git add lib/symphony_elixir/agent_workspace_guard.ex lib/symphony_elixir/codex/app_server.ex test/symphony_elixir/agent_workspace_guard_test.exs
git commit -m "refactor: extract workspace cwd validation into AgentWorkspaceGuard"
```

---

## Task 3: Конфиг — поле `agent.kind` и секция `claude:`

**Files:**
- Modify: `lib/symphony_elixir/config/schema.ex` (Agent schema:128-157; новая `Claude`-секция; embeds:270-280; cast_embed:360-372)
- Test: `test/symphony_elixir/config_claude_test.exs` (Create)

- [ ] **Step 1: Написать падающий тест**

```elixir
# test/symphony_elixir/config_claude_test.exs
defmodule SymphonyElixir.ConfigClaudeTest do
  use SymphonyElixir.TestSupport

  test "agent.kind defaults to codex and is overridable to claude" do
    write_workflow_file!(workflow_path())
    assert Config.settings!().agent.kind == "codex"

    write_workflow_file!(workflow_path(), agent_kind: "claude")
    assert Config.settings!().agent.kind == "claude"
  end

  test "claude section parses with sensible defaults" do
    write_workflow_file!(workflow_path(), agent_kind: "claude")
    claude = Config.settings!().claude

    assert claude.bin == "claude"
    assert claude.permission_mode == "bypassPermissions"
    assert claude.auth == "subscription"
    assert claude.turn_timeout_ms == 3_600_000
    assert claude.read_timeout_ms == 5_000
  end

  test "claude section honours overrides" do
    write_workflow_file!(workflow_path(),
      agent_kind: "claude",
      claude_bin: "/usr/local/bin/claude",
      claude_model: "opus",
      claude_permission_mode: "acceptEdits",
      claude_auth: "api_key"
    )

    claude = Config.settings!().claude
    assert claude.bin == "/usr/local/bin/claude"
    assert claude.model == "opus"
    assert claude.permission_mode == "acceptEdits"
    assert claude.auth == "api_key"
  end

  defp workflow_path do
    Path.join(System.tmp_dir!(), "symphony-claude-cfg-#{System.unique_integer([:positive])}.md")
  end
end
```

(`Config` уже в alias-ах `TestSupport`. Тест расширяет `write_workflow_file!` — см. Step 4.)

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/config_claude_test.exs`
Expected: FAIL — `key :kind not found` / `key :claude not found`.

- [ ] **Step 3: Добавить `kind` в Agent schema**

В `lib/symphony_elixir/config/schema.ex`, в `defmodule Agent` (строки 136-156):

```elixir
    embedded_schema do
      field(:kind, :string, default: "codex")
      field(:max_concurrent_agents, :integer, default: 10)
      field(:max_turns, :integer, default: 20)
      field(:max_retry_backoff_ms, :integer, default: 300_000)
      field(:max_concurrent_agents_by_state, :map, default: %{})
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(
        attrs,
        [:kind, :max_concurrent_agents, :max_turns, :max_retry_backoff_ms, :max_concurrent_agents_by_state],
        empty_values: []
      )
      |> validate_inclusion(:kind, ["codex", "claude"])
      |> validate_number(:max_concurrent_agents, greater_than: 0)
      |> validate_number(:max_turns, greater_than: 0)
      |> validate_number(:max_retry_backoff_ms, greater_than: 0)
      |> update_change(:max_concurrent_agents_by_state, &Schema.normalize_state_limits/1)
      |> Schema.validate_state_limits(:max_concurrent_agents_by_state)
    end
```

- [ ] **Step 4: Добавить embedded-схему `Claude`**

В `lib/symphony_elixir/config/schema.ex` сразу после `defmodule Codex ... end` (после строки 206) добавить:

```elixir
  defmodule Claude do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:bin, :string, default: "claude")
      field(:permission_mode, :string, default: "bypassPermissions")
      field(:model, :string)
      field(:fallback_model, :string)
      field(:allowed_tools, {:array, :string}, default: ["mcp__linear__linear_graphql"])
      field(:disallowed_tools, {:array, :string}, default: [])
      field(:extra_args, {:array, :string}, default: [])
      field(:auth, :string, default: "subscription")
      field(:max_budget_usd, :float)
      field(:turn_timeout_ms, :integer, default: 3_600_000)
      field(:read_timeout_ms, :integer, default: 5_000)
      field(:stall_timeout_ms, :integer, default: 300_000)
      field(:mcp_token, :string)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(
        attrs,
        [
          :bin,
          :permission_mode,
          :model,
          :fallback_model,
          :allowed_tools,
          :disallowed_tools,
          :extra_args,
          :auth,
          :max_budget_usd,
          :turn_timeout_ms,
          :read_timeout_ms,
          :stall_timeout_ms,
          :mcp_token
        ],
        empty_values: []
      )
      |> validate_required([:bin])
      |> validate_inclusion(:permission_mode, [
        "acceptEdits",
        "auto",
        "bypassPermissions",
        "default",
        "dontAsk",
        "plan"
      ])
      |> validate_inclusion(:auth, ["subscription", "api_key"])
      |> validate_number(:turn_timeout_ms, greater_than: 0)
      |> validate_number(:read_timeout_ms, greater_than: 0)
      |> validate_number(:stall_timeout_ms, greater_than_or_equal_to: 0)
    end
  end
```

- [ ] **Step 5: Зарегистрировать embed и cast_embed**

В `embedded_schema do ... end` верхнего уровня (после строки 276, `embeds_one(:codex, ...)`):

```elixir
    embeds_one(:claude, Claude, on_replace: :update, defaults_to_struct: true)
```

В приватной `changeset/1` (после строки 368, `|> cast_embed(:codex, ...)`):

```elixir
    |> cast_embed(:claude, with: &Claude.changeset/2)
```

- [ ] **Step 6: Расширить тест-хелпер `write_workflow_file!`**

В `test/support/test_support.exs`:

(a) В default-конфиг `Keyword.merge([...])` (после строки 110, `max_concurrent_agents_by_state: %{}`) добавить:

```elixir
          agent_kind: "codex",
```

(после `codex_stall_timeout_ms: 300_000,` строка 117) добавить:

```elixir
          claude_bin: "claude",
          claude_permission_mode: "bypassPermissions",
          claude_model: nil,
          claude_auth: "subscription",
          claude_allowed_tools: ["mcp__linear__linear_graphql"],
          claude_turn_timeout_ms: 3_600_000,
          claude_read_timeout_ms: 5_000,
          claude_stall_timeout_ms: 300_000,
          claude_mcp_token: nil,
```

(b) После `prompt = Keyword.get(config, :prompt)` (строка 166) добавить извлечения:

```elixir
    agent_kind = Keyword.get(config, :agent_kind)
    claude_bin = Keyword.get(config, :claude_bin)
    claude_permission_mode = Keyword.get(config, :claude_permission_mode)
    claude_model = Keyword.get(config, :claude_model)
    claude_auth = Keyword.get(config, :claude_auth)
    claude_allowed_tools = Keyword.get(config, :claude_allowed_tools)
    claude_turn_timeout_ms = Keyword.get(config, :claude_turn_timeout_ms)
    claude_read_timeout_ms = Keyword.get(config, :claude_read_timeout_ms)
    claude_stall_timeout_ms = Keyword.get(config, :claude_stall_timeout_ms)
    claude_mcp_token = Keyword.get(config, :claude_mcp_token)
```

(c) В списке `sections` заменить строку `"agent:"`-блока (строки 185-189) на блок с `kind` и добавить рендер `claude:` после `codex:`-блока (после строки 197):

```elixir
        "agent:",
        "  kind: #{yaml_value(agent_kind)}",
        "  max_concurrent_agents: #{yaml_value(max_concurrent_agents)}",
        "  max_turns: #{yaml_value(max_turns)}",
        "  max_retry_backoff_ms: #{yaml_value(max_retry_backoff_ms)}",
        "  max_concurrent_agents_by_state: #{yaml_value(max_concurrent_agents_by_state)}",
```

и сразу после блока `codex:` (после `"  stall_timeout_ms: #{yaml_value(codex_stall_timeout_ms)}",`):

```elixir
        claude_yaml(
          claude_bin,
          claude_permission_mode,
          claude_model,
          claude_auth,
          claude_allowed_tools,
          claude_turn_timeout_ms,
          claude_read_timeout_ms,
          claude_stall_timeout_ms,
          claude_mcp_token
        ),
```

(d) Добавить приватную функцию-рендерер рядом с `server_yaml/2` (после строки 281):

```elixir
  defp claude_yaml(bin, permission_mode, model, auth, allowed_tools, turn_timeout_ms, read_timeout_ms, stall_timeout_ms, mcp_token) do
    [
      "claude:",
      "  bin: #{yaml_value(bin)}",
      "  permission_mode: #{yaml_value(permission_mode)}",
      model && "  model: #{yaml_value(model)}",
      "  auth: #{yaml_value(auth)}",
      "  allowed_tools: #{yaml_value(allowed_tools)}",
      "  turn_timeout_ms: #{yaml_value(turn_timeout_ms)}",
      "  read_timeout_ms: #{yaml_value(read_timeout_ms)}",
      "  stall_timeout_ms: #{yaml_value(stall_timeout_ms)}",
      mcp_token && "  mcp_token: #{yaml_value(mcp_token)}"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join("\n")
  end
```

- [ ] **Step 7: Запустить тест — убедиться, что проходит**

Run: `mise exec -- mix test test/symphony_elixir/config_claude_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 8: Регрессия конфига и проверка форматирования**

Run: `mise exec -- mix test test/symphony_elixir/ && mise exec -- mix format`
Expected: существующие тесты зелёные.

- [ ] **Step 9: Коммит**

```bash
git add lib/symphony_elixir/config/schema.ex test/support/test_support.exs test/symphony_elixir/config_claude_test.exs
git commit -m "feat: add agent.kind and claude config section"
```

---

## Task 4: `Config.agent_kind/0` и `claude_runtime_settings/2`

**Files:**
- Modify: `lib/symphony_elixir/config.ex` (после `codex_runtime_settings/2`, строка 115)
- Test: `test/symphony_elixir/config_claude_test.exs` (дополнить)

- [ ] **Step 1: Дописать падающие тесты**

В `test/symphony_elixir/config_claude_test.exs` добавить:

```elixir
  test "agent_kind/0 returns the configured backend as an atom" do
    write_workflow_file!(workflow_path())
    assert Config.agent_kind() == :codex

    write_workflow_file!(workflow_path(), agent_kind: "claude")
    assert Config.agent_kind() == :claude
  end

  test "claude_runtime_settings/2 surfaces the claude policy fields" do
    write_workflow_file!(workflow_path(), agent_kind: "claude", claude_model: "sonnet")
    assert {:ok, rt} = Config.claude_runtime_settings()
    assert rt.bin == "claude"
    assert rt.permission_mode == "bypassPermissions"
    assert rt.model == "sonnet"
    assert rt.allowed_tools == ["mcp__linear__linear_graphql"]
    assert rt.turn_timeout_ms == 3_600_000
  end
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/config_claude_test.exs`
Expected: FAIL — `function Config.agent_kind/0 is undefined`.

- [ ] **Step 3: Реализовать функции**

В `lib/symphony_elixir/config.ex` после `codex_runtime_settings/2` (после строки 115) добавить:

```elixir
  @type claude_runtime_settings :: %{
          bin: String.t(),
          permission_mode: String.t(),
          model: String.t() | nil,
          fallback_model: String.t() | nil,
          allowed_tools: [String.t()],
          disallowed_tools: [String.t()],
          extra_args: [String.t()],
          auth: String.t(),
          max_budget_usd: float() | nil,
          turn_timeout_ms: pos_integer(),
          read_timeout_ms: pos_integer(),
          mcp_token: String.t() | nil
        }

  @spec agent_kind() :: :codex | :claude
  def agent_kind do
    case settings!().agent.kind do
      "claude" -> :claude
      _ -> :codex
    end
  end

  @spec claude_runtime_settings() :: {:ok, claude_runtime_settings()} | {:error, term()}
  def claude_runtime_settings do
    with {:ok, settings} <- settings() do
      c = settings.claude

      {:ok,
       %{
         bin: c.bin,
         permission_mode: c.permission_mode,
         model: c.model,
         fallback_model: c.fallback_model,
         allowed_tools: c.allowed_tools,
         disallowed_tools: c.disallowed_tools,
         extra_args: c.extra_args,
         auth: c.auth,
         max_budget_usd: c.max_budget_usd,
         turn_timeout_ms: c.turn_timeout_ms,
         read_timeout_ms: c.read_timeout_ms,
         mcp_token: c.mcp_token
       }}
    end
  end
```

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run: `mise exec -- mix test test/symphony_elixir/config_claude_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Коммит**

```bash
git add lib/symphony_elixir/config.ex test/symphony_elixir/config_claude_test.exs
git commit -m "feat: add Config.agent_kind/0 and claude_runtime_settings/0"
```

---

## Task 5: Behaviour `AgentBackend` + резолвер

**Files:**
- Create: `lib/symphony_elixir/agent_backend.ex`
- Modify: `lib/symphony_elixir/codex/app_server.ex` (добавить `@behaviour`)
- Test: `test/symphony_elixir/agent_backend_test.exs`

- [ ] **Step 1: Написать падающий тест**

```elixir
# test/symphony_elixir/agent_backend_test.exs
defmodule SymphonyElixir.AgentBackendTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend

  test "resolves the codex backend by default" do
    write_workflow_file!(workflow_path())
    assert AgentBackend.resolve() == SymphonyElixir.Codex.AppServer
  end

  test "resolves the claude backend when agent.kind == claude" do
    write_workflow_file!(workflow_path(), agent_kind: "claude")
    assert AgentBackend.resolve() == SymphonyElixir.Claude.AppServer
  end

  test "for/1 maps atoms to modules" do
    assert AgentBackend.for(:codex) == SymphonyElixir.Codex.AppServer
    assert AgentBackend.for(:claude) == SymphonyElixir.Claude.AppServer
  end

  defp workflow_path do
    Path.join(System.tmp_dir!(), "symphony-backend-#{System.unique_integer([:positive])}.md")
  end
end
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/agent_backend_test.exs`
Expected: FAIL — `module SymphonyElixir.AgentBackend is not available`.

- [ ] **Step 3: Реализовать behaviour + резолвер**

```elixir
# lib/symphony_elixir/agent_backend.ex
defmodule SymphonyElixir.AgentBackend do
  @moduledoc """
  Контракт агентного бэкенда и резолвер реализации по `agent.kind`.
  Обе реализации (Codex.AppServer, Claude.AppServer) должны соблюдать один
  интерфейс из трёх функций, чтобы AgentRunner работал без изменений логики.
  """

  alias SymphonyElixir.Config

  @type session :: map()

  @callback start_session(workspace :: Path.t(), opts :: keyword()) ::
              {:ok, session()} | {:error, term()}
  @callback run_turn(session(), prompt :: String.t(), issue :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback stop_session(session()) :: :ok

  @spec resolve() :: module()
  def resolve, do: for(Config.agent_kind())

  @spec for(:codex | :claude) :: module()
  def for(:claude), do: SymphonyElixir.Claude.AppServer
  def for(_), do: SymphonyElixir.Codex.AppServer
end
```

- [ ] **Step 4: Пометить Codex.AppServer как реализацию behaviour**

В `lib/symphony_elixir/codex/app_server.ex` после `require Logger` (строка 6) добавить:

```elixir
  @behaviour SymphonyElixir.AgentBackend
```

(Сигнатуры `start_session/2`, `run_turn/4`, `stop_session/1` уже совпадают с callbacks.)

- [ ] **Step 5: Запустить — claude-тест ещё упадёт (модуля нет), codex-тесты зелёные**

Run: `mise exec -- mix test test/symphony_elixir/agent_backend_test.exs`
Expected: тесты `codex`/`for(:codex)` — PASS; тест с `:claude` падает на `Claude.AppServer is not available` — это нормально, модуль появится в Task 7. Временно пометить этот тест `@tag :pending` ИЛИ выполнять Task 6-7 перед повторным прогоном. Для чистоты: добавить `@tag :skip` на claude-кейсы здесь и снять в Task 7 Step 6.

Применить: добавить `@tag :skip` над тестом `"resolves the claude backend ..."` и над строкой `assert AgentBackend.for(:claude) == ...` вынести в отдельный `@tag :skip`-тест.

- [ ] **Step 6: Коммит**

```bash
git add lib/symphony_elixir/agent_backend.ex lib/symphony_elixir/codex/app_server.ex test/symphony_elixir/agent_backend_test.exs
git commit -m "feat: add AgentBackend behaviour and resolver"
```

---

## Task 6: `Claude.StreamMapper` — маппинг событий stream-json

Чистый модуль: вход — декодированный объект строки `stream-json`, выход — `{:event, atom, details}` | `{:result, :ok | :error, details}` | `:ignore`. Это ядро паритета стрима.

**Files:**
- Create: `lib/symphony_elixir/claude/stream_mapper.ex`
- Test: `test/symphony_elixir/claude/stream_mapper_test.exs`

- [ ] **Step 1: Написать падающий тест**

```elixir
# test/symphony_elixir/claude/stream_mapper_test.exs
defmodule SymphonyElixir.Claude.StreamMapperTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.StreamMapper

  test "system/init maps to a notification" do
    decoded = %{"type" => "system", "subtype" => "init", "session_id" => "abc", "tools" => []}
    assert {:event, :notification, details} = StreamMapper.classify(decoded)
    assert details.payload == decoded
  end

  test "assistant text maps to a notification" do
    decoded = %{
      "type" => "assistant",
      "message" => %{"content" => [%{"type" => "text", "text" => "hi"}], "usage" => %{"output_tokens" => 3}}
    }

    assert {:event, :notification, details} = StreamMapper.classify(decoded)
    assert details.usage == %{"output_tokens" => 3}
  end

  test "tool_result without error maps to tool_call_completed" do
    decoded = %{
      "type" => "user",
      "message" => %{"content" => [%{"type" => "tool_result", "tool_use_id" => "t1", "is_error" => false}]}
    }

    assert {:event, :tool_call_completed, _details} = StreamMapper.classify(decoded)
  end

  test "tool_result with error maps to tool_call_failed" do
    decoded = %{
      "type" => "user",
      "message" => %{"content" => [%{"type" => "tool_result", "tool_use_id" => "t1", "is_error" => true}]}
    }

    assert {:event, :tool_call_failed, _details} = StreamMapper.classify(decoded)
  end

  test "successful result returns an ok result with usage and text" do
    decoded = %{
      "type" => "result",
      "subtype" => "success",
      "is_error" => false,
      "result" => "done",
      "usage" => %{"input_tokens" => 10, "output_tokens" => 5},
      "total_cost_usd" => 0.01
    }

    assert {:result, :ok, details} = StreamMapper.classify(decoded)
    assert details.result == "done"
    assert details.usage == %{"input_tokens" => 10, "output_tokens" => 5}
  end

  test "error result returns an error result" do
    decoded = %{"type" => "result", "subtype" => "error_during_execution", "is_error" => true}
    assert {:result, :error, details} = StreamMapper.classify(decoded)
    assert details.subtype == "error_during_execution"
  end

  test "usage-limit result is flagged retryable" do
    decoded = %{
      "type" => "result",
      "subtype" => "error_during_execution",
      "is_error" => true,
      "result" => "Claude usage limit reached. Try again later."
    }

    assert {:result, :error, details} = StreamMapper.classify(decoded)
    assert details.retryable == true
  end
end
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/claude/stream_mapper_test.exs`
Expected: FAIL — `module SymphonyElixir.Claude.StreamMapper is not available`.

- [ ] **Step 3: Реализовать маппер**

```elixir
# lib/symphony_elixir/claude/stream_mapper.ex
defmodule SymphonyElixir.Claude.StreamMapper do
  @moduledoc """
  Чистый маппинг событий Claude Code `--output-format stream-json` в словарь
  событий Symphony (как у Codex.AppServer). Без побочных эффектов.
  """

  @type classification ::
          {:event, atom(), map()}
          | {:result, :ok | :error, map()}
          | :ignore

  @limit_markers ["usage limit", "rate limit", "overloaded", "try again later"]

  @spec classify(map()) :: classification()
  def classify(%{"type" => "result"} = decoded) do
    usage = Map.get(decoded, "usage")
    base = %{payload: decoded, usage: usage, subtype: Map.get(decoded, "subtype")}

    if Map.get(decoded, "is_error", false) or limit?(decoded) do
      {:result, :error,
       Map.merge(base, %{
         reason: {:claude_result_error, Map.get(decoded, "subtype"), Map.get(decoded, "result")},
         retryable: limit?(decoded)
       })}
    else
      {:result, :ok,
       Map.merge(base, %{
         result: Map.get(decoded, "result"),
         cost_usd: Map.get(decoded, "total_cost_usd"),
         num_turns: Map.get(decoded, "num_turns")
       })}
    end
  end

  def classify(%{"type" => "assistant", "message" => message} = decoded) when is_map(message) do
    {:event, :notification, %{payload: decoded, usage: Map.get(message, "usage")}}
  end

  def classify(%{"type" => "user", "message" => %{"content" => content}} = decoded)
      when is_list(content) do
    case Enum.find(content, &match?(%{"type" => "tool_result"}, &1)) do
      %{"is_error" => true} ->
        {:event, :tool_call_failed, %{payload: decoded}}

      %{"type" => "tool_result"} ->
        {:event, :tool_call_completed, %{payload: decoded}}

      _ ->
        {:event, :notification, %{payload: decoded}}
    end
  end

  def classify(%{"type" => "system"} = decoded) do
    {:event, :notification, %{payload: decoded}}
  end

  def classify(decoded) when is_map(decoded) do
    {:event, :other_message, %{payload: decoded}}
  end

  @spec limit?(map()) :: boolean()
  def limit?(decoded) when is_map(decoded) do
    text =
      [Map.get(decoded, "result"), Map.get(decoded, "subtype")]
      |> Enum.filter(&is_binary/1)
      |> Enum.map_join(" ", &String.downcase/1)

    Enum.any?(@limit_markers, &String.contains?(text, &1))
  end
end
```

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run: `mise exec -- mix test test/symphony_elixir/claude/stream_mapper_test.exs`
Expected: PASS (7 tests).

- [ ] **Step 5: Коммит**

```bash
git add lib/symphony_elixir/claude/stream_mapper.ex test/symphony_elixir/claude/stream_mapper_test.exs
git commit -m "feat: add Claude StreamMapper for stream-json events"
```

---

## Task 7: `Claude.AppServer` — запуск Claude headless + мультитёрн

**Files:**
- Create: `lib/symphony_elixir/claude/app_server.ex`
- Modify: `test/symphony_elixir/agent_backend_test.exs` (снять `@tag :skip` из Task 5)
- Test: `test/symphony_elixir/claude/app_server_test.exs`

Контракт session-map (для совместимости с AgentRunner): `%{kind: :claude, port: port() | nil, metadata: map(), thread_id: String.t(), turn_number: pos_integer(), workspace: Path.t(), worker_host: String.t() | nil}`. `run_turn` принимает session, инкрементит turn_number через значение в самой session нельзя (immutable) — поэтому номер turn'а ведём в опции `:turn_number` (AgentRunner вызывает run_turn последовательно; используем монотонный счётчик в session через ETS не нужен — берём из issue-контекста). Упрощение: первый turn — без `--resume`; последующие — определяем по наличию маркер-файла `<workspace>/.symphony-claude-session` (создаётся после первого turn'а). Это устойчиво и тестируемо.

- [ ] **Step 1: Написать падающий тест с фейковым `claude`**

```elixir
# test/symphony_elixir/claude/app_server_test.exs
defmodule SymphonyElixir.Claude.AppServerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Claude.AppServer
  alias SymphonyElixir.Linear.Issue

  setup do
    root = Path.join(System.tmp_dir!(), "symphony-claude-#{System.unique_integer([:positive])}")
    ws = Path.join(root, "ENG-7")
    File.mkdir_p!(ws)

    bin_dir = Path.join(root, "bin")
    File.mkdir_p!(bin_dir)
    fake = Path.join(bin_dir, "claude")
    argv_trace = Path.join(root, "argv.log")

    # Фейковый claude: пишет argv в trace и эмитит канонический stream-json.
    script = """
    #!/bin/sh
    printf '%s\\n' "$*" >> "#{argv_trace}"
    printf '%s\\n' '{"type":"system","subtype":"init","session_id":"s-1","tools":[]}'
    printf '%s\\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}],"usage":{"output_tokens":2}}}'
    printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"done","usage":{"input_tokens":1,"output_tokens":2},"total_cost_usd":0.001,"num_turns":1}'
    exit 0
    """

    File.write!(fake, script)
    File.chmod!(fake, 0o755)

    workflow = Path.join(root, "WORKFLOW.md")
    write_workflow_file!(workflow,
      agent_kind: "claude",
      workspace_root: root,
      claude_bin: fake
    )

    on_exit(fn -> File.rm_rf(root) end)

    {:ok, ws: ws, argv_trace: argv_trace, root: root}
  end

  defp issue do
    %Issue{id: "id-7", identifier: "ENG-7", title: "Test", state: "In Progress", url: "http://x", labels: []}
  end

  test "start_session validates cwd and returns a claude session map", %{ws: ws} do
    assert {:ok, session} = AppServer.start_session(ws, [])
    assert session.kind == :claude
    assert is_binary(session.thread_id)
    assert session.workspace == Path.expand(ws) or String.ends_with?(session.workspace, "ENG-7")
    assert :ok = AppServer.stop_session(session)
  end

  test "run_turn streams events and returns the result tuple", %{ws: ws} do
    test_pid = self()
    {:ok, session} = AppServer.start_session(ws, [])

    assert {:ok, result} =
             AppServer.run_turn(session, "do the task", issue(),
               on_message: fn msg -> send(test_pid, {:claude_msg, msg}) end
             )

    assert result.result == "done"
    assert is_binary(result.session_id)

    assert_receive {:claude_msg, %{event: :session_started}}
    assert_receive {:claude_msg, %{event: :turn_completed}}
    AppServer.stop_session(session)
  end

  test "first turn omits --resume, second turn includes it", %{ws: ws, argv_trace: trace} do
    {:ok, session} = AppServer.start_session(ws, [])
    {:ok, _} = AppServer.run_turn(session, "turn 1", issue(), on_message: fn _ -> :ok end)
    {:ok, _} = AppServer.run_turn(session, "turn 2", issue(), on_message: fn _ -> :ok end)
    AppServer.stop_session(session)

    [first, second | _] = trace |> File.read!() |> String.split("\n", trim: true)
    refute first =~ "--resume"
    assert first =~ "--session-id"
    assert second =~ "--resume"
  end
end
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/claude/app_server_test.exs`
Expected: FAIL — `module SymphonyElixir.Claude.AppServer is not available`.

- [ ] **Step 3: Реализовать Claude.AppServer**

```elixir
# lib/symphony_elixir/claude/app_server.ex
defmodule SymphonyElixir.Claude.AppServer do
  @moduledoc """
  Claude Code бэкенд для Symphony. Запускает `claude -p --output-format stream-json`
  в рабочей директории задачи на каждый turn и маппит события в словарь Symphony.
  Реализует тот же интерфейс, что Codex.AppServer.
  """

  @behaviour SymphonyElixir.AgentBackend

  require Logger

  alias SymphonyElixir.{AgentWorkspaceGuard, Claude.StreamMapper, Config, SSH, UUID}

  @port_line_bytes 1_048_576
  @session_marker ".symphony-claude-session"

  @impl true
  @spec start_session(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_session(workspace, opts \\ []) do
    worker_host = Keyword.get(opts, :worker_host)

    with {:ok, expanded_workspace} <-
           AgentWorkspaceGuard.validate(workspace, Config.settings!().workspace.root, worker_host) do
      {:ok,
       %{
         kind: :claude,
         thread_id: UUID.v4(),
         workspace: expanded_workspace,
         worker_host: worker_host,
         metadata: base_metadata(worker_host)
       }}
    end
  end

  @impl true
  @spec run_turn(map(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(session, prompt, issue, opts \\ []) do
    on_message = Keyword.get(opts, :on_message, fn _ -> :ok end)
    {:ok, rt} = Config.claude_runtime_settings()

    session_id = "#{session.thread_id}-#{turn_number(session)}"
    emit(on_message, :session_started, %{session_id: session_id, thread_id: session.thread_id}, session.metadata)

    command = build_command(session, prompt, rt)

    case start_port(session.workspace, session.worker_host, command) do
      {:ok, port} ->
        try do
          receive_loop(port, on_message, rt.turn_timeout_ms, "", session, %{ok: false, result: nil, usage: nil})
          |> finalize(session, session_id, on_message)
        after
          mark_session_started(session)
          close_port(port)
        end

      {:error, reason} ->
        emit(on_message, :startup_failed, %{reason: reason}, session.metadata)
        {:error, reason}
    end
  end

  @impl true
  @spec stop_session(map()) :: :ok
  def stop_session(_session), do: :ok

  # --- сборка команды ---

  defp build_command(session, prompt, rt) do
    resume_args =
      if resumable?(session) do
        ["--resume", session.thread_id]
      else
        ["--session-id", session.thread_id]
      end

    mcp_args = mcp_args(rt)

    base =
      [
        shell_escape(rt.bin),
        "-p",
        shell_escape(prompt),
        "--output-format",
        "stream-json",
        "--verbose",
        "--permission-mode",
        rt.permission_mode
      ] ++
        resume_args ++
        model_args(rt) ++
        tool_args(rt) ++
        mcp_args ++
        budget_args(rt) ++
        Enum.map(rt.extra_args, &shell_escape/1)

    Enum.join(base, " ")
  end

  defp model_args(%{model: model}) when is_binary(model), do: ["--model", model]
  defp model_args(_), do: []

  defp tool_args(rt) do
    allow =
      case rt.allowed_tools do
        [] -> []
        tools -> ["--allowedTools", Enum.join(tools, ",")]
      end

    disallow =
      case rt.disallowed_tools do
        [] -> []
        tools -> ["--disallowedTools", Enum.join(tools, ",")]
      end

    allow ++ disallow
  end

  defp budget_args(%{max_budget_usd: usd}) when is_float(usd), do: ["--max-budget-usd", to_string(usd)]
  defp budget_args(_), do: []

  defp mcp_args(rt) do
    case System.get_env("SYMPHONY_MCP_URL") do
      url when is_binary(url) and url != "" ->
        config =
          %{"mcpServers" => %{"linear" => mcp_server_entry(url, rt)}}
          |> Jason.encode!()

        ["--mcp-config", shell_escape(config), "--strict-mcp-config"]

      _ ->
        []
    end
  end

  defp mcp_server_entry(url, %{mcp_token: token}) when is_binary(token) do
    %{"type" => "http", "url" => url, "headers" => %{"Authorization" => "Bearer #{token}"}}
  end

  defp mcp_server_entry(url, _rt), do: %{"type" => "http", "url" => url}

  # --- порт/процесс (зеркало Codex.AppServer.start_port) ---

  defp start_port(workspace, nil, command) do
    case System.find_executable("bash") do
      nil ->
        {:error, :bash_not_found}

      executable ->
        port =
          Port.open(
            {:spawn_executable, String.to_charlist(executable)},
            [
              :binary,
              :exit_status,
              :stderr_to_stdout,
              args: [~c"-lc", String.to_charlist(command)],
              cd: String.to_charlist(workspace),
              line: @port_line_bytes
            ]
          )

        {:ok, port}
    end
  end

  defp start_port(workspace, worker_host, command) when is_binary(worker_host) do
    remote = "cd #{shell_escape(workspace)} && #{command}"
    SSH.start_port(worker_host, remote, line: @port_line_bytes)
  end

  defp receive_loop(port, on_message, timeout_ms, pending, session, acc) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        line = pending <> to_string(chunk)
        handle_line(port, on_message, line, timeout_ms, session, acc)

      {^port, {:data, {:noeol, chunk}}} ->
        receive_loop(port, on_message, timeout_ms, pending <> to_string(chunk), session, acc)

      {^port, {:exit_status, 0}} ->
        acc

      {^port, {:exit_status, status}} ->
        if acc.ok, do: acc, else: %{acc | result: {:error, {:port_exit, status}}}
    after
      timeout_ms ->
        %{acc | result: {:error, :turn_timeout}}
    end
  end

  defp handle_line(port, on_message, line, timeout_ms, session, acc) do
    case Jason.decode(line) do
      {:ok, decoded} ->
        case StreamMapper.classify(decoded) do
          {:event, event, details} ->
            emit(on_message, event, details, with_usage(session.metadata, details))
            receive_loop(port, on_message, timeout_ms, "", session, acc)

          {:result, :ok, details} ->
            emit(on_message, :turn_completed, details, with_usage(session.metadata, details))
            receive_loop(port, on_message, timeout_ms, "", session, %{acc | ok: true, result: {:ok, details}, usage: details.usage})

          {:result, :error, details} ->
            emit(on_message, :turn_failed, details, with_usage(session.metadata, details))
            receive_loop(port, on_message, timeout_ms, "", session, %{acc | result: {:error, {:turn_failed, details}}})

          :ignore ->
            receive_loop(port, on_message, timeout_ms, "", session, acc)
        end

      {:error, _} ->
        if String.trim(line) != "" and String.starts_with?(String.trim_leading(line), "{") do
          emit(on_message, :malformed, %{payload: line, raw: line}, session.metadata)
        else
          log_non_json(line)
        end

        receive_loop(port, on_message, timeout_ms, "", session, acc)
    end
  end

  defp finalize(acc, session, session_id, on_message) do
    case acc.result do
      {:ok, details} ->
        {:ok,
         %{
           result: details.result,
           session_id: session_id,
           thread_id: session.thread_id,
           turn_id: turn_number(session)
         }}

      {:error, reason} ->
        emit(on_message, :turn_ended_with_error, %{session_id: session_id, reason: reason}, session.metadata)
        {:error, reason}

      nil ->
        # Процесс завершился без события result — трактуем как ошибку.
        reason = {:no_result, session_id}
        emit(on_message, :turn_ended_with_error, %{session_id: session_id, reason: reason}, session.metadata)
        {:error, reason}
    end
  end

  # --- мультитёрн через маркер в воркспейсе ---

  defp resumable?(session), do: File.exists?(Path.join(session.workspace, @session_marker))

  defp turn_number(session) do
    if resumable?(session), do: read_turn(session) + 1, else: 1
  end

  defp mark_session_started(session) do
    path = Path.join(session.workspace, @session_marker)
    next = if File.exists?(path), do: read_turn(session) + 1, else: 1
    File.write(path, "#{session.thread_id}\n#{next}\n")
  end

  defp read_turn(session) do
    case File.read(Path.join(session.workspace, @session_marker)) do
      {:ok, content} ->
        case content |> String.split("\n", trim: true) |> List.last() |> Integer.parse() do
          {n, _} -> n
          _ -> 1
        end

      _ ->
        1
    end
  end

  # --- утилиты ---

  defp emit(on_message, event, details, metadata) when is_function(on_message, 1) do
    message =
      metadata
      |> Map.merge(details)
      |> Map.put(:event, event)
      |> Map.put(:timestamp, DateTime.utc_now())

    on_message.(message)
  end

  defp with_usage(metadata, %{usage: usage}) when is_map(usage), do: Map.put(metadata, :usage, usage)
  defp with_usage(metadata, _details), do: metadata

  defp base_metadata(worker_host) when is_binary(worker_host), do: %{worker_host: worker_host}
  defp base_metadata(_), do: %{}

  defp close_port(port) when is_port(port) do
    case :erlang.port_info(port) do
      :undefined -> :ok
      _ -> (try do Port.close(port); :ok rescue ArgumentError -> :ok end)
    end
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp log_non_json(line) do
    text = line |> String.trim() |> String.slice(0, 1_000)

    if text != "" do
      if String.match?(text, ~r/\b(error|warn|warning|failed|fatal|panic|exception)\b/i) do
        Logger.warning("Claude stream output: #{text}")
      else
        Logger.debug("Claude stream output: #{text}")
      end
    end
  end
end
```

- [ ] **Step 4: Запустить тест Claude.AppServer**

Run: `mise exec -- mix test test/symphony_elixir/claude/app_server_test.exs`
Expected: PASS (3 tests). Если падает на permission-mode `bypassPermissions` (фейковому скрипту флаги безразличны) — проверить, что argv пишется в trace (фейк игнорирует неизвестные флаги).

- [ ] **Step 5: Снять skip с claude-кейсов в agent_backend_test**

Удалить `@tag :skip` (добавленные в Task 5 Step 5) и прогнать:

Run: `mise exec -- mix test test/symphony_elixir/agent_backend_test.exs`
Expected: PASS (все кейсы).

- [ ] **Step 6: Коммит**

```bash
git add lib/symphony_elixir/claude/app_server.ex test/symphony_elixir/claude/app_server_test.exs test/symphony_elixir/agent_backend_test.exs
git commit -m "feat: add Claude.AppServer headless backend with multi-turn resume"
```

---

## Task 8: `Claude.LinearMcp` — обработчик MCP JSON-RPC

Чистый модуль: вход — декодированный JSON-RPC запрос, выход — JSON-RPC ответ. `tools/call` для `linear_graphql` делегирует в `Codex.DynamicTool.execute/3` (единый источник правды).

**Files:**
- Create: `lib/symphony_elixir/claude/linear_mcp.ex`
- Test: `test/symphony_elixir/claude/linear_mcp_test.exs`

- [ ] **Step 1: Написать падающий тест**

```elixir
# test/symphony_elixir/claude/linear_mcp_test.exs
defmodule SymphonyElixir.Claude.LinearMcpTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.LinearMcp

  test "initialize returns protocol + server info" do
    resp = LinearMcp.handle_request(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})
    assert resp["id"] == 1
    assert resp["result"]["serverInfo"]["name"] == "symphony-linear"
    assert is_binary(resp["result"]["protocolVersion"])
  end

  test "tools/list exposes linear_graphql with its input schema" do
    resp = LinearMcp.handle_request(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}})
    [tool] = resp["result"]["tools"]
    assert tool["name"] == "linear_graphql"
    assert tool["inputSchema"]["required"] == ["query"]
  end

  test "tools/call linear_graphql delegates to the tool executor" do
    executor = fn "linear_graphql", %{"query" => "query { viewer { id } }"} ->
      %{"success" => true, "output" => "{\"data\":{}}", "contentItems" => [%{"type" => "inputText", "text" => "{\"data\":{}}"}]}
    end

    resp =
      LinearMcp.handle_request(
        %{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "tools/call",
          "params" => %{"name" => "linear_graphql", "arguments" => %{"query" => "query { viewer { id } }"}}
        },
        tool_executor: executor
      )

    assert resp["result"]["isError"] == false
    assert [%{"type" => "text", "text" => "{\"data\":{}}"}] = resp["result"]["content"]
  end

  test "tools/call failure marks isError true" do
    executor = fn _name, _args -> %{"success" => false, "output" => "boom", "contentItems" => []} end

    resp =
      LinearMcp.handle_request(
        %{"jsonrpc" => "2.0", "id" => 4, "method" => "tools/call", "params" => %{"name" => "linear_graphql", "arguments" => %{}}},
        tool_executor: executor
      )

    assert resp["result"]["isError"] == true
  end

  test "unknown method returns a JSON-RPC error" do
    resp = LinearMcp.handle_request(%{"jsonrpc" => "2.0", "id" => 5, "method" => "nope", "params" => %{}})
    assert resp["error"]["code"] == -32601
  end
end
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/claude/linear_mcp_test.exs`
Expected: FAIL — `module SymphonyElixir.Claude.LinearMcp is not available`.

- [ ] **Step 3: Реализовать модуль**

```elixir
# lib/symphony_elixir/claude/linear_mcp.ex
defmodule SymphonyElixir.Claude.LinearMcp do
  @moduledoc """
  Минимальный MCP-сервер (JSON-RPC поверх HTTP) с единственным инструментом
  `linear_graphql`. Делегирует выполнение в Codex.DynamicTool (единый источник
  правды по схеме и логике вызова Linear).
  """

  alias SymphonyElixir.Codex.DynamicTool

  @protocol_version "2025-06-18"

  @spec handle_request(map(), keyword()) :: map()
  def handle_request(request, opts \\ [])

  def handle_request(%{"method" => "initialize", "id" => id}, _opts) do
    ok(id, %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "symphony-linear", "version" => "0.1.0"}
    })
  end

  def handle_request(%{"method" => "tools/list", "id" => id}, _opts) do
    ok(id, %{"tools" => DynamicTool.tool_specs()})
  end

  def handle_request(%{"method" => "tools/call", "id" => id, "params" => params}, opts) do
    executor = Keyword.get(opts, :tool_executor, &DynamicTool.execute/2)
    name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    result = executor.(name, arguments)
    success = Map.get(result, "success", false)

    content =
      case Map.get(result, "contentItems") do
        items when is_list(items) and items != [] ->
          Enum.map(items, fn item -> %{"type" => "text", "text" => Map.get(item, "text", "")} end)

        _ ->
          [%{"type" => "text", "text" => Map.get(result, "output", "")}]
      end

    ok(id, %{"content" => content, "isError" => not success})
  end

  def handle_request(%{"id" => id}, _opts) do
    error(id, -32601, "Method not found")
  end

  def handle_request(_request, _opts) do
    error(nil, -32600, "Invalid Request")
  end

  defp ok(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  defp error(id, code, message), do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
end
```

Примечание: `DynamicTool.execute/2` фактически `execute/3` с дефолтным `opts \\ []`; арность 2 валидна.

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run: `mise exec -- mix test test/symphony_elixir/claude/linear_mcp_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Коммит**

```bash
git add lib/symphony_elixir/claude/linear_mcp.ex test/symphony_elixir/claude/linear_mcp_test.exs
git commit -m "feat: add Claude LinearMcp JSON-RPC handler reusing DynamicTool"
```

---

## Task 9: MCP-контроллер + маршрут `POST /mcp`

Тонкий Phoenix-контроллер поверх `LinearMcp`. Авторизация — Bearer-токен из `claude.mcp_token`/`SYMPHONY_MCP_TOKEN` (эндпоинт слушает только localhost, см. `server.host` default `127.0.0.1`).

**Files:**
- Create: `lib/symphony_elixir_web/controllers/mcp_controller.ex`
- Modify: `lib/symphony_elixir_web/router.ex`
- Test: `test/symphony_elixir/claude/mcp_controller_test.exs`

- [ ] **Step 1: Написать падающий тест (через прямой вызов экшена с собранным conn)**

Проект не имеет ConnCase; тестируем экшен напрямую, собирая `%Plug.Conn{}` через `Plug.Test`.

```elixir
# test/symphony_elixir/claude/mcp_controller_test.exs
defmodule SymphonyElixirWeb.McpControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias SymphonyElixirWeb.McpController

  defp call(body_params, headers \\ []) do
    conn =
      conn(:post, "/mcp", "")
      |> put_private(:phoenix_endpoint, SymphonyElixirWeb.Endpoint)
      |> Map.put(:body_params, body_params)

    conn = Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)
    McpController.rpc(conn, body_params)
  end

  test "tools/list returns 200 with the linear_graphql tool" do
    conn = call(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "params" => %{}})
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert [%{"name" => "linear_graphql"}] = body["result"]["tools"]
  end
end
```

(Токен-проверку покрываем интеграционно; по умолчанию `mcp_token` не задан → проверка отключена. См. Step 3.)

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/claude/mcp_controller_test.exs`
Expected: FAIL — `module SymphonyElixirWeb.McpController is not available`.

- [ ] **Step 3: Реализовать контроллер**

```elixir
# lib/symphony_elixir_web/controllers/mcp_controller.ex
defmodule SymphonyElixirWeb.McpController do
  @moduledoc """
  HTTP-транспорт для MCP-инструмента linear_graphql, потребляемого Claude Code.
  Делегирует в SymphonyElixir.Claude.LinearMcp.
  """

  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.Claude.LinearMcp
  alias SymphonyElixir.Config

  @spec rpc(Conn.t(), map()) :: Conn.t()
  def rpc(conn, params) do
    case authorized?(conn) do
      true ->
        json(conn, LinearMcp.handle_request(params))

      false ->
        conn
        |> put_status(401)
        |> json(%{"jsonrpc" => "2.0", "error" => %{"code" => -32001, "message" => "Unauthorized"}})
    end
  end

  defp authorized?(conn) do
    case expected_token() do
      nil ->
        true

      token ->
        Conn.get_req_header(conn, "authorization") == ["Bearer #{token}"]
    end
  end

  defp expected_token do
    case safe_config_token() do
      token when is_binary(token) and token != "" -> token
      _ -> blank_to_nil(System.get_env("SYMPHONY_MCP_TOKEN"))
    end
  end

  defp safe_config_token do
    try do
      Config.settings!().claude.mcp_token
    rescue
      _ -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
```

- [ ] **Step 4: Добавить маршрут**

В `lib/symphony_elixir_web/router.ex`, в существующий JSON-scope (рядом с `get("/api/v1/state", ...)`) добавить ПЕРЕД `match(:*, "/*path", ...)`:

```elixir
  post("/mcp", McpController, :rpc)
```

(Парсинг JSON-тела уже обеспечивает `Plug.Parsers` в endpoint.ex.)

- [ ] **Step 5: Запустить — убедиться, что проходит**

Run: `mise exec -- mix test test/symphony_elixir/claude/mcp_controller_test.exs`
Expected: PASS (1 test).

- [ ] **Step 6: Коммит**

```bash
git add lib/symphony_elixir_web/controllers/mcp_controller.ex lib/symphony_elixir_web/router.ex test/symphony_elixir/claude/mcp_controller_test.exs
git commit -m "feat: expose linear_graphql via /mcp HTTP endpoint"
```

---

## Task 10: Переключить AgentRunner на резолвер бэкенда

**Files:**
- Modify: `lib/symphony_elixir/agent_runner.ex` (строки 7, 91, 95, 104)
- Test: `test/symphony_elixir/agent_runner_backend_test.exs`

- [ ] **Step 1: Написать падающий тест (бэкенд-свап через конфиг)**

```elixir
# test/symphony_elixir/agent_runner_backend_test.exs
defmodule SymphonyElixir.AgentRunnerBackendTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend

  test "AgentRunner uses the resolver which honours agent.kind" do
    write_workflow_file!(workflow_path(), agent_kind: "claude")
    assert AgentBackend.resolve() == SymphonyElixir.Claude.AppServer

    write_workflow_file!(workflow_path())
    assert AgentBackend.resolve() == SymphonyElixir.Codex.AppServer
  end

  defp workflow_path do
    Path.join(System.tmp_dir!(), "symphony-runner-#{System.unique_integer([:positive])}.md")
  end
end
```

(Полный end-to-end прогон раннера с фейковым бэкендом покрывается интеграционно в Task 12; здесь фиксируем, что путь выбора бэкенда подключён.)

- [ ] **Step 2: Запустить — убедиться, что зелёный кроме отсутствующего использования резолвера**

Run: `mise exec -- mix test test/symphony_elixir/agent_runner_backend_test.exs`
Expected: PASS (резолвер уже есть из Task 5). Этот тест — страховка перед правкой раннера.

- [ ] **Step 3: Заменить alias на резолвер**

В `lib/symphony_elixir/agent_runner.ex`:

(a) Удалить строку 7 `alias SymphonyElixir.Codex.AppServer` и в строке 8 оставить остальные алиасы. Добавить:

```elixir
  alias SymphonyElixir.AgentBackend
```

(b) В `run_codex_turns/5` (строка 91) заменить `AppServer.start_session(...)` и `AppServer.stop_session(...)`:

```elixir
    backend = AgentBackend.resolve()

    with {:ok, session} <- backend.start_session(workspace, worker_host: worker_host) do
      try do
        do_run_codex_turns(session, workspace, issue, codex_update_recipient, opts, issue_state_fetcher, 1, max_turns, backend)
      after
        backend.stop_session(session)
      end
    end
```

(c) Прокинуть `backend` в `do_run_codex_turns/9` (добавить последний аргумент) и в строке 104 заменить `AppServer.run_turn(...)` на `backend.run_turn(...)`. Сигнатуру `do_run_codex_turns` расширить на `backend` и передавать его в рекурсивный вызов (строки 116-125).

Конкретно — заменить заголовок и тело рекурсии:

```elixir
  defp do_run_codex_turns(app_session, workspace, issue, codex_update_recipient, opts, issue_state_fetcher, turn_number, max_turns, backend) do
    prompt = build_turn_prompt(issue, opts, turn_number, max_turns)

    with {:ok, turn_session} <-
           backend.run_turn(
             app_session,
             prompt,
             issue,
             on_message: codex_message_handler(codex_update_recipient, issue)
           ) do
      Logger.info("Completed agent run for #{issue_context(issue)} session_id=#{turn_session[:session_id]} workspace=#{workspace} turn=#{turn_number}/#{max_turns}")

      case continue_with_issue?(issue, issue_state_fetcher) do
        {:continue, refreshed_issue} when turn_number < max_turns ->
          Logger.info("Continuing agent run for #{issue_context(refreshed_issue)} after normal turn completion turn=#{turn_number}/#{max_turns}")

          do_run_codex_turns(
            app_session,
            workspace,
            refreshed_issue,
            codex_update_recipient,
            opts,
            issue_state_fetcher,
            turn_number + 1,
            max_turns,
            backend
          )

        {:continue, refreshed_issue} ->
          Logger.info("Reached agent.max_turns for #{issue_context(refreshed_issue)} with issue still active; returning control to orchestrator")
          :ok

        {:done, _refreshed_issue} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
```

- [ ] **Step 4: Регрессия всех тестов раннера/оркестратора**

Run: `mise exec -- mix test`
Expected: PASS — существующие тесты Codex-пути не сломаны (резолвер по умолчанию → Codex.AppServer); новые тесты зелёные.

- [ ] **Step 5: Коммит**

```bash
git add lib/symphony_elixir/agent_runner.ex test/symphony_elixir/agent_runner_backend_test.exs
git commit -m "feat: select agent backend via AgentBackend resolver in AgentRunner"
```

---

## Task 11: Прокинуть MCP URL в окружение агента

Claude-бэкенд читает `SYMPHONY_MCP_URL` (Task 7, `mcp_args/1`). Нужно выставлять его при старте, исходя из `server.host`/`server.port`, чтобы агент в воркспейсе ходил на локальный MCP-эндпоинт.

**Files:**
- Modify: `lib/symphony_elixir/claude/app_server.ex` (вычислять URL из Config, а не только из env)
- Test: `test/symphony_elixir/claude/app_server_test.exs` (дополнить)

- [ ] **Step 1: Дописать падающий тест**

В `test/symphony_elixir/claude/app_server_test.exs` добавить:

```elixir
  test "passes --mcp-config when server endpoint is configured", %{ws: ws, argv_trace: trace, root: root} do
    workflow = Path.join(root, "WORKFLOW.md")
    write_workflow_file!(workflow,
      agent_kind: "claude",
      workspace_root: root,
      claude_bin: Path.join([root, "bin", "claude"]),
      server_port: 4599,
      server_host: "127.0.0.1"
    )

    {:ok, session} = AppServer.start_session(ws, [])
    {:ok, _} = AppServer.run_turn(session, "go", issue(), on_message: fn _ -> :ok end)
    AppServer.stop_session(session)

    argv = trace |> File.read!()
    assert argv =~ "--mcp-config"
    assert argv =~ "127.0.0.1:4599/mcp"
  end
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `mise exec -- mix test test/symphony_elixir/claude/app_server_test.exs`
Expected: FAIL — argv не содержит `--mcp-config` (env `SYMPHONY_MCP_URL` не выставлен).

- [ ] **Step 3: Вычислять MCP URL из конфига**

В `lib/symphony_elixir/claude/app_server.ex` заменить `mcp_args/1`:

```elixir
  defp mcp_args(rt) do
    case mcp_url() do
      url when is_binary(url) ->
        config = Jason.encode!(%{"mcpServers" => %{"linear" => mcp_server_entry(url, rt)}})
        ["--mcp-config", shell_escape(config), "--strict-mcp-config"]

      nil ->
        []
    end
  end

  defp mcp_url do
    case System.get_env("SYMPHONY_MCP_URL") do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        settings = Config.settings!()

        case Config.server_port() do
          port when is_integer(port) and port > 0 ->
            "http://#{settings.server.host}:#{port}/mcp"

          _ ->
            nil
        end
    end
  end
```

- [ ] **Step 4: Запустить — убедиться, что проходит**

Run: `mise exec -- mix test test/symphony_elixir/claude/app_server_test.exs`
Expected: PASS (5 tests суммарно по файлу).

- [ ] **Step 5: Коммит**

```bash
git add lib/symphony_elixir/claude/app_server.ex test/symphony_elixir/claude/app_server_test.exs
git commit -m "feat: derive Claude MCP URL from server config"
```

---

## Task 12: Полный прогон, формат, кредо + пример WORKFLOW

**Files:**
- Modify: `WORKFLOW.md` (корень репо) — добавить пример `agent.kind`/`claude:` (закомментированный альтернативный блок) ИЛИ создать `WORKFLOW.claude.md` в корне репо как готовый пример.
- Прогон всех проверок.

- [ ] **Step 1: Создать пример WORKFLOW.claude.md**

Создать `WORKFLOW.claude.md` в корне репозитория (копия `WORKFLOW.md` со сменой бэкенда). Ключевые отличия во фронтматтере:

```yaml
agent:
  kind: claude
  max_concurrent_agents: 1   # осторожный режим под подписку
  max_turns: 20
claude:
  bin: claude
  permission_mode: bypassPermissions
  auth: subscription
  allowed_tools: ["mcp__linear__linear_graphql"]
  turn_timeout_ms: 3600000
  read_timeout_ms: 5000
server:
  port: 4599
  host: 127.0.0.1
```

Тело-промпт — то же, что в `WORKFLOW.md` (Linear MCP / linear_graphql уже упомянут в разделе "Prerequisite"). Скилл-блок `.codex/skills` останется до Плана 2 — добавить комментарий-заметку в начале файла:

```markdown
<!-- NOTE: Codex-скиллы land/commit/push/pull/linear портируются отдельно (План 2).
     До этого агент Claude выполняет эти шаги штатными средствами (git/gh) по тексту workflow. -->
```

- [ ] **Step 2: Полный прогон тестов**

Run: `mise exec -- mix test`
Expected: PASS — все тесты зелёные.

- [ ] **Step 3: Формат и линт**

Run: `mise exec -- mix format && mise exec -- mix credo --strict`
Expected: формат применён; credo без новых нарушений (поправить, если есть).

- [ ] **Step 4: Сборка escript**

Run: `mise exec -- mix build`
Expected: `bin/symphony` собирается без ошибок компиляции.

- [ ] **Step 5: Коммит**

```bash
git add WORKFLOW.claude.md
git commit -m "docs: add example WORKFLOW.claude.md for the Claude backend"
```

---

## Самопроверка плана (выполнена при написании)

**Покрытие спеки:**
- §3 контракт `start_session/run_turn/stop_session` → Tasks 5, 7.
- §3 валидация cwd (PathSafety) → Task 2.
- §3 session-map поля (`thread_id`, `turn_id`, metadata) → Task 7.
- §3 мультитёрн `--resume` → Task 7 (Step 1 тест + маркер).
- §3 словарь событий + `metadata.usage` → Tasks 6, 7.
- §3 авто-approval (`bypassPermissions`) → Task 3 (конфиг) + Task 7 (флаг).
- §3 sandbox → права/allowedTools → Tasks 3, 7.
- §3 `linear_graphql` через Elixir-MCP → Tasks 8, 9, 11.
- §3 таймауты → Tasks 3, 4, 7.
- §4 архитектура `agent.kind` + резолвер → Tasks 3, 5, 10.
- §5 конфиг-секция `claude:` → Tasks 3, 4.
- §7 ошибки/лимиты (ретраибл) → Tasks 6 (limit?), 7 (finalize).
- §7 запрет `--bare`/`--no-session-persistence` → не используются в build_command (Task 7).
- §8 тесты → каждая задача TDD.
- §9 развёртывание WSL2 → раздел ниже (вне кода).
- §5.6 скиллы → вынесены в План 2 (декомпозиция).

**Сканирование плейсхолдеров:** нет "TBD"/"позже"/"аналогично". Весь код приведён целиком.

**Согласованность типов:** `start_session/2`, `run_turn/4`, `stop_session/1` едины в behaviour (Task 5) и обеих реализациях; session-map поля (`kind`, `thread_id`, `workspace`, `worker_host`, `metadata`) консистентны между Task 7 и AgentRunner (Task 10); `DynamicTool.execute/2` арность подтверждена (default opts). Имя сообщения `{:codex_worker_update, …}` не меняется (AgentRunner правит только источник, не тег).

---

## После реализации: ручная проверка в WSL2 (вне автотестов)

1. В WSL2 Ubuntu: установить `git`, `mise`, Claude Code CLI; один раз `claude` → залогиниться подпиской (OAuth).
2. `export LINEAR_API_KEY=...`
3. `mise trust && mise install && mise exec -- mix setup && mise exec -- mix build`
4. Запуск с примером: `mise exec -- ./bin/symphony ./WORKFLOW.claude.md` (порт 4599 поднимет web+MCP).
5. Создать одну задачу в Linear в активном статусе → убедиться, что агент Claude её подхватывает, ходит в `linear_graphql`, ведёт workpad, события идут в дашборд.
6. Следить за лимитами подписки; при упоре — `claude.auth: api_key` + `ANTHROPIC_API_KEY`.
