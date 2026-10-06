local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local output = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("Unable to install lazy.nvim:\n" .. output)
  end
end

vim.opt.rtp:prepend(lazypath)

-- Each language branch adds lua/user/lang/<language>.lua. The base branch has
-- none. Languages also get their own lockfile, so merging the base branch into
-- a language branch never conflicts on pinned plugin commits.
local config_dir = vim.fn.stdpath("config")
local languages = {}
for name, type in vim.fs.dir(config_dir .. "/lua/user/lang") do
  if type == "file" and name:sub(-4) == ".lua" then
    languages[#languages + 1] = name:sub(1, -5)
  end
end
table.sort(languages)

local spec = { { import = "user.plugins.specs" } }
local lockfile = config_dir .. "/lazy-lock.json"
if #languages > 0 then
  spec[#spec + 1] = { import = "user.lang" }
  lockfile = config_dir .. "/lazy-lock-" .. table.concat(languages, "-") .. ".json"
end

require("lazy").setup(spec, {
  lockfile = lockfile,
  checker = { enabled = false },
  change_detection = { notify = false },
  install = { colorscheme = { "tokyonight", "habamax" } },
  rocks = { enabled = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "netrwPlugin",
        "rplugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
