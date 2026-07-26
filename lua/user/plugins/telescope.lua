local status_ok, telescope = pcall(require, "telescope")
if not status_ok then
  print("Telescope plugin not found!")
  return
end

telescope.setup({
  pickers = {
    find_files = {
      hidden = true
    }
  }
})


local opts = { noremap = true, silent = true }
local keymap = vim.api.nvim_set_keymap

-- -- this keymap shows all the files in the current working directory.
-- keymap("n", "<leader>ff", "<Cmd>Telescope find_files<cr>", opts)
-- -- need to install the ripgrep binary to use this live_grep feature. Awesome feature exactly what I was looking for.
-- keymap("n", "<leader>fg", "<Cmd>Telescope live_grep<cr>", opts)
-- -- This keymap is used to open a specific buffer from a list of buffers.
-- keymap("n", "<leader>fb", "<Cmd>Telescope buffers<cr>", opts)
-- -- Opens help center where we can get results of :help command.
-- keymap("n", "<leader>fh", "<Cmd>Telescope help_tags<cr>", opts)
