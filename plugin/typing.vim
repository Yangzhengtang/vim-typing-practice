vim9script
# vim-typing-practice: practise typing over the text of any buffer.
# The original buffer and file are never modified; see PLAN.md.

if exists('g:loaded_typing_practice')
  finish
endif
if !has('textprop') || !has('popupwin') || !has('timers')
  echohl WarningMsg
  echomsg 'vim-typing-practice needs Vim 9 with +textprop, +popupwin and +timers'
  echohl None
  finish
endif
g:loaded_typing_practice = 1

import autoload 'typing/session.vim'

# Colours are defined with `default` so a colorscheme or vimrc can override them.
def DefineHighlights()
  highlight default TypingPending ctermfg=242 guifg=#6c6c6c
  highlight default TypingWrong ctermfg=15 ctermbg=160 guifg=#ffffff guibg=#d70000
  highlight default TypingFixed cterm=underline ctermfg=178 gui=underline guifg=#d7af00
  highlight default TypingCursor cterm=reverse gui=reverse
  highlight default link TypingStatus Pmenu
  highlight default link TypingStatusWarn ErrorMsg
enddef
DefineHighlights()

augroup TypingPracticeHighlights
  autocmd!
  autocmd ColorScheme * DefineHighlights()
augroup END

command! -range=% -bang -bar TypingStart session.Start(<line1>, <line2>, <bang>0)
command! -bar TypingStop session.Stop()
command! -bar TypingHistory session.History()

# No default key mappings. Users who want one can map these themselves, e.g.
#   nmap <leader>t <Plug>(typing-start)
# In Visual mode the selection is practised; in Normal mode the whole buffer.
nnoremap <silent> <Plug>(typing-start) <Cmd>TypingStart<CR>
xnoremap <silent> <Plug>(typing-start) :<C-u>execute ":'<,'>TypingStart"<CR>
