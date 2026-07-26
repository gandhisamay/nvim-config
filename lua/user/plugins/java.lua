local status_ok, jdtls = pcall(require, "jdtls")
if not status_ok then
  return
end

local config = {
  root_dir = vim.fs.dirname(vim.fs.find({ 'gradlew', '.git', 'mvnw' }, { upward = true })[1]),
}

require('jdtls').start_or_attach(config);
