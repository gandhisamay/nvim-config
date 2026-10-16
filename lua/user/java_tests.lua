-- Runs JUnit tests through jdtls (the java-test bundle) and nvim-dap, and shows
-- them live in a panel: each test is pending, running, passed or failed as the
-- runner reports it. <CR> on a failed test opens its failure output.
--
-- Scopes: the nearest test method, the current class, or every test class of
-- the project (one JVM per module, so a Spring context is built once per
-- module, not per class). Runs requested before jdtls has imported the project
-- wait for it.
local M = {}

local ns = vim.api.nvim_create_namespace("user_java_tests")
local uv = vim.uv

local TEST_LEVEL_CLASS, TEST_LEVEL_METHOD = 5, 6
local TEST_KIND_TESTNG = 2

local icons = { pending = "○", running = "●", passed = "✓", failed = "✗", skipped = "↷" }
local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local highlights = {
  pending = "Comment",
  running = "DiagnosticInfo",
  passed = "DiagnosticOk",
  failed = "DiagnosticError",
  skipped = "DiagnosticWarn",
}

-- jdtls clients that reported ServiceReady.
local ready = {}
-- The run requested while jdtls was still starting: { scope, bufnr, lnum }.
local pending

-- The current (or last) run:
-- { title, scope, root, nodes = { [id] = node }, roots = { node }, classes = { [fq] = uri },
--   started, finished, active }
local run
local panel = { buf = nil, line_nodes = {} }

---------------------------------------------------------------------------
-- jdtls requests
---------------------------------------------------------------------------

local function command(client, bufnr, name, arguments, callback)
  client:request("workspace/executeCommand", { command = name, arguments = arguments }, function(err, result)
    if err then
      vim.notify(string.format("%s: %s", name, err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    callback(result)
  end, bufnr)
end

-- Launch arguments for the given test names, with the full test classpath
-- (the runner's own classpath can miss classes, vscode-java-test#1073).
local function launch_args(client, bufnr, request, uri, callback)
  command(client, bufnr, "vscode.java.test.junit.argument", { vim.json.encode(request) }, function(args)
    if not args then
      vim.notify("jdtls returned no launch arguments; see :JdtShowLogs", vim.log.levels.ERROR)
      return
    end
    if args.errorMessage then
      vim.notify(args.errorMessage, vim.log.levels.WARN)
      return
    end
    args = args.body or args
    local options = vim.json.encode({ scope = "test" })
    command(client, bufnr, "java.project.getClasspaths", { uri, options }, function(result)
      local seen, classpath = {}, {}
      for _, entry in ipairs(vim.list_extend(vim.list_slice(args.classpath or {}), result.classpaths or {})) do
        if not seen[entry] then
          seen[entry] = true
          classpath[#classpath + 1] = entry
        end
      end
      args.classpath = classpath
      callback(args)
    end)
  end)
end

local function nearest_method(lenses, lnum)
  local best
  local function visit(items)
    for _, lens in ipairs(items or {}) do
      local line = lens.range and lens.range.start.line
      if lens.testLevel == TEST_LEVEL_METHOD and line and line < lnum and (not best or line > best.range.start.line) then
        best = lens
      end
      visit(lens.children)
    end
  end
  visit(lenses)
  return best
end

---------------------------------------------------------------------------
-- Runner protocol (org.eclipse.jdt.internal.junit.runner.RemoteTestRunner)
---------------------------------------------------------------------------

-- Fields are comma separated; commas inside names are escaped as `\,`.
local function split_fields(text)
  local fields, current, i = {}, {}, 1
  while i <= #text do
    local char = text:sub(i, i)
    if char == "\\" and i < #text then
      current[#current + 1] = text:sub(i + 1, i + 1)
      i = i + 2
    else
      if char == "," then
        fields[#fields + 1] = table.concat(current)
        current = {}
      else
        current[#current + 1] = char
      end
      i = i + 1
    end
  end
  fields[#fields + 1] = table.concat(current)
  return fields
end

-- `method(com.foo.BarTest)` -> "method", "com.foo.BarTest"
local function split_test_name(name)
  local method, class = name:match("^(.-)%((.*)%)$")
  if method then
    return method, class
  end
  return nil, name
end

local function add_node(group, fields)
  -- id, name, isSuite, testCount, isDynamic, parentId, displayName, paramTypes, uniqueId
  local id = group .. ":" .. fields[1]
  local method, class = split_test_name(fields[2] or "")
  local suite = fields[3] == "true"
  local display = fields[7] ~= "" and fields[7] or fields[2]
  local node = {
    id = id,
    suite = suite,
    class = class,
    method = not suite and method or nil,
    display = suite and display or display:gsub("%(%)$", ""),
    status = "pending",
    children = {},
    trace = {},
  }
  local parent = run.nodes[group .. ":" .. (fields[6] or "")]
  run.nodes[id] = node
  if parent then
    node.parent = parent
    table.insert(parent.children, node)
  else
    table.insert(run.roots, node)
  end
end

local function finish_node(node)
  if node.start then
    node.duration = (uv.hrtime() - node.start) / 1e9
  end
  if node.status == "running" then
    node.status = "passed"
  end
end

-- One reader per runner connection; `group` keeps node ids unique when a
-- project run starts one JVM per module.
local function mk_reader(group, on_change)
  local partial = ""
  local block -- "trace" | "expected" | "actual"
  local failing

  local function handle(line)
    if block then
      local closing = { trace = "%TRACEE", expected = "%EXPECTE", actual = "%ACTUALE" }
      if vim.startswith(line, closing[block]) then
        block = nil
      elseif failing then
        local target = block == "trace" and failing.trace or failing[block]
        target[#target + 1] = line
      end
      return
    end

    local tag = line:match("^%%(%u+)")
    if not tag then
      return
    end
    local rest = line:sub(#tag + 2):gsub("^%s+", "")
    local fields = split_fields(rest)
    local node = run.nodes[group .. ":" .. (fields[1] or "")]

    if tag == "TSTTREE" then
      add_node(group, fields)
    elseif tag == "TESTS" and node then
      node.start = uv.hrtime()
      node.status = vim.startswith(fields[2] or "", "@Ignore: ") and "skipped" or "running"
      run.current = node
    elseif tag == "TESTE" and node then
      finish_node(node)
    elseif (tag == "FAILED" or tag == "ERROR") and node then
      node.status = vim.startswith(fields[2] or "", "@AssumptionFailure: ") and "skipped" or "failed"
      failing = node
    elseif tag == "TRACES" then
      block = "trace"
    elseif tag == "EXPECTS" and failing then
      failing.expected, block = {}, "expected"
    elseif tag == "ACTUALS" and failing then
      failing.actual, block = {}, "actual"
    end
  end

  return vim.schedule_wrap(function(err, chunk)
    assert(not err, err)
    if not chunk then
      return
    end
    local lines = vim.split(partial .. chunk, "\n", { plain = true })
    partial = table.remove(lines)
    for _, line in ipairs(lines) do
      handle((line:gsub("\r$", "")))
    end
    on_change()
  end)
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

-- A suite's status follows its children: failed if any failed, running while
-- any runs, passed once all are done.
local function status_of(node)
  if not node.suite or #node.children == 0 then
    return node.status
  end
  local any_running, any_pending, all_skipped = false, false, true
  for _, child in ipairs(node.children) do
    local status = status_of(child)
    if status == "failed" or node.status == "failed" then
      return "failed"
    end
    any_running = any_running or status == "running"
    any_pending = any_pending or status == "pending"
    all_skipped = all_skipped and status == "skipped"
  end
  if any_running then
    return "running"
  end
  if any_pending then
    return (run.finished and "skipped") or (node.status == "running" and "running") or "pending"
  end
  return all_skipped and "skipped" or "passed"
end

local function counts()
  local result = { total = 0, passed = 0, failed = 0, skipped = 0, done = 0 }
  for _, node in pairs(run.nodes) do
    if not node.suite then
      result.total = result.total + 1
      local status = node.status
      if status == "passed" or status == "failed" or status == "skipped" then
        result[status] = result[status] + 1
        result.done = result.done + 1
      end
    elseif node.status == "failed" and #node.children == 0 then
      -- A class that failed to initialize, without test children.
      result.failed = result.failed + 1
    end
  end
  return result
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function panel_win()
  if not (panel.buf and vim.api.nvim_buf_is_valid(panel.buf)) then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == panel.buf then
      return win
    end
  end
end

local function format_duration(seconds)
  if not seconds then
    return ""
  end
  return seconds >= 60 and string.format("%dm%02ds", seconds / 60, seconds % 60) or string.format("%.1fs", seconds)
end

local function render()
  if not run or not (panel.buf and vim.api.nvim_buf_is_valid(panel.buf)) then
    return
  end
  local lines, marks, line_nodes = {}, {}, {}
  local frame = spinner[math.floor(uv.hrtime() / 1e8) % #spinner + 1]
  local function icon(status)
    return status == "running" and frame or icons[status]
  end

  local c = counts()
  local elapsed = ((run.finished or uv.hrtime()) - run.started) / 1e9
  local state = run.finished and (c.failed > 0 and "failed" or "passed") or "running"
  local header = string.format(" %s %s   ✓ %d  ✗ %d", icon(state), run.title, c.passed, c.failed)
  if c.skipped > 0 then
    header = header .. string.format("  ↷ %d", c.skipped)
  end
  if c.total > 0 then
    header = header .. string.format("   %d/%d", c.done, c.total)
  end
  header = header .. "   " .. format_duration(elapsed)
  lines[1] = header
  marks[1] = { { 0, 4, highlights[state] }, { 4, #header, "Title" } }
  lines[2] = run.status_line or (#run.roots == 0 and " Starting the test JVM…" or "")
  marks[2] = { { 0, #lines[2], "Comment" } }

  local function add(node, depth)
    local status = status_of(node)
    if run.failed_only and status ~= "failed" then
      return
    end
    -- In project runs, fold each class once it has passed so the running and
    -- failed ones stand out; <Tab> unfolds it again.
    if node.suite and node.collapsed == nil and run.scope == "project" and (status == "passed" or status == "skipped") then
      node.collapsed = true
    end
    local indent = string.rep("  ", depth)
    local fold = ""
    if node.suite then
      fold = node.collapsed and "▸ " or "▾ "
    end
    local glyph = icon(status)
    local text = string.format(" %s%s%s %s", indent, fold, glyph, node.display)
    local duration = (not node.suite and status ~= "running") and format_duration(node.duration) or ""
    if status == "running" and node.start then
      duration = format_duration((uv.hrtime() - node.start) / 1e9)
    end
    if duration ~= "" then
      text = text .. "  " .. duration
    end
    lines[#lines + 1] = text
    line_nodes[#lines] = node
    local icon_start = 1 + #indent + #fold
    local name_start = icon_start + #glyph + 1
    marks[#lines] = {
      { icon_start, icon_start + #glyph, highlights[status] },
      { name_start, name_start + #node.display, node.suite and "Directory" or (status == "failed" and "DiagnosticError" or "Normal") },
      { name_start + #node.display, #text, "Comment" },
    }
    if node.suite and not node.collapsed then
      for _, child in ipairs(node.children) do
        add(child, depth + 1)
      end
    end
  end
  for _, root in ipairs(run.roots) do
    add(root, 0)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = " <CR> failure output / go to test · <Tab> fold · F failed only · r rerun · s stop · o JVM output · q close"
  marks[#lines] = { { 0, #lines[#lines], "Comment" } }

  vim.bo[panel.buf].modifiable = true
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  vim.bo[panel.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(panel.buf, ns, 0, -1)
  for line, ranges in pairs(marks) do
    for _, range in ipairs(ranges) do
      if range[2] > range[1] then
        vim.api.nvim_buf_set_extmark(panel.buf, ns, line - 1, range[1], {
          end_col = math.min(range[2], #lines[line]),
          hl_group = range[3],
        })
      end
    end
  end
  panel.line_nodes = line_nodes

  -- Keep the running test in view while the panel isn't focused.
  local win = panel_win()
  if win and win ~= vim.api.nvim_get_current_win() and run.current and not run.finished then
    for line, node in pairs(line_nodes) do
      if node == run.current then
        vim.api.nvim_win_set_cursor(win, { line, 0 })
        break
      end
    end
  end
end

-- File of a class in the project: test classes from jdtls first, then the
-- usual Maven / Gradle source folders.
local function class_file(fq_class)
  local outer = fq_class:gsub("%$.*$", "")
  local uri = run.classes[outer]
  if uri then
    return vim.uri_to_fname(uri)
  end
  local relative = outer:gsub("%.", "/") .. ".java"
  return vim.fn.globpath(run.root, "**/src/*/java/" .. relative, false, true)[1]
end

local function open_location(file, lnum, pattern)
  local target
  -- A normal file window, not the panel, Neo-tree or a float.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == "" and buf ~= panel.buf then
      target = win
      break
    end
  end
  if target then
    vim.api.nvim_set_current_win(target)
  else
    vim.cmd("aboveleft split")
  end
  vim.cmd.edit(vim.fn.fnameescape(file))
  if lnum then
    vim.api.nvim_win_set_cursor(0, { math.min(lnum, vim.api.nvim_buf_line_count(0)), 0 })
  elseif pattern then
    vim.fn.cursor(1, 1)
    vim.fn.search(pattern, "cW")
  end
  vim.cmd("normal! zz")
end

local function jump_to_test(node)
  local file = node.class and class_file(node.class)
  if not file then
    vim.notify("Source of " .. (node.class or node.display) .. " not found", vim.log.levels.WARN)
    return
  end
  local name = node.method or (node.class or ""):match("([%w_]+)$")
  open_location(file, nil, name and ("\\<" .. vim.fn.escape(name, "\\") .. "\\>\\s*[({]") or nil)
end

-- Failure output of a test: expected / actual and the stack trace. <CR> on a
-- stack frame opens it.
local function show_failure(node)
  local lines, marks, frames = {}, {}, {}
  local function add(text, hl)
    lines[#lines + 1] = text
    marks[#lines] = hl
  end
  local top_package = (node.class or ""):match("^([%w_]+%.[%w_]+)")

  add(" " .. (node.class or "") .. (node.method and ("#" .. node.method) or ""), "Title")
  add("")
  if node.expected and node.actual then
    add(" Expected:", "DiagnosticOk")
    for _, line in ipairs(node.expected) do
      add("   " .. line)
    end
    add(" Actual:", "DiagnosticError")
    for _, line in ipairs(node.actual) do
      add("   " .. line)
    end
    add("")
  end
  for _, raw in ipairs(node.trace) do
    local line = raw:gsub("\t", "    ")
    local class, file, lnum = line:match("^%s*at ([%w_.$/]+)%.[%w_$<>]+%(([%w_$]+%.java):(%d+)%)")
    if class then
      class = class:gsub("^.*/", "")
      frames[#lines + 1] = { class = class, lnum = tonumber(lnum) }
      add(" " .. line, (top_package and vim.startswith(class, top_package)) and "Normal" or "Comment")
    elseif line:match("^%s*Caused by:") then
      add(" " .. line, "WarningMsg")
    elseif line:match("^%s*%.%.%. %d+ more") then
      add(" " .. line, "Comment")
    else
      add(" " .. line, "DiagnosticError")
    end
  end
  if #node.trace == 0 then
    add(" The runner reported no stack trace. Press o in the test panel for the JVM output.", "Comment")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for line, hl in pairs(marks) do
    if hl then
      vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, { end_col = #lines[line], hl_group = hl })
    end
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = math.floor(vim.o.columns * 0.85)
  local height = math.min(#lines, math.floor(vim.o.lines * 0.7))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " ✗ " .. node.display .. " ",
    title_pos = "center",
    footer = " <CR> open frame · q close ",
    footer_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<CR>", function()
    local frame = frames[vim.api.nvim_win_get_cursor(win)[1]]
    local file = frame and class_file(frame.class)
    if not file then
      return
    end
    close()
    open_location(file, frame.lnum)
  end, { buffer = buf, nowait = true })
end

local function node_under_cursor()
  return panel.line_nodes[vim.api.nvim_win_get_cursor(0)[1]]
end

local function create_panel()
  local buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, buf, "Java tests")
  vim.bo[buf].filetype = "javatests"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  panel.buf = buf

  local function map(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true })
  end
  map("<CR>", function()
    local node = node_under_cursor()
    if not node then
      return
    end
    if status_of(node) == "failed" and (not node.suite or #node.trace > 0) then
      show_failure(node)
    elseif node.suite and #node.children > 0 then
      node.collapsed = not node.collapsed
      render()
    else
      jump_to_test(node)
    end
  end)
  map("gd", function()
    local node = node_under_cursor()
    if node then
      jump_to_test(node)
    end
  end)
  map("<Tab>", function()
    local node = node_under_cursor()
    while node and not node.suite do
      node = node.parent
    end
    if node then
      node.collapsed = not node.collapsed
      render()
    end
  end)
  map("F", function()
    if run then
      run.failed_only = not run.failed_only
      render()
    end
  end)
  map("r", function()
    if run and run.rerun then
      run.rerun()
    end
  end)
  map("s", function()
    if run and run.active then
      run.status_line = " Stopping…"
      require("dap").terminate()
    end
  end)
  map("o", function()
    require("dap").repl.open()
  end)
  map("q", function()
    vim.api.nvim_win_close(0, false)
  end)
  return buf
end

local function open_panel(focus)
  if not (panel.buf and vim.api.nvim_buf_is_valid(panel.buf)) then
    create_panel()
  end
  local win = panel_win()
  if not win then
    local current = vim.api.nvim_get_current_win()
    vim.cmd("botright 14split")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, panel.buf)
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    vim.wo[win].winfixheight = true
    if not focus then
      vim.api.nvim_set_current_win(current)
    end
  elseif focus then
    vim.api.nvim_set_current_win(win)
  end
  render()
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

local timer

local function schedule_render()
  if run.render_pending then
    return
  end
  run.render_pending = true
  vim.defer_fn(function()
    run.render_pending = false
    render()
  end, 50)
end

-- Run the jobs one after another: { name, kind, request, uri }.
local function start_jobs(client, bufnr, jobs)
  local dap = require("dap")
  local experimental = require("jdtls.dap").experimental

  timer = timer or uv.new_timer()
  timer:stop()
  timer:start(100, 100, vim.schedule_wrap(function()
    if run and run.active then
      render()
    else
      timer:stop()
    end
  end))

  local function finish()
    run.active = false
    run.finished = uv.hrtime()
    run.current = nil
    run.status_line = nil
    render()
    local c = counts()
    local message = c.failed > 0 and string.format("Tests: ✗ %d failed, ✓ %d passed", c.failed, c.passed)
      or string.format("Tests: ✓ %d passed", c.passed)
    vim.notify(message, c.failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
  end

  local function next_job(index)
    local job = jobs[index]
    if not job or run.stopped then
      finish()
      return
    end
    run.status_line = #jobs > 1 and string.format(" Module %s (%d/%d)", job.name, index, #jobs) or nil
    render()
    launch_args(client, bufnr, job.request, job.uri, function(args)
      local config = experimental.make_config({ fullName = run.title, testKind = job.kind }, args)
      -- Lets the dap-ui listeners tell test runs from debug sessions.
      config.nvimTestRun = true
      local server
      dap.run(config, {
        before = function(conf)
          server = assert(uv.new_tcp())
          server:bind("127.0.0.1", 0)
          server:listen(128, function(err)
            assert(not err, err)
            local sock = assert(uv.new_tcp())
            server:accept(sock)
            sock:read_start(mk_reader(index, schedule_render))
          end)
          conf.args = conf.args:gsub("-port ([0-9]+)", "-port " .. server:getsockname().port)
          return conf
        end,
        after = function()
          if server then
            server:shutdown()
            server:close()
          end
          -- Tests still marked running when the JVM exits were cut short.
          for _, node in pairs(run.nodes) do
            if node.status == "running" then
              node.status = "failed"
              node.trace = { "The test JVM exited while this test was running." }
            end
          end
          vim.schedule(function()
            next_job(index + 1)
          end)
        end,
      })
    end)
  end

  next_job(1)
end

local function new_run(title, scope, client, rerun)
  run = {
    title = title,
    scope = scope,
    root = client.root_dir,
    nodes = {},
    roots = {},
    classes = {},
    started = uv.hrtime(),
    active = true,
    rerun = rerun,
  }
  open_panel(false)
end

local function start(scope, bufnr, lnum)
  if run and run.active then
    vim.notify("Tests are already running; press s in the test panel to stop them", vim.log.levels.WARN)
    open_panel(false)
    return
  end
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "jdtls" })[1]
  local uri = vim.uri_from_bufnr(bufnr)
  local rerun = function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      start(scope, bufnr, lnum)
    end
  end

  if scope == "project" then
    new_run(vim.fs.basename(client.root_dir), scope, client, rerun)
    run.status_line = " Finding test classes…"
    render()
    command(client, bufnr, "vscode.java.test.findJavaProjects", { vim.uri_from_fname(client.root_dir) }, function(projects)
      local jobs, remaining = {}, #(projects or {})
      if remaining == 0 then
        run.status_line = " No Java projects found"
        run.active = false
        render()
        return
      end
      for _, project in ipairs(projects) do
        command(client, bufnr, "vscode.java.test.findTestPackagesAndTypes", { project.jdtHandler }, function(packages)
          -- One job per test kind (JUnit 4 / 5) in the module.
          local by_kind = {}
          for _, package in ipairs(packages or {}) do
            for _, class in ipairs(package.children or {}) do
              if class.testKind ~= TEST_KIND_TESTNG then
                run.classes[class.fullName] = class.uri
                by_kind[class.testKind] = by_kind[class.testKind] or { names = {}, uri = class.uri }
                table.insert(by_kind[class.testKind].names, class.fullName)
              end
            end
          end
          for kind, entry in pairs(by_kind) do
            table.sort(entry.names)
            jobs[#jobs + 1] = {
              name = project.projectName,
              kind = kind,
              uri = entry.uri,
              request = {
                testKind = kind,
                projectName = project.projectName,
                testLevel = TEST_LEVEL_CLASS,
                testNames = entry.names,
              },
            }
          end
          remaining = remaining - 1
          if remaining == 0 then
            if #jobs == 0 then
              run.status_line = " No JUnit test classes found"
              run.active = false
              render()
              return
            end
            table.sort(jobs, function(a, b)
              return a.name < b.name
            end)
            start_jobs(client, bufnr, jobs)
          end
        end)
      end
    end)
    return
  end

  command(client, bufnr, "vscode.java.test.findTestTypesAndMethods", { uri }, function(lenses)
    local lens
    if scope == "nearest" then
      lens = nearest_method(lenses, lnum)
    else
      lens = vim.iter(lenses or {}):find(function(item)
        return item.testLevel == TEST_LEVEL_CLASS
      end)
    end
    if not lens then
      vim.notify(scope == "nearest" and "No test method above the cursor" or "No test class in this file")
      return
    end
    if lens.testKind == TEST_KIND_TESTNG then
      -- The TestNG runner speaks another protocol; let nvim-jdtls handle it.
      local jdtls = require("jdtls")
      local fn = scope == "nearest" and jdtls.test_nearest_method or jdtls.test_class
      fn({ bufnr = bufnr, lnum = lnum })
      return
    end

    local class = lens.fullName:gsub("#.*$", "")
    new_run(scope == "nearest" and lens.label or class:match("([%w_$]+)$"), scope, client, rerun)
    run.classes[class] = lens.uri or uri
    start_jobs(client, bufnr, {
      {
        name = lens.projectName,
        kind = lens.testKind,
        uri = uri,
        request = {
          testKind = lens.testKind,
          projectName = lens.projectName,
          testLevel = lens.testLevel,
          testNames = { lens.testLevel == TEST_LEVEL_CLASS and lens.fullName or lens.jdtHandler },
        },
      },
    })
  end)
end

---------------------------------------------------------------------------
-- Readiness and public API
---------------------------------------------------------------------------

local function ready_client(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "jdtls" })) do
    if ready[client.id] then
      return client
    end
  end
end

-- Start the run that was waiting for jdtls, once its buffer has a ready client.
local function flush()
  if pending and vim.api.nvim_buf_is_valid(pending.bufnr) and ready_client(pending.bufnr) then
    local request = pending
    pending = nil
    start(request.scope, request.bufnr, request.lnum)
  end
end

---Record that jdtls finished importing the project (ServiceReady).
---@param client_id integer
function M.mark_ready(client_id)
  ready[client_id] = true
  vim.schedule(flush)
end

---Run the nearest test method, the current class, or every test in the project.
---@param scope "nearest"|"class"|"project"
function M.run(scope)
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  if ready_client(bufnr) then
    start(scope, bufnr, lnum)
    return
  end
  pending = { scope = scope, bufnr = bufnr, lnum = lnum }
  vim.notify("jdtls is still importing the project; the tests start when it's ready")
end

---Show or hide the test panel.
function M.toggle_panel()
  local win = panel_win()
  if win then
    vim.api.nvim_win_close(win, false)
  elseif run then
    open_panel(true)
  else
    vim.notify("No test run yet")
  end
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("user_java_tests", { clear = true }),
  callback = flush,
})

return M
