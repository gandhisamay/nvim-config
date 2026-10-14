-- Exercises jdtls with the requests an editing session sends, so the JVM has
-- JIT-compiled the hot paths (search, refactoring, completion, ...) before the
-- first real rename or reference lookup. Only read-only requests: rename
-- computes edits but they are never applied.
local M = {}

local SYMBOL_METHOD = 6

local function first_method(symbols)
  for _, symbol in ipairs(symbols or {}) do
    if symbol.kind == SYMBOL_METHOD and symbol.selectionRange then
      return symbol
    end
    local found = first_method(symbol.children)
    if found then
      return found
    end
  end
end

---Run `rounds` passes of read-only requests against `bufnr`, then `on_done()`.
---@param client vim.lsp.Client
---@param bufnr integer
---@param rounds integer
---@param on_done fun()?
function M.run(client, bufnr, rounds, on_done)
  local uri = vim.uri_from_bufnr(bufnr)
  local doc = { uri = uri }

  client:request("textDocument/documentSymbol", { textDocument = doc }, function(err, symbols)
    local method = not err and first_method(symbols)
    if not method then
      if on_done then
        on_done()
      end
      return
    end

    local start = method.selectionRange.start
    local pos = { line = start.line, character = start.character + 1 }
    local at = { textDocument = doc, position = pos }
    local range = method.range

    local requests = {
      { "textDocument/hover", at },
      { "textDocument/definition", at },
      { "textDocument/references", { textDocument = doc, position = pos, context = { includeDeclaration = true } } },
      { "textDocument/documentHighlight", at },
      { "textDocument/implementation", at },
      { "textDocument/prepareRename", at },
      { "textDocument/rename", { textDocument = doc, position = pos, newName = "jdtlsWarmup" } },
      { "textDocument/completion", at },
      { "textDocument/signatureHelp", at },
      { "textDocument/codeAction", { textDocument = doc, range = range, context = { diagnostics = {} } } },
      { "textDocument/semanticTokens/full", { textDocument = doc } },
      { "textDocument/foldingRange", { textDocument = doc } },
      { "workspace/symbol", { query = "Message" } },
    }

    local queue = {}
    for _ = 1, rounds do
      vim.list_extend(queue, requests)
    end

    local index = 0
    local function step()
      index = index + 1
      local item = queue[index]
      if not item or client:is_stopped() then
        if on_done then
          on_done()
        end
        return
      end
      -- Errors (a cancelled or unsupported request) don't matter; keep going.
      client:request(item[1], item[2], function()
        step()
      end, bufnr)
    end
    step()
  end, bufnr)
end

return M
