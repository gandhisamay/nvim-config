local Terminal = require('toggleterm.terminal').Terminal

local horizontalTerm = Terminal:new({

  cmd = "zsh",
  dir = "%:p:h",
  -- direction = "horizontal",
  direction = "horizontal",
  -- function to run on opening the terminal
  on_open = function(_)
    vim.cmd("startinsert!")
  end,
  -- function to run on closing the terminal
  on_close = function(_)
    vim.cmd("startinsert!")
  end,
})

function HorizontalTermToggle()
  horizontalTerm:toggle()
end

vim.api.nvim_set_keymap("n", "<leader>h", "<cmd>lua HorizontalTermToggle()<CR>", { noremap = true, silent = true })

local floatTerm = Terminal:new({

  cmd = "zsh",
  dir = "%:p:h",
  -- direction = "horizontal",
  direction = "float",
  -- function to run on opening the terminal
  on_open = function(_)
    vim.cmd("startinsert!")
  end,
  -- function to run on closing the terminal
  on_close = function(_)
    vim.cmd("startinsert!")
  end,
})

function FloatTermToggle()
  floatTerm:toggle()
end

vim.api.nvim_set_keymap("n", "<leader>m", "<cmd>lua FloatTermToggle()<CR>", { noremap = true, silent = true })
