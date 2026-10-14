-- Java / Spring Boot support. Loaded when user.profile finds Java in the project.
-- Requires: a JDK 21+ to run jdtls (other installed JDKs are registered as project
-- runtimes), Maven or a Maven wrapper, and the tools from scripts/install-java-tools.sh
-- (jdtls, Lombok, java-debug and java-test bundles, Spring Boot language server).

local profile = require("user.profile")
local util = require("user.util")

local active = profile.active("java")

local tools = (vim.env.XDG_DATA_HOME or vim.fn.expand("~/.local/share")) .. "/nvim-java-tools"
local is_mac = vim.fn.has("mac") == 1
local is_arm = vim.uv.os_uname().machine == "arm64" or vim.uv.os_uname().machine == "aarch64"

local function build_root(bufnr)
  return vim.fs.root(bufnr or 0, profile.languages.java.root_markers)
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

-- The Spring Boot language server (spring-boot.nvim) and the jars it loads into
-- jdtls, the same list as the VS Code extension's `javaExtensions`. The rest of
-- spring-boot/jars/ belongs to other language servers.
local spring_boot_ls = vim.fn.glob(tools .. "/spring-boot/language-server/spring-boot-language-server-*.jar", true, true)[1]
local spring_boot_jars = vim.tbl_filter(
  function(jar)
    return vim.uv.fs_stat(jar) ~= nil
  end,
  vim.tbl_map(function(name)
    return tools .. "/spring-boot/jars/" .. name
  end, {
    "io.projectreactor.reactor-core.jar",
    "org.reactivestreams.reactive-streams.jar",
    "jdt-ls-commons.jar",
    "jdt-ls-extension.jar",
    "sts-gradle-tooling.jar",
  })
)

local function bundles()
  local jars = vim.fn.glob(tools .. "/java-debug/*.jar", true, true)
  for _, jar in ipairs(vim.fn.glob(tools .. "/java-test/*.jar", true, true)) do
    local name = vim.fs.basename(jar)
    -- These two are launched by java-test itself, not loaded into jdtls.
    if name ~= "com.microsoft.java.test.runner-jar-with-dependencies.jar" and name ~= "jacocoagent.jar" then
      jars[#jars + 1] = jar
    end
  end
  if spring_boot_ls then
    vim.list_extend(jars, spring_boot_jars)
  end
  return jars
end

local warmed_clients = {}

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
    handlers = {
      -- nvim-jdtls echoes this message by default; keep that and, once the
      -- project is imported, warm up the JVM's JIT so the first rename isn't
      -- 3-5x slower than the rest.
      ["language/status"] = function(_, result, ctx)
        vim.api.nvim_command(
          string.format(':echohl Function | echo "%s" | echohl None', string.sub(result.message or "", 1, vim.v.echospace))
        )
        if result.type == "ServiceReady" and vim.env.NVIM_JAVA_WARMUP ~= "0" and not warmed_clients[ctx.client_id] then
          warmed_clients[ctx.client_id] = true
          local client = vim.lsp.get_client_by_id(ctx.client_id)
          -- Wait for the build triggered by the import to settle.
          vim.defer_fn(function()
            if client and not client:is_stopped() and vim.api.nvim_buf_is_valid(bufnr) then
              require("user.java_warmup").run(client, bufnr, 1)
            end
          end, 2000)
        end
      end,
    },
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
          -- Default "firstLetter" hides `String` while typing `string`.
          matchCase = "off",
          guessMethodArguments = "insertBestGuessedArguments",
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

-- jdtls imports the Maven project and builds its index when it starts, and
-- that is most of the latency of the first rename or reference search (~40 s
-- on a fresh workspace). It normally starts only when a Java file is opened,
-- so start it at launch instead, like an IDE does: open one of the project's
-- Java files in a hidden buffer, which runs the same FileType path as a real
-- one. Opt out with NVIM_JAVA_WARMUP=0.
local no_warmup_filetypes = { gitcommit = true, gitrebase = true, gitsendemail = true, help = true, man = true }

local function warm_up()
  if vim.env.NVIM_JAVA_WARMUP == "0" then
    return
  end

  -- A Java buffer already starts jdtls; `git commit` and friends shouldn't
  -- spin up a JVM.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and (vim.bo[buf].filetype == "java" or no_warmup_filetypes[vim.bo[buf].filetype]) then
      return
    end
  end

  local name = vim.api.nvim_buf_get_name(0)
  local root = vim.fs.root(name ~= "" and name or vim.uv.cwd(), profile.languages.java.root_markers)
  if not root or vim.fn.executable("rg") == 0 then
    return
  end

  -- Prefer a main source file; any .java file works to pick the module.
  vim.system({ "rg", "--files", "-g", "*.java" }, { cwd = root, text = true }, function(result)
    local files = vim.split(result.stdout or "", "\n", { trimempty = true })
    local main = vim.tbl_filter(function(file)
      return file:find("/src/main/java/", 1, true) or file:find("^src/main/java/")
    end, files)
    -- The largest main source file is usually a core class, which gives the
    -- JIT warm-up the most to chew on (many symbols, callers, overrides).
    local first, size = files[1], -1
    for _, file in ipairs(#main > 0 and main or files) do
      local stat = vim.uv.fs_stat(root .. "/" .. file)
      if stat and stat.size > size then
        first, size = file, stat.size
      end
    end
    if not first then
      return
    end
    vim.schedule(function()
      local buf = vim.fn.bufadd(root .. "/" .. first)
      vim.bo[buf].buflisted = false
      vim.fn.bufload(buf)
      vim.bo[buf].filetype = "java"
    end)
  end)
end

-- Run the Spring Boot app of the module the current file belongs to, using the
-- project's Maven wrapper when it has one.
local function run_spring_boot()
  if util.close_focused_runner() then
    return
  end

  local module = vim.fs.root(0, { "pom.xml" })
  if not module then
    vim.notify("No pom.xml above the current file", vim.log.levels.WARN)
    return
  end

  local root = build_root() or module
  local maven = vim.uv.fs_stat(root .. "/mvnw") and (root .. "/mvnw") or "mvn"
  util.toggle_runner(vim.fn.shellescape(maven) .. " spring-boot:run", module, "Spring Boot")
end

-- Java-only plugins are always declared so they stay installed and pinned in
-- the lockfile; `cond` keeps them from loading when Java isn't active.
local plugins = {
  -- Spring Boot language server: application.yml / .properties completion and
  -- validation, and bean / request mapping symbols. It learns the classpath
  -- from jdtls, so it is a dependency of nvim-jdtls: its commands have to be
  -- registered before jdtls imports the project.
  {
    "JavaHello/spring-boot.nvim",
    cond = active and spring_boot_ls ~= nil,
    ft = { "java", "yaml", "jproperties" },
    opts = function()
      return {
        ls_path = spring_boot_ls,
        jars = spring_boot_jars,
        java_cmd = jdtls_java(), -- needs Java 21+
        -- A separate JVM; don't start it in plain Java projects.
        project_filter = function(root)
          return require("spring_boot.util").has_spring_boot_dependency(root)
        end,
        server = {
          settings = {
            ["spring-boot"] = {
              ls = {
                -- Every custom @Value key has no metadata and is "unknown";
                -- as warnings they bury the real problems (deprecated keys,
                -- wrong types, duplicates).
                problem = {
                  ["application-properties"] = { PROP_UNKNOWN_PROPERTY = "HINT" },
                  ["application-yaml"] = { YAML_UNKNOWN_PROPERTY = "HINT" },
                },
              },
            },
          },
        },
      }
    end,
  },
  {
    "mfussenegger/nvim-jdtls",
    cond = active,
    ft = "java",
    dependencies = { "hrsh7th/cmp-nvim-lsp", "JavaHello/spring-boot.nvim" },
    config = function()
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_java", { clear = true }),
        pattern = "java",
        callback = function(args)
          start_jdtls(args.buf)
        end,
      })
      -- Not for the warm-up, which can run while a non-Java buffer is current.
      if vim.bo.filetype == "java" then
        start_jdtls(vim.api.nvim_get_current_buf())
      end
    end,
  },
}

if not active then
  return plugins
end

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("user_java_warmup", { clear = true }),
  once = true,
  callback = warm_up,
})

-- Acts in Java buffers, and in files of a Java build (pom.xml, application.yml, ...).
profile.map("java", "n", "<leader>r", run_spring_boot, "Run Spring Boot app")
profile.map("java", "n", "<leader>fe", function()
  vim.cmd.SpringBoot("RequestMappings")
end, "Find Spring endpoints")
profile.map("java", "n", "<leader>fB", function()
  vim.cmd.SpringBoot("Beans")
end, "Find Spring beans")

return vim.list_extend(plugins, {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { languages = { "java", "properties", "xml" } },
  },
})
