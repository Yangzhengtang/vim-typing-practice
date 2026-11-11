# vim-typing-practice — project guide

## Purpose

A Vim 9 plugin for typing practice over the text of an open buffer: dimmed text
that turns normal as it is typed, red marking and a warning on wrong keys, a
blinking position highlight, and time/speed/accuracy statistics with saved
history. It must never modify the buffer or file being practised on.

## Design

The full design, the decisions agreed with the owner, and the milestones are in
[PLAN.md](PLAN.md). Summary:

- vim9script only; Vim 9 with `+textprop`, `+popupwin`, `+timers`.
- Practice happens in a `nomodifiable` scratch copy in a new tab.
- A popup window with a `filter` callback is the single key sink; no mappings
  during a session.
- Colours are text properties; the blink is a timer toggling a highlight group.
- Pure `engine` module decides whether a key is right; `render` and `stats`
  consume its events.

## Implementation (current source, 2026-11-11)

| Path | Role |
| --- | --- |
| [plugin/typing.vim](plugin/typing.vim) | Feature guard, highlight defaults, `:TypingStart`, `:TypingStop`, `:TypingHistory`, `<Plug>(typing-start)`. |
| [autoload/typing/engine.vim](autoload/typing/engine.vim) | Pure logic: builds the list of targets from lines and judges keys (`stay` / `advance`). |
| [autoload/typing/stats.vim](autoload/typing/stats.vim) | Pure counters: clock with idle exclusion, WPM, accuracy, streaks, missed keys. |
| [autoload/typing/render.vim](autoload/typing/render.vim) | Text properties (dim, wrong, fixed, cursor, `↵` marker), blink timer, terminal cursor hide/restore. |
| [autoload/typing/ui.vim](autoload/typing/ui.vim) | Status popup (also the key sink), warning flash, summary popup, text formatting. |
| [autoload/typing/history.vim](autoload/typing/history.vim) | JSONL append/load, totals, the `:TypingHistory` view. |
| [autoload/typing/session.vim](autoload/typing/session.vim) | Lifecycle: scratch tab, key filter, finish/restart/close/abort, cleanup. |
| [doc/typing.txt](doc/typing.txt) | `:help typing-practice`. |
| [test/](test/) | `run.sh` (headless runner with a per-file watchdog), `harness.vim`, one `test_*.vim` per module plus `test_integration.vim`. |
| [spike/](spike/) | Feasibility scripts behind PLAN.md section 3. Not loaded by the plugin. |

Module interfaces are specified in PLAN.md section 5.1.

## Development commands

```sh
./test/run.sh                    # all tests
./test/run.sh test/test_load.vim # one file
vim --cmd 'set runtimepath^=~/Projects/vim-typing-practice' file.txt   # try it uninstalled
```

Tests run Vim with `-Nu NONE -i NONE`, so they do not read the user's vimrc.
Tests that write history must point `g:typing_history_file` at a temporary file.

## Constraints

- Never modify the practised buffer or its file. Tests assert this.
- Session history is user data. It lives outside the repository (default
  `~/.vim/typing-practice/history.jsonl`) and must not be committed or used as a
  test fixture.
- Installing into `~/.vim/pack` changes the user's Vim setup; do it only on request.
- Any change that hides the terminal cursor must restore it on every exit path.

## Status

**2026-11-11 — milestones M0–M4 implemented, M5 partly; first commit made on this date.**

Checks actually performed on this date, Vim 9.1.1752 on macOS inside tmux:

- `./test/run.sh`: 8 files passed (143 test functions plus the load test).
  The runner was shown to report a failing assertion (exit 1) and to kill and
  report a hanging test (`timed out`).
- Real-terminal run in an isolated tmux server, keys sent with `tmux
  send-keys`, once per error mode on a four-line sample with indentation, a
  blank line and curly quotes. Observed: pending text dim, typed text normal,
  wrong character red, warning text in the status popup, cursor cell
  alternating between captures, terminal cursor hidden while typing, corrected
  character underlined amber, summary popup, terminal cursor visible again
  after closing, sample file checksum unchanged, and one history record
  written to a temporary file. In the `advance` run the end state was also
  read from inside Vim: one tab, no popups, no timers, `t_ve` restored, buffer
  unmodified.
- `:helptags doc` exits 0.

Not checked: input through a real input method; GUI Vim; a real terminal
resize; a colorscheme change during a session; large files; the summary popup
in a terminal shorter than about 20 rows (it needs a scrollbar at 12 rows).
Not done: installation into `~/.vim/pack` (only on request).

How it was built: modules were written by delegated agents against the
contract in PLAN.md section 5.1, then reviewed and re-tested here. One fix made
after the agents' work: progress is characters passed ÷ total (it was
characters correct ÷ total), with a regression test.

## Next step

The open M5 items in [PLAN.md](PLAN.md) section 6, then the backlog there.
