vim9script
# Tests for autoload/typing/render.vim (PLAN.md section 5.1).
# Each test makes its own scratch buffer; rendering is observed through
# prop_list() and, for the cursor/marker check, through the screen.

import autoload 'typing/engine.vim'
import autoload 'typing/render.vim'

const TYPE_PENDING = 'TypingPending'
const TYPE_FIXED = 'TypingFixed'
const TYPE_WRONG = 'TypingWrong'
const TYPE_CURSOR = 'TypingCursor'
const TYPE_BREAK_PENDING = 'TypingBreakPending'
const TYPE_BREAK_CORRECT = 'TypingBreakCorrect'
const TYPE_BREAK_FIXED = 'TypingBreakFixed'
const TYPE_BREAK_WRONG = 'TypingBreakWrong'
const TYPE_BREAK_CURSOR = 'TypingBreakCursor'
const ALL_TYPES = [TYPE_PENDING, TYPE_FIXED, TYPE_WRONG, TYPE_CURSOR,
  TYPE_BREAK_PENDING, TYPE_BREAK_CORRECT, TYPE_BREAK_FIXED, TYPE_BREAK_WRONG,
  TYPE_BREAK_CURSOR]

def NewBuf(lines: list<string>): number
  enew
  setline(1, lines)
  setlocal buftype=nofile noswapfile nobuflisted
  setlocal nomodifiable
  &modified = false
  return bufnr('%')
enddef

def Props(buf: number, lnum: number): list<dict<any>>
  return prop_list(lnum, {bufnr: buf})
enddef

# [col, length] of the properties of one type on one line.
def PropsOf(buf: number, lnum: number, type: string): list<list<number>>
  return mapnew(
    filter(Props(buf, lnum), (_, p) => p.type == type),
    (_, p) => [p.col, p.length])
enddef

def Breaks(buf: number, lnum: number): list<dict<any>>
  return filter(Props(buf, lnum), (_, p) => p.type =~# '^TypingBreak')
enddef

def AllBreaks(buf: number): list<dict<any>>
  var out: list<dict<any>> = []
  for lnum in range(1, len(getbufline(buf, 1, '$')))
    extend(out, Breaks(buf, lnum))
  endfor
  return out
enddef

def CursorProps(buf: number): list<list<number>>
  var out: list<list<number>> = []
  for lnum in range(1, len(getbufline(buf, 1, '$')))
    for p in Props(buf, lnum)
      if p.type == TYPE_CURSOR || p.type == TYPE_BREAK_CURSOR
        add(out, [lnum, p.col, p.type == TYPE_BREAK_CURSOR ? 1 : 0])
      endif
    endfor
  endfor
  return out
enddef

def PendingOn(buf: number, lnum: number): list<list<number>>
  return PropsOf(buf, lnum, TYPE_PENDING)
enddef

# Give a key to the engine and render its event.
def Type(buf: number, st: dict<any>, key: string): dict<any>
  var ev = engine.Feed(st, key)
  render.Apply(buf, st, ev)
  return ev
enddef

def TypeAll(buf: number, st: dict<any>, keys: list<string>)
  for k in keys
    Type(buf, st, k)
  endfor
enddef

def NewSession(lines: list<string>, opts: dict<any> = {}): dict<any>
  var buf = NewBuf(lines)
  var st = engine.Build(getline(1, '$'), opts)
  render.Setup(buf, st)
  return {buf: buf, st: st}
enddef

def PropKeys(buf: number): list<string>
  var out: list<string> = []
  for lnum in range(1, len(getbufline(buf, 1, '$')))
    for p in Props(buf, lnum)
      add(out, printf('%d|%d|%d|%s|%s', lnum, p.col, get(p, 'length', 0),
        p.type, get(p, 'text', '-')))
    endfor
  endfor
  sort(out)
  return out
enddef

# 1. Initial props -----------------------------------------------------------

def Test_initial_pending_props()
  var buf = NewBuf(['abc', '  de', '', 'xy'])
  var st = engine.Build(getline(1, '$'))
  render.Setup(buf, st)

  assert_equal([[1, 3]], PendingOn(buf, 1))
  assert_equal([[3, 2]], PendingOn(buf, 2))
  assert_equal([], Props(buf, 3))
  assert_equal([[1, 2]], PendingOn(buf, 4))
  # Exactly one cursor property, on the first target.
  assert_equal([[1, 1, 0]], CursorProps(buf))
enddef

def Test_initial_multibyte_byte_columns()
  var buf = NewBuf(["\u00e9\u4e2dx"])
  var st = engine.Build(getline(1, '$'))
  render.Setup(buf, st)
  # Two-byte and three-byte characters: one pending region of 6 bytes, not 3.
  assert_equal([[1, 6]], PendingOn(buf, 1))
  assert_equal([[1, 1, 0]], CursorProps(buf))

  Type(buf, st, "\u00e9")
  assert_equal([[3, 4]], PendingOn(buf, 1))
  assert_equal([[1, 3, 0]], CursorProps(buf))
  Type(buf, st, "\u4e2d")
  assert_equal([[6, 1]], PendingOn(buf, 1))
  assert_equal([[1, 6, 0]], CursorProps(buf))
enddef

def Test_initial_indented_line_columns()
  var buf = NewBuf(["  abc", "\tab"])
  var st = engine.Build(getline(1, '$'))
  render.Setup(buf, st)
  # Leading whitespace is skipped, so dimming starts on the first character.
  assert_equal([[3, 3]], PendingOn(buf, 1))
  assert_equal([[2, 2]], PendingOn(buf, 2))
  assert_equal([[1, 3, 0]], CursorProps(buf))
enddef

# 2. Pending boundary --------------------------------------------------------

def Test_pending_boundary_follows_each_key()
  var s = NewSession(['abc'])
  var buf = s.buf
  var st = s.st
  Type(buf, st, 'a')
  assert_equal([[2, 2]], PendingOn(buf, 1))
  Type(buf, st, 'b')
  assert_equal([[3, 1]], PendingOn(buf, 1))
  Type(buf, st, 'c')
  assert_true(st.done)
  assert_equal([], PendingOn(buf, 1), 'no pending after the line is typed')
  assert_equal([], CursorProps(buf), 'no cursor when done')
enddef

def Test_pending_boundary_multi_line()
  var s = NewSession(['ab', 'cd'])
  var buf = s.buf
  var st = s.st
  assert_equal([[1, 2]], PendingOn(buf, 1))
  assert_equal([[1, 2]], PendingOn(buf, 2))
  TypeAll(buf, st, ['a', 'b', ' '])
  assert_equal([], PendingOn(buf, 1), 'line 1 fully typed')
  assert_equal([[1, 2]], PendingOn(buf, 2), 'line 2 still pending')
  assert_equal([[2, 1, 0]], CursorProps(buf))
enddef

# 3. stay mode --------------------------------------------------------------

def Test_stay_wrong_then_fixed()
  var s = NewSession(['ab'])
  var buf = s.buf
  var st = s.st
  var ev = Type(buf, st, 'x')
  assert_equal('wrong', ev.kind)
  assert_equal([[1, 1]], PropsOf(buf, 1, TYPE_WRONG))
  assert_equal([[1, 2]], PendingOn(buf, 1), 'pending unchanged')
  assert_equal([[1, 1, 0]], CursorProps(buf), 'cursor unchanged')

  Type(buf, st, 'a')
  assert_equal([], PropsOf(buf, 1, TYPE_WRONG), 'wrong prop replaced')
  assert_equal([[1, 1]], PropsOf(buf, 1, TYPE_FIXED))
  assert_equal([[2, 1]], PendingOn(buf, 1))
  assert_equal([[1, 2, 0]], CursorProps(buf))
enddef

# 4. advance mode -----------------------------------------------------------

def Test_advance_wrong_and_backspace()
  var s = NewSession(['ab', 'cd'], {on_error: 'advance'})
  var buf = s.buf
  var st = s.st
  Type(buf, st, 'x')
  assert_equal(1, st.pos)
  assert_equal([[1, 1]], PropsOf(buf, 1, TYPE_WRONG))
  assert_equal([[2, 1]], PendingOn(buf, 1))
  assert_equal([[1, 2, 0]], CursorProps(buf))
  assert_equal([[1, 2]], PendingOn(buf, 2), 'line 2 untouched')

  Type(buf, st, "\<BS>")
  assert_equal(0, st.pos)
  assert_equal([], PropsOf(buf, 1, TYPE_WRONG), 'wrong prop removed')
  assert_equal([[1, 2]], PendingOn(buf, 1), 'pending restored over target')
  assert_equal([[1, 1, 0]], CursorProps(buf))
enddef

def Test_advance_backspace_across_line_break()
  var s = NewSession(['ab', 'cd'], {on_error: 'advance'})
  var buf = s.buf
  var st = s.st
  TypeAll(buf, st, ['a', 'b', ' '])
  assert_equal(3, st.pos, 'current target is c on line 2')
  assert_equal([], PendingOn(buf, 1))
  assert_equal([[1, 2]], PendingOn(buf, 2))
  assert_equal([[2, 1, 0]], CursorProps(buf))
  assert_equal([TYPE_BREAK_CORRECT], mapnew(Breaks(buf, 1), (_, p) => p.type))

  Type(buf, st, "\<BS>")
  assert_equal(2, st.pos, 'the break is the current target again')
  assert_equal([[1, 2]], PendingOn(buf, 2), 'line 2 pending not lost')
  assert_equal([[1, 3, 1]], CursorProps(buf), 'cursor is the break marker')
  assert_equal([TYPE_BREAK_CURSOR], mapnew(Breaks(buf, 1), (_, p) => p.type))
  assert_equal(1, len(Breaks(buf, 1)), 'one marker on the line')

  Type(buf, st, ' ')
  assert_equal(3, st.pos)
  assert_equal([TYPE_BREAK_CORRECT], mapnew(Breaks(buf, 1), (_, p) => p.type))
  assert_equal([[2, 1, 0]], CursorProps(buf))
  assert_equal([[1, 2]], PendingOn(buf, 2))
enddef

# 5. Break markers ----------------------------------------------------------

def Test_break_marker_at_end_of_line()
  # The break is at len(line) + 1: past the last byte, no trailing whitespace.
  var s = NewSession(['a', 'b'])
  var buf = s.buf
  var st = s.st
  var b = Breaks(buf, 1)
  assert_equal(1, len(b), 'exactly one break marker')
  assert_equal(2, b[0].col, 'marker at len(line) + 1')
  assert_equal(TYPE_BREAK_PENDING, b[0].type)
  assert_equal("\u21b5", get(b[0], 'text', ''), 'inline virtual text is the marker')

  Type(buf, st, 'a')
  b = Breaks(buf, 1)
  assert_equal(1, len(b))
  assert_equal(TYPE_BREAK_CURSOR, b[0].type, 'current break is the cursor')
  assert_equal([[1, 2, 1]], CursorProps(buf))
enddef

def Test_break_marker_types()
  var s = NewSession(['a', 'b'], {on_error: 'advance'})
  var buf = s.buf
  var st = s.st
  assert_equal([TYPE_BREAK_PENDING], mapnew(Breaks(buf, 1), (_, p) => p.type))

  Type(buf, st, 'a')
  assert_equal([TYPE_BREAK_CURSOR], mapnew(Breaks(buf, 1), (_, p) => p.type))

  Type(buf, st, 'x')
  assert_equal([TYPE_BREAK_WRONG], mapnew(Breaks(buf, 1), (_, p) => p.type),
    'wrong break red once the cursor has moved on')
  assert_equal(1, len(Breaks(buf, 1)))
  assert_equal([[2, 1, 0]], CursorProps(buf))

  Type(buf, st, "\<BS>")
  assert_equal([TYPE_BREAK_CURSOR], mapnew(Breaks(buf, 1), (_, p) => p.type))

  Type(buf, st, ' ')
  assert_equal([TYPE_BREAK_FIXED], mapnew(Breaks(buf, 1), (_, p) => p.type),
    'corrected break is fixed')
  Type(buf, st, 'b')
  assert_equal([TYPE_BREAK_FIXED], mapnew(Breaks(buf, 1), (_, p) => p.type))
  assert_equal([], CursorProps(buf))
enddef

def Test_break_marker_with_trailing_whitespace()
  var s = NewSession(['ab   ', 'c'])
  var buf = s.buf
  var st = s.st
  var b = Breaks(buf, 1)
  assert_equal(1, len(b))
  assert_equal(3, b[0].col, 'just after the last non-blank character')
  # At the start the dim region covers the whole line (including the trailing
  # blanks); once both characters are typed it starts at the break column.
  assert_equal([[1, 5]], PendingOn(buf, 1))
  assert_equal([[1, 1]], PendingOn(buf, 2))
  TypeAll(buf, st, ['a', 'b'])
  assert_equal([[3, 3]], PendingOn(buf, 1),
    'trailing whitespace after the marker stays dimmed')
  assert_equal(2, len(Props(buf, 1)), 'pending and the break marker cursor')

  # Typing the break leaves the marker (dim, not the cursor) and no pending.
  Type(buf, st, ' ')
  assert_equal([TYPE_BREAK_CORRECT], mapnew(Breaks(buf, 1), (_, p) => p.type))
  assert_equal([], PendingOn(buf, 1))
enddef

def Test_one_break_marker_per_break_target()
  var lines = ['ab', '', 'cd', 'ef']
  var s = NewSession(lines)
  var buf = s.buf
  var st = s.st
  var breaks: list<dict<any>> = []
  for i in range(0, len(st.targets) - 1)
    if st.targets[i].kind == 'break'
      add(breaks, st.targets[i])
    endif
  endfor
  assert_equal(2, len(breaks))
  for t in breaks
    var b = Breaks(buf, t.lnum)
    assert_equal(1, len(b), printf('line %d', t.lnum))
    assert_equal(t.col, b[0].col, printf('line %d', t.lnum))
  endfor
  assert_equal(2, len(AllBreaks(buf)))
enddef

# 6. Cursor -----------------------------------------------------------------

def Test_one_cursor_on_current_target()
  var s = NewSession(['abc', 'de'], {on_error: 'advance'})
  var buf = s.buf
  var st = s.st
  assert_equal([[1, 1, 0]], CursorProps(buf))
  TypeAll(buf, st, ['x', 'y'])
  assert_equal([[1, 3, 0]], CursorProps(buf), 'old cursor removed')
  Type(buf, st, 'z')
  assert_equal(3, st.pos)
  assert_equal([[1, 4, 1]], CursorProps(buf), 'break marker is the cursor')
  assert_equal(1, len(AllBreaks(buf)), 'no duplicate marker')
  TypeAll(buf, st, [' ', 'd', 'e'])
  assert_true(st.done)
  assert_equal([], CursorProps(buf), 'no cursor when done')
  assert_equal([], PendingOn(buf, 2), 'no pending when done')
enddef

# 7. Buffer text untouched --------------------------------------------------

def Test_text_and_modified_unchanged()
  var lines = ['  ab', '', "c\td  ", "\u00e9x"]
  var buf = NewBuf(lines)
  var copy = getline(1, '$')
  var st = engine.Build(copy)
  render.Setup(buf, st)
  var keys: list<string> = []
  for t in st.targets
    add(keys, t.kind == 'break' ? ' ' : t.char)
  endfor
  TypeAll(buf, st, keys)
  assert_true(st.done)
  assert_equal(copy, getline(1, '$'), 'buffer text unchanged')
  assert_false(&modified, 'buffer not modified')
enddef

# 8. Setup twice, Teardown --------------------------------------------------

def Test_setup_twice_matches_fresh_setup()
  var lines = ['ab', 'cd']
  var b1 = NewBuf(lines)
  var st1 = engine.Build(getline(1, '$'))
  render.Setup(b1, st1)
  TypeAll(b1, st1, ['a', 'x', 'b'])
  assert_equal('fixed', st1.targets[1].state)

  # Restart on the same buffer with a fresh state.
  var st2 = engine.Build(getline(1, '$'))
  render.Setup(b1, st2)
  var keys1 = PropKeys(b1)

  var b2 = NewBuf(lines)
  var st3 = engine.Build(getline(1, '$'))
  render.Setup(b2, st3)
  var keys2 = PropKeys(b2)

  assert_equal(keys2, keys1, 'restart equals a fresh setup')
  assert_equal([], filter(keys1, (_, k) => k =~# 'TypingFixed'))
enddef

def Test_teardown_removes_props_and_types()
  var s = NewSession(['ab', 'cd'])
  var buf = s.buf
  render.Teardown(buf)
  for lnum in range(1, 2)
    assert_equal([], Props(buf, lnum), printf('line %d', lnum))
  endfor
  for name in ALL_TYPES
    assert_equal({}, prop_type_get(name, {bufnr: buf}), name)
  endfor

  var ok = true
  try
    render.Teardown(buf)
  catch
    ok = false
  endtry
  assert_true(ok, 'second Teardown is safe')
enddef

def Test_teardown_after_bwipeout()
  var s = NewSession(['ab'])
  var buf = s.buf
  execute 'bwipeout! ' .. buf
  assert_false(bufexists(buf))
  var ok = true
  try
    render.Teardown(buf)
  catch
    ok = false
  endtry
  assert_true(ok, 'Teardown after bwipeout! is safe')
  render.Teardown(buf)
enddef

# 9. CursorPos --------------------------------------------------------------

def Test_cursor_pos()
  var s0 = NewSession(['ab', 'cd'])
  assert_equal([1, 1], render.CursorPos(s0.st))
  Type(s0.buf, s0.st, 'a')
  assert_equal([1, 2], render.CursorPos(s0.st))
  var s = NewSession(['ab', 'cd'])
  var buf = s.buf
  var st2 = s.st
  TypeAll(buf, st2, ['a', 'b', ' ', 'c', 'd'])
  assert_true(st2.done)
  assert_equal([2, 2], render.CursorPos(st2), 'last target when done')

  var empty = engine.Build(['', '   '])
  assert_equal([1, 1], render.CursorPos(empty), 'no targets')
enddef

# 10. Terminal cursor -------------------------------------------------------

def Test_terminal_cursor_hide_restore()
  var orig = &t_ve
  try
    &t_ve = 'TESTVE'
    render.HideTerminalCursor()
    assert_equal('', &t_ve, 'hidden')
    # A second Hide must not save the now-empty value.
    &t_ve = ''
    render.HideTerminalCursor()
    assert_equal('', &t_ve)
    render.RestoreTerminalCursor()
    assert_equal('TESTVE', &t_ve, 'saved value not overwritten by second Hide')
    render.RestoreTerminalCursor()
    assert_equal('TESTVE', &t_ve, 'second Restore is a no-op')
  finally
    &t_ve = orig
  endtry
enddef

def Test_teardown_restores_terminal_cursor()
  var orig = &t_ve
  var s = NewSession(['a'])
  try
    &t_ve = 'TEARDOWNVE'
    render.HideTerminalCursor()
    assert_equal('', &t_ve)
    render.Teardown(s.buf)
    assert_equal('TEARDOWNVE', &t_ve, 'Teardown restores t_ve')
  finally
    &t_ve = orig
  endtry
enddef

# 11. Blink -----------------------------------------------------------------

def BlinkOn(): bool
  return execute('highlight TypingCursorBlink') =~# 'links to TypingCursor'
enddef

def Test_blink_flips_and_stops()
  var before = execute('highlight TypingCursor')
  render.StartBlink(20)
  sleep 120m
  var seen_on = false
  var seen_off = false
  for _ in range(1, 60)
    sleep 5m
    if BlinkOn()
      seen_on = true
    else
      seen_off = true
    endif
    if seen_on && seen_off
      break
    endif
  endfor
  assert_true(seen_on, 'blink "on" phase seen')
  assert_true(seen_off, 'blink "off" phase seen')

  render.StopBlink()
  assert_true(BlinkOn(), 'StopBlink leaves the linked form')
  sleep 80m
  assert_true(BlinkOn(), 'still linked after StopBlink')

  # Pulse forces the linked form even if the timer was in the off phase.
  render.StartBlink(20)
  var saw_off = false
  for _ in range(1, 60)
    sleep 5m
    if !BlinkOn()
      saw_off = true
      break
    endif
  endfor
  assert_true(saw_off, 'timer reached its off phase')
  render.Pulse()
  assert_true(BlinkOn(), 'Pulse forces the linked form')
  render.StopBlink()
  assert_true(BlinkOn())

  render.StartBlink(0)
  assert_true(BlinkOn())
  for _ in range(1, 20)
    sleep 10m
    assert_true(BlinkOn(), 'StartBlink(0) never flips')
  endfor
  render.StopBlink()

  assert_equal(before, execute('highlight TypingCursor'),
    'the user-facing TypingCursor group is untouched')
enddef

# 12. Screen check ----------------------------------------------------------

def ScreenCell(lnum: number, col: number): dict<any>
  var pos = screenpos(win_getid(), lnum, col)
  if pos.row == 0
    return {attr: -99, text: '', row: 0, col: 0}
  endif
  return {attr: screenattr(pos.row, pos.col),
    text: screenstring(pos.row, pos.col), row: pos.row, col: pos.col}
enddef

def Test_screen_cursor_off_phase()
  var s = NewSession(['abcd'])
  var buf = s.buf
  var st = s.st
  Type(buf, st, 'a')  # typed: col 1, cursor: col 2, pending: col 3
  winrestview({lnum: 1, col: 0, topline: 1})
  redraw
  var typed = ScreenCell(1, 1)
  var cursor = ScreenCell(1, 2)
  var pending = ScreenCell(1, 3)
  assert_notequal(-99, cursor.attr, 'line is on screen')
  assert_notequal(cursor.attr, pending.attr, 'cursor differs from pending')
  assert_notequal(cursor.attr, typed.attr, 'cursor differs from typed')

  # Watch the blink until the cursor cell matches the pending cell.
  render.StartBlink(20)
  var saw_on = false
  var saw_off = false
  var off_attr = -1
  var off_pending = -1
  for _ in range(1, 100)
    sleep 5m
    redraw
    var a = screenattr(cursor.row, cursor.col)
    var b = screenattr(pending.row, pending.col)
    if a == b
      saw_off = true
      off_attr = a
      off_pending = b
      break
    else
      saw_on = true
    endif
  endfor
  assert_true(saw_on, 'saw the cursor "on" phase')
  assert_true(saw_off, 'saw the cursor "off" phase')
  if saw_off
    assert_equal(off_pending, off_attr,
      'off phase shows the pending colour through')
  endif
  render.StopBlink()
enddef

def Test_screen_wrong_and_marker()
  var s = NewSession(['abc', 'de'], {on_error: 'advance'})
  var buf = s.buf
  var st = s.st
  Type(buf, st, 'x')  # wrong on col 1, cursor col 2
  Type(buf, st, 'b')  # correct on col 2, cursor col 3
  winrestview({lnum: 1, col: 0, topline: 1})
  redraw
  var wrong = ScreenCell(1, 1)
  var typed = ScreenCell(1, 2)
  var cursor = ScreenCell(1, 3)
  assert_notequal(-99, wrong.attr, 'line is on screen')
  assert_notequal(wrong.attr, typed.attr, 'wrong differs from typed')
  assert_notequal(cursor.attr, typed.attr, 'cursor differs from typed')

  # The line-end marker of line 1 must be visible on screen, one cell after the
  # last character (the break column is len + 1).
  var row = ScreenCell(1, 1).row
  assert_equal('c', screenstring(cursor.row, cursor.col),
    'the marker does not overwrite the last character')
  assert_equal("\u21b5", screenstring(cursor.row, cursor.col + 1),
    'marker sits at its break column')
  var count = 0
  var marker_col = 0
  for c in range(1, &columns)
    if screenstring(row, c) == "\u21b5"
      count += 1
      marker_col = c
    endif
  endfor
  assert_equal(1, count, 'exactly one marker on the line')
  assert_notequal(0, marker_col)
enddef

def Test_setup_at_mid_position()
  var st = engine.Build(['ab', 'cd'])
  engine.Feed(st, 'a')
  engine.Feed(st, 'b')
  engine.Feed(st, ' ')
  assert_equal(3, st.pos)
  var buf = NewBuf(['ab', 'cd'])
  render.Setup(buf, st)
  assert_equal([], PendingOn(buf, 1), 'typed line has no dim region')
  assert_equal([[1, 2]], PendingOn(buf, 2))
  assert_equal([[2, 1, 0]], CursorProps(buf))
  assert_equal([TYPE_BREAK_CORRECT], mapnew(Breaks(buf, 1), (_, p) => p.type))
  assert_equal([], Breaks(buf, 2), 'the last line has no break')
enddef

def Test_ignored_event_keeps_props_stable()
  var s = NewSession(['a', 'b'])
  var buf = s.buf
  var st = s.st
  var before = PropKeys(buf)
  var ev = engine.Feed(st, "\<Up>")
  assert_equal('ignored', ev.kind)
  render.Apply(buf, st, ev)
  assert_equal(before, PropKeys(buf), 'ignored event changes nothing')
  assert_equal(1, len(CursorProps(buf)), 'still exactly one cursor')
  assert_equal(1, len(AllBreaks(buf)), 'still exactly one marker')
enddef

def Test_setup_with_break_current_and_done()
  # Setup at a break: the marker is the cursor, no other cursor prop.
  var st = engine.Build(['ab', 'cd'])
  engine.Feed(st, 'a')
  engine.Feed(st, 'b')
  assert_equal(2, st.pos)
  var buf = NewBuf(['ab', 'cd'])
  render.Setup(buf, st)
  assert_equal([TYPE_BREAK_CURSOR], mapnew(Breaks(buf, 1), (_, p) => p.type))
  assert_equal([[1, 3, 1]], CursorProps(buf))
  assert_equal([], PendingOn(buf, 1))

  # Setup on a finished state: no cursor and no pending anywhere.
  var done = engine.Build(['ab', 'cd'])
  for k in ['a', 'b', ' ', 'c', 'd']
    engine.Feed(done, k)
  endfor
  assert_true(done.done)
  var buf2 = NewBuf(['ab', 'cd'])
  render.Setup(buf2, done)
  assert_equal([], CursorProps(buf2))
  for lnum in range(1, 2)
    assert_equal([], PendingOn(buf2, lnum), printf('line %d', lnum))
  endfor
  assert_equal([TYPE_BREAK_CORRECT], mapnew(Breaks(buf2, 1), (_, p) => p.type))
enddef

# Contracts checked after every key of a longer session.
def CheckRender(buf: number, st: dict<any>, label: string)
  var targets = st.targets
  var pos = st.pos
  var done = get(st, 'done', false)
  var lines = getbufline(buf, 1, '$')
  var n = len(lines)

  var cursors: list<list<number>> = []
  for lnum in range(1, n)
    for p in Props(buf, lnum)
      if p.type == TYPE_CURSOR
        add(cursors, [lnum, p.col, 0])
      elseif p.type == TYPE_BREAK_CURSOR
        add(cursors, [lnum, p.col, 1])
      endif
    endfor
  endfor
  if done || empty(targets)
    assert_equal([], cursors, label .. ': no cursor when done')
  else
    var ct = targets[pos]
    assert_equal([[ct.lnum, ct.col, ct.kind == 'break' ? 1 : 0]], cursors,
      label .. ': exactly one cursor on the current target')
  endif

  for i in range(0, len(targets) - 1)
    var t = targets[i]
    if t.kind == 'break'
      var want = TYPE_BREAK_PENDING
      if i == pos && !done
        want = TYPE_BREAK_CURSOR
      elseif t.state == 'wrong'
        want = TYPE_BREAK_WRONG
      elseif t.state == 'fixed'
        want = TYPE_BREAK_FIXED
      elseif t.state == 'correct'
        want = TYPE_BREAK_CORRECT
      endif
      assert_equal([[t.col, want]],
        mapnew(Breaks(buf, t.lnum), (_, p) => [p.col, p.type]),
        printf('%s: break %d', label, i))
    else
      var got = mapnew(
        filter(Props(buf, t.lnum), (_, p) => get(p, 'id', 0) == i + 1),
        (_, p) => [p.col, get(p, 'length', -1), p.type])
      var wantst = ''
      if t.state == 'wrong'
        wantst = TYPE_WRONG
      elseif t.state == 'fixed'
        wantst = TYPE_FIXED
      endif
      if wantst == ''
        assert_equal([], got, printf('%s: char %d carries no prop', label, i))
      else
        assert_equal([[t.col, t.len, wantst]], got,
          printf('%s: char %d', label, i))
      endif
    endif
  endfor

  var first: dict<number> = {}
  if !done && !empty(targets)
    for i in range(pos, len(targets) - 1)
      var k = string(targets[i].lnum)
      if !has_key(first, k)
        first[k] = targets[i].col
      endif
    endfor
  endif
  for lnum in range(1, n)
    var exp: list<list<number>> = []
    var k = string(lnum)
    if has_key(first, k)
      var linelen = len(lines[lnum - 1])
      if first[k] <= linelen
        add(exp, [first[k], linelen - first[k] + 1])
      endif
    endif
    assert_equal(exp, PendingOn(buf, lnum),
      printf('%s: pending region line %d', label, lnum))
  endfor
enddef

def Test_advance_backspace_off_break_keeps_marker()
  var s = NewSession(['ab', 'cd'], {on_error: 'advance'})
  var buf = s.buf
  var st = s.st
  TypeAll(buf, st, ['a', 'b'])
  assert_equal(2, st.pos)
  assert_equal([TYPE_BREAK_CURSOR], mapnew(Breaks(buf, 1), (_, p) => p.type))

  # Backspace moves from the break to the character before it, on the same
  # line.  The engine reports only that character as changed; the marker must
  # still be restored to its pending style.
  Type(buf, st, "\<BS>")
  assert_equal(1, st.pos)
  assert_equal(1, len(Breaks(buf, 1)), 'marker not lost')
  assert_equal([TYPE_BREAK_PENDING], mapnew(Breaks(buf, 1), (_, p) => p.type))
  assert_equal([[2, 1]], PendingOn(buf, 1))
  assert_equal([[1, 2, 0]], CursorProps(buf))
enddef

def Test_long_session_invariants()
  var cases = [
    ['  ab', '', "c\u00e9d  ", 'ef'],
    ["\tab\t", 'x  ', "\u4e2d y", ''],
    ['a', 'b', 'c'],
  ]
  for lines in cases
    for mode in ['stay', 'advance']
      var buf = NewBuf(lines)
      var st = engine.Build(getline(1, '$'), {on_error: mode})
      render.Setup(buf, st)
      CheckRender(buf, st, mode .. ' setup')
      for step in range(1, 300)
        var key = 'z'
        if !st.done && !empty(st.targets)
          var t = st.targets[st.pos]
          var m = step % 8
          if m == 0 || m == 1 || m == 5
            key = t.kind == 'break' ? ' ' : t.char
          elseif m == 2
            key = "\<BS>"
          elseif m == 3
            key = "\<Up>"
          elseif m == 4
            key = index(t.accept, 'x') >= 0 ? 'q' : 'x'
          elseif m == 6
            key = "\r"
          endif
        endif
        var ev = engine.Feed(st, key)
        render.Apply(buf, st, ev)
        CheckRender(buf, st, printf('%s step %d key %s', mode, step,
          strtrans(key)))
      endfor
      assert_true(st.done, mode .. ': session reached the end')
      assert_equal(lines, getline(1, '$'), mode .. ': text unchanged')
      assert_false(&modified, mode .. ': buffer not modified')
    endfor
  endfor
enddef

# Run -----------------------------------------------------------------------

Test_initial_pending_props()
Test_initial_multibyte_byte_columns()
Test_initial_indented_line_columns()
Test_pending_boundary_follows_each_key()
Test_pending_boundary_multi_line()
Test_stay_wrong_then_fixed()
Test_advance_wrong_and_backspace()
Test_advance_backspace_across_line_break()
Test_break_marker_at_end_of_line()
Test_break_marker_types()
Test_break_marker_with_trailing_whitespace()
Test_one_break_marker_per_break_target()
Test_one_cursor_on_current_target()
Test_text_and_modified_unchanged()
Test_setup_twice_matches_fresh_setup()
Test_teardown_removes_props_and_types()
Test_teardown_after_bwipeout()
Test_cursor_pos()
Test_terminal_cursor_hide_restore()
Test_teardown_restores_terminal_cursor()
Test_blink_flips_and_stops()
Test_screen_cursor_off_phase()
Test_screen_wrong_and_marker()
Test_setup_at_mid_position()
Test_ignored_event_keeps_props_stable()
Test_setup_with_break_current_and_done()
Test_advance_backspace_off_break_keeps_marker()
Test_long_session_invariants()

def Test_resume_setup()
  var b = NewBuf(['ab', 'cde'])
  var st = engine.Build(['ab', 'cde'])
  engine.StartAt(st, 4)
  render.Setup(b, st)
  assert_equal([], PendingOn(b, 1))
  assert_equal('TypingBreakCorrect', Breaks(b, 1)[0].type)
  assert_equal([[2, 2]], PendingOn(b, 2))
  assert_equal([], filter(Props(b, 2), (_, p) => p.col < 2))
  Type(b, st, 'd')
  assert_equal([[3, 1]], PendingOn(b, 2))
  assert_equal(1, st.standing)
  render.Teardown(b)
  execute 'bwipeout! ' .. b
enddef

Test_resume_setup()
