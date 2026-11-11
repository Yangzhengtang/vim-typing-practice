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
| [autoload/typing/progress.vim](autoload/typing/progress.vim) | Resume positions: JSON file keyed by absolute path, text fingerprint. |
| [autoload/typing/session.vim](autoload/typing/session.vim) | Lifecycle: resume prompt, scratch tab, key filter, guard popup across transitions, finish/restart/close/abort, cleanup. |
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
- Session history and resume positions are user data. They live outside the
  repository (defaults `~/.vim/typing-practice/history.jsonl` and
  `progress.json`; the latter holds absolute file paths) and must not be
  committed, read for documentation or used as test fixtures. The owner has
  real history there. `test/harness.vim` points both files at temporary paths.
- During a session no typed key may reach Normal mode, including in the gaps
  between popups (PLAN.md section 5.1, "Key sink across transitions").
- Installing into `~/.vim/pack` changes the user's Vim setup; do it only on request.
- Any change that hides the terminal cursor must restore it on every exit path.

## Status

**2026-11-11 — milestones M0–M4 and M6 (resume) implemented, M5 partly.**
Two commits on this date: the first version (M0–M4), then resume, the
key-sink fix and the summary grace period.

Checks actually performed on this date, Vim 9.1.1752 on macOS inside tmux:

- `./test/run.sh`: 10 files passed, also with `TERM=dumb` and with `TERM`
  unset. The runner was shown to report a failing assertion (exit 1) and to
  kill and report a hanging test (`timed out`).
- Real-terminal runs in an isolated tmux server, keys sent with `tmux
  send-keys`:
  - First version, once per error mode, on a four-line sample with
    indentation, a blank line and curly quotes: pending text dim, typed text
    normal, wrong character red, warning text in the status popup, cursor cell
    alternating between captures, terminal cursor hidden while typing,
    corrected character underlined amber, summary popup, sample file checksum
    unchanged, one history record written to a temporary file.
  - Resume: stop midway with Esc (summary shows `Position saved`), entry
    written to a temporary progress file, `:TypingStart` shows the menu,
    Enter resumes at the saved character with earlier text in normal colour
    and progress 47%, finishing empties the progress file and writes a record
    with `start` 28. End state read from inside Vim: one tab, no popups, no
    timers, `t_ve` restored, buffer unmodified.
  - Key sink: Esc immediately followed by `q:ix`, and the full text followed
    by overshoot keys `rq:i`. In both the summary was showing afterwards, with
    no macro recording, no command-line window and no restart. Before the fix
    the first sequence started a macro recording and left the session unusable.
- `:helptags doc` exits 0.

Known behaviour: in a terminal Vim recognises Esc only after its key-code
timeout (up to one second with default settings); Ctrl-C is immediate. The help
file explains `ttimeoutlen`.

Not checked: input through a real input method; GUI Vim; a real terminal
resize; a colorscheme change during a session; large files; the summary popup
in a terminal shorter than about 22 rows. In the tmux runs keys arrive in
bursts, so the WPM figures there are meaningless.
Not done: installation into `~/.vim/pack` (only on request).

How it was built: modules were written by delegated agents against the
contract in PLAN.md section 5.1, then reviewed and re-tested here. Fixes that
came out of that review: progress is characters passed ÷ total; the key sink
across transitions; the summary grace period; the runner's watchdog and
terminal-type default.

## Next step

The open M5 items in [PLAN.md](PLAN.md) section 6, then the backlog there.
