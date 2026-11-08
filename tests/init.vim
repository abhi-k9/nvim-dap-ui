let s:root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set rtp^=' . fnameescape(s:root)
let s:deps = empty($DAPUI_TEST_DEPS) ? fnamemodify(s:root, ':h') : expand($DAPUI_TEST_DEPS)
for s:dependency in ['plenary.nvim', 'nvim-dap', 'nvim-nio']
  execute 'set rtp+=' . fnameescape(s:deps . '/' . s:dependency)
endfor
runtime! plugin/plenary.vim
