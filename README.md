# nvim-config

My Neovim configuration (lazy.nvim, Neovim 0.12+).

## The idea: one branch, languages picked per project

Language tooling is what makes Neovim slow: language servers, debug adapters, test runners,
Treesitter parsers and formatters. A config that loads every language pays for all of them.
So every language lives in its own module, `lua/user/lang/<language>.lua`, and each Neovim
process loads only the languages of the project it was started in.

| Module | What it adds |
|---|---|
| base (`lua/user/plugins/specs.lua`) | Options, keymaps, UI, file explorer, fuzzy finder, git, completion, the LSP / DAP / formatter / Treesitter plumbing, and parsers for files every repo has (bash, json, lua, markdown, vim, yaml). |
| `go` | gopls, gofumpt / goimports, delve debugging, neotest-go, `go run` runner, Go parsers. |
| `java` | Java / Spring Boot: jdtls (with Lombok), Java debugging and tests, Maven runner, parsers for java, xml, properties. Run `scripts/install-java-tools.sh` once per machine. |

Open a Go repo and a Java repo side by side and each Neovim gets its own setup; nothing to switch.

## How languages are picked

`lua/user/profile.lua` decides once, at startup, from the file or directory Neovim was
started on (or the working directory). First match wins:

1. `$NVIM_LANGS`, e.g. `NVIM_LANGS=go,java nvim`, or `NVIM_LANGS=none nvim`.
2. `M.projects` in `profile.lua`, for repos whose files don't tell the full story:
   `["~/work/monorepo"] = { "go" }`.
3. Build files in the project (git root): `go.mod` / `go.work` → go; `pom.xml`, `build.gradle`,
   `mvnw`, … → java. It looks a few levels below the root too, so a repo with `services/api`
   (Maven) and `services/worker` (Go) loads both.
4. The extension of the file being opened, when the project has no build files
   (`nvim ~/scratch/main.go`).

`:Langs` shows what was loaded and which language the current buffer belongs to. The choice is
fixed for the session: `:cd` into another repo doesn't change it, so start a new Neovim there.

## Repos with several languages

Each buffer belongs to one language:

- Source files by filetype: `*.go`, `go.mod`, … → go; `*.java` → java.
- Everything else (`pom.xml`, `application.yml`, a Dockerfile, …) by the **nearest** build file
  above it. `services/api/src/main/resources/application.yml` is Java because
  `services/api/pom.xml` is closer than any `go.mod`.
- A file whose nearest directory has both kinds of build file (a root README next to `pom.xml`
  and `go.mod`) belongs to neither.

LSP, completion, Treesitter and formatting already follow the filetype. Language keys follow
the buffer's language: `<leader>r` is `go run` in Go buffers and `spring-boot:run` in Java
buffers, and tells you when the buffer belongs to no single language. Terminals, pickers and
the file tree act for the last file buffer you were in, so `<leader>r` in a runner closes it.

## How a language module plugs in

`lua/user/lazy.lua` imports every file in `lua/user/lang/`. A module extends the base plugins
through lazy.nvim's spec merging instead of editing base files:

```lua
-- lua/user/lang/<language>.lua
local profile = require("user.profile")
local active = profile.active("<language>")

-- Language-only plugins: always declared, so they stay installed and pinned in the lockfile.
-- `cond` keeps them from loading when the language isn't active.
local plugins = {
  { "<author>/<plugin>", cond = active, ft = "<ft>" },
}

if not active then
  return plugins
end

-- Keys that act only in this language's buffers (other languages may map the same key).
profile.map("<language>", "n", "<leader>r", run_project, "Run project")

return vim.list_extend(plugins, {
  -- Treesitter parsers (appended to the base list).
  { "nvim-treesitter/nvim-treesitter", opts = { languages = { "<parser>" } } },

  -- Language servers (each one is passed to vim.lsp.config() and enabled).
  { "neovim/nvim-lspconfig", opts = { servers = { ["<server>"] = { --[[ settings ]] } } } },

  -- Formatters.
  { "stevearc/conform.nvim", opts = { formatters_by_ft = { ["<ft>"] = { "<formatter>" } } } },
})
```

Then add the language to `M.languages` in `lua/user/profile.lua`: its filetypes, the build files
that mark it, and its project root markers.

Don't use `enabled = false` for this: lazy.nvim treats disabled plugins as removed and drops them
from the lockfile. Base plugins extended by a module (Treesitter, lspconfig, conform, nvim-dap)
are only extended when the language is active, never given a `cond`, since that would turn them
off for every language.

Shared helpers live in `lua/user/util.lua`: `project_root()`, which uses the current buffer's
language root markers, and `toggle_runner(cmd, root, name)` for run-the-project terminals.

## Lockfile

One `lazy-lock.json` pins every plugin, of every language, whichever languages a session loads.

## Adding a language

```sh
# add lua/user/lang/<language>.lua (and scripts/ if the language needs installed tools)
# add the language to M.languages in lua/user/profile.lua
nvim   # in a project of that language; lazy.nvim installs and pins its plugins
git add . && git commit -m "add <language> support" && git push
```
Then add it to the table above.

The old `lua_config`, `go` and `java` branches are from the branch-per-language setup and are
kept only for history. `vim_script` is the previous Vimscript config.

## Requirements

- Neovim 0.12+
- `git`, `rg` (ripgrep), a C compiler (`cc`)
- `tree-sitter` CLI on `PATH` (the nvim-treesitter `main` branch compiles parsers with it)
- A Nerd Font in the terminal (for icons)
- Each language module lists its own extra requirements at the top of
  `lua/user/lang/<language>.lua`.
