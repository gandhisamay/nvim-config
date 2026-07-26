local opt = vim.opt

-- Neovim may be launched from a terminal that predates the latest .bashrc.
-- Keep Ubuntu-local editor and Go tools available in that case as well.
local local_paths = {
  vim.fn.expand("~/go/bin"),
  vim.fn.expand("~/.local/bin"),
  vim.fn.expand("~/.local/nvim/bin"),
}
for index = #local_paths, 1, -1 do
  local path = local_paths[index]
  if not vim.env.PATH:find(path, 1, true) then
    vim.env.PATH = path .. ":" .. vim.env.PATH
  end
end

-- None of the configured plugins use these language hosts. Disabling them
-- avoids needless provider discovery and startup warnings.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

opt.autoread = true
opt.backup = false
opt.breakindent = true
opt.clipboard = "unnamedplus"
opt.cmdheight = 1
opt.completeopt = { "menu", "menuone", "noselect" }
opt.conceallevel = 0
opt.cursorline = true
opt.expandtab = true
opt.fileencoding = "utf-8"
opt.hlsearch = true
opt.ignorecase = true
opt.mouse = "a"
opt.number = true
opt.numberwidth = 4
opt.pumheight = 12
opt.relativenumber = true
opt.scrolloff = 8
opt.shiftwidth = 2
opt.shortmess:append("I")
opt.showmode = false
opt.showtabline = 2
opt.sidescrolloff = 8
opt.signcolumn = "yes"
opt.smartcase = true
opt.smartindent = true
opt.splitbelow = true
opt.splitright = true
opt.swapfile = true
opt.tabstop = 4
opt.termguicolors = true
opt.timeoutlen = 400
opt.undofile = true
opt.updatetime = 200
opt.whichwrap:append("<,>,[,],h,l")
opt.wrap = false
opt.writebackup = true

local swap_dir = vim.fn.stdpath("state") .. "/swap"
vim.fn.mkdir(swap_dir, "p")
opt.directory = swap_dir .. "//"

-- Prefer the Windows-side clipboard bridge in WSL. This avoids relying on X11.
-- Use the known executable directly: scanning WSL's Windows-heavy PATH here
-- adds roughly 100 ms to every Neovim launch.
local win32yank = "/mnt/c/Program Files/Neovim/bin/win32yank.exe"
if vim.fn.has("wsl") == 1 and vim.uv.fs_stat(win32yank) then
  vim.g.clipboard = {
    name = "win32yank-wsl",
    copy = {
      ["+"] = { win32yank, "-i", "--crlf" },
      ["*"] = { win32yank, "-i", "--crlf" },
    },
    paste = {
      ["+"] = { win32yank, "-o", "--lf" },
      ["*"] = { win32yank, "-o", "--lf" },
    },
    cache_enabled = 0,
  }
end
