local fn = vim.fn

-- Automatically install packer
local install_path = fn.stdpath "data" .. "/site/pack/packer/start/packer.nvim"
if fn.empty(fn.glob(install_path)) > 0 then
  PACKER_BOOTSTRAP = fn.system {
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/wbthomason/packer.nvim",
    install_path,
  }
  print "Installing packer close and reopen Neovim..."
  vim.cmd [[packadd packer.nvim]]
end


local group = vim.api.nvim_create_augroup("packer_user_config", { clear = true })
vim.api.nvim_create_autocmd("BufWritePost", {
  command = "source <afile> | PackerSync",
  pattern = "plugins.lua", -- the name of your plugins file
  group = group,
})                         -- Use a protected call so we don't error out on first use

local status_ok, packer = pcall(require, "packer")
if not status_ok then
  return
end

-- Have packer use a popup window
packer.init {
  display = {
    open_fn = function()
      return require("packer.util").float { border = "rounded" }
    end,
  },
}

-- Install your plugins here
return packer.startup(function(use)
  -- My plugins here
  -- My plugins here
  use "chrisbra/csv.vim"
  use "wbthomason/packer.nvim" -- Have packer manage itself
  use "nvim-lua/popup.nvim"    -- An implementation of the Popup API from vim in Neovim
  use "nvim-lua/plenary.nvim"  -- Useful lua functions used ny lots of plugins

  -- Colorschemes
  -- use "lunarvim/colorschemes" -- A bunch of colorschemes you can try out
  use "lunarvim/darkplus.nvim"

  -- cmp plugins
  use "hrsh7th/nvim-cmp"         -- The completion plugin
  use "hrsh7th/cmp-buffer"       -- buffer completions
  use "hrsh7th/cmp-path"         -- path completions
  use "hrsh7th/cmp-cmdline"      -- cmdline completions
  use "saadparwaiz1/cmp_luasnip" -- snippet completions
  use "hrsh7th/cmp-nvim-lsp"
  use "hrsh7th/cmp-nvim-lua"

  -- snippets
  use "L3MON4D3/LuaSnip" --snippet engine

  -- LSP
  use "neovim/nvim-lspconfig" -- enable LSP
  use "williamboman/mason.nvim"
  use "williamboman/mason-lspconfig.nvim"

  -- My added plugins here
  use "LunarVim/Colorschemes"
  use "lewis6991/gitsigns.nvim"

  use {
    'nvim-telescope/telescope.nvim', tag = '0.1.0',
    requires = { { 'nvim-lua/plenary.nvim' } }
  }

  use {
    "akinsho/toggleterm.nvim",
    tag = 'v2.*',
    config = function()
      require("toggleterm").setup()
    end
  }

  use "stevearc/stickybuf.nvim"
  use "stevearc/aerial.nvim"
  -- Vim starter like startify
  use {
    'goolord/alpha-nvim',
    requires = { 'kyazdani42/nvim-web-devicons' },
    config = function()
      require 'alpha'.setup(require 'alpha.themes.startify'.config)
    end,
  }

  use 'kyazdani42/nvim-tree.lua'

  use {
    'numToStr/Comment.nvim',
    config = function()
      require('Comment').setup()
    end
  }

  use {
    "windwp/nvim-autopairs",
    config = function()
      require("nvim-autopairs").setup {}
    end
  }

  use 'nvim-lualine/lualine.nvim'
  use 'lewis6991/impatient.nvim'
  -- use "ahmedkhalf/project.nvim"

  -- Dart config
  use { 'akinsho/flutter-tools.nvim',
    requires = {
      'nvim-lua/plenary.nvim',
      -- 'stevearc/dressing.nvim',
    },
  }

  use "jose-elias-alvarez/null-ls.nvim"
  -- use 'notjedi/nvim-rooter.lua'

  use {
    'xeluxee/competitest.nvim',
    requires = 'MunifTanjim/nui.nvim',
    config = function()
      require 'competitest'.setup({})
    end,
  }

  use 'Pocco81/auto-save.nvim'
  use({
      "kylechui/nvim-surround",
      tag = "*", -- Use for stability; omit to use `main` branch for the latest features
      config = function()
        require("nvim-surround").setup({
          -- Configuration here, or leave empty to use defaults
        })
      end
    }, -- using packer.nvim
    use { 'akinsho/bufferline.nvim', tag = "v2.*", requires = 'kyazdani42/nvim-web-devicons', config = function()
      require('bufferline').setup()
    end
    })

  use 'folke/tokyonight.nvim'
  use 'vimpostor/vim-tpipeline'
  use("nathom/filetype.nvim")

  use {
    'nvim-treesitter/nvim-treesitter',
    run = function()
      local ts_update = require('nvim-treesitter.install').update({ with_sync = false })
      ts_update()
    end,
  }

  -- use {
  --   'nvim-java/nvim-java',
  --   requires = {
  --     'nvim-java/lua-async-await',
  --     'nvim-java/nvim-java-core',
  --     'nvim-java/nvim-java-test',
  --     'nvim-java/nvim-java-dap',
  --     'MunifTanjim/nui.nvim',
  --     'neovim/nvim-lspconfig',
  --     'mfussenegger/nvim-dap',
  --     {
  --       'williamboman/mason.nvim',
  --       opts = {
  --         registries = {
  --           'github:nvim-java/mason-registry',
  --           'github:mason-org/mason-registry',
  --         },
  --       },
  --     }
  --   },
  --   config = function()
  --     require('java').setup({})
  --   end
  -- }

  use 'mboughaba/i3config.vim'
  use { 'ibhagwan/fzf-lua',
    -- optional for icon support
    requires = { 'nvim-tree/nvim-web-devicons' }
  }
  -- Lua
  use {
    "folke/todo-comments.nvim",
    requires = "nvim-lua/plenary.nvim",
    config = function()
      require("todo-comments").setup {}
    end
  }

  use 'mfussenegger/nvim-jdtls'

  use "vimwiki/vimwiki"
  use "ahmedkhalf/project.nvim"
  use "rcarriga/nvim-notify"
  use 'searleser97/cpbooster.vim'
  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if PACKER_BOOTSTRAP then
    require("packer").sync()
  end
end)
