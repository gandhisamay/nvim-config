local api = vim.api

local i3config_group = api.nvim_create_augroup("SetFileType", { clear = true })
api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  command = "set filetype=i3config",
  pattern = "config",
  group = i3config_group,
})
