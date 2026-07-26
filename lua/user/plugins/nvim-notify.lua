local notify = require("notify")

vim.notify = notify;

notify.setup({
  stages = "fade",
  background_colour = 'FloatShadow',
  timeout = 3000,
})
