vim9script
# Run in a real terminal: vim -Nu NONE -i NONE -S spike/render.vim  (quit with Ctrl-C then :qa!)
highlight TypDim ctermfg=242
highlight TypErr ctermfg=15 ctermbg=160
highlight TypCur cterm=reverse
enew
setlocal buftype=nofile noswapfile
setline(1, ['hello world foo', 'second line'])
setlocal nomodifiable
prop_type_add('TypPending', {bufnr: bufnr(), highlight: 'TypDim', priority: 10})
prop_type_add('TypWrong', {bufnr: bufnr(), highlight: 'TypErr', priority: 30})
prop_type_add('TypCursor', {bufnr: bufnr(), highlight: 'TypCur', priority: 40})
prop_add(1, 7, {type: 'TypPending', end_lnum: 2, end_col: 12})
prop_add(1, 4, {type: 'TypWrong', length: 1})
prop_add(1, 7, {type: 'TypCursor', length: 1})
var on = true
timer_start(400, (_) => {
  on = !on
  execute 'highlight TypCur cterm=' .. (on ? 'reverse' : 'NONE')
}, {repeat: -1})
&t_ve = ''
popup_create('WPM 0', {filter: (_, k) => true, mapping: false, line: 5, col: 1})
