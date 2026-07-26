local status_ok, lspconfig = pcall(require, "lspconfig")
if not status_ok then
  return
end

M = require("user.lsp.handlers")
M.setup()

lspconfig["clangd"].setup({
  on_attach = M.on_attach,
  capabilities = M.capabilities,
})

lspconfig["pyright"].setup({
  on_attach = M.on_attach,
  capabilities = M.capabilities,
})

lspconfig["lua_ls"].setup({
  on_attach = M.on_attach,
  capabilities = M.capabilities,
})

lspconfig["bashls"].setup({
  on_attach = M.on_attach,
  capabilities = M.capabilities,
})

lspconfig["dartls"].setup({
  on_attach = M.on_attach,
  capabilities = M.capabilities,
})

lspconfig["jdtls"].setup({
  on_attach = M.on_attach,
  capabilities = M.capabilities,

})

lspconfig["emmet_ls"].setup({
  on_attach = M.on_attach,
  capabilities = M.capabilities,
})

-- lspconfig["java_language_server"].setup({
--   on_attach = M.on_attach,
--   capabilities = M.capabilities,
-- })
