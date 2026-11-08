local ok, err = xpcall(function()
  for _, dependency in ipairs({ "plenary", "dap", "nio" }) do
    local loaded, load_error = pcall(require, dependency)
    if not loaded then
      error(
        ("Could not load test dependency %s. Set DAPUI_TEST_DEPS to the plugins' parent directory (see CONTRIBUTING.md).\n%s"):format(
          dependency,
          load_error
        ),
        0
      )
    end
  end

  local test_file = vim.env.DAPUI_TEST_FILE
  if test_file and test_file ~= "" then
    -- Run in this process so individual tests use the same init as the suite.
    require("plenary.busted").run(test_file)
  else
    require("plenary.test_harness").test_directory("tests/", { minimal_init = "tests/init.vim" })
  end
end, debug.traceback)

if not ok then
  io.stderr:write(err, "\n")
  vim.cmd("cquit 1")
end
