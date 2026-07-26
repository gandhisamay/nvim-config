local capabilities = require("cmp_nvim_lsp").default_capabilities()

vim.diagnostic.config({
  severity_sort = true,
  update_in_insert = true,
  underline = true,
  virtual_text = { spacing = 2, source = true, prefix = "●" },
  float = { border = "rounded", source = true },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "",
      [vim.diagnostic.severity.WARN] = "",
      [vim.diagnostic.severity.INFO] = "",
      [vim.diagnostic.severity.HINT] = "󰌵",
    },
  },
})

vim.lsp.config("gopls", {
  cmd = { vim.fn.expand("~/go/bin/gopls") },
  capabilities = capabilities,
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
})

vim.lsp.enable("gopls")

local group = vim.api.nvim_create_augroup("user_lsp", { clear = true })
vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(args)
    local map = function(lhs, rhs, desc, mode)
      vim.keymap.set(mode or "n", lhs, rhs, { buffer = args.buf, desc = desc })
    end

    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gD", vim.lsp.buf.declaration, "Go to declaration")
    map("gr", vim.lsp.buf.references, "Find references")
    map("gI", vim.lsp.buf.implementation, "Go to implementation")
    map("gi", vim.lsp.buf.implementation, "Go to implementation")
    map("K", vim.lsp.buf.hover, "Hover documentation")
    map("<C-k>", vim.lsp.buf.signature_help, "Signature help")
    map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    map("<leader>ca", vim.lsp.buf.code_action, "Code action", { "n", "x" })
    map("<leader>ld", vim.diagnostic.open_float, "Line diagnostics")
    map("gl", vim.diagnostic.open_float, "Line diagnostics")
    map("<leader>q", vim.diagnostic.setloclist, "Diagnostics list")
    map("[d", function()
      vim.diagnostic.jump({ count = -1, float = true })
    end, "Previous diagnostic")
    map("]d", function()
      vim.diagnostic.jump({ count = 1, float = true })
    end, "Next diagnostic")

    if vim.lsp.inlay_hint then
      map("<leader>uh", function()
        local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = args.buf })
        vim.lsp.inlay_hint.enable(not enabled, { bufnr = args.buf })
      end, "Toggle inlay hints")
    end
  end,
})
