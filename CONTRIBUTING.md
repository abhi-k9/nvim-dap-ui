# Contributing

Keep fixes focused and include a regression test that fails before the change.
Use the existing Lua style and explain non-obvious lifecycle or compatibility
requirements in comments. Avoid changing debugger behavior solely to accommodate
a test double; mocks should reflect the nvim-dap API they represent.

## Running tests

The tests use Neovim, [plenary.nvim](https://github.com/nvim-lua/plenary.nvim),
[nvim-dap](https://github.com/mfussenegger/nvim-dap), and
[nvim-nio](https://github.com/nvim-neotest/nvim-nio). No debug adapter is required.
Install or clone these dependencies before running the suite; the test runner
does not download them or load your Neovim configuration.

By default, the test init looks for dependencies beside the nvim-dap-ui checkout:

```text
plugins/
  nvim-dap-ui/
  nvim-dap/
  nvim-nio/
  plenary.nvim/
```

Dependencies in Neovim's standard package directories also work. For a plugin
manager or another checkout location, set `DAPUI_TEST_DEPS` to the parent directory
containing the three dependency directories. For example:

```sh
export DAPUI_TEST_DEPS="$HOME/.local/share/nvim/lazy"
```

Run the suite or one test file:

```sh
./scripts/test
./scripts/test tests/unit/controls_spec.lua
```

Test paths are relative to the repository root, or absolute. The script can be
invoked from another working directory. Both forms use `tests/init.vim` and return
a nonzero status for test failures, setup errors, or a failing Neovim process.
Standard output and standard error are retained in the console output.

Use `NVIM` to select another Neovim executable when checking compatibility:

```sh
NVIM=/path/to/nvim ./scripts/test
```

## Formatting

Use [StyLua](https://github.com/JohnnyMorganz/StyLua) with the repository's
`stylua.toml` configuration:

```sh
./scripts/style
stylua --check lua/ tests/
git diff --check
```
