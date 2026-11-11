vim9script
# Popups and text formatting for typing practice: the live status line, the
# wrong-key warning flash and the end-of-session summary. See PLAN.md section
# 5.1 for the contract.
#
# Formatting functions are pure. The popup functions keep a little script-local
# state per popup (latest status text and warning timer) so that a status update
# arriving during a warning is shown when the warning ends.

# popup id -> {text: latest status line, timer: warning timer id or -1,
#              warned: true while the warning text is shown}
var status_state: dict<dict<any>> = {}

# Summary popup id -> true once OnKey has been (or is being) called.
var summary_state: dict<bool> = {}

def AsFloat(v: any): float
  if type(v) == v:t_float
    return v
  elseif type(v) == v:t_number
    return v * 1.0
  endif
  return 0.0
enddef

def AsBool(v: any): bool
  if type(v) == v:t_bool
    return v
  elseif type(v) == v:t_number
    return v != 0
  endif
  return false
enddef

# Round to the nearest integer, accepting a Number or a Float.
def RoundInt(v: any): number
  if type(v) == v:t_float
    return float2nr(round(v))
  elseif type(v) == v:t_number
    return v
  endif
  return 0
enddef

def PopupExists(id: number): bool
  return !empty(popup_getpos(id))
enddef

def StatusState(id: number): dict<any>
  if !has_key(status_state, id)
    status_state[id] = {text: '', timer: -1, warned: false}
  endif
  return status_state[id]
enddef

# Seconds as MM:SS. Minutes keep counting past 59; negative values show 00:00.
export def FormatTime(seconds: float): string
  var total = float2nr(seconds)
  if total < 0
    total = 0
  endif
  return printf('%02d:%02d', total / 60, total % 60)
enddef

# One live status line: time, rounded WPM, accuracy, errors and progress.
export def StatusText(snap: dict<any>): string
  var text = FormatTime(AsFloat(get(snap, 'elapsed', 0.0)))
    .. '  ' .. RoundInt(get(snap, 'wpm', 0.0)) .. ' wpm'
    .. '  ' .. printf('%.1f%%', AsFloat(get(snap, 'accuracy', 100.0)))
    .. '  ' .. RoundInt(get(snap, 'errors', 0)) .. ' err'
    .. '  ' .. RoundInt(get(snap, 'progress', 0.0)) .. '%'
  if AsBool(get(snap, 'paused', false))
    text ..= '  paused'
  endif
  return text
enddef

# Readable form of a key for the warning and summary text.
export def KeyName(key: string): string
  if key == "\n" || key == "\r"
    return '↵'
  elseif key == ' '
    return '␣'
  elseif key == "\t"
    return '⇥'
  endif
  return key
enddef

export def WarnText(expected: string, typed: string): string
  return '✗ expected "' .. KeyName(expected) .. '", typed "' .. KeyName(typed) .. '"'
enddef

def LabelLine(label: string, value: string, width: number): string
  return label .. repeat(' ', width - strdisplaywidth(label) + 2) .. value
enddef

# The summary popup text. `snap` is a stats.Snapshot, `top` a stats.TopMissed,
# `hist` a history.Summarize of the sessions before this one.
export def SummaryLines(snap: dict<any>, top: list<dict<any>>,
    hist: dict<any>, completed: bool): list<string>
  var main: list<list<any>> = [
    ['Time', FormatTime(AsFloat(get(snap, 'elapsed', 0.0)))],
    ['WPM (net)', printf('%.1f', AsFloat(get(snap, 'wpm', 0.0)))],
    ['Raw WPM', printf('%.1f', AsFloat(get(snap, 'raw_wpm', 0.0)))],
    ['CPM', printf('%.1f', AsFloat(get(snap, 'cpm', 0.0)))],
    ['Accuracy', printf('%.1f%%', AsFloat(get(snap, 'accuracy', 100.0)))],
    ['Keystrokes', string(RoundInt(get(snap, 'keystrokes', 0)))],
    ['Errors', string(RoundInt(get(snap, 'errors', 0)))],
    ['Longest streak', string(RoundInt(get(snap, 'best_streak', 0)))],
    ['Characters', string(RoundInt(get(snap, 'pos', 0))) .. '/'
      .. string(RoundInt(get(snap, 'total', 0)))
      .. '  (' .. string(RoundInt(get(snap, 'progress', 0.0))) .. '%)']
  ]

  var compare: list<list<any>> = []
  var show_history = RoundInt(get(hist, 'count', 0)) > 0
  if show_history
    add(compare, ['Best WPM',
      printf('%.1f', AsFloat(get(hist, 'best_wpm', 0.0)))])
    add(compare, ['Last 10', printf('%.1f WPM, %.1f%% accuracy',
      AsFloat(get(hist, 'avg_wpm', 0.0)),
      AsFloat(get(hist, 'avg_accuracy', 0.0)))])
  endif

  # All label/value pairs share one value column so the summary reads as a table.
  var width = 0
  for pair in main + compare
    var used = strdisplaywidth(pair[0])
    if used > width
      width = used
    endif
  endfor

  var out: list<string> = [completed ? 'Typing finished' : 'Typing stopped early']
  for pair in main
    add(out, LabelLine(pair[0], pair[1], width))
  endfor

  add(out, 'Most-missed keys')
  if empty(top)
    add(out, '  no mistakes')
  else
    for entry in top
      var line = '  ' .. KeyName(get(entry, 'char', ''))
        .. '  ×' .. string(RoundInt(get(entry, 'misses', 0)))
        .. ' of ' .. string(RoundInt(get(entry, 'attempts', 0)))
      var typed: list<any> = get(entry, 'typed', [])
      if !empty(typed)
        var parts: list<string> = []
        for pair in typed
          add(parts, KeyName(pair[0]) .. ' ×' .. string(RoundInt(pair[1])))
        endfor
        line ..= '  (typed ' .. join(parts, ', ') .. ')'
      endif
      add(out, line)
    endfor
  endif

  if show_history
    add(out, 'Comparison')
    for pair in compare
      add(out, LabelLine(pair[0], pair[1], width))
    endfor
    var new_best = completed && AsFloat(get(snap, 'wpm', 0.0)) > AsFloat(get(hist, 'best_wpm', 0.0))
    if new_best
      add(out, 'New best!')
    endif
  endif

  add(out, '')
  add(out, 'r  restart    any other key  close')
  return out
enddef

# Live status popup: one line at the bottom-right corner of `winid`, passing
# every key to `Filter` and reporting closes (including Ctrl-C as -1) to
# `OnClose`.
export def OpenStatus(winid: number, Filter: func(number, string): bool,
    OnClose: func(number, any)): number
  var screenpos = win_screenpos(winid)
  var id = popup_create([''], {
    line: screenpos[0] + winheight(winid) - 1,
    col: screenpos[1] + winwidth(winid) - 1,
    pos: 'botright',
    highlight: 'TypingStatus',
    padding: [0, 1, 0, 1],
    mapping: false,
    filter: Filter,
    callback: OnClose,
    wrap: false,
    zindex: 300
  })
  status_state[id] = {text: '', timer: -1, warned: false}
  return id
enddef

# Remember the latest status and show it, unless a warning is on screen.
export def SetStatus(id: number, text: string): void
  if !PopupExists(id)
    return
  endif
  var st = StatusState(id)
  st.text = text
  if !st.warned
    popup_settext(id, [text])
  endif
enddef

def EndWarn(id: number): void
  if !PopupExists(id)
    return
  endif
  var st: dict<any> = get(status_state, id, {})
  if empty(st)
    return
  endif
  st.timer = -1
  st.warned = false
  popup_setoptions(id, {highlight: 'TypingStatus'})
  popup_settext(id, [st.text])
enddef

# Show `text` in the warning colour for `ms`, then go back to the latest status.
export def Warn(id: number, text: string, ms: number = 600): void
  if !PopupExists(id)
    return
  endif
  var st = StatusState(id)
  if get(st, 'timer', -1) != -1
    timer_stop(st.timer)
    st.timer = -1
  endif
  st.warned = true
  popup_settext(id, [text])
  popup_setoptions(id, {highlight: 'TypingStatusWarn'})
  st.timer = timer_start(ms, (_: number) => EndWarn(id))
enddef

# End a warning now and show the latest status again.
export def ClearWarn(id: number): void
  var st: dict<any> = get(status_state, id, {})
  if empty(st)
    return
  endif
  if get(st, 'timer', -1) != -1
    timer_stop(st.timer)
    st.timer = -1
  endif
  st.warned = false
  if PopupExists(id)
    popup_setoptions(id, {highlight: 'TypingStatus'})
    popup_settext(id, [st.text])
  endif
enddef

# Move the popup to the current bottom-right corner of `winid` (VimResized).
export def Reposition(id: number, winid: number): void
  if !PopupExists(id)
    return
  endif
  var screenpos = win_screenpos(winid)
  popup_setoptions(id, {
    line: screenpos[0] + winheight(winid) - 1,
    col: screenpos[1] + winwidth(winid) - 1,
    pos: 'botright'
  })
enddef

# Stop the warning timer, forget the state and close the popup. The close
# result is 0, which tells the caller it was not Ctrl-C (-1). Safe twice.
export def CloseStatus(id: number): void
  var st: dict<any> = get(status_state, id, {})
  if !empty(st) && get(st, 'timer', -1) != -1
    timer_stop(st.timer)
  endif
  if has_key(status_state, id)
    remove(status_state, id)
  endif
  if PopupExists(id)
    popup_close(id, 0)
  endif
enddef

def FinishSummary(id: number, key: string, OnKey: func(string)): void
  if get(summary_state, id, false)
    return
  endif
  summary_state[id] = true
  if PopupExists(id)
    popup_close(id, 0)
  endif
  if has_key(summary_state, id)
    remove(summary_state, id)
  endif
  OnKey(key)
enddef

def SummaryKey(id: number, key: string, OnKey: func(string)): bool
  FinishSummary(id, key, OnKey)
  return true
enddef

def SummaryClosed(id: number, result: any, OnKey: func(string)): void
  if result == -1
    # Ctrl-C closes the popup without calling the filter.
    FinishSummary(id, "\<C-c>", OnKey)
  elseif has_key(summary_state, id)
    remove(summary_state, id)
  endif
enddef

# Centred summary popup. The first key closes it and is passed to `OnKey`;
# Ctrl-C does the same with "\<C-c>". `OnKey` is called exactly once.
export def ShowSummary(lines: list<string>, OnKey: func(string)): number
  var id = popup_create(lines, {
    pos: 'center',
    border: [],
    padding: [1, 2, 1, 2],
    title: ' Typing practice ',
    mapping: false,
    filter: (pid: number, key: string): bool => SummaryKey(pid, key, OnKey),
    callback: (pid: number, result: any) => SummaryClosed(pid, result, OnKey),
    wrap: false,
    zindex: 250
  })
  summary_state[id] = false
  return id
enddef
