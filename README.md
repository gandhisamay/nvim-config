# nvim-config

My Neovim configuration (lazy.nvim, Neovim 0.12+).

## The idea: one base, one branch per language

Language tooling is what makes Neovim slow: language servers, debug adapters, test runners,
Treesitter parsers and formatters. A config that carries every language pays for all of them.
So this repo keeps languages apart:

- **`lua_config` is the base.** It holds everything that isn't tied to one language: options,
  keymaps, UI, file explorer, fuzzy finder, git, completion, the LSP / DAP / formatter / Treesitter
  plumbing, and parsers for files every repo has (bash, json, lua, markdown, vim, yaml).
  It has **no** language servers or language-specific plugins.
- **Each language gets its own branch** built on top of the base. It adds exactly one file,
  `lua/user/lang/<language>.lua`, plus any setup scripts that language needs.
- **Base changes flow into every language branch.** Language changes never flow back into the base.

| Branch | What it adds |
|---|---|
| `lua_config` | General base. No language tooling. |
| `java` | Java / Spring Boot: jdtls (with Lombok), Java debugging and tests, Maven runner, parsers for java, xml, properties. Run `scripts/install-java-tools.sh` once per machine. |
| `go` | Go: gopls, gofumpt / goimports, delve debugging, neotest-go, `go run` runner, Go parsers. |

The old `vim_script` branch is the previous Vimscript config and isn't part of this scheme.

## How the language layer plugs in

`lua/user/lazy.lua` looks for files in `lua/user/lang/`. If any exist, it imports them as extra
lazy.nvim specs. A language file extends the base plugins through lazy.nvim's spec merging
instead of editing base files:

```lua
-- lua/user/lang/<language>.lua
return {
  -- Treesitter parsers (appended to the base list).
  { "nvim-treesitter/nvim-treesitter", opts = { languages = { "<parser>" } } },

  -- Language servers (each one is passed to vim.lsp.config() and enabled).
  { "neovim/nvim-lspconfig", opts = { servers = { ["<server>"] = { --[[ settings ]] } } } },

  -- Formatters.
  { "stevearc/conform.nvim", opts = { formatters_by_ft = { ["<ft>"] = { "<formatter>" } } } },

  -- Extra keys, e.g. a project runner (see user.util.toggle_runner).
  { "akinsho/toggleterm.nvim", keys = { { "<leader>r", function() --[[ ... ]] end } } },

  -- Language-only plugins, loaded on their filetype.
  { "<author>/<plugin>", ft = "<ft>" },
}
```

Shared helpers live in `lua/user/util.lua`: `project_root()` with a `root_markers` list that
language files may prepend to, and `toggle_runner(cmd, root, name)` for run-the-project terminals.

### Lockfiles

Every branch pins its own plugin versions so merges never conflict on them:

- base: `lazy-lock.json`
- a language branch: `lazy-lock-<language>.json`

`lazy-lock.json` is still present on language branches (inherited from the base) but unused there.

## Workflow

**A general change** (keymap, UI, a plugin every language uses): make it on `lua_config`, then
merge it into each language branch.
```sh
git switch lua_config
# edit, commit
git push

for b in java go; do
  git switch "$b" && git merge --no-edit lua_config && git push
done
```
Because language branches only add files the base never touches, these merges don't conflict.

**A language change:** make it on that language's branch, in `lua/user/lang/<language>.lua`.
Never merge a language branch into `lua_config`.

**A new language:**
```sh
git switch lua_config
git switch -c <language>
# add lua/user/lang/<language>.lua (and scripts/ if the language needs installed tools)
nvim   # lazy.nvim writes lazy-lock-<language>.json
git add . && git commit -m "add <language> support" && git push -u origin <language>
```
Then add the branch to the table above, on `lua_config`, and merge that into every branch.

**Switching language on this machine:** `~/.config/nvim` is a symlink to this repo, so
`git switch java` (or `go`, …) and restart Neovim. To run two languages side by side, check a
second branch out as a worktree and point an `NVIM_APPNAME` at it:
```sh
git worktree add ~/projects/nvim-config-go go
ln -s ~/projects/nvim-config-go ~/.config/nvim-go
NVIM_APPNAME=nvim-go nvim     # Go config, with its own plugin and state dirs
```

## What belongs where

| Goes in `lua_config` (base) | Goes in a language branch |
|---|---|
| Options, keymaps, colorscheme, statusline | Language servers and their settings |
| File explorer, fuzzy finder, git, terminal | Language-only plugins (jdtls, dap-go, …) |
| Completion, snippets engine | Debug adapter setup for that language |
| LSP keymaps and diagnostics (on `LspAttach`) | Test adapters for that language |
| DAP core, its UI and generic step keys | Formatters for that language |
| Treesitter setup and common-file parsers | Treesitter parsers for that language |
| Formatter plumbing (`F` to format) | Filetype indentation / filetype detection |
| | Project runner command, root markers |

## Requirements

- Neovim 0.12+
- `git`, `rg` (ripgrep), a C compiler (`cc`)
- `tree-sitter` CLI on `PATH` (the nvim-treesitter `main` branch compiles parsers with it)
- A Nerd Font in the terminal (for icons)
- Language branches list their own extra requirements at the top of `lua/user/lang/<language>.lua`.
