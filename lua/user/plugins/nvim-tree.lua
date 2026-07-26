local keymap = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

keymap("n", "<leader>y", "<Cmd>NvimTreeToggle<CR>", opts)

require("nvim-tree").setup({
  update_cwd = true,
  update_focused_file = {
    enable = true,
    update_cwd = true
  },
  diagnostics = {
    enable = true,
    show_on_dirs = false,
    debounce_delay = 50,
    icons = {
      hint = "",
      info = "",
      warning = "",
      error = "",
    },
  },
  renderer = {
    icons = {
      glyphs = {
        git = {
          unstaged = "",
          staged = "s",
          unmerged = "",
          renamed = "➜",
          deleted = "",
          untracked = "",
          ignored = "◌",
        },
      },
    },
  },
  git = {
    enable = true,
    ignore = false,
    show_on_dirs = true,
    timeout = 400,
  },
  view = {
    side = "right"
  },
})
