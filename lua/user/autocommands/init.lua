local group = vim.api.nvim_create_augroup("user_defaults", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank({ timeout = 150 })
  end,
})

vim.filetype.add({
  filename = {
    [vim.fn.expand("~/.config/i3/config")] = "i3config",
    [vim.fn.expand("~/.config/sway/config")] = "i3config",
  },
})
