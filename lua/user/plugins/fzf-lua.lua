local opts = { noremap = true, silent = true }
local keymap = vim.api.nvim_set_keymap

keymap("n", "<leader>f", "<Cmd>FzfLua files<cr>", opts)
keymap("n", "<leader>l", "<Cmd>FzfLua live_grep<CR>", opts)
keymap("n", "<leader>i", "<Cmd>FzfLua lsp_code_actions<Cr>", opts)
