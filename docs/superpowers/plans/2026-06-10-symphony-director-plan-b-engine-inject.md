# Symphony-as-Director — План B: движковый инжект ролей/knowledge

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`). TDD как в Плане 1; тесты гоняются в WSL: `cd ~/code/symphony/elixir && mise exec -- mix test ...`. Правки файлов — через UNC `\\wsl.localhost\Ubuntu\home\dsevruk\code\symphony\...`.

**Goal:** Дать `Claude.AppServer` инжектить роли/скиллы (`--plugin-dir`) и монтировать knowledge (`--add-dir`) в headless-запуск, конфигурируемо через секцию `claude`.

**Architecture:** Новые поля `claude.plugin_dir` (string) и `claude.add_dirs` ([string]) в Ecto-схеме → `Config.claude_runtime_settings/0` → `Claude.AppServer.build_command` добавляет `--plugin-dir <dir>` и `--add-dir <dir>` (по одному на каждый). Codex-путь не трогаем; всё под `agent.kind: claude`.

**Tech Stack:** Elixir/Ecto, ExUnit, фейковый `claude` (argv-trace) — паттерны из Плана 1.

---

## Task 1: Схема + конфиг (plugin_dir, add_dirs)

**Files:**
- Modify: `lib/symphony_elixir/config/schema.ex` (модуль `Claude`)
- Modify: `lib/symphony_elixir/config.ex` (`claude_runtime_settings/0` + `@type`)
- Modify: `test/support/test_support.exs` (overrides + `claude_yaml`)
- Test: `test/symphony_elixir/config_claude_test.exs` (дополнить)

- [ ] **Step 1: Дописать падающий тест**

В `test/symphony_elixir/config_claude_test.exs` добавить:
```elixir
  test "claude plugin_dir and add_dirs parse and surface via runtime settings" do
    write_workflow_file!(Workflow.workflow_file_path(),
      agent_kind: "claude",
      claude_plugin_dir: "/home/u/sym/knowledge/sym-plugin",
      claude_add_dirs: ["/home/u/sym/knowledge"]
    )

    c = Config.settings!().claude
    assert c.plugin_dir == "/home/u/sym/knowledge/sym-plugin"
    assert c.add_dirs == ["/home/u/sym/knowledge"]

    assert {:ok, rt} = Config.claude_runtime_settings()
    assert rt.plugin_dir == "/home/u/sym/knowledge/sym-plugin"
    assert rt.add_dirs == ["/home/u/sym/knowledge"]
  end
```

- [ ] **Step 2: Запустить — упадёт**

Run: `cd ~/code/symphony/elixir && mise exec -- mix test test/symphony_elixir/config_claude_test.exs`
Expected: FAIL — `key :plugin_dir not found` / `:claude_plugin_dir` override не рендерится.

- [ ] **Step 3: Добавить поля в схему `Claude`**

В `lib/symphony_elixir/config/schema.ex`, в `defmodule Claude` embedded_schema, после `field(:mcp_token, :string)` добавить:
```elixir
      field(:plugin_dir, :string)
      field(:add_dirs, {:array, :string}, default: [])
```
И в `cast(..., [...], ...)` добавить `:plugin_dir, :add_dirs` в список полей.

- [ ] **Step 4: Surface в `Config`**

В `lib/symphony_elixir/config.ex`: в `@type claude_runtime_settings` добавить `plugin_dir: String.t() | nil, add_dirs: [String.t()]`; в map результата `claude_runtime_settings/0` добавить `plugin_dir: c.plugin_dir, add_dirs: c.add_dirs`.

- [ ] **Step 5: Расширить `test_support.exs`**

(a) В defaults `Keyword.merge([...])` после `claude_mcp_token: nil,` добавить:
```elixir
          claude_plugin_dir: nil,
          claude_add_dirs: [],
```
(b) После `claude_mcp_token = Keyword.get(config, :claude_mcp_token)` добавить:
```elixir
    claude_plugin_dir = Keyword.get(config, :claude_plugin_dir)
    claude_add_dirs = Keyword.get(config, :claude_add_dirs)
```
(c) В вызове `claude_yaml(...)` добавить в keyword:
```elixir
          plugin_dir: claude_plugin_dir,
          add_dirs: claude_add_dirs,
```
(d) В функции `claude_yaml(opts)` в список добавить:
```elixir
      opts[:plugin_dir] && "  plugin_dir: #{yaml_value(opts[:plugin_dir])}",
      "  add_dirs: #{yaml_value(opts[:add_dirs] || [])}",
```

- [ ] **Step 6: Запустить — пройдёт**

Run: `cd ~/code/symphony/elixir && mise exec -- mix test test/symphony_elixir/config_claude_test.exs`
Expected: PASS.

- [ ] **Step 7: Коммит**

```bash
cd ~/code/symphony && git add elixir/lib/symphony_elixir/config/schema.ex elixir/lib/symphony_elixir/config.ex elixir/test/support/test_support.exs elixir/test/symphony_elixir/config_claude_test.exs && git commit -q -m "feat: add claude.plugin_dir and claude.add_dirs config"
```

---

## Task 2: `Claude.AppServer` — флаги `--plugin-dir` и `--add-dir`

**Files:**
- Modify: `lib/symphony_elixir/claude/app_server.ex` (`build_command` + хелперы)
- Test: `test/symphony_elixir/claude/app_server_test.exs` (дополнить)

- [ ] **Step 1: Дописать падающий тест**

В `test/symphony_elixir/claude/app_server_test.exs` добавить (использует фейковый `claude` из `setup`):
```elixir
  test "passes --plugin-dir and --add-dir when configured", %{ws: ws, argv_trace: trace, root: root, fake: fake} do
    write_workflow_file!(Workflow.workflow_file_path(),
      agent_kind: "claude",
      workspace_root: root,
      claude_bin: fake,
      claude_plugin_dir: "/home/u/sym/knowledge/sym-plugin",
      claude_add_dirs: ["/home/u/sym/knowledge"]
    )

    {:ok, session} = AppServer.start_session(ws, [])
    {:ok, _} = AppServer.run_turn(session, "go", issue(), on_message: fn _ -> :ok end)
    AppServer.stop_session(session)

    argv = File.read!(trace)
    assert argv =~ "--plugin-dir"
    assert argv =~ "sym-plugin"
    assert argv =~ "--add-dir"
    assert argv =~ "/home/u/sym/knowledge"
  end
```

- [ ] **Step 2: Запустить — упадёт**

Run: `cd ~/code/symphony/elixir && mise exec -- mix test test/symphony_elixir/claude/app_server_test.exs`
Expected: FAIL — argv без `--plugin-dir`/`--add-dir`.

- [ ] **Step 3: Реализовать**

В `lib/symphony_elixir/claude/app_server.ex`, в `build_command`, добавить в конкатенацию `base` (например, после `mcp_args(rt) ++`) вызовы `plugin_args(rt) ++ add_dir_args(rt) ++`. И добавить хелперы:
```elixir
  defp plugin_args(%{plugin_dir: dir}) when is_binary(dir) and dir != "",
    do: ["--plugin-dir", shell_escape(dir)]

  defp plugin_args(_rt), do: []

  defp add_dir_args(%{add_dirs: dirs}) when is_list(dirs) do
    Enum.flat_map(dirs, fn dir -> ["--add-dir", shell_escape(dir)] end)
  end

  defp add_dir_args(_rt), do: []
```

- [ ] **Step 4: Запустить — пройдёт**

Run: `cd ~/code/symphony/elixir && mise exec -- mix test test/symphony_elixir/claude/app_server_test.exs`
Expected: PASS (все тесты файла).

- [ ] **Step 5: Коммит**

```bash
cd ~/code/symphony && git add elixir/lib/symphony_elixir/claude/app_server.ex elixir/test/symphony_elixir/claude/app_server_test.exs && git commit -q -m "feat: inject --plugin-dir and --add-dir in Claude.AppServer"
```

---

## Task 3: Полный прогон + формат + credo

- [ ] **Step 1: Прогон/формат/линт**

Run:
```bash
cd ~/code/symphony/elixir && mise exec -- mix format && mise exec -- mix test 2>&1 | tail -4 && mise exec -- mix credo --strict 2>&1 | tail -4
```
Expected: все тесты зелёные; credo «no issues».

- [ ] **Step 2: Сборка escript**

Run: `cd ~/code/symphony/elixir && mise exec -- mix build`
Expected: `bin/symphony` собирается.

- [ ] **Step 3: Коммит формата (если правил)**

```bash
cd ~/code/symphony && git add -A && git commit -q -m "chore: format" || echo "nothing"
```

---

## Самопроверка плана

**Покрытие спеки §8:** `claude.plugin_dir` → Task 1+2; `claude.add_dirs` → Task 1+2. (Telegram-MCP — План D; проза WORKFLOW — План C.)
**Плейсхолдеры:** код приведён целиком; `/home/u/...` — тестовые значения.
**Согласованность:** имена полей `plugin_dir`/`add_dirs` едины в схеме, `Config`, `test_support`, тестах; `claude_yaml(opts)` уже принимает keyword (рефактор из Плана 1), добавляем ключи `plugin_dir`/`add_dirs`.

## Дальше
- **План C:** `WORKFLOW.turbo-wedge.md` — проза пайплайна + `claude.plugin_dir: ~/sym/knowledge/sym-plugin`, `claude.add_dirs: [~/sym/knowledge]`, `tracker.project_slug: eba744f08eb5`, `workspace.root: ~/sym/workspaces`, хук клонирования `turbo-wedge`.
- Подготовка прогона: статусы Linear (Discovery/Design/Review/Waiting/Human Review), `gh` в WSL (для PR), тестовый тикет в Todo.
