vim.g.mapleader = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

map({ "n", "x" }, "<Space>", "<Nop>", { desc = "Leader key" })
map("n", "<A-m>", "q", { desc = "Record macro" })
map("n", "q", "<Nop>", { desc = "Disable default macro key" })
map("n", "<C-a>", "<Cmd>%y+<CR>", { desc = "Copy entire file" })
map("n", "<A-s>", "<Cmd>ASToggle<CR>", { desc = "Toggle autosave" })

map("i", "jk", "<Esc>", { desc = "Exit insert mode" })
map({ "n", "i", "x" }, "<C-s>", "<Cmd>write<CR>", { desc = "Save file" })

map("n", "<C-h>", "<C-w>h", { desc = "Focus left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Focus lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Focus upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Focus right window" })
map("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Focus left window" })
map("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Focus lower window" })
map("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Focus upper window" })
map("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Focus right window" })

map("n", "<S-h>", "<Cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<S-l>", "<Cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<S-w>", "<Cmd>bwipeout<CR><Cmd>bnext<CR>", { desc = "Close current buffer" })
map("n", "<leader>bd", "<Cmd>bdelete<CR>", { desc = "Delete buffer" })

map("n", "<leader>tk", "<C-w>t<C-w>K", { desc = "Make split horizontal" })
map("n", "<leader>th", "<C-w>t<C-w>H", { desc = "Make split vertical" })

map("n", "<C-Up>", "<Cmd>resize +2<CR>", { desc = "Increase window height" })
map("n", "<C-Down>", "<Cmd>resize -2<CR>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<Cmd>vertical resize -2<CR>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<Cmd>vertical resize +2<CR>", { desc = "Increase window width" })

map("x", "<", "<gv", { desc = "Indent left" })
map("x", ">", ">gv", { desc = "Indent right" })
map("x", "J", ":move '>+1<CR>gv=gv", { desc = "Move selection down" })
map("x", "K", ":move '<-2<CR>gv=gv", { desc = "Move selection up" })
map("x", "<A-j>", ":move '>+1<CR>gv=gv", { desc = "Move selection down" })
map("x", "<A-k>", ":move '<-2<CR>gv=gv", { desc = "Move selection up" })
map("x", "p", [["_dP]], { desc = "Paste without replacing register" })

map("n", "<leader>cb", "<Cmd>Test<CR>", { desc = "CPBooster test" })
map("n", "<leader>ct", "<Cmd>Submit<CR>", { desc = "CPBooster submit" })
map("n", "<leader>cn", "<Cmd>!cpb clone<CR>", { desc = "CPBooster clone" })
map("n", "<leader>gt", function()
  require("user.functions.generate_test_cases")()
end, { desc = "Generate CompetiTest cases" })
map("n", "<A-j>", "<Cmd>%!jq<CR>", { desc = "Format JSON with jq" })
map("n", "<leader>w", "<Cmd>!mysql -u root < %<CR>", { desc = "Run file in MySQL" })

map("n", "<Esc>", "<Cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
