vim9script
# Rendering for a typing session: dimming, wrong/fixed colours, the line-end
# marker, the blinking cursor property and the terminal cursor.
# It never changes buffer text and touches only its own text properties.
# See PLAN.md section 5.1 for the contract.

# Buffer-local text property type names.  The first four style characters; the
# break ones carry the inline virtual text shown at a line end.
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
const BREAK_TYPES = [TYPE_BREAK_PENDING, TYPE_BREAK_CORRECT, TYPE_BREAK_FIXED,
  TYPE_BREAK_WRONG, TYPE_BREAK_CURSOR]
const CURSOR_TYPES = [TYPE_CURSOR, TYPE_BREAK_CURSOR]

const BREAK_TEXT = "\u21b5"

# The internal group used by cursor properties.  "On" links it to the
# user-facing TypingCursor group; "off" removes the link so whatever property
# sits underneath (a dim pending region, a wrong or fixed character) shows.
highlight default link TypingCursorBlink TypingCursor

# Per-buffer memory of the previous position, used to limit the pending props
# Apply reworks to the lines it moved between.
var states: dict<dict<any>> = {}

var blink_timer: number = -1
var blink_on: bool = true
var blink_ms: number = 0

var ve_saved: string = ''
var ve_hidden: bool = false

def EnsureCursorOn()
  highlight! link TypingCursorBlink TypingCursor
enddef

def CursorOff()
  highlight! link TypingCursorBlink NONE
enddef

def AddTypes(buf: number)
  prop_type_add(TYPE_PENDING, {bufnr: buf, highlight: 'TypingPending',
    priority: 10})
  prop_type_add(TYPE_FIXED, {bufnr: buf, highlight: 'TypingFixed',
    priority: 20})
  prop_type_add(TYPE_WRONG, {bufnr: buf, highlight: 'TypingWrong',
    priority: 30})
  prop_type_add(TYPE_CURSOR, {bufnr: buf, highlight: 'TypingCursorBlink',
    priority: 40})
  prop_type_add(TYPE_BREAK_PENDING, {bufnr: buf, highlight: 'TypingPending',
    priority: 10})
  prop_type_add(TYPE_BREAK_CORRECT, {bufnr: buf, highlight: 'TypingPending',
    priority: 10})
  prop_type_add(TYPE_BREAK_FIXED, {bufnr: buf, highlight: 'TypingFixed',
    priority: 20})
  prop_type_add(TYPE_BREAK_WRONG, {bufnr: buf, highlight: 'TypingWrong',
    priority: 30})
  prop_type_add(TYPE_BREAK_CURSOR, {bufnr: buf,
    highlight: 'TypingCursorBlink', priority: 40})
enddef

def ExistingTypes(buf: number): list<string>
  var names: list<string> = []
  for name in ALL_TYPES
    if !empty(prop_type_get(name, {bufnr: buf}))
      add(names, name)
    endif
  endfor
  return names
enddef

def ClearProps(buf: number)
  var names = ExistingTypes(buf)
  if !empty(names)
    prop_remove({types: names, all: true, bufnr: buf})
  endif
enddef

def DeleteTypes(buf: number)
  for name in ALL_TYPES
    prop_type_delete(name, {bufnr: buf})
  endfor
enddef

def BreakType(state: string): string
  if state == 'wrong'
    return TYPE_BREAK_WRONG
  elseif state == 'fixed'
    return TYPE_BREAK_FIXED
  elseif state == 'correct'
    return TYPE_BREAK_CORRECT
  endif
  return TYPE_BREAK_PENDING
enddef

# One break marker per line.  Virtual text has no length and carries its own
# prop type, so each style needs its own type.
def AddBreakMarker(buf: number, t: dict<any>, type: string)
  prop_remove({types: BREAK_TYPES, all: true, bufnr: buf}, t.lnum)
  prop_add(t.lnum, t.col, {type: type, bufnr: buf, text: BREAK_TEXT})
enddef

def AddCharStyle(buf: number, i: number, t: dict<any>, type: string)
  prop_add(t.lnum, t.col, {type: type, bufnr: buf, length: t.len,
    id: i + 1})
enddef

def RemoveCharStyle(buf: number, i: number, t: dict<any>)
  prop_remove({id: i + 1, all: true, bufnr: buf}, t.lnum)
enddef

def RemoveCursor(buf: number, lnum: number)
  prop_remove({types: CURSOR_TYPES, all: true, bufnr: buf}, lnum)
enddef

# The first target on lnum whose index is at or after st.pos, or {}.
def FirstPending(st: dict<any>, lnum: number): dict<any>
  var targets = st.targets
  var pos = get(st, 'pos', 0)
  if empty(targets) || pos < 0 || pos >= len(targets)
    return {}
  endif
  for i in range(pos, len(targets) - 1)
    var t = targets[i]
    if t.lnum == lnum
      return t
    elseif t.lnum > lnum
      break
    endif
  endfor
  return {}
enddef

# Replace the one pending property of a line with the dim region from the
# first untyped target (inclusive) to the end of the line.  A break has no
# bytes of its own, but trailing whitespace after it is still dimmed.
def ReworkLine(buf: number, st: dict<any>, lnum: number,
    known: dict<any> = {})
  prop_remove({types: [TYPE_PENDING], all: true, bufnr: buf}, lnum)
  var t = empty(known) ? FirstPending(st, lnum) : known
  if empty(t)
    return
  endif
  var lines = getbufline(buf, lnum)
  if empty(lines)
    return
  endif
  var linelen = len(lines[0])
  if t.col > linelen
    return
  endif
  var length = linelen - t.col + 1
  if length > 0
    prop_add(lnum, t.col, {type: TYPE_PENDING, bufnr: buf, length: length})
  endif
enddef

def AddCursor(buf: number, t: dict<any>)
  RemoveCursor(buf, t.lnum)
  if t.kind == 'break'
    AddBreakMarker(buf, t, TYPE_BREAK_CURSOR)
  else
    prop_add(t.lnum, t.col, {type: TYPE_CURSOR, bufnr: buf, length: t.len})
  endif
enddef

export def Setup(buf: number, st: dict<any>)
  var targets = get(st, 'targets', [])
  var pos = get(st, 'pos', 0)
  var done = get(st, 'done', false)

  ClearProps(buf)
  DeleteTypes(buf)
  AddTypes(buf)
  EnsureCursorOn()

  if !empty(targets)
    for i in range(0, len(targets) - 1)
      var t = targets[i]
      if t.kind == 'break'
        var style = done || i != pos ? BreakType(t.state) : TYPE_BREAK_CURSOR
        AddBreakMarker(buf, t, style)
      elseif t.state == 'wrong'
        AddCharStyle(buf, i, t, TYPE_WRONG)
      elseif t.state == 'fixed'
        AddCharStyle(buf, i, t, TYPE_FIXED)
      endif
    endfor
  endif

  if !empty(targets) && pos >= 0 && pos < len(targets)
    var seen: dict<bool> = {}
    for i in range(pos, len(targets) - 1)
      var t = targets[i]
      var key = string(t.lnum)
      if has_key(seen, key)
        continue
      endif
      seen[key] = true
      ReworkLine(buf, st, t.lnum, t)
    endfor
  endif

  if !done && !empty(targets) && pos >= 0 && pos < len(targets)
    AddCursor(buf, targets[pos])
  endif

  states[string(buf)] = {pos: pos}
enddef

export def Apply(buf: number, st: dict<any>, ev: dict<any>)
  var targets = get(st, 'targets', [])
  var pos = get(st, 'pos', 0)
  var key = string(buf)
  var oldpos = has_key(states, key) ? states[key].pos : pos

  # Restyle only the targets the engine reported as changed.
  for ci in get(ev, 'changed', [])
    if ci < 0 || ci >= len(targets)
      continue
    endif
    var t = targets[ci]
    if t.kind == 'break'
      var style = !get(st, 'done', false) && ci == pos
        ? TYPE_BREAK_CURSOR
        : BreakType(t.state)
      AddBreakMarker(buf, t, style)
    else
      RemoveCharStyle(buf, ci, t)
      if t.state == 'wrong'
        AddCharStyle(buf, ci, t, TYPE_WRONG)
      elseif t.state == 'fixed'
        AddCharStyle(buf, ci, t, TYPE_FIXED)
      endif
    endif
  endfor

  # Rework the pending region only on the lines between the old and the new
  # position (both included).
  var lo = oldpos < pos ? oldpos : pos
  var hi = oldpos < pos ? pos : oldpos
  var reworked: dict<bool> = {}
  for i in range(lo, hi)
    if i < 0 || i >= len(targets)
      continue
    endif
    var lnum = targets[i].lnum
    var lkey = string(lnum)
    if has_key(reworked, lkey)
      continue
    endif
    reworked[lkey] = true
    ReworkLine(buf, st, lnum)
  endfor

  # Move the cursor property/marker. Removing the cursor also removes a break
  # target's marker, so a break that stops being current must get its state
  # style back (Backspace can move off a break without the engine reporting
  # that break as changed).
  if oldpos >= 0 && oldpos < len(targets)
    var ot = targets[oldpos]
    RemoveCursor(buf, ot.lnum)
    if ot.kind == 'break'
      AddBreakMarker(buf, ot,
        !get(st, 'done', false) && oldpos == pos ? TYPE_BREAK_CURSOR
          : BreakType(ot.state))
    endif
  endif
  if !get(st, 'done', false) && pos >= 0 && pos < len(targets)
    AddCursor(buf, targets[pos])
  endif

  states[key] = {pos: pos}
enddef

export def CursorPos(st: dict<any>): list<number>
  var targets = get(st, 'targets', [])
  if empty(targets)
    return [1, 1]
  endif
  var pos = get(st, 'pos', 0)
  if pos < 0
    pos = 0
  elseif pos >= len(targets)
    pos = len(targets) - 1
  endif
  return [targets[pos].lnum, targets[pos].col]
enddef

def BlinkTick(_timer: number)
  blink_on = !blink_on
  if blink_on
    EnsureCursorOn()
  else
    CursorOff()
  endif
  redraw
enddef

export def StartBlink(ms: number)
  if blink_timer != -1
    timer_stop(blink_timer)
    blink_timer = -1
  endif
  blink_on = true
  EnsureCursorOn()
  blink_ms = ms > 0 ? ms : 0
  if blink_ms > 0
    blink_timer = timer_start(blink_ms, BlinkTick, {repeat: -1})
  endif
enddef

export def StopBlink()
  if blink_timer != -1
    timer_stop(blink_timer)
    blink_timer = -1
  endif
  blink_on = true
  EnsureCursorOn()
enddef

export def Pulse()
  blink_on = true
  EnsureCursorOn()
  if blink_timer != -1
    timer_stop(blink_timer)
    blink_timer = timer_start(blink_ms, BlinkTick, {repeat: -1})
  endif
enddef

export def HideTerminalCursor()
  if has('gui_running') || ve_hidden
    return
  endif
  ve_saved = &t_ve
  &t_ve = ''
  ve_hidden = true
enddef

export def RestoreTerminalCursor()
  if !ve_hidden
    return
  endif
  &t_ve = ve_saved
  ve_saved = ''
  ve_hidden = false
enddef

export def Teardown(buf: number)
  StopBlink()
  RestoreTerminalCursor()
  var key = string(buf)
  if has_key(states, key)
    remove(states, key)
  endif
  if !bufexists(buf)
    return
  endif
  try
    ClearProps(buf)
    DeleteTypes(buf)
  catch
    # The buffer disappeared between the check and the cleanup.
  endtry
enddef
