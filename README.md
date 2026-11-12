# vim-typing-practice

Practise typing over text from an open Vim buffer or a selected line range in
a separate scratch tab. The original syntax colours are kept in your
colorscheme while pending text is a uniform grey, wrong keys are marked red,
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
line end. During practice, keys are captured as typing input, so colon does
not open the command line.

Esc pauses the session, at the start or midway: the clock stops and ordinary
Vim motions (`j`, `w`, `}`, `gg`, `G`, counts, `/search` …) move the cursor in
the read-only practice copy. Enter or `i` types from the cursor, Esc goes back
to where you left off, and `q` finishes. To end a session early press Esc then
`q`, or Ctrl-C at any time; the summary appears, where `r` restarts and any
other key closes it.

`:TypingStop` stops an active or paused session, or closes its summary. `:TypingHistory`
opens saved results in a scratch split; press `q` to close it. History is saved
by default after at least 20 judged keystrokes, including unfinished sessions.

Stopping early on a named file saves your position; the next
`:TypingStart` on the same line range offers to resume. Use `:TypingStart!`
to start from the beginning, or set `g:typing_resume` to `'always'` or
`'never'` to control the offer. Positions are stored locally in
`~/.vim/typing-practice/progress.json`, including absolute file paths.

No keys are mapped by default. Example vimrc settings:

```vim
nmap <leader>t <Plug>(typing-start)
xmap <leader>t <Plug>(typing-start)
let g:typing_on_error = 'stay'       " Or 'advance', with Backspace to go back
let g:typing_line_end = 'either'     " Or 'enter' or 'space'
let g:typing_resume = 'ask'         " Or 'always' or 'never'
let g:typing_summary_grace_ms = 500  " 0 to accept summary keys immediately
let g:typing_blink_ms = 500          " 0 for a steady position marker
let g:typing_esc_timeout_ms = 50     " Key-code timeout during a session; 0 leaves it
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
