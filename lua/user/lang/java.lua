-- Java / Spring Boot support.
-- Requires: a JDK 21+ to run jdtls (other installed JDKs are registered as project
-- runtimes), Maven or a Maven wrapper, and the tools from scripts/install-java-tools.sh
-- (jdtls, Lombok, java-debug and java-test bundles).

local util = require("user.util")

local tools = (vim.env.XDG_DATA_HOME or vim.fn.expand("~/.local/share")) .. "/nvim-java-tools"
local is_mac = vim.fn.has("mac") == 1
local is_arm = vim.uv.os_uname().machine == "arm64" or vim.uv.os_uname().machine == "aarch64"

local function build_root(bufnr)
  return vim.fs.root(bufnr or 0, {
    { "mvnw", "gradlew" },
    ".git",
    { "pom.xml", "build.gradle", "build.gradle.kts" },
  })
end

-- Installed JDKs as { [major] = home }, preferring full JDKs for this CPU
-- architecture. Probed once, on the first Java buffer.
local jdks
local function installed_jdks()
  if jdks then
    return jdks
  end
  jdks = {}

  if is_mac then
    local listing = vim.system({ "/usr/libexec/java_home", "-V" }, { text = true }):wait().stderr or ""
    local scores = {}
    for line in listing:gmatch("[^\n]+") do
      local version, arch, home = line:match("^%s+([%d%.%_]+)%s+%(([%w_]+)%).-(/%S.*)$")
      if version then
        local major = tonumber(version:match("^1%.(%d+)") or version:match("^(%d+)"))
        local score = ((arch == "arm64") == is_arm and 2 or 0) + (home:find("%.jre/") and 0 or 1)
        if major and score > (scores[major] or -1) then
          scores[major] = score
          jdks[major] = home
        end
      end
    end
  end

  if vim.env.JAVA_HOME and vim.tbl_isempty(jdks) then
    jdks[21] = vim.env.JAVA_HOME
  end
  return jdks
end

local function jdtls_java()
  local newest
  for major in pairs(installed_jdks()) do
    if major >= 21 and (not newest or major > newest) then
      newest = major
    end
  end
  return newest and (jdks[newest] .. "/bin/java") or "java"
end

local function runtimes()
  local result = {}
  for major, home in pairs(installed_jdks()) do
    result[#result + 1] = {
      name = major <= 8 and ("JavaSE-1." .. major) or ("JavaSE-" .. major),
      path = home,
    }
  end
  return result
end

local function bundles()
  local jars = vim.fn.glob(tools .. "/java-debug/*.jar", true, true)
  for _, jar in ipairs(vim.fn.glob(tools .. "/java-test/*.jar", true, true)) do
    local name = vim.fs.basename(jar)
    -- These two are launched by java-test itself, not loaded into jdtls.
    if name ~= "com.microsoft.java.test.runner-jar-with-dependencies.jar" and name ~= "jacocoagent.jar" then
      jars[#jars + 1] = jar
    end
  end
  return jars
end

local function start_jdtls(bufnr)
  local launcher = vim.fn.glob(tools .. "/jdtls/plugins/org.eclipse.equinox.launcher_*.jar", true, true)[1]
  if not launcher then
    vim.notify_once("jdtls is not installed. Run scripts/install-java-tools.sh", vim.log.levels.WARN)
    return
  end

  local root = build_root(bufnr)
  if not root then
    return
  end

  local platform = (is_mac and "config_mac" or "config_linux") .. (is_arm and "_arm" or "")
  local workspace = vim.fn.stdpath("cache") .. "/jdtls/" .. root:gsub("[/\\:]", "%%")
  local jdtls = require("jdtls")

  jdtls.start_or_attach({
    name = "jdtls",
    cmd = {
      jdtls_java(),
      "-Declipse.application=org.eclipse.jdt.ls.core.id1",
      "-Dosgi.bundles.defaultStartLevel=4",
      "-Declipse.product=org.eclipse.jdt.ls.core.product",
      "-Dlog.level=WARNING",
      -- Same JVM tuning as the VS Code Java extension.
      "-Xms256m",
      "-Xmx4g",
      "-XX:+UseParallelGC",
      "-XX:GCTimeRatio=4",
      "-XX:AdaptiveSizePolicyWeight=90",
      "-Dsun.zip.disableMemoryMapping=true",
      "--add-modules=ALL-SYSTEM",
      "--add-opens",
      "java.base/java.util=ALL-UNNAMED",
      "--add-opens",
      "java.base/java.lang=ALL-UNNAMED",
      "-javaagent:" .. tools .. "/lombok.jar",
      "-jar",
      launcher,
      "-configuration",
      tools .. "/jdtls/" .. platform,
      "-data",
      workspace,
    },
    root_dir = root,
    capabilities = require("cmp_nvim_lsp").default_capabilities(),
    init_options = {
      bundles = bundles(),
      extendedClientCapabilities = jdtls.extendedClientCapabilities,
    },
    settings = {
      java = {
        configuration = {
          runtimes = runtimes(),
          updateBuildConfiguration = "interactive",
        },
        eclipse = { downloadSources = true },
        maven = { downloadSources = true },
        references = { includeDecompiledSources = true },
        -- Code lenses re-resolve on every change and are the main source of lag
        -- in large Spring projects.
        implementationsCodeLens = { enabled = false },
        referencesCodeLens = { enabled = false },
        inlayHints = { parameterNames = { enabled = "literals" } },
        signatureHelp = { enabled = true },
        sources = {
          organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 },
        },
        completion = {
          favoriteStaticMembers = {
            "org.junit.jupiter.api.Assertions.*",
            "org.mockito.Mockito.*",
            "org.mockito.ArgumentMatchers.*",
            "org.hamcrest.Matchers.*",
            "org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*",
            "org.springframework.test.web.servlet.result.MockMvcResultMatchers.*",
          },
          filteredTypes = { "com.sun.*", "sun.*", "jdk.*", "java.awt.*" },
        },
      },
    },
    on_attach = function(_, attached)
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = attached, desc = desc })
      end
      map("n", "<leader>oi", jdtls.organize_imports, "Organize imports")
      map("n", "<leader>ev", jdtls.extract_variable, "Extract variable")
      map("x", "<leader>ev", function()
        jdtls.extract_variable(true)
      end, "Extract variable")
      map("n", "<leader>ec", jdtls.extract_constant, "Extract constant")
      map("x", "<leader>em", function()
        jdtls.extract_method(true)
      end, "Extract method")
      map("n", "<leader>tn", jdtls.test_nearest_method, "Run nearest test")
      map("n", "<leader>tF", jdtls.test_class, "Run test class")
    end,
  }, { dap = { hotcodereplace = "auto" } }, { bufnr = bufnr })
end

-- Run the Spring Boot app of the module the current file belongs to, using the
-- project's Maven wrapper when it has one.
local function run_spring_boot()
  local module = vim.fs.root(0, { "pom.xml" })
  if not module then
    vim.notify("No pom.xml above the current file", vim.log.levels.WARN)
    return
  end

  local root = build_root() or module
  local maven = vim.uv.fs_stat(root .. "/mvnw") and (root .. "/mvnw") or "mvn"
  util.toggle_runner(vim.fn.shellescape(maven) .. " spring-boot:run", module, "Spring Boot")
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { languages = { "java", "properties", "xml" } },
  },

  {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    dependencies = { "hrsh7th/cmp-nvim-lsp" },
    config = function()
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_java", { clear = true }),
        pattern = "java",
        callback = function(args)
          start_jdtls(args.buf)
        end,
      })
      start_jdtls(vim.api.nvim_get_current_buf())
    end,
  },

  {
    "akinsho/toggleterm.nvim",
    keys = {
      {
        "<leader>r",
        run_spring_boot,
        mode = "n",
        desc = "Run Spring Boot app",
      },
    },
  },
}
