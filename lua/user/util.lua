local M = {}

-- Groups of root markers, highest priority first (see :h vim.fs.root()).
-- Language modules in lua/user/lang/ may prepend their own markers.
M.root_markers = { ".git" }

function M.project_root()
  local root = vim.fs.root(0, M.root_markers)
  if root then
    return root
  end

  local buffer_path = vim.api.nvim_buf_get_name(0)
  return (buffer_path ~= "" and vim.fs.dirname(buffer_path)) or vim.uv.cwd()
end

local runners = {}

-- Toggle a terminal that runs `cmd` in `root`. Completed output stays visible;
-- the next invocation after the command exits starts a fresh run.
function M.toggle_runner(cmd, root, name)
  -- When invoked from the runner itself, the project buffer is no longer
  -- current, so close the focused runner before trying to detect a root.
  for _, terminal in pairs(runners) do
    if terminal:is_focused() then
      terminal:close()
      return
    end
  end

  local key = root .. "\0" .. cmd
  local terminal = runners[key]

  if terminal and terminal.job_id and vim.fn.jobwait({ terminal.job_id }, 0)[1] ~= -1 then
    terminal:shutdown()
    runners[key] = nil
    terminal = nil
  end

  if not terminal then
    terminal = require("toggleterm.terminal").Terminal:new({
      cmd = cmd,
      dir = root,
      direction = "horizontal",
      size = 15,
      hidden = true,
      close_on_exit = false,
      display_name = name .. ": " .. vim.fs.basename(root),
    })
    runners[key] = terminal
  end

  terminal:toggle(15)
end

return M
