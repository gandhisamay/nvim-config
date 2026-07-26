local status_ok, dashboard = pcall(require, "dashboard")
if not status_ok then
  print("Dashboard plugin not found!")
  return
end


dashboard.setup {
  theme = 'hyper',
  config = {
    week_header = {
      enable = true,
    },
    shortcut = {
      {
        desc = ' Files',
        group = 'Label',
        action = 'FzfLua files',
        key = 'f',
      },
      {
        desc = ' dotfiles',
        group = 'Number',
        action = ":lua require('fzf-lua').files({ cwd='~/dotfiles/' })",
        key = 'd',
      },
    },
  },

}
