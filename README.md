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
| `java` | Java / Spring Boot: jdtls (with Lombok), Java debugging and tests, Maven runner, parsers for java, xml, properties. In Spring Boot projects, the Spring Boot language server (spring-boot.nvim) adds completion, hover and validation in `application*.properties` / `.yml` (keys without metadata, like custom `@Value` keys, are hints, not warnings) and bean / endpoint search. Run `scripts/install-java-tools.sh` once per machine. jdtls starts (and indexes the project) at launch, even when you open a non-Java file, then warms its JIT with a few read-only requests (`lua/user/java_warmup.lua`); set `NVIM_JAVA_WARMUP=0` to start it only when a Java file is opened. |

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

## Keymaps

`<leader>` is `<Space>`. Mode is normal unless noted (`x` = visual, `i` = insert, `t` = terminal).

### Files, search and navigation

| Key | Action |
|---|---|
| `<leader>f` / `<leader>ff` | Find project files |
| `<leader>l` / `<leader>fg` | Live grep project |
| `<leader>fb` | Find buffers |
| `<leader>fr` | Recent files |
| `<leader>fs` | Document symbols |
| `<leader>fh` | Help tags |
| `<leader>/` | Find in file |
| `<leader>*` | Find word under cursor in file |
| `<Esc>` | Clear search highlight |
| `<leader>y` | Toggle file explorer |
| `<leader>yg` | Toggle git explorer |
| `<leader>a` | Toggle symbol outline |
| `{` / `}` | Previous / next symbol (in the outline) |

### Buffers and windows

| Key | Action |
|---|---|
| `<S-h>` / `<S-l>` | Previous / next buffer |
| `<S-w>` | Close current buffer |
| `<leader>bd` | Delete buffer |
| `<C-h>` `<C-j>` `<C-k>` `<C-l>` | Focus left / lower / upper / right window (also in `t`) |
| `<C-Up>` / `<C-Down>` | Increase / decrease window height |
| `<C-Left>` / `<C-Right>` | Decrease / increase window width (also in `t`) |
| `<leader>tk` / `<leader>th` | Make split horizontal / vertical |

### Editing

| Key | Action |
|---|---|
| `jk` (`i`) | Exit insert mode |
| `<C-s>` (`n`, `i`, `x`) | Save file |
| `<C-a>` | Copy entire file |
| `<A-s>` | Toggle autosave |
| `<A-m>` | Record macro (`q` is disabled) |
| `<` / `>` (`x`) | Indent left / right, keeping the selection |
| `J` / `K`, `<A-j>` / `<A-k>` (`x`) | Move selection down / up |
| `p` (`x`) | Paste without replacing the register |
| `F` | Format buffer |
| `<A-j>` | Format JSON with `jq` |

### LSP and diagnostics

| Key | Action |
|---|---|
| `gd` / `gD` | Go to definition / declaration |
| `gr` | Find references |
| `gi` / `gI` | Go to implementation |
| `K` | Hover documentation |
| `<C-k>` | Signature help |
| `<leader>rn` | Rename symbol |
| `<leader>ca` / `<leader>i` | Code action (`ca` also in `x`) |
| `<leader>ld` / `gl` | Line diagnostics |
| `<leader>q` | Diagnostics list |
| `[d` / `]d` | Previous / next diagnostic |
| `<leader>uh` | Toggle inlay hints |

### Git

| Key | Action |
|---|---|
| `<leader>g` | LazyGit |
| `<leader>df` | Preview changed hunk (old code) |
| `<leader>dr` | Reset hunk (revert to committed code) |
| `<leader>dR` | Reset buffer (revert all changes in the file) |

### Terminals

| Key | Action |
|---|---|
| `<leader>h` / `<leader>tt` | Horizontal terminal |
| `<leader>m` / `<leader>tf` | Floating terminal |
| `<C-q>` (`t`) | Hide terminal |

### Debugging

| Key | Action |
|---|---|
| `<F5>` | Debug continue |
| `<F10>` / `<F11>` / `<F12>` | Step over / into / out |
| `<leader>db` | Toggle breakpoint |
| `<leader>du` | Toggle debug UI |

### Claude Code

| Key | Action |
|---|---|
| `<leader>ai` | Toggle Claude Code |
| `<C-.>` (`n`, `i`, `x`, `t`) | Focus Claude Code |
| `<leader>xf` | Send file to Claude Code |
| `<leader>xv` (`x`) | Send selection to Claude Code |

### Sessions

| Key | Action |
|---|---|
| `<leader>qs` | Restore session |
| `<leader>ql` | Restore last session |
| `<leader>qS` | Select session |
| `<leader>qd` | Don't save this session |

### Language-specific

Only active in buffers of that language (see [How languages are picked](#how-languages-are-picked)).

| Key | Go | Java |
|---|---|---|
| `<leader>r` | `go run .` | Run Spring Boot app |
| `<leader>tn` | Run nearest test | Run nearest test |
| `<leader>tF` | Run test file | Run test class |
| `<leader>tA` | | Run all project tests |
| `<leader>ts` | Test summary | Test panel (live results; `<CR>` on a failure shows its output) |
| `<leader>to` | Test output | |
| `<leader>da` | Debug with arguments | |
| `<leader>dt` | Debug Go test | |
| `<leader>oi` | | Organize imports |
| `<leader>ev` (`n`, `x`) | | Extract variable |
| `<leader>ec` | | Extract constant |
| `<leader>em` (`x`) | | Extract method |
| `<leader>fe` | | Find Spring endpoints (request mappings) |
| `<leader>fB` | | Find Spring beans |

### Misc

| Key | Action |
|---|---|
| `<leader>cb` / `<leader>ct` / `<leader>cn` | CPBooster test / submit / clone |
| `<leader>w` | Run file in MySQL |

## Requirements

- Neovim 0.12+
- `git`, `rg` (ripgrep), a C compiler (`cc`)
- `tree-sitter` CLI on `PATH` (the nvim-treesitter `main` branch compiles parsers with it)
- A Nerd Font in the terminal (for icons)
- Each language module lists its own extra requirements at the top of
  `lua/user/lang/<language>.lua`.
