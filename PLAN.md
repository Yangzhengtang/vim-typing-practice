# vim-typing-practice — plan

Written 2026-11-11. Status of each part is labelled: **decided** (agreed with the
owner), **verified** (checked by running code), **proposed** (my default; change
freely) or **unverified** (a risk to check during the named milestone).

## 1. Goal

A Vim plugin for practising typing over the text of any file you have open.

- The text is shown dimmed. Characters return to normal colour as you type them.
- A wrong key turns the character red and shows a warning.
- The current position is marked with a blinking highlight.
- Time, speed, accuracy and related statistics are shown live and summarised at
  the end; results are saved so progress can be reviewed.
- **The original buffer and file are never modified.** (I read "the user's
  operation would touch the original file" in the request as "would *not* touch";
  say so if you meant the opposite.)

## 2. Decisions from the kickoff questions (decided)

| Topic | Decision |
| --- | --- |
| Editor | Vim 9 only, written in vim9script (text properties, popup windows, timers). No Neovim support. |
| Wrong key | Both behaviours, selected by an option. Default `stay`: the cursor waits for the right key. Alternative `advance`: the cursor moves on and Backspace goes back. |
| Content | Tuned for prose: leading indentation and blank lines are skipped, and a line end accepts Space or Enter. |
| Statistics | Live WPM/CPM, accuracy, errors, time and progress; end-of-session summary popup; most-missed keys; saved history with a viewer. |

## 3. Feasibility (verified 2026-11-11, Vim 9.1.1752, macOS, tmux)

Scripts are in [spike/](spike/). Results:

| Question | Result |
| --- | --- |
| Can one mechanism capture every key without mappings? | Yes. A popup window with a `filter` callback and `mapping: false` received letters, Space, Enter, Backspace, Tab, `:`, Esc and multi-byte characters (`“`, `中`). A buffer-local mapping on `h` did not fire. |
| Is the text left alone? | Yes. The practice buffer is `nomodifiable`; text properties can still be added and the lines were unchanged afterwards. |
| Does Ctrl-C leave a clean exit path? | Yes. Ctrl-C closes the popup and calls its `callback` with `-1`, which is where cleanup hooks in. |
| Do dim, red and cursor colours render together? | Yes. tmux capture showed colour 242 for pending text, white-on-red for the wrong character, and reverse video on the cursor cell. |
| Can the cursor blink independently of the terminal? | Yes. A 400 ms timer toggling the `TypingCursor` highlight alternated the cell between reverse and plain across captures. |
| Can the real terminal cursor be hidden? | Yes. Clearing `t_ve` made tmux report the cursor as invisible. It must be restored on every exit path. |
| Can this be tested headlessly? | Yes. `feedkeys(..., 'xt')` drives the popup filter under `vim -Nu NONE --not-a-term`; [test/run.sh](test/run.sh) reports assert failures and exits non-zero (confirmed with a deliberately failing test). |

Not yet verified: see section 9.

## 4. User experience (proposed unless marked)

### Commands

| Command | Effect |
| --- | --- |
| `:TypingStart` | Practise the whole buffer. |
| `:{range}TypingStart` | Practise a line range, e.g. `:'<,'>TypingStart` for a visual selection or `:.,$TypingStart` from the cursor line. |
| `:TypingStop` | End the session (same as Esc). |
| `:TypingHistory` | Open the history view. |

No default key mappings. `<Plug>(typing-start)` is provided for users who want one.

### Session flow

1. `:TypingStart` copies the selected lines into a scratch buffer
   (`buftype=nofile`, `noswapfile`, `nomodifiable`) shown in a new tab. The
   original buffer, its window layout and its file are not touched.
2. All text is dimmed; the cursor highlight sits on the first character.
3. The clock starts on the first keystroke.
4. Typing continues until the last character, or until Esc / Ctrl-C /
   `:TypingStop`, or until the practice window loses focus.
5. The summary popup appears. `r` restarts the same text; any other key closes
   the tab and returns to the original window.

### What must be typed (prose rules — decided)

- Leading whitespace on each line is skipped; trailing whitespace is ignored.
- Blank lines are skipped.
- At the end of a line, Space or Enter moves to the next line. A dim `↵` marker
  shows the position so the cursor has a cell to sit on.
- A Tab inside a line accepts Tab or Space.
- Typographic punctuation accepts its keyboard equivalent: `’ ‘` → `'`,
  `“ ”` → `"`, `– —` → `-`, `…` → `.`, non-breaking space → Space. The table is
  configurable.
- Other non-ASCII characters must be typed as they are (an input method
  works because the key sink receives whole multi-byte characters). An option
  skips them instead.

### Keys during a session

| Key | `stay` mode | `advance` mode |
| --- | --- | --- |
| Correct character | Character turns normal; cursor advances. | Same. |
| Wrong character | Character turns red, warning shown, cursor stays. Counts as one error per keystroke. | Character turns red, warning shown, cursor advances. |
| Backspace | Ignored. | Moves back one character and clears its state. |
| Esc, Ctrl-C | End the session and show the summary. | Same. |
| Arrows, function keys, mouse | Ignored and not counted. | Same. |

A character that was wrong and then corrected is shown in the `TypingFixed`
colour (underlined amber) so slips stay visible. Link it to `Normal` to hide them.

### Wrong-key warning

Three signals: the character itself turns red; the status popup switches to a
warning colour for about 600 ms and shows `✗ expected "e", typed "r"`; and, if
enabled, the terminal bell rings.

### Blinking cursor

The current character carries a `TypingCursor` text property. A timer toggles
that highlight group every `g:typing_blink_ms`. Each keystroke resets the cycle
to "on" so the cursor is always visible while typing. The real terminal cursor
is hidden for the session and restored on every exit path.

### Statistics

| Figure | Definition |
| --- | --- |
| Time | From the first keystroke to the last. Gaps longer than `g:typing_idle_seconds` are not counted. |
| Keystrokes | Character keys that were judged. Backspace and ignored keys are excluded. |
| Accuracy | Correct keystrokes ÷ keystrokes. |
| Raw WPM | Keystrokes ÷ 5 ÷ minutes. |
| WPM (net) | Characters currently typed correctly ÷ 5 ÷ minutes. |
| CPM | Net WPM × 5. |
| Errors | Wrong keystrokes. |
| Longest streak | Longest run of consecutive correct keystrokes. |
| Progress | Characters completed ÷ total characters. |
| Most-missed keys | For each expected character: misses, attempts, and what was typed instead (for example `e → r ×4`). Top five by misses. |

Live display: a one-line popup at the bottom right of the practice window, for
example `01:23  54 wpm  96.4%  7 err  42%`, refreshed on every key and once a
second. This popup is also the key sink.

Summary popup: all figures above, plus a comparison with your best and your
average over the last ten sessions.

### History

One JSON object per line is appended to `g:typing_history_file` (default
`~/.vim/typing-practice/history.jsonl`, outside this repository). Fields: start
time, file name (tail only), line range, duration, character count, net and raw
WPM, accuracy, errors, longest streak, error mode, whether the text was
finished, and missed-key counts. Sessions with fewer than 20 keystrokes are not
saved.

`:TypingHistory` opens a read-only scratch buffer with the most recent sessions
as a table, totals (best WPM, average of the last ten, all-time most-missed
keys) and a one-line WPM trend.

### Resume (requested 2026-11-11)

When a session on a named file stops before the end of the text, the position
is saved. The next `:TypingStart` on that file offers to continue from there.

- **Saved when** a session ends early (`q` while paused, Ctrl-C,
  `:TypingStop`, leaving the practice tab) at a position that differs from
  where the session started and is not the very first character. A session
  that ends where it started, or at the top, leaves any saved position as it
  was.
  Finishing the text deletes the saved position. Buffers without a file name
  save nothing.
- **Where**: one JSON file, `g:typing_progress_file` (default
  `~/.vim/typing-practice/progress.json`, outside this repository), keyed by
  the file's absolute path. Each entry holds the line range, the position, the
  total, the line number, a fingerprint of the text and the time.
- **Offer**: `:TypingStart` with the same line range as the saved entry shows a
  small menu: `Resume at line 12 (37%)` or `Start from the beginning`. Esc
  cancels and starts nothing. A different line range gets no offer.
- **Text changed since** (fingerprint or total differs): the exact position is
  not trusted. The menu offers `Resume at line 12 (text changed)`, which starts
  at the first character of that line, or of the next line that has text.
- **A resumed session** shows everything before the resume point in normal
  colour. Those characters are not keystrokes: they do not count towards WPM,
  accuracy or errors. Progress and the character count show the position in
  the whole text. Backspace in `advance` mode stops at the resume point.
  Restart (`r`) starts again from the same resume point.
- **Summary** of a session stopped early adds a line saying the position was
  saved and where.
- `g:typing_resume`: `'ask'` (default), `'always'` (resume without asking) or
  `'never'` (neither save nor offer). `:TypingStart!` starts from the
  beginning without asking.

### Original colours (requested 2026-11-11)

The practice copy keeps the syntax highlighting of the original buffer, in
whatever colorscheme is active (molokai, for example).

- The practice buffer gets the origin's `'syntax'` value (not its `'filetype'`,
  so no filetype plugins or autocommands run). Concealing is switched off in
  the practice window so every character stays visible.
- Untyped text is a uniform grey (`TypingPending`): its property does not
  combine with syntax colours. Typing a character correctly removes the grey
  and its original syntax colour appears.
- Wrong, corrected and cursor marks sit on top as before.
- If syntax highlighting is off, or the buffer has no syntax, typed text is in
  the Normal colour as before.
- A line range is highlighted from its first line, so constructs that began
  earlier in the file (a long comment or string) may be coloured differently.

### Moving to another position (requested 2026-11-11)

Esc no longer ends the session. It pauses it so the cursor can be moved, at
the very start or in the middle.

| Key while paused | Effect |
| --- | --- |
| Any Vim motion (`j`, `k`, `w`, `}`, `gg`, `G`, counts, `/search` …) | Moves the real cursor in the practice buffer. The buffer stays read-only. |
| Enter or `i` | Type from the cursor: the first character at or after it becomes the current position. |
| Esc | Back to typing at the position you left. |
| `q` | End the session and show the summary. |
| Ctrl-C | End the session and show the summary (also while typing, as before). |

- While paused the terminal cursor is visible, the position marker stops
  blinking and stays where typing would continue, the clock is stopped, and
  the status popup shows the keys above.
- Jumping forward marks the text in between as skipped: shown as typed, not
  counted. Jumping backward makes everything from the new position onward
  untyped again; its wrong/corrected marks are cleared. Keystrokes, errors and
  time already recorded stay, and characters that were standing as correct
  still count towards net WPM.
- After a jump, Backspace in `advance` mode stops at the jump position.
- If there is nothing to type at or after the cursor, a message says so and the
  session stays paused.
- Leaving the practice tab while paused ends the session as it does while
  typing. `:TypingStop` works in every phase.
- Esc is made responsive for the session: `'ttimeout'`/`'ttimeoutlen'` are set
  to `g:typing_esc_timeout_ms` (default 50; 0 leaves them alone) and restored
  on every exit path.

### Options

| Option | Default | Meaning |
| --- | --- | --- |
| `g:typing_on_error` | `'stay'` | `'stay'` or `'advance'`. |
| `g:typing_line_end` | `'either'` | Key accepted at a line end: `'either'`, `'enter'` or `'space'`. |
| `g:typing_equivalents` | table above | Map of text character to the accepted key. `{}` disables. |
| `g:typing_skip_non_ascii` | `false` | Skip characters outside ASCII that have no equivalent. |
| `g:typing_blink_ms` | `500` | Blink half-period. `0` gives a steady cursor. |
| `g:typing_bell` | `false` | Ring the bell on a wrong key. |
| `g:typing_idle_seconds` | `5` | Gaps longer than this are not timed. |
| `g:typing_resume` | `'ask'` | `'ask'`, `'always'` or `'never'`; see Resume. |
| `g:typing_progress_file` | `~/.vim/typing-practice/progress.json` | Where resume positions are saved. |
| `g:typing_esc_timeout_ms` | `50` | Key-code timeout used during a session so Esc registers quickly. `0` leaves Vim's setting alone. |
| `g:typing_summary_grace_ms` | `500` | Keys are ignored for this long after the summary appears. `0` disables. |
| `g:typing_history` | `true` | Save sessions. |
| `g:typing_history_file` | `~/.vim/typing-practice/history.jsonl` | Where sessions are saved. |

Highlight groups (all `highlight default`, so a colorscheme or vimrc wins):
`TypingPending`, `TypingWrong`, `TypingFixed`, `TypingCursor`, `TypingStatus`,
`TypingStatusWarn`. They are defined in [plugin/typing.vim](plugin/typing.vim).

## 5. Architecture (proposed)

```
plugin/typing.vim             commands, highlight defaults, feature guard   (exists)
autoload/typing/session.vim   lifecycle: scratch tab, key sink, cleanup     (stub)
autoload/typing/engine.vim    pure logic: build targets, judge keys
autoload/typing/render.vim    text properties, blink timer, cursor hiding
autoload/typing/stats.vim     counters, clock, WPM/accuracy, missed keys
autoload/typing/ui.vim        status popup, warning flash, summary popup
autoload/typing/history.vim   JSONL read/write, :TypingHistory view
doc/typing.txt                :help typing-practice
test/                         run.sh, harness.vim, test_*.vim               (exists)
```

Key points:

- **Engine is pure.** `engine.Build(lines, opts)` returns a list of targets, each
  with its line, byte column, byte length, accepted keys and state
  (`pending`, `correct`, `wrong`, `fixed`). `engine.Feed(state, key)` returns an
  event (`correct`, `wrong`, `back`, `ignored`, `done`) and the indexes of the
  targets that changed. It touches no buffer, so it is unit-tested directly.
- **Render and stats consume events.** Render updates only the properties of the
  changed targets; stats updates counters. Neither decides whether a key was right.
- **Dimming is one text property per line** covering the untyped part of that
  line. Advancing replaces the current line's property, so the cost per
  keystroke does not depend on file size.
- **One cleanup function, safe to call twice.** It stops timers, closes popups,
  restores `t_ve` and closes the tab. It is reached from Esc, Ctrl-C (popup
  callback `-1`), `:TypingStop`, completion, `WinLeave`/`BufLeave` of the
  practice window, and `VimLeavePre`.

### 5.1 Module interfaces (contract)

Every module is a vim9script autoload file, imported with
`import autoload 'typing/<name>.vim'`. Exported names and dict keys below are
the contract between modules; change them only together with their consumers.

#### engine.vim — pure (no buffers, windows, popups, timers or `g:` variables)

```
DefaultEquivalents(): dict<string>
Build(lines: list<string>, opts: dict<any> = {}): dict<any>
Feed(st: dict<any>, key: string): dict<any>
```

`opts` (all optional): `on_error` (`'stay'`), `line_end` (`'either'`),
`equivalents` (`DefaultEquivalents()`), `skip_non_ascii` (`false`).

State returned by `Build`:

| Key | Type | Meaning |
| --- | --- | --- |
| `targets` | `list<dict<any>>` | Everything to type, in order. |
| `pos` | number | Index of the current target; `len(targets)` when finished. |
| `standing` | number | Targets before `pos` whose state is `correct` or `fixed`. Maintained incrementally. |
| `on_error` | string | `'stay'` or `'advance'`. |
| `done` | bool | True when `pos == len(targets)` (also for empty input). |

Target:

| Key | Type | Meaning |
| --- | --- | --- |
| `lnum` | number | 1-based index into `lines`. |
| `col` | number | 1-based byte column of the character. For a break: the byte column just after the last non-blank character of the line. |
| `len` | number | Byte length of the character; `0` for a break. |
| `char` | string | The character; `"\n"` for a break. |
| `kind` | string | `'char'` or `'break'`. |
| `accept` | `list<string>` | Keys that count as correct. |
| `state` | string | `'pending'`, `'correct'`, `'wrong'` or `'fixed'`. |
| `missed` | bool | True once a wrong key was pressed on this target. |

Build rules:

- Leading whitespace of a line produces no targets; trailing whitespace is
  ignored; a line that is blank after trimming produces no targets.
- Each remaining character (split with `'\zs'`, so composing characters stay
  attached) is a `char` target. `accept` is the character itself plus its entry
  in `equivalents` if any. A Tab accepts `"\t"` and `' '`.
- With `skip_non_ascii`, a non-ASCII character without an equivalent produces no
  target.
- After the last character of every line that has targets, except the last such
  line, comes one `break` target. `accept` is `["\r", ' ']` for `either`,
  `["\r"]` for `enter`, `[' ']` for `space`.

`Feed` normalises `"\n"` to `"\r"`. Judged keys are `"\r"`, `"\t"` and any
single printable character (including multi-byte). Backspace is `"\<BS>"`,
`"\x08"` or `"\x7f"`. Anything else (Esc, arrows, function keys, mouse events,
other control characters) is ignored. Once `st.done`, every key is ignored.

| Situation | `stay` | `advance` |
| --- | --- | --- |
| Key in `accept` | state → `fixed` if `missed`, else `correct`; `pos` + 1 | same |
| Judged key not in `accept` | state → `wrong`, `missed` = true; `pos` unchanged | state → `wrong`, `missed` = true; `pos` + 1 |
| Backspace | ignored | if `pos` > 0: `pos` − 1 and that target → `pending` (keeps `missed`); else ignored |

Event returned by `Feed`:

| Key | Type | Meaning |
| --- | --- | --- |
| `kind` | string | `'correct'`, `'wrong'`, `'back'` or `'ignored'`. |
| `changed` | `list<number>` | Indexes of targets whose state changed. |
| `expected` | string | `char` of the judged target; `''` for `back`/`ignored`. |
| `typed` | string | The normalised key; `''` for `back`/`ignored`. |
| `pos`, `total`, `standing` | number | Values after the event. |
| `done` | bool | True when the text is finished after this event. |

#### stats.vim — pure

```
New(opts: dict<any> = {}): dict<any>            # opts: idle_seconds (5.0)
Record(s: dict<any>, ev: dict<any>, now: float) # ev from engine.Feed; now = seconds
Snapshot(s: dict<any>, now: float): dict<any>
TopMissed(s: dict<any>, n: number = 5): list<dict<any>>
MissedCounts(s: dict<any>): dict<number>        # expected char → misses, only > 0
```

`ignored` events change nothing. `correct` and `wrong` are keystrokes; `back` is
not a keystroke but does move the clock. The clock starts at the first
non-ignored event. Each later non-ignored event adds the gap since the previous
one if it is at most `idle_seconds`, otherwise nothing. `Snapshot` also adds the
open gap up to `now` under the same rule and sets `paused` when the gap is
longer. After an event with `done`, the clock is frozen.

Snapshot keys: `elapsed` (float seconds), `keystrokes`, `correct`, `errors`,
`accuracy` (float percent; `100.0` with no keystrokes), `raw_wpm`, `wpm`, `cpm`
(floats; `0.0` while `elapsed` is 0), `streak`, `best_streak`, `pos`, `total`,
`standing`, `progress` (float percent; `0.0` when `total` is 0), `started`,
`paused`, `finished`. Formulas are in section 4.

`TopMissed` entries: `{char, misses, attempts, typed}` where `typed` is a list of
`[key, count]` pairs, most frequent first. Order: misses descending, then miss
rate descending, then `char`.

#### history.vim

```
DefaultFile(): string            # g:typing_history_file or ~/.vim/typing-practice/history.jsonl
Append(file: string, record: dict<any>): bool   # mkdir -p, one JSON line; false on failure, never throws
Load(file: string): list<dict<any>>             # missing file → []; non-object lines skipped
Summarize(records: list<dict<any>>): dict<any>  # count, best_wpm, avg_wpm, avg_accuracy (last 10), missed
Lines(records: list<dict<any>>, limit: number = 30): list<string>
Show(file: string = DefaultFile())              # scratch split named "[Typing history]", q closes
```

Record keys: `time` (number, `localtime()`), `file`, `line1`, `line2`,
`duration` (float), `chars`, `wpm`, `raw_wpm`, `accuracy`, `errors`,
`best_streak`, `mode`, `completed` (bool), `missed` (dict char → misses).
`Summarize().missed` is a list of `[char, misses]`, top five over all records.

#### render.vim — text properties, blink, terminal cursor

```
Setup(buf: number, st: dict<any>)                  # prop types + props for every target; cursor on st.pos
Apply(buf: number, st: dict<any>, ev: dict<any>)   # after engine.Feed: restyle ev.changed, move dim boundary and cursor
CursorPos(st: dict<any>): list<number>             # [lnum, byte col] of the current target (last target when done; [1, 1] if none)
StartBlink(ms: number)                             # ms <= 0: steady cursor, no timer
StopBlink()
Pulse()                                            # cursor "on" now, restart the blink cycle
HideTerminalCursor()                               # save and clear t_ve; idempotent; no-op in the GUI
RestoreTerminalCursor()                            # idempotent
Teardown(buf: number)                              # StopBlink + RestoreTerminalCursor + remove props/types if buf exists
```

- Prop types are buffer-local (`bufnr: buf`) and use the highlight groups from
  [plugin/typing.vim](plugin/typing.vim): pending (priority 10), fixed (20),
  wrong (30), cursor (40).
- Dimming: for each line, one pending prop from the byte column of the first
  target on that line with index ≥ `st.pos` to the end of the line; no prop if
  the line has no such target. `Apply` only reworks the lines between the old
  and new position.
- `correct` targets carry no prop (normal colour). `wrong` and `fixed` `char`
  targets carry a prop on `[col, col + len)`.
- Each `break` target shows an inline virtual-text `↵` at its `col`, styled by
  the target's state (pending dim, wrong red, fixed amber, correct dim) and as
  the cursor when it is the current target.
- The cursor prop/marker uses an internal group `TypingCursorBlink`. Blinking
  flips that group between a link to `TypingCursor` (on) and cleared (off); it
  never redefines the user-facing `TypingCursor` group.

#### ui.vim — popups and text formatting

```
FormatTime(seconds: float): string                 # 'MM:SS'; minutes keep counting past 59
StatusText(snap: dict<any>): string                # '01:23  54 wpm  96.4%  7 err  42%' (+ ' paused' when snap.paused)
KeyName(key: string): string                       # "\n"/"\r" → ↵, ' ' → ␣, "\t" → ⇥, else the key
WarnText(expected: string, typed: string): string  # '✗ expected "e", typed "r"' using KeyName
SummaryLines(snap: dict<any>, top: list<dict<any>>, hist: dict<any>, completed: bool): list<string>
OpenStatus(winid: number, Filter: func(number, string): bool, OnClose: func(number, any)): number
SetStatus(id: number, text: string)
Warn(id: number, text: string, ms: number = 600)   # warning colour + text for ms, then back to the latest status
ClearWarn(id: number)
Reposition(id: number, winid: number)
CloseStatus(id: number)
ShowSummary(lines: list<string>, OnKey: func(string)): number
```

- `snap` is a `stats.Snapshot`, `top` is `stats.TopMissed`, `hist` is
  `history.Summarize` of the sessions *before* this one.
- The status popup sits at the bottom-right corner of window `winid`, uses
  `TypingStatus` / `TypingStatusWarn`, has `mapping: false`, and passes every
  key to `Filter`; `OnClose` is the popup callback (result `-1` on Ctrl-C).
- The summary popup is centred with a border and title. Its filter consumes the
  next key, closes the popup and calls `OnKey(key)`.

#### session.vim — lifecycle

```
Start(line1: number, line2: number)
Stop()
History()                        # history.Show()
State(): dict<any>               # for tests
SetClock(F: func(): float)       # tests inject a clock; default reltimefloat(reltime())
```

Options are read once at `Start`: those in section 4 plus
`g:typing_history_min_keys` (20). Phases: `idle`, `prompt`, `typing`,
`paused`, `summary`. Since M7, Esc while typing pauses instead of finishing;
see "Colours and pause additions (M7)" below, which supersedes the Esc
behaviour described in this list.

- **Start**: refused while a session is active. Takes the lines of the current
  buffer, builds the engine state, and returns with "nothing to type" (opening
  nothing) if there are no targets. Otherwise opens a new tab with a scratch
  copy (`buftype=nofile`, `bufhidden=wipe`, `noswapfile`, `nobuflisted`,
  `nomodifiable`, named `[Typing] <tail>`; window-local `wrap`, `linebreak`, no
  number/list/cursorline/spell/sign/fold columns, `scrolloff=5`), then
  `render.Setup`, `HideTerminalCursor`, `StartBlink`, the status popup and a
  1 s status refresh timer. The origin buffer, its `modified` flag and its
  window are never changed.
- **Key filter** (always consumes the key): Esc → `Finish(false)`; otherwise
  `engine.Feed`; ignored events do nothing; for the rest `stats.Record`,
  `render.Apply`, `render.Pulse`, move the practice window's cursor to
  `render.CursorPos`, refresh the status, `ui.Warn` (+ bell if enabled) on a
  wrong key or `ui.ClearWarn` otherwise, and `Finish(true)` when done. Ctrl-C
  (status popup closed with `-1`) → `Finish(false)`.
- **Finish(completed)**: stop the timers, close the status popup, take the
  snapshot, summarise earlier history *before* appending, append the record if
  history is on and keystrokes ≥ `min_keys`, show the summary popup.
- **Summary key**: `r` restarts the same text in the same practice buffer with
  fresh engine state and statistics; any other key closes.
- **Close**: full cleanup, close the practice tab, return to the origin window.
- **Abort** (practice window/buffer/tab left, or buffer wiped, while typing):
  save the record as incomplete under the same rule, no summary, then close.
- **Stop**: typing → `Finish(false)`; summary → close; idle → message.
- **Cleanup** is idempotent and re-entrancy safe: timers stopped,
  `render.Teardown`, popups closed, the `TypingPracticeSession` autocommands
  removed, state back to idle. `VimLeavePre` restores the terminal cursor;
  `VimResized` repositions the status popup.

`State()` keys: `phase`, `buf`, `winid`, `tabnr`, `origin_winid`, `st`, `stats`,
`status_id`, `summary_id`, `lines`, `last_record`, `last_saved`, `last_summary`.

#### Colours and pause additions (M7)

engine.vim:

```
IndexAt(st: dict<any>, lnum: number, col: number): number   # byte col; -1 if none
Jump(st: dict<any>, index: number): dict<any>               # event of kind 'jump'
```

`IndexAt` returns the first target that contains or follows the position: on
line `lnum` the first target with `col + max(len, 1) > col_arg`, otherwise the
first target on a later line. `Jump` (valid for `0 <= index < len(targets)`,
otherwise an `ignored` event): targets before `index` that are `pending`
become `skipped`; targets from `index` on become `pending` and lose `missed`;
`pos` and `start` become `index`; `standing` is recounted for the targets
before `index`; `done` is false. The event has `kind: 'jump'`, `changed: []`
(the caller re-renders everything), `lost` = the number of `correct`/`fixed`
targets that were reset, and the usual `pos`, `total`, `standing`, `done`.

stats.vim:

```
Pause(s: dict<any>, now: float)   # close the open gap under the idle rule; the next event adds no gap
```

A `jump` event is not a keystroke; `lost` is added to a banked count so net
WPM uses `standing + banked`. Snapshots gain `passed` (targets passed by
typing: +1 when a `correct`/`wrong` event advances, −1 on `back`) and
`banked`. History `chars` becomes `passed`; `start` stays the position where
the session first started typing.

render.vim: the pending property type is created with `combine: false`.
`Setup` remains the way to re-render after a jump.

render.vim, found during M7: the character cursor property type is also
`combine: false`. Vim lets the highest-priority property on a cell decide
whether syntax attributes are kept, so a combining cursor would show the
syntax bold in the blink's "off" phase. Side effect: a wrong character under
the cursor shows without the syntax bold/italic.

session.vim, pending commands while paused: keys pass through untouched when
Vim is not in plain Normal mode (command line, Visual, operator-pending) and
for the key after a prefix such as `f`, `t`, `g`, `'`, so `fi` and `fq` stay
motions. A count before Enter, `i` or `q` is cancelled first.

session.vim: the practice buffer gets `&l:syntax` from the origin; the window
gets `conceallevel=0`. New phase `'paused'`. Esc while typing →
`stats.Pause`, `render.StopBlink`, `render.RestoreTerminalCursor`, status hint,
and the key filter passes keys through to Vim (returns false) except Enter,
`i`, Esc and `q`. Enter/`i` → `engine.IndexAt` at the practice window's
cursor, `engine.Jump`, `stats.Record`, `render.Setup`, back to typing. Esc →
back to typing with the real cursor returned to `render.CursorPos`. `q` →
`Finish(false)`. The key-code timeout is saved, set and restored by the
session together with the terminal cursor.

#### Key sink across transitions (added 2026-11-11)

From `Start` (or its resume prompt) until the practice tab is closed, no typed
key may reach Normal mode. Finish → summary, summary key → restart/close and
resume choice → practice start are deferred with zero-delay timers, and keys
already in the typeahead run before such a timer fires, so `session.vim` keeps
a transparent guard popup whose filter swallows keys across each transition.
The summary also ignores keys for `g:typing_summary_grace_ms` after it
appears, so overshoot keystrokes cannot dismiss it or trigger a restart.

#### Resume additions (M6)

engine.vim:

```
StartAt(st: dict<any>, index: number)             # only before the first Feed
IndexAtLine(st: dict<any>, lnum: number): number  # first target with lnum >= given; -1 if none
```

`StartAt` clamps `index` to `[0, len(targets) - 1]`, sets the state of every
target before it to `'skipped'`, sets `st.pos` and a new key `st.start` to it
and leaves `standing` at 0. `Build` sets `st.start = 0`. Backspace in `advance`
mode is ignored when `pos <= st.start`. `skipped` targets are never counted in
`standing`. Render gives `skipped` characters no property (normal colour).

stats.vim: `New` also accepts `pos` (default 0), the starting position, so
progress is right before the first key.

progress.vim (new; file I/O only):

```
DefaultFile(): string                           # g:typing_progress_file or the default path
Fingerprint(lines: list<string>): string        # sha256 of the lines joined with "\n"
Load(file: string): dict<any>                   # path → entry; missing or corrupt file → {}
Get(file: string, path: string): dict<any>      # entry or {}
Save(file: string, path: string, entry: dict<any>): bool   # read-modify-write via a temp file + rename; never throws
Remove(file: string, path: string): bool
```

Entry keys: `line1`, `line2`, `pos`, `total`, `lnum`, `hash`, `time`.

ui.vim: `ShowChoice(title: string, items: list<string>, OnPick: func(number)): number`
— a `popup_menu`; `OnPick` gets the 1-based item, or 0 when cancelled, exactly once.

session.vim: `Start(line1, line2, fresh: bool = false)`; `:TypingStart` takes a
bang. New phase `'prompt'` while the menu is open (a second `Start` is refused;
`Stop` cancels it). The practice tab opens only after the choice. `State()`
adds `start` (resume index of the running session, 0 otherwise), `prompt_id`
and `path`. History records add `start`, and `chars` becomes `pos - start`.

## 6. Milestones

Each milestone ends with `./test/run.sh` passing and a check in a real
terminal. State as of 2026-11-11: M0–M4, M6 and M7 implemented and checked; M5
partly done. Checks actually performed are recorded in
[PROJECT_GUIDE.md](PROJECT_GUIDE.md).

| # | Scope | Done when |
| --- | --- | --- |
| M0 | Project scaffold, spike, test runner. **Done 2026-11-11.** | Plugin loads in a clean Vim; `test/test_load.vim` passes. |
| M1 ✔ | Core loop in `stay` mode: engine, scratch tab, key sink, dim → normal → red, prose rules, exit paths. | Engine unit tests cover indentation, blank lines, line ends and equivalents. A `feedkeys` test types a three-line text to completion and another quits midway; in both the original buffer is unchanged and unmodified. |
| M2 ✔ | Blinking cursor, hidden terminal cursor, line-end marker, warning flash and bell, `advance` mode with Backspace. | Tests cover both error modes including Backspace at a line start. `t_ve` is restored after finish, Esc, Ctrl-C and leaving the window. tmux capture shows the blink. |
| M3 ✔ | Clock with idle exclusion, live status popup, summary popup, restart. | Stats unit tests use an injected clock and check every figure in section 4 against hand-computed values. |
| M4 ✔ | Most-missed keys, history file, `:TypingHistory`. | A session appends one valid JSON line to a temporary history file; the viewer renders a fixture file; a corrupt line is skipped without an error. |
| M5 (partly) | Ranges and visual selection, long-line wrapping, window resize, colorscheme change, `doc/typing.txt`, README usage, install into `~/.vim/pack`. | `:help typing-practice` works; a manual pass on a real prose file and a real terminal resize. **Done:** ranges, Visual `<Plug>` mapping, wrapping options, help file, README. **Open:** real resize and colorscheme-change checks, large-file timing, installation (only on request). |
| M6 ✔ | Resume from the saved position (section 4 "Resume"). | Tests for `progress.vim`, `engine.StartAt`, and the session flows: ask → resume, ask → start over, cancel, `always`, `never`, bang, changed text, different range, finishing clears the entry, an unnamed buffer saves nothing. A real-terminal run: stop midway, start again, pick resume, finish. |
| M7 ✔ | Original syntax colours; Esc pauses to move the cursor and type from another position. | Tests for `engine.IndexAt`/`Jump`, `stats.Pause` and the banked count, the non-combining pending property, and the session flows (pause at start and midway, jump forward and backward, Esc back, `q`, Ctrl-C, nothing at cursor, leaving the tab while paused, timeout option saved and restored). Real-terminal runs with a built-in colorscheme and with a pause-move-type sequence. |

Backlog, not planned: a strict mode for source code (type indentation, Enter
only), per-word statistics, generated drills from your most-missed keys,
Neovim support.

## 7. Testing

- Unit tests for `engine` and `stats`: no windows or popups involved.
- Integration tests: start a session on a fixture buffer, drive it with
  `feedkeys(..., 'xt')`, then assert on text properties, statistics, the history
  file and the untouched original buffer.
- Rendering checks: tmux `capture-pane -e` on an isolated tmux server, as in the
  spike, for colours, blink and cursor visibility. These are manual until they
  prove worth automating.
- Tests always run with `-u NONE -i NONE` and a temporary history file, so they
  never read your vimrc or write to your real history.

## 8. Installation (proposed, at M5)

Symlink the repository into Vim's native package path:

```sh
mkdir -p ~/.vim/pack/local/start
ln -s ~/Projects/vim-typing-practice ~/.vim/pack/local/start/vim-typing-practice
```

This changes `~/.vim`, so it will be done only when you ask for it.

## 9. Risks and open points

| Item | State | Checked in |
| --- | --- | --- |
| Input-method (IME) input of multi-byte characters reaches the key sink as whole characters. Verified with `feedkeys` only, not with a real IME. | unverified | M1, manually |
| The line-end `↵` marker as virtual text can carry the blinking cursor highlight. | verified 2026-11-11 (headless screen attributes) | M2 |
| If Vim is killed during a session, the terminal cursor stays hidden until `reset` or `tput cnorm`. Normal exits are covered by `VimLeavePre`. | accepted limitation | M2, documented |
| Very large files: one property per line at start-up. Expected to be fine; not measured. | unverified | M5 |
| GUI Vim (MacVim/gVim): `t_ve` does not apply; `guicursor` would be used instead. Not available on this machine. | unverified, low priority | backlog |

Choices I made that you may want to change: the project name; practising in a
new tab rather than in place; Esc ending the session immediately rather than
pausing; the history location; the `TypingFixed` colour for corrected slips.
