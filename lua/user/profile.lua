-- Decides which language modules (lua/user/lang/*.lua) this Neovim process
-- loads, and which language each buffer belongs to.
--
-- Languages are picked once, at startup, from the project being opened. First
-- match wins:
--   1. $NVIM_LANGS, e.g. NVIM_LANGS=go,java nvim (or "none")
--   2. M.projects below, for repos whose files don't tell the full story
--   3. build files in the project (go.mod, pom.xml, ...), a few levels deep
--   4. the extension of the file being opened, when the project has none
-- Each Neovim process decides on its own, so a Go repo and a Java repo can be
-- open side by side with different setups.

local M = {}

M.languages = {
  go = {
    filetypes = { "go", "gomod", "gosum", "gowork", "gotmpl" },
    -- Build files that mark a directory as Go.
    markers = { "go.work", "go.mod" },
    -- Project root for pickers and runners (see :h vim.fs.root()).
    root_markers = { { "go.work", "go.mod" }, ".git" },
  },
  java = {
    filetypes = { "java" },
    markers = {
      "pom.xml",
      "build.gradle",
      "build.gradle.kts",
      "settings.gradle",
      "settings.gradle.kts",
      "mvnw",
      "gradlew",
    },
    root_markers = { { "mvnw", "gradlew" }, ".git", { "pom.xml", "build.gradle", "build.gradle.kts" } },
  },
}

-- Explicit languages for a project root (and everything under it), e.g.
--   ["~/work/monorepo"] = { "go" },
M.projects = {}

-- How deep to look for build files below the project root, and directories not
-- worth looking into.
local scan_depth = 3
local scan_limit = 5000
local skip_dirs = {
  bin = true,
  build = true,
  dist = true,
  node_modules = true,
  out = true,
  target = true,
  vendor = true,
}

local function language_names()
  local names = vim.tbl_keys(M.languages)
  table.sort(names)
  return names
end

-- The file or directory Neovim was started on, or the working directory.
local function start_path()
  local arg = vim.fn.argv(0)
  if arg ~= "" and arg ~= "-" then
    return vim.fs.normalize(vim.fn.fnamemodify(arg, ":p"))
  end
  return vim.uv.cwd()
end

local function from_env()
  local value = vim.env.NVIM_LANGS
  if not value or value == "" then
    return nil
  end
  local result = {}
  for name in value:gmatch("[^,%s]+") do
    if M.languages[name] then
      result[name] = true
    elseif name ~= "none" then
      vim.schedule(function()
        vim.notify("NVIM_LANGS: unknown language " .. name, vim.log.levels.WARN)
      end)
    end
  end
  return result
end

local function from_projects(root)
  for path, names in pairs(M.projects) do
    path = vim.fs.normalize(vim.fn.expand(path))
    if root == path or vim.startswith(root, path .. "/") then
      local result = {}
      for _, name in ipairs(names) do
        result[name] = true
      end
      return result
    end
  end
end

local function from_markers(dir, root)
  local by_file = {}
  for name, language in pairs(M.languages) do
    for _, marker in ipairs(language.markers) do
      by_file[marker] = name
    end
  end

  local result = {}

  -- Build files above the start directory, up to the project root.
  for name, language in pairs(M.languages) do
    local found = vim.fs.root(dir, language.markers)
    if found and (found == root or vim.startswith(found, root .. "/")) then
      result[name] = true
    end
  end

  -- Build files below the project root, for repos with several modules. Not
  -- below $HOME or /: they hold many projects, even when tracked by git.
  if root == vim.fs.normalize(vim.uv.os_homedir()) or root == "/" then
    return result
  end
  local seen = 0
  for path, type in
    vim.fs.dir(root, {
      depth = scan_depth,
      skip = function(name)
        return name:sub(1, 1) ~= "." and not skip_dirs[name]
      end,
    })
  do
    seen = seen + 1
    if seen > scan_limit or vim.tbl_count(result) == vim.tbl_count(M.languages) then
      break
    end
    local name = type == "file" and by_file[vim.fs.basename(path)]
    if name then
      result[name] = true
    end
  end

  return result
end

local function from_extension(path)
  if vim.fn.isdirectory(path) == 1 then
    return {}
  end
  local filetype = vim.filetype.match({ filename = path })
  for name, language in pairs(M.languages) do
    if filetype and vim.tbl_contains(language.filetypes, filetype) then
      return { [name] = true }
    end
  end
  return {}
end

local active
local function detect()
  active = from_env()
  if active then
    return
  end

  local path = start_path()
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
  local root = vim.fs.root(dir, ".git") or dir

  active = from_projects(root) or from_markers(dir, root)
  if vim.tbl_isempty(active) then
    active = from_extension(path)
  end
end

--- Whether a language's module is loaded in this Neovim process.
function M.active(name)
  if not active then
    detect()
  end
  return active[name] == true
end

--- Active languages, sorted.
function M.list()
  return vim.tbl_filter(M.active, language_names())
end

-- Language of the last file buffer that had one. Terminals, pickers and the
-- file tree act on behalf of that buffer.
local last

--- The language a buffer belongs to, or nil when no single language does.
function M.owner(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if vim.bo[buf].buftype ~= "" then
    return last
  end

  local names = M.list()
  if #names <= 1 then
    return names[1]
  end

  local filetype = vim.bo[buf].filetype
  for _, name in ipairs(names) do
    if vim.tbl_contains(M.languages[name].filetypes, filetype) then
      return name
    end
  end

  -- pom.xml, application.yml, a README, ...: the nearest build file decides.
  local best, best_length, tie
  for _, name in ipairs(names) do
    local dir = vim.fs.root(buf, M.languages[name].markers)
    if dir then
      if not best_length or #dir > best_length then
        best, best_length, tie = name, #dir, false
      elseif #dir == best_length then
        tie = true
      end
    end
  end
  return not tie and best or nil
end

-- Keys language modules register: actions[mode][lhs][language] = { rhs, desc }.
local actions = {}

local function dispatch(mode, lhs)
  local owner = M.owner(0)
  local action = owner and actions[mode][lhs][owner]
  if action then
    return action.rhs()
  end

  local names = vim.tbl_keys(actions[mode][lhs])
  table.sort(names)
  local message = owner and ("%s has no %s action"):format(owner, lhs)
    or ("%s: this buffer belongs to no single language (%s)"):format(lhs, table.concat(names, ", "))
  vim.notify(message, vim.log.levels.WARN)
end

--- Map a key for one language. The same key can do something different for
--- each language; it acts according to the language of the current buffer.
function M.map(language, mode, lhs, rhs, desc)
  for _, m in ipairs(type(mode) == "table" and mode or { mode }) do
    actions[m] = actions[m] or {}
    actions[m][lhs] = actions[m][lhs] or {}
    actions[m][lhs][language] = { rhs = rhs, desc = desc }

    local descriptions = {}
    for name, action in vim.spairs(actions[m][lhs]) do
      descriptions[#descriptions + 1] = name .. ": " .. action.desc
    end

    vim.keymap.set(m, lhs, function()
      return dispatch(m, lhs)
    end, { desc = table.concat(descriptions, " | ") })
  end
end

vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("user_profile", { clear = true }),
  callback = function(args)
    if vim.bo[args.buf].buftype == "" then
      last = M.owner(args.buf) or last
    end
  end,
})

vim.api.nvim_create_user_command("Langs", function()
  local names = M.list()
  local owner = M.owner(0)
  vim.notify(
    ("Loaded languages: %s\nThis buffer: %s"):format(
      #names > 0 and table.concat(names, ", ") or "none",
      owner or "no single language"
    )
  )
end, { desc = "Show loaded language modules" })

return M
