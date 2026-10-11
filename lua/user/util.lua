local profile = require("user.profile")

local M = {}

-- The current buffer's project: its language's root markers (see
-- user.profile), or the git root.
function M.project_root()
  local language = profile.owner(0)
  local markers = language and profile.languages[language].root_markers or { ".git" }
  local root = vim.fs.root(0, markers)
  if root then
    return root
  end

  local buffer_path = vim.api.nvim_buf_get_name(0)
  return (buffer_path ~= "" and vim.fs.dirname(buffer_path)) or vim.uv.cwd()
end

local runners = {}

-- Close the runner terminal if it is the focused window.
function M.close_focused_runner()
  for _, terminal in pairs(runners) do
    if terminal:is_focused() then
      terminal:close()
      return true
    end
  end
  return false
end

-- Toggle a terminal that runs `cmd` in `root`. Completed output stays visible;
-- the next invocation after the command exits starts a fresh run.
function M.toggle_runner(cmd, root, name)
  -- When invoked from the runner itself, the project buffer is no longer
  -- current, so close the focused runner before trying to detect a root.
  if M.close_focused_runner() then
    return
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
