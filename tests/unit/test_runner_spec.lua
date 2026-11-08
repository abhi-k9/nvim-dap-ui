local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h:h")
local runner = root .. "/scripts/test"
local bash = vim.fn.exepath("bash")

describe("test runner", function()
  if bash == "" then
    pending("requires Bash to run scripts/test")
    return
  end

  local directory

  local function fixture(name, contents)
    local path = directory .. "/" .. name
    vim.fn.writefile(vim.split(contents, "\n", { plain = true }), path)
    return path
  end

  local function run(path, environment)
    local stdout, stderr = {}, {}
    local job = vim.fn.jobstart({ bash, runner, path }, {
      cwd = directory,
      -- Override only the child environment; nested runs must not affect this suite.
      env = vim.tbl_extend("force", {
        NVIM = vim.v.progpath,
        NVIM_LOG_FILE = directory .. "/nvim.log",
      }, environment or {}),
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, lines)
        stdout = lines
      end,
      on_stderr = function(_, lines)
        stderr = lines
      end,
    })
    assert.True(job > 0, "Could not start test runner")
    local status = vim.fn.jobwait({ job }, 10000)[1]
    if status == -1 then
      vim.fn.jobstop(job)
      vim.fn.jobwait({ job }, 1000)
    end
    assert.Not.equal(-1, status, "Test runner timed out")
    return status, table.concat(stdout, "\n"), table.concat(stderr, "\n")
  end

  before_each(function()
    -- Keep fixtures outside tests/ so a suite run never discovers itself recursively.
    directory = vim.fn.tempname()
    vim.fn.mkdir(directory, "p")
  end)

  after_each(function()
    vim.fn.delete(directory, "rf")
  end)

  it("runs a quoted test path from another directory with dependencies loaded", function()
    local path = fixture(
      "test with spaces and 'quotes'.lua",
      [[
describe("fixture", function()
  it("loads dependencies", function()
    assert.is_table(require("plenary"))
    assert.is_table(require("dap"))
    assert.is_table(require("nio"))
    assert.is_table(require("dapui.config"))
  end)
end)
]]
    )
    local status, output = run(path)
    assert.equal(0, status, output)
    assert.Truthy(output:find("loads dependencies", 1, true))
  end)

  it("fails when an assertion fails", function()
    local path = fixture(
      "assertion.lua",
      [[
describe("fixture", function()
  it("fails", function() assert.True(false, "fixture assertion failure") end)
end)
]]
    )
    local status, output = run(path)
    assert.Not.equal(0, status, output)
    assert.Truthy(output:find("fixture assertion failure", 1, true))
  end)

  it("fails when test setup throws", function()
    local path = fixture(
      "setup.lua",
      [[
describe("fixture", function()
  before_each(function() error("fixture setup failure") end)
  it("never runs", function() end)
end)
]]
    )
    local status, output = run(path)
    assert.Not.equal(0, status, output)
    assert.Truthy(output:find("fixture setup failure", 1, true))
  end)

  it("fails when loading the test throws", function()
    local path = fixture("load.lua", [[error("fixture load failure")]])
    local status, output = run(path)
    assert.Not.equal(0, status, output)
    assert.Truthy(output:find("fixture load failure", 1, true))
  end)

  it("fails when a test has invalid Lua syntax", function()
    local path = fixture("syntax.lua", "not valid lua!")
    local status, output = run(path)
    assert.Not.equal(0, status, output)
    assert.Truthy(output:find("FAILED TO LOAD FILE", 1, true))
  end)

  it("rejects a missing test file", function()
    local path = directory .. "/missing.lua"
    local status, _, errors = run(path)
    assert.equal(2, status)
    assert.Truthy(errors:find("Test file not found: " .. path, 1, true))
  end)

  it("preserves a failing process status and its standard error", function()
    local path = fixture("unused.lua", "")
    local nvim = fixture("fake-nvim", "#!/bin/sh\necho 'fixture process error' >&2\nexit 7")
    assert.True(vim.loop.fs_chmod(nvim, 493)) -- 0755
    local status, output = run(path, { NVIM = nvim })
    assert.equal(7, status)
    assert.Truthy(output:find("fixture process error", 1, true))
  end)

  it("fails when a process reports setup errors but exits successfully", function()
    local path = fixture("unused.lua", "")
    local nvim =
      fixture("fake-nvim", "#!/bin/sh\nprintf '\\033[31mErrors : \\033[0m\\t1\\n'\nexit 0")
    assert.True(vim.loop.fs_chmod(nvim, 493)) -- 0755
    local status = run(path, { NVIM = nvim })
    assert.equal(1, status)
  end)
end)
