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

-- Language modules in lua/user/lang/ are always imported, so every plugin
-- stays installed and pinned in one lockfile. Each module loads its plugins
-- only when user.profile picked its language for this project.
local spec = {
  { import = "user.plugins.specs" },
  { import = "user.lang" },
}

require("lazy").setup(spec, {
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
