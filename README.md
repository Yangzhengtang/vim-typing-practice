# vim-typing-practice

Practise typing over text from an open Vim buffer or a selected line range in
a separate scratch tab. Pending text is dimmed, wrong keys are marked red,
and a blinking highlight marks the current position. The plugin tracks speed,
accuracy and errors, shows a summary, and can save session history. The original
buffer and file are never modified.

## Requirements

Vim 9 with `+textprop`, `+popupwin` and `+timers`. Neovim is not supported.
Real input-method input and GUI Vim have not been verified.

## Installation

Use Vim's native packages. For an existing checkout, run these commands with
`/path/to/vim-typing-practice` replaced by its absolute path:

```sh
mkdir -p ~/.vim/pack/local/start
ln -s /path/to/vim-typing-practice ~/.vim/pack/local/start/vim-typing-practice
```

Alternatively, clone the repository into
`~/.vim/pack/local/start/vim-typing-practice`. Restart Vim, then run:

```vim
:helptags ALL
```

## Usage

Open a text buffer and run `:TypingStart`. Use `:'<,'>TypingStart` for a Visual
selection or `:.,$TypingStart` for the cursor line through the end. Type the
shown text; indentation and blank lines are skipped. Space or Enter accepts a
line end. Esc or Ctrl-C stops and shows the summary; `r` restarts there, and any
other key closes it. During practice, keys are captured as typing input, so
colon does not open the command line.

`:TypingStop` stops an active session, or closes its summary. `:TypingHistory`
opens saved results in a scratch split; press `q` to close it. History is saved
by default after at least 20 judged keystrokes, including unfinished sessions.

No keys are mapped by default. Example vimrc settings:

```vim
nmap <leader>t <Plug>(typing-start)
xmap <leader>t <Plug>(typing-start)
let g:typing_on_error = 'stay'       " Or 'advance', with Backspace to go back
let g:typing_line_end = 'either'     " Or 'enter' or 'space'
let g:typing_blink_ms = 500          " 0 for a steady position marker
let g:typing_history = v:true       " v:false disables saving and comparison
let g:typing_history_min_keys = 20
```

See `:help typing-practice` for all options, colours, statistics and limitations.

## Development

```sh
./test/run.sh                    # all tests, in a clean headless Vim
./test/run.sh test/test_load.vim # one file
```

To try the plugin without installing it:

```sh
vim --cmd 'set runtimepath^=~/Projects/vim-typing-practice' some-file.txt
```

See [PROJECT_GUIDE.md](PROJECT_GUIDE.md) for layout and current state.
