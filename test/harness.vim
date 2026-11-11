vim9script
# Sources one test file in a clean Vim and reports assert failures.
# Invoked by test/run.sh with g:test_file and g:test_out set.

try
  runtime plugin/typing.vim
  execute 'source' fnameescape(g:test_file)
catch
  add(v:errors, $'{v:exception} @ {v:throwpoint}')
endtry

writefile(v:errors, g:test_out)
if empty(v:errors)
  qall!
else
  cquit!
endif
