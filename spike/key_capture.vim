vim9script
# Run: vim -Nu NONE -i NONE --not-a-term -S spike/key_capture.vim  (writes result.txt)
# Feasibility spike: popup filter as key sink, text props, timers, Ctrl-C.
var got: list<string> = []
var closed: list<any> = []
var ticks = 0
def Filter(id: number, key: string): bool
  add(got, key)
  if key == "\<Esc>"
    popup_close(id, 'esc')
  endif
  return true
enddef
def Closed(id: number, result: any)
  add(closed, result)
enddef
var out: list<string> = []
try
  highlight TypDim ctermfg=242 guifg=#6c6c6c
  highlight TypErr ctermfg=15 ctermbg=160 guifg=#ffffff guibg=#d70000
  enew
  setlocal buftype=nofile noswapfile bufhidden=wipe
  setline(1, ['hello world', '  second “line” 中文'])
  setlocal nomodifiable
  prop_type_add('TypPending', {bufnr: bufnr(), highlight: "TypDim", priority: 10})
  prop_type_add('TypWrong', {bufnr: bufnr(), highlight: "TypErr", priority: 30})
  prop_add(1, 1, {type: 'TypPending', end_lnum: 2, end_col: col([2, '$'])})
  prop_add(1, 3, {type: 'TypWrong', length: 1})
  add(out, 'props on nomodifiable buffer: ' .. string(len(prop_list(1))))
  var pid = popup_create('stats', {filter: Filter, callback: Closed, mapping: false, line: 1, col: 40})
  nnoremap <buffer> h :let g:leaked = 1<CR>
  feedkeys("he \<CR>\<BS>\<Tab>“中:q\<Esc>", 'xt')
  add(out, 'keys: ' .. string(got))
  add(out, 'closed: ' .. string(closed))
  add(out, 'leaked to mapping: ' .. string(exists('g:leaked')))
  add(out, 'buffer intact: ' .. string(getline(1, '$')))
  # Ctrl-C closes a filtered popup with -1
  got = []
  closed = []
  pid = popup_create('stats', {filter: Filter, callback: Closed, mapping: false})
  feedkeys("a\<C-c>", 'xt')
  add(out, 'ctrl-c keys: ' .. string(got) .. ' closed: ' .. string(closed))
  # timers fire while idle
  var t = timer_start(20, (_) => {
    ticks += 1
  }, {repeat: 3})
  sleep 150m
  add(out, 'timer ticks: ' .. string(ticks))
  add(out, 't_ve: ' .. string(&t_ve) .. ' has gui: ' .. has('gui_running'))
catch
  add(out, 'ERROR: ' .. v:exception .. ' @ ' .. v:throwpoint)
endtry
writefile(out, 'result.txt')
qa!
