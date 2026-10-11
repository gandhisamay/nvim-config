-- Go support. Loaded when user.profile finds Go in the project.
-- Requires: go, gopls and dlv in ~/go/bin (go install golang.org/x/tools/gopls@latest,
-- go install github.com/go-delve/delve/cmd/dlv@latest), gofumpt and goimports for formatting.

local profile = require("user.profile")
local util = require("user.util")

local active = profile.active("go")

-- Go-only plugins are always declared so they stay installed and pinned in the
-- lockfile; `cond` keeps them from loading when Go isn't active.
local plugins = {
  {
    "leoluz/nvim-dap-go",
    cond = active,
    lazy = true,
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {},
  },

  {
    "nvim-neotest/neotest",
    cond = active,
    lazy = true,
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/neotest-go",
    },
    init = function()
      -- neotest-go still calls the removed-in-future compatibility helper.
      -- Keep its behavior without emitting a deprecation warning on Nvim 0.12.
      if vim.fn.has("nvim-0.12") == 1 then
        vim.tbl_flatten = function(value)
          return vim.iter(value):flatten(math.huge):totable()
        end
      end
    end,
    config = function()
      require("neotest").setup({
        adapters = {
          require("neotest-go")({
            experimental = { test_table = true },
            args = { "-count=1", "-timeout=60s" },
          }),
        },
      })
    end,
  },
}

if not active then
  return plugins
end

local go_bin = vim.fn.expand("~/go/bin")
if not vim.env.PATH:find(go_bin, 1, true) then
  vim.env.PATH = go_bin .. ":" .. vim.env.PATH
end

vim.filetype.add({ extension = { gotmpl = "gotmpl" } })

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_go", { clear = true }),
  pattern = "go",
  callback = function()
    vim.bo.expandtab = false
    vim.bo.shiftwidth = 0
    vim.bo.softtabstop = 0
    vim.bo.tabstop = 4
  end,
})

local function parse_command_line_arguments(input)
  local arguments = {}
  local current = {}
  local quote
  local escaped = false
  local token_started = false

  for index = 1, #input do
    local character = input:sub(index, index)

    if escaped then
      current[#current + 1] = character
      escaped = false
    elseif character == "\\" and quote ~= "'" then
      escaped = true
      token_started = true
    elseif quote then
      if character == quote then
        quote = nil
      else
        current[#current + 1] = character
      end
    elseif character == '"' or character == "'" then
      quote = character
      token_started = true
    elseif character:match("%s") then
      if token_started then
        arguments[#arguments + 1] = table.concat(current)
        current = {}
        token_started = false
      end
    else
      current[#current + 1] = character
      token_started = true
    end
  end

  if escaped then
    return nil, "Go arguments end with an unfinished escape"
  end
  if quote then
    return nil, "Go arguments contain an unclosed " .. quote .. " quote"
  end
  if token_started then
    arguments[#arguments + 1] = table.concat(current)
  end

  return arguments
end

-- Keys act in Go buffers only; other languages may map the same keys.
local function map(lhs, rhs, desc)
  profile.map("go", "n", lhs, rhs, desc)
end

map("<leader>r", function()
  util.toggle_runner("go run .", util.project_root(), "Go")
end, "Run Go project")

map("<leader>da", function()
  local root = util.project_root()

  vim.ui.input({ prompt = "Go args: " }, function(input)
    if input == nil then
      return
    end

    local arguments, error_message = parse_command_line_arguments(input)
    if not arguments then
      vim.notify(error_message, vim.log.levels.ERROR)
      return
    end

    -- Loading nvim-dap-go registers the "go" adapter.
    require("dap-go")
    require("dap").run({
      type = "go",
      request = "launch",
      name = "Debug Go project",
      program = root,
      cwd = root,
      args = arguments,
    })
  end)
end, "Debug Go project with arguments")

map("<leader>dt", function()
  require("dap-go").debug_test()
end, "Debug Go test")

map("<leader>tn", function()
  require("neotest").run.run()
end, "Run nearest test")

map("<leader>tF", function()
  require("neotest").run.run(vim.fn.expand("%"))
end, "Run test file")

map("<leader>ts", function()
  require("neotest").summary.toggle()
end, "Test summary")

map("<leader>to", function()
  require("neotest").output.open({ enter = true })
end, "Test output")

return vim.list_extend(plugins, {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { languages = { "go", "gomod", "gosum", "gowork" } },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gopls = {
          cmd = { vim.fn.expand("~/go/bin/gopls") },
          settings = {
            gopls = {
              completeFunctionCalls = true,
              gofumpt = true,
              staticcheck = true,
              usePlaceholders = true,
              analyses = {
                nilness = true,
                shadow = true,
                unusedparams = true,
                unusedwrite = true,
              },
              hints = {
                assignVariableTypes = true,
                compositeLiteralFields = true,
                compositeLiteralTypes = true,
                constantValues = true,
                functionTypeParameters = true,
                parameterNames = true,
                rangeVariableTypes = true,
              },
            },
          },
        },
      },
    },
  },

  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        go = { "goimports", "gofumpt" },
      },
    },
  },

  {
    "mfussenegger/nvim-dap",
    -- So <F5> in a Go buffer offers nvim-dap-go's launch configurations.
    dependencies = { "leoluz/nvim-dap-go" },
  },
})
