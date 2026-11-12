vim9script
g:typing_resume = 'never'
g:typing_summary_grace_ms = 0
# Tests for the original syntax colours (session part) and the paused phase:
# Esc pauses, motions move the real cursor, Enter/i type from the cursor, Esc
# returns, q and Ctrl-C end the session. Sessions are driven with
# feedkeys(..., 'xt'); every test ends idle, in one tab, with no popups, no
# extra timers and the terminal options restored. History and progress always
# go to temp files.

import autoload 'typing/session.vim'
import autoload 'typing/history.vim'
import autoload 'typing/progress.vim'
import autoload 'typing/ui.vim'

g:typing_history_file = tempname()
g:typing_progress_file = tempname()
g:typing_blink_ms = 0

# The terminal options as this Vim started, restored at the very end.
const ORIGINAL_TTIMEOUT = &ttimeout
const ORIGINAL_TTIMEOUTLEN = &ttimeoutlen

var fake_now = 0.0
var expected_ve = ''
var expected_tt: list<any> = []
var origin_state: dict<any> = {}

def TestClock(): float
  return reltimefloat(reltime())
enddef

def FakeClock(): float
  return fake_now
enddef

def ResetOptions()
  g:typing_summary_grace_ms = 0
  g:typing_resume = 'never'
  g:typing_on_error = 'stay'
  g:typing_line_end = 'either'
  g:typing_skip_non_ascii = false
  g:typing_blink_ms = 0
  g:typing_bell = false
  g:typing_idle_seconds = 5
  g:typing_history = true
  g:typing_history_min_keys = 1
  g:typing_history_file = tempname()
  g:typing_progress_file = tempname()
  if exists('g:typing_esc_timeout_ms')
    unlet g:typing_esc_timeout_ms
  endif
enddef

# Known terminal options before each test; CheckClean expects them back.
def Fresh(): number
  assert_equal('idle', session.State().phase)
  assert_equal([], popup_list())
  assert_equal([], timer_info())
  &t_ve = 'PAUSEVE'
  expected_ve = &t_ve
  &ttimeout = false
  &ttimeoutlen = 200
  expected_tt = [false, 200]
  origin_state = {}
  session.SetClock(TestClock)
  fake_now = 0.0
  ResetOptions()
  enew!
  execute 'silent! %delete _'
  &modified = false
  return len(timer_info())
enddef

def Origin(text: list<string>): number
  enew!
  execute 'silent! %delete _'
  setline(1, text)
  &modified = false
  origin_state = {buf: bufnr(), win: win_getid(), text: getline(1, '$'),
    modified: &modified}
  return bufnr()
enddef

def Keys(keys: string)
  feedkeys(keys, 'xt')
  sleep 20m
enddef

def CheckClean(timers: number)
  sleep 40m
  assert_equal('idle', session.State().phase)
  assert_equal(1, tabpagenr('$'))
  assert_equal([], popup_list())
  assert_equal(timers, len(timer_info()))
  assert_equal(expected_ve, &t_ve)
  assert_equal(expected_tt, [&ttimeout, &ttimeoutlen])
  if !empty(origin_state)
    assert_equal(origin_state.win, win_getid())
    assert_equal(origin_state.buf, bufnr())
    assert_equal(origin_state.text, getline(1, '$'))
    assert_equal(origin_state.modified, &modified)
  endif
  assert_notmatch('OnLeave\|OnWipeout\|OnVimLeave\|OnResized',
    execute('autocmd TypingPracticeSession'))
enddef

# End whatever is left: summary or session, then the deferred tab close.
def StopAll()
  session.Stop()
  sleep 20m
  if session.State().phase != 'idle'
    session.Stop()
  endif
enddef

def StatusLines(): list<string>
  return getbufline(winbufnr(session.State().status_id), 1, '$')
enddef

def Cursor(): list<number>
  var cur = getcurpos(session.State().winid)
  return [cur[1], cur[2]]
enddef

# True when a TypingPending property covers byte column `col` of line `lnum`.
def Pending(bnr: number, lnum: number, col: number): bool
  for p in prop_list(lnum, {bufnr: bnr, types: ['TypingPending']})
    if p.col <= col && col < p.col + p.length
      return true
    endif
  endfor
  return false
enddef

# Every char target before `pos` is not pending, every one from it on is.
def CheckDimFrom(pos: number)
  var s = session.State()
  var i = 0
  for t in s.st.targets
    if t.kind == 'char'
      assert_equal(i >= pos, Pending(s.buf, t.lnum, t.col),
        $'target {i} ({t.char}) at {t.lnum}:{t.col}, position {pos}')
    endif
    i += 1
  endfor
enddef

def States(from: number, to: number): list<string>
  return mapnew(session.State().st.targets[from : to], (_, t) => t.state)
enddef

var ft_count = 0

def Test_syntax_kept()
  var t0 = Fresh()
  var conceal = &conceallevel
  set conceallevel=2 concealcursor=nc
  syntax on
  Origin(['let x = 1', 'echo x'])
  setlocal syntax=vim
  ft_count = 0
  augroup TestPauseFileType
    autocmd!
    autocmd FileType * ft_count += 1
  augroup END
  try
    TypingStart
    var s = session.State()
    assert_equal('typing', s.phase)
    assert_equal('vim', getbufvar(s.buf, '&syntax'))
    assert_equal('', getbufvar(s.buf, '&filetype'))
    assert_equal('vim', getbufvar(s.buf, 'current_syntax', ''))
    assert_equal(0, ft_count)
    assert_equal(s.winid, win_getid())
    assert_equal(0, &l:conceallevel)
    assert_equal('', &l:concealcursor)
    Keys('let x = 1 echo x')
    assert_equal('summary', session.State().phase)
    Keys('r')
    s = session.State()
    assert_equal('typing', s.phase)
    assert_equal('vim', getbufvar(s.buf, '&syntax'))
    assert_equal(0, getwinvar(s.winid, '&conceallevel'))
    assert_equal(0, ft_count)
    StopAll()
  finally
    augroup TestPauseFileType
      autocmd!
    augroup END
    syntax off
    &conceallevel = conceal
    set concealcursor=
  endtry
  CheckClean(t0)
enddef

# A buffer without syntax gives a practice buffer without syntax.
def Test_no_syntax()
  var t0 = Fresh()
  Origin(['abc'])
  TypingStart
  assert_equal('', getbufvar(session.State().buf, '&syntax'))
  StopAll()
  CheckClean(t0)
enddef

def Test_esc_at_start()
  var t0 = Fresh()
  g:typing_blink_ms = 10
  Origin(['abc def'])
  TypingStart
  assert_equal('', &t_ve)
  var typing_timers = len(timer_info())
  Keys("\<Esc>")
  var s = session.State()
  assert_equal('paused', s.phase)
  assert_equal('PAUSEVE', &t_ve)
  assert_equal([ui.PausedText()], StatusLines())
  assert_equal([1, 1], Cursor())
  # The blink timer is stopped; the cursor marker stays on the position.
  assert_equal(typing_timers - 1, len(timer_info()))
  assert_true(index(map(prop_list(1, {bufnr: s.buf}), (_, p) => p.type),
    'TypingCursor') >= 0)
  # The one-second refresh must not overwrite the hint.
  sleep 1200m
  assert_equal('paused', session.State().phase)
  assert_equal([ui.PausedText()], StatusLines())
  Keys("\<Esc>")
  assert_equal('typing', session.State().phase)
  assert_equal('', &t_ve)
  assert_equal(typing_timers, len(timer_info()))
  assert_notequal([ui.PausedText()], StatusLines())
  StopAll()
  CheckClean(t0)
enddef

def Test_motions_while_paused()
  var t0 = Fresh()
  var text = ['one two three', 'four five', '', 'six seven yi']
  Origin(text)
  TypingStart
  var s = session.State()
  Keys('one')
  assert_equal([1, 4], Cursor())
  Keys("\<Esc>")
  assert_equal('paused', session.State().phase)
  assert_equal([1, 4], Cursor())
  Keys('j')
  assert_equal([2, 4], Cursor())
  Keys('w')
  assert_equal([2, 6], Cursor())
  Keys('gg')
  assert_equal([1, 1], Cursor())
  Keys('G')
  assert_equal(4, Cursor()[0])
  Keys('gg2j')
  assert_equal(3, Cursor()[0])
  Keys('}')
  assert_equal(4, Cursor()[0])
  # A search runs in command-line mode: its i and Enter are not session keys.
  Keys("gg/yi\<CR>")
  assert_equal([4, 11], Cursor())
  assert_equal('paused', session.State().phase)
  assert_equal(3, session.State().st.pos)
  assert_equal(text, getbufline(s.buf, 1, '$'))
  assert_false(getbufvar(s.buf, '&modified'))
  assert_false(getbufvar(s.buf, '&modifiable'))
  assert_equal('', reg_recording())
  assert_equal('n', mode())

  # Esc returns to typing where it was left, with the cursor on the target.
  Keys("\<Esc>")
  assert_equal('typing', session.State().phase)
  assert_equal(3, session.State().st.pos)
  assert_equal([1, 4], Cursor())
  assert_equal('', &t_ve)
  Keys(' ')
  assert_equal(4, session.State().st.pos)
  assert_equal(4, session.State().stats.keystrokes)
  StopAll()
  CheckClean(t0)
enddef

# Keys that wait for an argument or a count are not mistaken for session keys.
def Test_pending_commands()
  var t0 = Fresh()
  Origin(['xxi yq', 'ab', 'cd', 'ef'])
  TypingStart
  Keys("\<Esc>")
  Keys('fi')
  assert_equal('paused', session.State().phase)
  assert_equal([1, 3], Cursor())
  Keys('fq')
  assert_equal('paused', session.State().phase)
  assert_equal([1, 6], Cursor())
  assert_equal('', reg_recording())
  Keys('gg2j')
  assert_equal([3, 1], Cursor())
  # A count before Enter is cancelled; Enter then types from the cursor.
  Keys("2\<CR>")
  assert_equal('typing', session.State().phase)
  assert_equal([3, 1], Cursor())
  assert_equal(10, session.State().st.pos)
  Keys("\<Esc>")
  # Esc after a count only cancels the count.
  Keys("3\<Esc>")
  assert_equal('paused', session.State().phase)
  Keys('k')
  assert_equal([2, 1], Cursor())
  Keys("\<Esc>")
  assert_equal('typing', session.State().phase)
  StopAll()
  CheckClean(t0)
enddef

def Test_jump_forward_and_backward()
  for key in ["\<CR>", 'i']
    var t0 = Fresh()
    # a0 b1 c2 ␣3 d4 e5 f6 ↵7 g8 h9 i10 ␣11 j12 k13 l14
    Origin(['abc def', 'ghi jkl'])
    TypingStart
    Keys('ab')
    Keys("\<Esc>jw")
    assert_equal([2, 5], Cursor())
    Keys(key)
    var s = session.State()
    assert_equal('typing', s.phase)
    assert_equal(12, s.st.pos)
    assert_equal('', &t_ve)
    assert_equal([2, 5], Cursor())
    assert_equal(['correct', 'correct'], States(0, 1))
    assert_equal(repeat(['skipped'], 10), States(2, 11))
    CheckDimFrom(12)
    Keys('j')
    assert_equal(13, session.State().st.pos)

    # Backward: everything from the new position is untyped again.
    Keys("\<Esc>ggl")
    assert_equal([1, 2], Cursor())
    Keys(key)
    s = session.State()
    assert_equal('typing', s.phase)
    assert_equal(1, s.st.pos)
    assert_equal('', &t_ve)
    assert_equal([1, 2], Cursor())
    assert_equal(['correct'], States(0, 0))
    assert_equal(repeat(['pending'], 14), States(1, 14))
    CheckDimFrom(1)
    # b (1) and j (12) were standing as correct and stay banked.
    assert_equal(2, s.stats.banked)
    Keys('b')
    assert_equal(2, session.State().st.pos)

    session.Stop()
    s = session.State()
    assert_equal('summary', s.phase)
    assert_false(s.last_record.completed)
    # a, b, j and b again were passed by typing; jumps pass nothing.
    assert_equal(4, s.last_record.chars)
    assert_equal(0, s.last_record.start)
    StopAll()
    CheckClean(t0)
  endfor
enddef

def Test_quit_while_paused()
  for key in ['q', "\<C-c>"]
    var t0 = Fresh()
    Origin(['abcdef'])
    TypingStart
    Keys('ab')
    Keys("\<Esc>")
    assert_equal('paused', session.State().phase)
    feedkeys(key, 'xt')
    sleep 20m
    sleep 30m
    var s = session.State()
    assert_equal('summary', s.phase)
    assert_true(s.summary_id > 0)
    assert_false(s.last_record.completed)
    assert_equal(2, s.last_record.chars)
    assert_equal('Typing stopped early', s.last_summary[0])
    assert_equal('', reg_recording())
    assert_equal(1, len(history.Load(g:typing_history_file)))
    Keys('x')
    CheckClean(t0)
  endfor
enddef

def Test_nothing_after_cursor()
  for key in ["\<CR>", 'i']
    var t0 = Fresh()
    Origin(['ab', '', '   '])
    TypingStart
    Keys('a')
    Keys("\<Esc>G")
    assert_equal(3, Cursor()[0])
    Keys(key)
    var s = session.State()
    assert_equal('paused', s.phase)
    assert_equal(1, s.st.pos)
    assert_equal('PAUSEVE', &t_ve)
    assert_match('nothing to type from here', execute('messages'))
    assert_equal([ui.PausedText()], StatusLines())
    Keys("\<Esc>")
    assert_equal('typing', session.State().phase)
    assert_equal([1, 2], Cursor())
    StopAll()
    CheckClean(t0)
  endfor
enddef

def Test_leave_and_stop_while_paused()
  var t0 = Fresh()
  Origin(['abc'])
  TypingStart
  var practice = session.State().buf
  Keys('a')
  Keys("\<Esc>")
  tabprevious
  sleep 40m
  assert_equal('idle', session.State().phase)
  assert_false(bufexists(practice))
  var recs = history.Load(g:typing_history_file)
  assert_equal(1, len(recs))
  assert_false(recs[0].completed)
  assert_equal(1, recs[0].chars)
  CheckClean(t0)

  t0 = Fresh()
  Origin(['abc'])
  TypingStart
  Keys("a\<Esc>")
  session.Stop()
  assert_equal('summary', session.State().phase)
  assert_false(session.State().last_record.completed)
  session.Stop()
  CheckClean(t0)

  # A Vim command that closes the practice window while paused.
  t0 = Fresh()
  Origin(['abc'])
  TypingStart
  Keys("a\<Esc>")
  Keys(":quit\<CR>")
  assert_equal('idle', session.State().phase)
  assert_equal(1, len(history.Load(g:typing_history_file)))
  CheckClean(t0)
enddef

# Without autocommands nothing reports the change: the next session key or
# the one-second tick notices that the window no longer shows the buffer.
def Test_window_invalid_while_paused()
  for by_key in [true, false]
    var t0 = Fresh()
    Origin(['abc'])
    TypingStart
    var practice = session.State().buf
    Keys("a\<Esc>")
    noautocmd enew
    assert_false(bufexists(practice))
    if by_key
      Keys("\<CR>")
    else
      sleep 1100m
    endif
    sleep 20m
    assert_equal('idle', session.State().phase)
    assert_equal(1, len(history.Load(g:typing_history_file)))
    CheckClean(t0)
  endfor
enddef

def Test_clock_and_chars()
  var t0 = Fresh()
  session.SetClock(FakeClock)
  Origin(['abcdef'])
  TypingStart
  fake_now = 100.0
  Keys('a')
  fake_now = 101.0
  Keys('b')
  # Pausing closes the open gap (0.5 s); time paused is not counted.
  fake_now = 101.5
  Keys("\<Esc>")
  fake_now = 200.0
  Keys('l')
  fake_now = 300.0
  Keys("\<Esc>")
  # The first key after returning adds no gap.
  fake_now = 301.0
  Keys('c')
  fake_now = 302.0
  Keys('d')
  fake_now = 302.0
  Keys("\<Esc>l")
  assert_equal([1, 6], Cursor())
  fake_now = 400.0
  Keys("\<CR>")
  # Nor does the first key after a jump.
  fake_now = 450.0
  Keys('f')
  var s = session.State()
  assert_equal('summary', s.phase)
  assert_true(s.last_record.completed)
  assert_equal(2.5, s.last_record.duration)
  # a b c d f typed; e skipped.
  assert_equal(5, s.last_record.chars)
  assert_equal(24.0, s.last_record.wpm)
  assert_equal(24.0, s.last_record.raw_wpm)
  Keys('x')
  session.SetClock(TestClock)
  CheckClean(t0)
enddef

def Test_saved_position_after_jumps()
  var t0 = Fresh()
  g:typing_resume = 'ask'
  # a0 b1 c2 ↵3 d4 e5 f6 g7 ↵8 h9 i10 j11
  Origin(['abc', 'defg', 'hij'])
  execute 'silent file ' .. fnameescape(tempname() .. ' pause.txt')
  var path = fnamemodify(bufname(), ':p')
  origin_state.text = getline(1, '$')
  TypingStart
  assert_equal('typing', session.State().phase)
  Keys('ab')
  Keys("\<Esc>j\<CR>")
  assert_equal(6, session.State().st.pos)
  Keys('f')
  Keys("\<Esc>q")
  var s = session.State()
  assert_equal('summary', s.phase)
  assert_equal(7, progress.Get(g:typing_progress_file, path).pos)
  assert_equal(2, progress.Get(g:typing_progress_file, path).lnum)
  assert_match('Position saved: line 2', join(s.last_summary))
  assert_equal(3, s.last_record.chars)
  Keys('x')
  CheckClean(t0)

  # Resume at 7, then jump back: the earlier position is saved.
  t0 = len(timer_info())
  TypingStart
  assert_equal('prompt', session.State().phase)
  Keys("\<CR>")
  assert_equal(7, session.State().start)
  Keys('g')
  Keys("\<Esc>ggl\<CR>")
  assert_equal(1, session.State().st.pos)
  Keys("\<Esc>q")
  s = session.State()
  assert_equal(7, s.last_record.start)
  assert_equal(1, s.last_record.chars)
  assert_equal(1, progress.Get(g:typing_progress_file, path).pos)
  assert_equal(1, progress.Get(g:typing_progress_file, path).lnum)
  # Restart begins at the session's first start, not at the jump.
  Keys('r')
  assert_equal(7, session.State().st.pos)
  assert_equal(7, session.State().st.start)
  StopAll()
  CheckClean(t0)

  # Resume at 1, no movement: nothing new is saved. Then a jump and leaving
  # the tab while paused saves as it does while typing.
  t0 = len(timer_info())
  TypingStart
  Keys("\<CR>")
  assert_equal(1, session.State().start)
  Keys("\<Esc>q")
  assert_notmatch('Position saved:', join(session.State().last_summary))
  assert_equal(1, progress.Get(g:typing_progress_file, path).pos)
  Keys('x')
  CheckClean(t0)
  t0 = len(timer_info())
  TypingStart
  Keys("\<CR>")
  Keys("\<Esc>j\<CR>")
  assert_equal(5, session.State().st.pos)
  Keys("\<Esc>")
  tabprevious
  sleep 40m
  assert_equal(5, progress.Get(g:typing_progress_file, path).pos)
  CheckClean(t0)
enddef

def Test_restart_after_jump()
  var t0 = Fresh()
  Origin(['abc def'])
  TypingStart
  Keys("a\<Esc>w\<CR>")
  assert_equal(4, session.State().st.pos)
  Keys('def')
  var s = session.State()
  assert_equal('summary', s.phase)
  assert_true(s.last_record.completed)
  assert_equal(0, s.last_record.start)
  assert_equal(4, s.last_record.chars)
  Keys('r')
  s = session.State()
  assert_equal('typing', s.phase)
  assert_equal(0, s.st.pos)
  assert_equal(0, s.st.start)
  assert_equal(0, s.stats.keystrokes)
  assert_equal(repeat(['pending'], 7), States(0, 6))
  CheckDimFrom(0)
  StopAll()
  CheckClean(t0)
enddef

# One typeahead batch: typing, Esc, a motion, Enter and more typing. Expected:
# 'ab' typed, the pause, j moves to line 2 column 3, Enter jumps there and
# 'xy' is typed from it; nothing reaches the buffer. With Esc q after it the
# session ends and the rest of the batch is swallowed by the transition guard.
def Test_typeahead()
  for tail in ['', "\<Esc>q:ix\<Esc>"]
    var t0 = Fresh()
    # a0 b1 c2 d3 ↵4 e5 f6 x7 y8 z9
    var origin = Origin(['abcd', 'efxyz'])
    TypingStart
    var practice = session.State().buf
    feedkeys("ab\<Esc>j\<CR>xy" .. tail, 'xt')
    sleep 20m
    var s = session.State()
    assert_equal('', reg_recording())
    assert_equal('n', mode())
    assert_equal('', getcmdwintype())
    assert_equal(['abcd', 'efxyz'], getbufline(practice, 1, '$'))
    assert_equal(['abcd', 'efxyz'], getbufline(origin, 1, '$'))
    assert_false(getbufvar(origin, '&modified'))
    assert_equal(9, s.st.pos)
    assert_equal(['correct', 'correct'], States(0, 1))
    assert_equal(repeat(['skipped'], 5), States(2, 6))
    assert_equal(['correct', 'correct', 'pending'], States(7, 9))
    assert_equal(4, s.stats.keystrokes)
    assert_equal(0, s.stats.errors)
    if tail == ''
      assert_equal('typing', s.phase)
      assert_equal([2, 5], Cursor())
      CheckDimFrom(9)
    else
      assert_equal('summary', s.phase)
      assert_equal(4, s.last_record.chars)
    endif
    StopAll()
    CheckClean(t0)
  endfor
enddef

def Test_esc_timeout()
  # Each exit path restores the options exactly once.
  for exit in ['complete', 'q', 'ctrl-c', 'abort', 'stop', 'vimleave', 'failure']
    var t0 = Fresh()
    Origin(['ab'])
    if exit == 'failure'
      session.SetClock((): float => str2float(eval('g:typing_missing_clock_value')))
    endif
    TypingStart
    sleep 20m
    if exit == 'failure'
      session.SetClock(TestClock)
      CheckClean(t0)
      continue
    endif
    assert_equal([true, 50], [&ttimeout, &ttimeoutlen], exit)
    if exit == 'complete'
      Keys('ab')
      assert_equal([true, 50], [&ttimeout, &ttimeoutlen])
      Keys('x')
    elseif exit == 'q'
      Keys("a\<Esc>q")
      Keys('x')
    elseif exit == 'ctrl-c'
      Keys("a\<Esc>")
      Keys("\<C-c>")
      sleep 30m
      assert_equal('summary', session.State().phase)
      Keys("\<C-c>")
    elseif exit == 'abort'
      Keys("a\<Esc>")
      tabprevious
    elseif exit == 'stop'
      StopAll()
    else
      Keys("a\<Esc>")
      doautocmd VimLeavePre
    endif
    CheckClean(t0)
    # Restored once: a later change by the user is not undone.
    &ttimeoutlen = 300
    sleep 40m
    assert_equal(300, &ttimeoutlen)
  endfor

  # The prompt phase is part of the session too.
  var t0 = Fresh()
  g:typing_resume = 'ask'
  Origin(['abc', 'def'])
  execute 'silent file ' .. fnameescape(tempname() .. ' timeout.txt')
  origin_state.text = getline(1, '$')
  assert_true(progress.Save(g:typing_progress_file, fnamemodify(bufname(), ':p'),
    {line1: 1, line2: 2, pos: 2, total: 7, lnum: 1,
      hash: progress.Fingerprint(['abc', 'def']), time: 1}))
  TypingStart
  assert_equal('prompt', session.State().phase)
  assert_equal([true, 50], [&ttimeout, &ttimeoutlen])
  Keys("\<Esc>")
  CheckClean(t0)

  # 0 leaves the options alone.
  t0 = Fresh()
  g:typing_esc_timeout_ms = 0
  Origin(['ab'])
  TypingStart
  assert_equal([false, 200], [&ttimeout, &ttimeoutlen])
  Keys("\<Esc>")
  assert_equal('paused', session.State().phase)
  StopAll()
  CheckClean(t0)

  # A configured value; a user value already below it is kept; -1 is replaced.
  for [user, configured, during] in [[200, 30, 30], [10, 50, 10], [0, 50, 0],
      [-1, 50, 50], [50, 50, 50]]
    t0 = Fresh()
    &ttimeoutlen = user
    expected_tt = [false, user]
    g:typing_esc_timeout_ms = configured
    Origin(['ab'])
    TypingStart
    assert_equal([true, during], [&ttimeout, &ttimeoutlen], string(user))
    StopAll()
    CheckClean(t0)
  endfor

  # ttimeout already on stays on.
  t0 = Fresh()
  &ttimeout = true
  expected_tt = [true, 200]
  Origin(['ab'])
  TypingStart
  assert_equal([true, 50], [&ttimeout, &ttimeoutlen])
  StopAll()
  CheckClean(t0)
enddef

Test_syntax_kept()
Test_no_syntax()
Test_esc_at_start()
Test_motions_while_paused()
Test_pending_commands()
Test_jump_forward_and_backward()
Test_quit_while_paused()
Test_nothing_after_cursor()
Test_leave_and_stop_while_paused()
Test_window_invalid_while_paused()
Test_clock_and_chars()
Test_saved_position_after_jumps()
Test_restart_after_jump()
Test_typeahead()
Test_esc_timeout()

&ttimeout = ORIGINAL_TTIMEOUT
&ttimeoutlen = ORIGINAL_TTIMEOUTLEN
session.SetClock(TestClock)
