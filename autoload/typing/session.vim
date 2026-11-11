vim9script
# Session lifecycle for typing practice: the practice tab, the key sink, the
# live status line, the end-of-session summary, restart and the saved history.
# The original buffer, its 'modified' flag and its window are never changed.
# See PLAN.md sections 4, 5 and 5.1.

import autoload 'typing/engine.vim'
import autoload 'typing/stats.vim'
import autoload 'typing/history.vim'
import autoload 'typing/render.vim'
import autoload 'typing/ui.vim'

const AUGROUP = 'TypingPracticeSession'
const TICK_MS = 1000

# Public phases are 'idle', 'typing' and 'summary'. Transient work is guarded by
# `cleaning` instead, so State() never shows an internal phase.
var phase = 'idle'
var cleaning = false

# Session state (see State()).
var st: dict<any> = {}
var snums: dict<any> = {}
var opts: dict<any> = {}
var lines: list<string> = []
var buf = 0
var winid = 0
var tabnr = 0
var origin_winid = 0
var origin_tail = ''
var first_line = 0
var last_line = 0
var status_id = -1
var summary_id = -1
var tick_timer = -1

# Options, read once at Start (the history file and the minimum key count are
# also read there so a session keeps the settings it started with).
var blink_ms = 500
var bell = false
var idle_seconds = 5.0
var history_enabled = true
var history_file = ''
var min_keys = 20
var mode = 'stay'

# Results of the most recent session, for tests and for :TypingHistory.
var last_record: dict<any> = {}
var last_saved = false
var last_summary: list<string> = []
var deferred_timer = -1
var started_at = 0

# The clock is injectable so tests can hand-compute durations and WPM.
def DefaultClock(): float
  return reltimefloat(reltime())
enddef

var ClockF: func(): float = DefaultClock

export def SetClock(F: func(): float)
  ClockF = F
enddef

def Now(): float
  return ClockF()
enddef

# The SID of this script, so autocommands can call the script-local handlers.
def ScriptId(): string
  return expand('<SID>')
enddef

def Echo(hl: string, msg: string)
  execute 'echohl ' .. hl
  echomsg msg
  echohl None
enddef

def ReadOptions(): dict<any>
  var o: dict<any> = {
    on_error: get(g:, 'typing_on_error', 'stay'),
    line_end: get(g:, 'typing_line_end', 'either'),
    skip_non_ascii: get(g:, 'typing_skip_non_ascii', false)
  }
  # The engine's own table is the default, so only pass a user table if it is set.
  if exists('g:typing_equivalents')
    o.equivalents = g:typing_equivalents
  endif
  return o
enddef

def ReadSettings()
  blink_ms = get(g:, 'typing_blink_ms', 500) + 0
  bell = get(g:, 'typing_bell', false) ? true : false
  idle_seconds = get(g:, 'typing_idle_seconds', 5) + 0.0
  history_enabled = get(g:, 'typing_history', true) ? true : false
  history_file = get(g:, 'typing_history_file', history.DefaultFile())
  min_keys = get(g:, 'typing_history_min_keys', 20) + 0
enddef

export def Start(line1: number, line2: number)
  if phase != 'idle' || cleaning
    Echo('WarningMsg', 'vim-typing-practice: a typing session is already active')
    return
  endif

  origin_winid = win_getid()
  var name = bufname()
  origin_tail = name == '' ? '[No Name]' : fnamemodify(name, ':t')
  lines = getline(line1, line2)
  first_line = line1
  last_line = line2
  opts = deepcopy(ReadOptions())

  st = engine.Build(lines, opts)
  if empty(st.targets)
    st = {}
    lines = []
    origin_winid = 0
    opts = {}
    Echo('WarningMsg', 'nothing to type')
    return
  endif

  ReadSettings()
  started_at = localtime()
  mode = st.on_error
  last_record = {}
  last_saved = false
  last_summary = []
  var tabstop = &tabstop

  try
    if !OpenPractice(tabstop)
      Cleanup()
      return
    endif
    render.Setup(buf, st)
    render.HideTerminalCursor()
    render.StartBlink(blink_ms)
    MoveCursor()

    snums = stats.New({idle_seconds: idle_seconds, total: len(st.targets)})
    status_id = ui.OpenStatus(winid, Filter, OnStatusClosed)
    ui.SetStatus(status_id, ui.StatusText(stats.Snapshot(snums, Now())))
    StartTick()
    InstallAutocmds()
    phase = 'typing'
  catch
    var error = v:exception
    Cleanup()
    Echo('ErrorMsg', 'vim-typing-practice: ' .. error)
  endtry
enddef

# A new tab with a scratch copy of the lines. The origin buffer is untouched.
def OpenPractice(tabstop: number): bool
  try
    tabnew
  catch
    Echo('ErrorMsg', 'vim-typing-practice: cannot open the practice tab')
    return false
  endtry

  buf = bufnr()
  winid = win_getid()
  tabnr = tabpagenr()

  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  &l:tabstop = tabstop
  setlocal wrap linebreak nonumber norelativenumber nolist
  setlocal nocursorline nocursorcolumn nospell signcolumn=no foldcolumn=0
  setlocal colorcolumn= nofoldenable
  &l:scrolloff = 5
  setline(1, lines)
  setlocal nomodifiable
  execute 'silent! file ' .. fnameescape('[Typing] ' .. origin_tail)
  return true
enddef

def StartTick()
  StopTick()
  tick_timer = timer_start(TICK_MS, (_: number) => OnTick(), {repeat: -1})
enddef

def StopTick()
  if tick_timer != -1
    timer_stop(tick_timer)
    tick_timer = -1
  endif
enddef

def OnTick()
  if phase == 'typing'
    RefreshStatus()
  endif
enddef

def RefreshStatus()
  if phase != 'typing' || status_id <= 0
    return
  endif
  ui.SetStatus(status_id, ui.StatusText(stats.Snapshot(snums, Now())))
enddef

# Put the real cursor on the current target so the window scrolls with the
# typing. win_execute also works when the practice window is not current.
def MoveCursor()
  if winid <= 0 || !WinExists(winid) || empty(st)
    return
  endif
  var pos = render.CursorPos(st)
  try
    win_execute(winid, $'call cursor({pos[0]}, {pos[1]})')
  catch
  endtry
enddef

def WinExists(id: number): bool
  return get(win_id2tabwin(id), 0, 0) > 0
enddef

# The status popup filter: every key is consumed.
def Filter(id: number, key: string): bool
  try
    HandleKey(key)
  catch
    # An error in a filter is treated as "not handled" and after three errors
    # Vim closes the popup, so never let one escape.
    Echo('ErrorMsg', 'vim-typing-practice: ' .. v:exception)
    Cleanup()
  endtry
  return true
enddef

def HandleKey(key: string)
  if phase != 'typing'
    return
  endif
  if key == "\<Esc>"
    Finish(false)
    return
  endif

  var ev = engine.Feed(st, key)
  if ev.kind == 'ignored'
    return
  endif

  stats.Record(snums, ev, Now())
  render.Apply(buf, st, ev)
  render.Pulse()
  MoveCursor()
  RefreshStatus()

  if ev.kind == 'wrong'
    ui.Warn(status_id, ui.WarnText(ev.expected, ev.typed))
    if bell
      echoraw("\x07")
    endif
  else
    ui.ClearWarn(status_id)
  endif

  if ev.done
    Finish(true)
  endif
enddef

# Ctrl-C closes the popup without calling the filter and reports -1.
def OnStatusClosed(id: number, result: any)
  if id == status_id && result == -1 && phase == 'typing'
    Finish(false)
  endif
enddef

def BuildRecord(snap: dict<any>, completed: bool): dict<any>
  return {
    time: started_at,
    file: origin_tail,
    line1: first_line,
    line2: last_line,
    duration: snap.elapsed,
    chars: snap.pos,
    wpm: snap.wpm,
    raw_wpm: snap.raw_wpm,
    accuracy: snap.accuracy,
    errors: snap.errors,
    best_streak: snap.best_streak,
    mode: mode,
    completed: completed,
    missed: stats.MissedCounts(snums)
  }
enddef

def Finish(completed: bool)
  if phase != 'typing'
    return
  endif
  # Change the phase first: closing popups and the tab can fire callbacks and
  # autocommands that must not start a second finish.
  phase = 'summary'

  StopTick()
  render.StopBlink()
  render.RestoreTerminalCursor()
  CloseStatusPopup()

  var snap = stats.Snapshot(snums, Now())
  var top = stats.TopMissed(snums)

  # The comparison must be computed before this session is appended.
  var hist: dict<any> = {}
  if history_enabled
    hist = history.Summarize(history.Load(history_file))
  endif

  last_record = BuildRecord(snap, completed)
  last_saved = false
  if history_enabled && snap.keystrokes >= min_keys
    last_saved = history.Append(history_file, last_record)
  endif
  last_summary = ui.SummaryLines(snap, top, hist, completed)
  ShowSummary()
enddef

# Track the single pending lifecycle transition so cleanup can cancel it.
# Creating a popup or changing windows from a popup filter is restricted.
def Defer(Action: func())
  CancelDeferred()
  deferred_timer = timer_start(0, (_: number) => {
    deferred_timer = -1
    try
      Action()
    catch
      var error = v:exception
      Cleanup()
      Echo('ErrorMsg', 'vim-typing-practice: ' .. error)
    endtry
  })
enddef

def CancelDeferred()
  if deferred_timer != -1
    timer_stop(deferred_timer)
    deferred_timer = -1
  endif
enddef

def ShowSummary()
  Defer(() => {
    if phase == 'summary' && !cleaning
      summary_id = ui.ShowSummary(last_summary, OnSummaryKey)
    endif
  })
enddef

def OnSummaryKey(key: string)
  if cleaning || phase != 'summary'
    return
  endif
  summary_id = -1
  Defer(() => {
    if key == 'r'
      Restart()
    else
      Close()
    endif
  })
enddef

# 'r' from the summary: the same lines and options, fresh state and statistics.
def Restart()
  if buf <= 0 || !bufexists(buf) || empty(lines)
    Close()
    return
  endif

  summary_id = -1
  started_at = localtime()
  st = engine.Build(lines, opts)
  snums = stats.New({idle_seconds: idle_seconds, total: len(st.targets)})
  last_record = {}
  last_saved = false
  last_summary = []

  render.Setup(buf, st)
  render.HideTerminalCursor()
  render.StartBlink(blink_ms)
  MoveCursor()

  status_id = ui.OpenStatus(winid, Filter, OnStatusClosed)
  ui.SetStatus(status_id, ui.StatusText(stats.Snapshot(snums, Now())))
  StartTick()
  InstallAutocmds()
  phase = 'typing'
enddef

# Leaving the practice window, buffer or tab aborts the session.
def OnLeave()
  if cleaning || phase == 'idle'
    return
  endif
  Abort()
enddef

def OnWipeout(bnr: number)
  if cleaning || phase == 'idle' || bnr != buf
    return
  endif
  Abort()
enddef

def OnVimLeave()
  var practice_win = winid
  var origin_win = origin_winid
  Abort()
  # Vim will not service a deferred tab close during shutdown.
  CancelDeferred()
  CloseTabNow(practice_win, origin_win)
  cleaning = false
  render.RestoreTerminalCursor()
enddef

def OnResized()
  if phase != 'idle' && status_id > 0 && winid > 0 && WinExists(winid)
    ui.Reposition(status_id, winid)
  endif
enddef

def InstallAutocmds()
  var sid = ScriptId()
  var b = buf
  augroup TypingPracticeSession
    autocmd!
  augroup END
  execute $'autocmd {AUGROUP} WinLeave <buffer={b}> call {sid}OnLeave()'
  execute $'autocmd {AUGROUP} BufLeave <buffer={b}> call {sid}OnLeave()'
  execute $'autocmd {AUGROUP} TabLeave <buffer={b}> call {sid}OnLeave()'
  execute $'autocmd {AUGROUP} BufWipeout <buffer={b}> call {sid}OnWipeout({b})'
  execute $'autocmd {AUGROUP} VimLeavePre * call {sid}OnVimLeave()'
  execute $'autocmd {AUGROUP} VimResized * call {sid}OnResized()'
enddef

def ClearAutocmds()
  augroup TypingPracticeSession
    autocmd!
  augroup END
enddef

# Save an unfinished session under the same rules as a finished one, without a
# summary popup.
def SaveIncomplete()
  var snap = stats.Snapshot(snums, Now())
  last_record = BuildRecord(snap, false)
  last_saved = false
  last_summary = []
  if history_enabled && snap.keystrokes >= min_keys
    last_saved = history.Append(history_file, last_record)
  endif
enddef

def Abort()
  if cleaning || phase == 'idle'
    return
  endif
  try
    if phase == 'typing'
      SaveIncomplete()
    endif
  finally
    Cleanup()
  endtry
enddef

def CloseStatusPopup()
  var id = status_id
  status_id = -1
  if id > 0
    ui.CloseStatus(id)
  endif
enddef

def ClosePopupId(id: number)
  if id > 0 && !empty(popup_getpos(id))
    popup_close(id, 0)
  endif
enddef

# Release resources before closing windows, with callbacks guarded throughout
# the deferred close. Teardown must run even if the buffer has already gone.
def Cleanup()
  if cleaning
    return
  endif
  cleaning = true
  phase = 'idle'
  CancelDeferred()

  var practice_win = winid
  var origin_win = origin_winid

  try
    StopTick()
    try
      render.Teardown(buf)
    catch
      render.RestoreTerminalCursor()
    endtry
    CloseStatusPopup()
    var sid = summary_id
    summary_id = -1
    ClosePopupId(sid)
    ClearAutocmds()
  finally
    phase = 'idle'
    st = {}
    snums = {}
    opts = {}
    lines = []
    buf = 0
    winid = 0
    tabnr = 0
    origin_winid = 0
    origin_tail = ''
    first_line = 0
    last_line = 0
    status_id = -1
    summary_id = -1
    tick_timer = -1
    mode = 'stay'
  endtry

  # Leave/wipe autocommands and popup filters must unwind before tab changes.
  Defer(() => {
    try
      CloseTabNow(practice_win, origin_win)
    finally
      cleaning = false
    endtry
  })
enddef

def CloseTabNow(practice_win: number, origin_win: number): bool
  if practice_win > 0 && WinExists(practice_win)
    try
      execute 'tabclose ' .. win_id2tabwin(practice_win)[0]
    catch
      return false
    endtry
  endif
  if origin_win > 0 && WinExists(origin_win) && win_getid() != origin_win
    try
      win_gotoid(origin_win)
    catch
    endtry
  endif
  return true
enddef

def Close()
  Cleanup()
enddef

export def Stop()
  if phase == 'typing'
    Finish(false)
  elseif phase == 'summary'
    Close()
  else
    Echo('WarningMsg', 'no typing session')
  endif
enddef

export def History()
  history.Show()
enddef

export def State(): dict<any>
  return {
    phase: phase,
    buf: buf,
    winid: winid,
    tabnr: tabnr,
    origin_winid: origin_winid,
    st: st,
    stats: snums,
    status_id: status_id,
    summary_id: summary_id,
    lines: lines,
    last_record: last_record,
    last_saved: last_saved,
    last_summary: last_summary
  }
enddef
