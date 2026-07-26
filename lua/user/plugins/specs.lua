local function project_root()
  local root = vim.fs.root(0, { "go.work", "go.mod", ".git" })
  if root then
    return root
  end

  local buffer_path = vim.api.nvim_buf_get_name(0)
  return (buffer_path ~= "" and vim.fs.dirname(buffer_path)) or vim.uv.cwd()
end

local function find_project_files()
  require("fzf-lua").files({
    cwd = project_root(),
    -- Avoid FzfLua probing for missing fd/fdfind executables. On WSL that
    -- probe scans the Windows-heavy PATH and adds roughly 200 ms per picker.
    cmd = [[rg --color=never --files --hidden -g "!.git" -g "!.jj"]],
  })
end

local function grep_project()
  require("fzf-lua").live_grep({ cwd = project_root() })
end

local lazygit_terminal
local function toggle_lazygit()
  if vim.fn.executable("lazygit") ~= 1 then
    vim.notify("lazygit is not installed or not on PATH", vim.log.levels.ERROR)
    return
  end

  if not lazygit_terminal then
    lazygit_terminal = require("toggleterm.terminal").Terminal:new({
      cmd = "lazygit",
      dir = "git_dir",
      direction = "float",
      hidden = true,
      float_opts = { border = "rounded" },
    })
  end

  lazygit_terminal:toggle()
end

local project_terminals = {}
local function toggle_project_runner()
  -- When invoked from the runner itself, the project buffer is no longer
  -- current, so close the focused runner before trying to detect a root.
  for _, terminal in pairs(project_terminals) do
    if terminal:is_focused() then
      terminal:close()
      return
    end
  end

  local root = project_root()
  local terminal = project_terminals[root]

  -- Keep completed output visible. The next invocation replaces the finished
  -- terminal and starts a fresh run.
  if terminal and terminal.job_id and vim.fn.jobwait({ terminal.job_id }, 0)[1] ~= -1 then
    terminal:shutdown()
    project_terminals[root] = nil
    terminal = nil
  end

  if not terminal then
    terminal = require("toggleterm.terminal").Terminal:new({
      cmd = "go run .",
      dir = root,
      direction = "horizontal",
      size = 15,
      hidden = true,
      close_on_exit = false,
      display_name = "Go: " .. vim.fs.basename(root),
    })
    project_terminals[root] = terminal
  end

  terminal:toggle(15)
end

return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = { style = "night" },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight-night")
    end,
  },

  { "nvim-tree/nvim-web-devicons", lazy = true, opts = {} },

  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "tokyonight",
        component_separators = { left = "│", right = "│" },
        section_separators = { left = "", right = "" },
      },
    },
  },

  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        diagnostics = "nvim_lsp",
        separator_style = "slant",
        show_buffer_close_icons = false,
        show_close_icon = false,
      },
    },
  },

  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local dashboard = require("alpha.themes.dashboard")
      dashboard.section.header.val = {
        "███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗",
        "████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║",
        "██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║",
        "██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║",
        "██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║",
        "╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝",
      }
      dashboard.section.buttons.val = {
        dashboard.button("f", "󰈞  Find file", "<Cmd>FzfLua files<CR>"),
        dashboard.button("g", "󰊄  Live grep", "<Cmd>FzfLua live_grep<CR>"),
        dashboard.button("r", "󰋚  Recent files", "<Cmd>FzfLua oldfiles<CR>"),
        dashboard.button("c", "  Configuration", "<Cmd>edit $MYVIMRC<CR>"),
        dashboard.button("q", "󰅚  Quit", "<Cmd>quitall<CR>"),
      }
      require("alpha").setup(dashboard.config)
    end,
  },

  {
    "nvim-tree/nvim-tree.lua",
    cmd = { "NvimTreeToggle", "NvimTreeFindFile" },
    keys = {
      { "<leader>y", "<Cmd>NvimTreeToggle<CR>", desc = "File explorer" },
    },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      disable_netrw = true,
      hijack_netrw = true,
      sync_root_with_cwd = true,
      respect_buf_cwd = true,
      update_focused_file = { enable = true },
      diagnostics = { enable = true },
      git = { enable = true, ignore = false, timeout = 400 },
      view = { side = "right", width = 36 },
      renderer = {
        group_empty = true,
        highlight_git = true,
      },
    },
  },

  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>f", find_project_files, desc = "Find project files" },
      { "<leader>l", grep_project, desc = "Live grep project" },
      { "<leader>i", "<Cmd>FzfLua lsp_code_actions<CR>", desc = "Code actions" },
      { "<leader>ff", find_project_files, desc = "Find project files" },
      { "<leader>fg", grep_project, desc = "Live grep project" },
      { "<leader>fb", "<Cmd>FzfLua buffers<CR>", desc = "Find buffers" },
      { "<leader>fh", "<Cmd>FzfLua helptags<CR>", desc = "Help tags" },
      { "<leader>fr", "<Cmd>FzfLua oldfiles<CR>", desc = "Recent files" },
      { "<leader>fs", "<Cmd>FzfLua lsp_document_symbols<CR>", desc = "Document symbols" },
    },
    opts = {
      fzf_opts = { ["--layout"] = "reverse-list" },
      winopts = { preview = { layout = "vertical" } },
    },
  },

  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
        untracked = { text = "▎" },
      },
      current_line_blame = false,
    },
  },

  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },

  {
    "numToStr/Comment.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },

  {
    "Pocco81/auto-save.nvim",
    cmd = "ASToggle",
    opts = {},
  },

  {
    "searleser97/cpbooster.vim",
    cmd = { "Test", "Debug", "Create", "Rtest", "Rdebug", "Addtc", "Submit" },
  },

  {
    "chrisbra/csv.vim",
    ft = "csv",
  },

  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    opts = {},
  },

  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },

  {
    "akinsho/toggleterm.nvim",
    version = "*",
    cmd = { "ToggleTerm", "TermExec" },
    keys = {
      {
        "<leader>h",
        "<Cmd>ToggleTerm direction=horizontal<CR>",
        mode = { "n", "t" },
        desc = "Terminal",
      },
      {
        "<leader>m",
        "<Cmd>ToggleTerm direction=float<CR>",
        mode = { "n", "t" },
        desc = "Floating terminal",
      },
      {
        "<leader>tt",
        "<Cmd>ToggleTerm direction=horizontal<CR>",
        mode = { "n", "t" },
        desc = "Terminal",
      },
      {
        "<leader>tf",
        "<Cmd>ToggleTerm direction=float<CR>",
        mode = { "n", "t" },
        desc = "Floating terminal",
      },
      {
        "<leader>g",
        toggle_lazygit,
        desc = "LazyGit",
      },
      {
        "<leader>r",
        toggle_project_runner,
        mode = { "n", "t" },
        desc = "Run Go project",
      },
    },
    opts = {
      direction = "horizontal",
      open_mapping = [[<C-\>]],
      shell = vim.o.shell,
      float_opts = { border = "rounded" },
    },
  },

  {
    "stevearc/aerial.nvim",
    cmd = { "AerialToggle", "AerialOpen" },
    keys = {
      { "<leader>a", "<Cmd>AerialToggle!<CR>", desc = "Symbol outline" },
    },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      on_attach = function(bufnr)
        vim.keymap.set("n", "{", "<Cmd>AerialPrev<CR>", { buffer = bufnr, desc = "Previous symbol" })
        vim.keymap.set("n", "}", "<Cmd>AerialNext<CR>", { buffer = bufnr, desc = "Next symbol" })
      end,
    },
  },

  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-path",
      "saadparwaiz1/cmp_luasnip",
      {
        "L3MON4D3/LuaSnip",
        build = "make install_jsregexp",
        dependencies = { "rafamadriz/friendly-snippets" },
        config = function()
          require("luasnip.loaders.from_vscode").lazy_load()
          require("luasnip.loaders.from_lua").lazy_load({
            paths = vim.fn.stdpath("config") .. "/lua/user/snippets",
          })
        end,
      },
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = false }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
        }, {
          { name = "buffer", keyword_length = 3 },
        }),
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "hrsh7th/cmp-nvim-lsp" },
    config = function()
      require("user.lsp")
    end,
  },

  {
    "stevearc/conform.nvim",
    cmd = "ConformInfo",
    keys = {
      {
        "<leader>cf",
        function()
          require("conform").format({ async = true, lsp_format = "fallback" })
        end,
        mode = { "n", "x" },
        desc = "Format buffer",
      },
    },
    opts = {
      formatters_by_ft = {
        go = { "goimports", "gofumpt" },
      },
    },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    lazy = false,
    build = ":TSUpdate",
    opts = {
      ensure_installed = {
        "bash",
        "go",
        "gomod",
        "gosum",
        "gowork",
        "json",
        "lua",
        "markdown",
        "markdown_inline",
        "vim",
        "vimdoc",
        "yaml",
      },
      auto_install = false,
      sync_install = false,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
      indent = {
        enable = true,
        disable = { "yaml" },
      },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },

  {
    "mfussenegger/nvim-dap",
    dependencies = {
      {
        "rcarriga/nvim-dap-ui",
        dependencies = { "nvim-neotest/nvim-nio" },
      },
      {
        "leoluz/nvim-dap-go",
        opts = {},
      },
    },
    keys = {
      {
        "<F5>",
        function()
          require("dap").continue()
        end,
        desc = "Debug continue",
      },
      {
        "<F10>",
        function()
          require("dap").step_over()
        end,
        desc = "Debug step over",
      },
      {
        "<F11>",
        function()
          require("dap").step_into()
        end,
        desc = "Debug step into",
      },
      {
        "<F12>",
        function()
          require("dap").step_out()
        end,
        desc = "Debug step out",
      },
      {
        "<leader>db",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "Toggle breakpoint",
      },
      {
        "<leader>dt",
        function()
          require("dap-go").debug_test()
        end,
        desc = "Debug Go test",
      },
      {
        "<leader>du",
        function()
          require("dapui").toggle()
        end,
        desc = "Toggle debug UI",
      },
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      dapui.setup()

      dap.listeners.before.attach.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        dapui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        dapui.close()
      end
    end,
  },

  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/neotest-go",
    },
    keys = {
      {
        "<leader>tn",
        function()
          require("neotest").run.run()
        end,
        desc = "Run nearest test",
      },
      {
        "<leader>tF",
        function()
          require("neotest").run.run(vim.fn.expand("%"))
        end,
        desc = "Run test file",
      },
      {
        "<leader>ts",
        function()
          require("neotest").summary.toggle()
        end,
        desc = "Test summary",
      },
      {
        "<leader>to",
        function()
          require("neotest").output.open({ enter = true })
        end,
        desc = "Test output",
      },
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

  {
    "akinsho/flutter-tools.nvim",
    ft = "dart",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },

  {
    "mfussenegger/nvim-jdtls",
    ft = "java",
  },

  {
    "folke/sidekick.nvim",
    opts = {
      -- Use Sidekick as a Codex CLI host only. Copilot NES can be enabled
      -- separately later without changing this terminal workflow.
      nes = { enabled = false },
      copilot = {
        status = { enabled = false },
      },
      cli = {
        picker = "fzf-lua",
        win = {
          layout = "right",
          split = { width = 80 },
        },
        mux = {
          enabled = true,
          backend = "tmux",
          create = "terminal",
        },
      },
    },
    keys = {
      {
        "<leader>ai",
        function()
          require("sidekick.cli").toggle({ name = "codex", focus = true })
        end,
        desc = "Toggle Codex",
      },
      {
        "<leader>xf",
        function()
          require("sidekick.cli").send({ msg = "{file}" })
        end,
        desc = "Send file to Codex",
      },
      {
        "<leader>xv",
        function()
          require("sidekick.cli").send({ msg = "{selection}" })
        end,
        mode = "x",
        desc = "Send selection to Codex",
      },
      {
        "<C-.>",
        function()
          require("sidekick.cli").focus({ name = "codex" })
        end,
        mode = { "n", "t", "i", "x" },
        desc = "Focus Codex",
      },
    },
  },

  {
    "vimwiki/vimwiki",
    cmd = { "VimwikiIndex", "VimwikiTabIndex" },
    init = function()
      vim.g.vimwiki_list = {
        { path = "~/vimwiki", syntax = "markdown", ext = ".md" },
      }
    end,
  },

  {
    "xeluxee/competitest.nvim",
    cmd = "CompetiTest",
    keys = {
      { "<leader>b", "<Cmd>CompetiTest run<CR>", desc = "Run competitive tests" },
      { "<leader>bn", "<Cmd>CompetiTest run_no_compile<CR>", desc = "Run without compiling" },
      { "<leader>e", "<Cmd>CompetiTest edit_testcase<CR>", desc = "Edit testcase" },
      { "<leader>d", "<Cmd>CompetiTest delete_testcase<CR>", desc = "Delete testcase" },
      { "<leader>pr", "<Cmd>CompetiTest receive problem<CR>", desc = "Receive problem" },
    },
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {},
  },
}
