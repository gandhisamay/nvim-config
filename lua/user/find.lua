-- VS Code style find box: a small input floating at the top-right of the
-- window. Matches are highlighted in the file while typing (Search /
-- CurSearch) and the cursor jumps to the nearest one.
local M = {}

local function to_pattern(query)
  -- Literal match; case-insensitive unless the query has an uppercase letter.
  local case = query:find("%u") and "\\C" or "\\c"
  return "\\V" .. case .. vim.fn.escape(query, "\\")
end

function M.open(initial)
  local target = vim.api.nvim_get_current_win()
  local origin = vim.api.nvim_win_get_cursor(target)
  local pattern
  local closed = false

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  -- Keeps nvim-cmp and nvim-autopairs out of the box (see plugins/specs.lua).
  vim.bo[buf].filetype = "findbox"
  vim.b[buf].completion = false
  local width = math.min(40, vim.api.nvim_win_get_width(target) - 4)
  local box = vim.api.nvim_open_win(buf, true, {
    relative = "win",
    win = target,
    anchor = "NE",
    row = 0,
    col = vim.api.nvim_win_get_width(target),
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " Find ",
    title_pos = "left",
    footer = "",
    footer_pos = "right",
  })

  local function set_footer(text)
    vim.api.nvim_win_set_config(box, { footer = text, footer_pos = "right" })
  end

  -- Highlights are window matches, not 'hlsearch': v:hlsearch set from the
  -- TextChanged autocmd is restored when the autocmd returns, so a previous
  -- :nohlsearch would hide every match.
  local all_match, current_match
  local function clear_matches()
    for _, id in ipairs({ all_match, current_match }) do
      pcall(vim.fn.matchdelete, id, target)
    end
    all_match, current_match = nil, nil
  end

  local function update_count()
    local count = vim.api.nvim_win_call(target, function()
      return vim.fn.searchcount({ recompute = true, maxcount = 9999 })
    end)
    if count.total == 0 then
      set_footer(" No results ")
    elseif count.incomplete == 2 then
      set_footer((" %d of %d+ "):format(count.current, count.maxcount))
    else
      set_footer((" %d of %d "):format(count.current, count.total))
    end
  end

  -- Search from `from` in the target window, keeping the match on screen.
  local function jump(flags, from)
    if current_match then
      pcall(vim.fn.matchdelete, current_match, target)
      current_match = nil
    end
    vim.api.nvim_win_call(target, function()
      if from then
        vim.api.nvim_win_set_cursor(target, from)
      end
      local line, col = unpack(vim.fn.searchpos(pattern, flags))
      if line == 0 then
        return
      end
      local _, end_col = unpack(vim.fn.searchpos(pattern, "cne"))
      current_match = vim.fn.matchaddpos("IncSearch", { { line, col, end_col - col + 1 } }, 20)
      if line < vim.fn.line("w0") or line > vim.fn.line("w$") then
        vim.cmd("normal! zz")
      end
    end)
    update_count()
  end

  local function on_change()
    local query = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    clear_matches()
    if query == "" then
      pattern = nil
      vim.api.nvim_win_set_cursor(target, origin)
      set_footer("")
      return
    end
    pattern = to_pattern(query)
    vim.fn.setreg("/", pattern)
    all_match = vim.fn.matchadd("Search", pattern, 10, -1, { window = target })
    jump("cw", origin)
  end

  local function close()
    if closed then
      return
    end
    closed = true
    clear_matches()
    if pattern then
      vim.fn.histadd("/", pattern)
      -- Hand the highlighting over to 'hlsearch' so n/N keep working and
      -- <Esc> clears it. Scheduled to run outside any autocmd.
      vim.schedule(function()
        vim.v.hlsearch = 1
      end)
    end
    if vim.api.nvim_win_is_valid(box) then
      vim.api.nvim_win_close(box, true)
    end
    if vim.api.nvim_win_is_valid(target) then
      vim.api.nvim_set_current_win(target)
    end
    vim.cmd("stopinsert")
  end

  local function step(flags)
    return function()
      if pattern then
        jump(flags)
      end
    end
  end

  local opts = { buffer = buf, nowait = true }
  vim.keymap.set({ "i", "n" }, "<CR>", step("w"), opts)
  vim.keymap.set({ "i", "n" }, "<S-CR>", step("bw"), opts)
  vim.keymap.set({ "i", "n" }, "<Down>", step("w"), opts)
  vim.keymap.set({ "i", "n" }, "<Up>", step("bw"), opts)
  vim.keymap.set({ "i", "n" }, "<C-n>", step("w"), opts)
  vim.keymap.set({ "i", "n" }, "<C-p>", step("bw"), opts)
  vim.keymap.set({ "i", "n" }, "<Esc>", close, opts)

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = buf, callback = on_change })
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })

  if initial and initial ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { initial })
    on_change()
  end
  vim.cmd("startinsert!")
end

return M
