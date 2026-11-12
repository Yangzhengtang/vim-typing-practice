vim9script
g:typing_summary_grace_ms = 0
g:typing_resume = 'never'
# Integration tests for autoload/typing/session.vim.
# Sessions are driven with feedkeys(..., 'xt'); every test ends idle, in a single
# tab, with no popups and no extra timers. History always goes to a temp file.

import autoload 'typing/session.vim'
import autoload 'typing/history.vim'
import autoload 'typing/ui.vim'

# Never write the real ~/.vim history; a small blink period keeps timers away.
g:typing_history_file = tempname()
g:typing_blink_ms = 0
g:typing_history_min_keys = 20

var fake_now = 0.0
var expected_ve = ''
var origin_state: dict<any> = {}

def TestClock(): float
  return reltimefloat(reltime())
enddef

def FakeClock(): float
  return fake_now
enddef

def ResetOptions()
  g:typing_summary_grace_ms = 0
  g:typing_on_error = 'stay'
  g:typing_line_end = 'either'
  g:typing_skip_non_ascii = false
  g:typing_blink_ms = 0
  g:typing_bell = false
  g:typing_idle_seconds = 5
  g:typing_history = true
  g:typing_history_min_keys = 20
  if exists('g:typing_equivalents')
    unlet g:typing_equivalents
  endif
enddef

def ClearHistory()
  if filereadable(g:typing_history_file)
    delete(g:typing_history_file)
  endif
enddef

# Reset everything a previous test may have left, and return the timer count.
def Fresh(): number
  assert_equal('idle', session.State().phase)
  assert_equal([], popup_list())
  assert_equal([], timer_info())
  &t_ve = 'TESTVE'
  expected_ve = &t_ve
  origin_state = {}
  session.SetClock(TestClock)
  fake_now = 0.0
  ResetOptions()
  ClearHistory()
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
  expected_ve = &t_ve
  origin_state = {buf: bufnr(), win: win_getid(), text: getline(1, '$'),
    modified: &modified}
  return bufnr()
enddef

# Every test must leave no session behind.
def CheckClean(timers: number)
  sleep 40m
  assert_equal('idle', session.State().phase)
  assert_equal(1, tabpagenr('$'))
  assert_equal([], popup_list())
  assert_equal(timers, len(timer_info()))
  assert_equal(expected_ve, &t_ve)
  if !empty(origin_state)
    assert_equal(origin_state.win, win_getid())
    assert_equal(origin_state.buf, bufnr())
    assert_equal(origin_state.text, getline(1, '$'))
    assert_equal(origin_state.modified, &modified)
  endif
  assert_notmatch('OnLeave\|OnWipeout\|OnVimLeave\|OnResized',
    execute('autocmd TypingPracticeSession'))
enddef

def Props(bnr: number, lnum: number): list<string>
  var types: list<string> = []
  for p in prop_list(lnum, {bufnr: bnr})
    add(types, p.type)
  endfor
  return types
enddef

def Test_stay_completion()
  var t0 = Fresh()
  g:typing_history_min_keys = 3
  &t_ve = 'SESSVE'
  var origin = Origin(['Hello there', '  second line', '', 'the end'])
  execute 'silent! file typing test.txt'
  &tabstop = 3
  var owin = win_getid()
  var text = getline(1, '$')
  var was_modified = &modified

  TypingStart
  var s = session.State()
  assert_equal('typing', s.phase)
  assert_equal(2, tabpagenr('$'))
  assert_equal('[Typing] typing test.txt', bufname(s.buf))
  assert_equal('nofile', getbufvar(s.buf, '&buftype'))
  assert_false(getbufvar(s.buf, '&swapfile'))
  assert_false(getbufvar(s.buf, '&modifiable'))
  assert_false(getbufvar(s.buf, '&buflisted'))
  assert_equal(3, getbufvar(s.buf, '&tabstop'))
  assert_true(&l:wrap)
  assert_true(&l:linebreak)
  assert_false(&l:number)
  assert_false(&l:relativenumber)
  assert_false(&l:list)
  assert_false(&l:cursorline)
  assert_false(&l:cursorcolumn)
  assert_false(&l:spell)
  assert_equal('no', &l:signcolumn)
  assert_equal(0, &l:foldcolumn)
  assert_equal('', &l:colorcolumn)
  assert_false(&l:foldenable)
  assert_equal(5, &l:scrolloff)
  assert_equal('', &t_ve)
  assert_equal(['Hello there', '  second line', '', 'the end'], getline(1, '$'))
  var total = len(s.st.targets)
  assert_equal(31, total)

  # Prose rules: the indented line has no leading targets, the blank line none.
  feedkeys('Hello there ', 'xt')
  sleep 20m
  assert_equal('typing', session.State().phase)
  feedkeys("second line\<CR>", 'xt')
  sleep 20m
  feedkeys('the end', 'xt')
  sleep 20m

  s = session.State()
  assert_equal('summary', s.phase)
  assert_equal(31, s.last_record.chars)
  assert_equal(true, s.last_record.completed)
  assert_equal('stay', s.last_record.mode)
  assert_equal('typing test.txt', s.last_record.file)
  assert_equal(1, s.last_record.line1)
  assert_equal(4, s.last_record.line2)
  assert_equal(31, s.last_record.best_streak)
  assert_equal(0, s.last_record.errors)
  assert_equal(100.0, s.last_record.accuracy)
  assert_equal({}, s.last_record.missed)
  assert_true(s.last_saved)
  assert_equal('Typing finished', s.last_summary[0])
  # The summary is still shown in the practice tab.
  assert_equal(2, tabpagenr('$'))

  feedkeys('x', 'xt')
  sleep 20m
  sleep 30m
  assert_equal('idle', session.State().phase)
  assert_equal(1, tabpagenr('$'))
  assert_equal(owin, win_getid())
  assert_equal(origin, bufnr())
  assert_equal(text, getline(1, '$'))
  assert_equal(was_modified, &modified)
  assert_false(&modified)
  assert_equal('SESSVE', &t_ve)

  var recs = history.Load(g:typing_history_file)
  assert_equal(1, len(recs))
  assert_equal(true, recs[0].completed)
  assert_equal(31, recs[0].chars)
  assert_equal('typing test.txt', recs[0].file)
  assert_equal('stay', recs[0].mode)
  assert_true(recs[0].wpm >= 0.0)
  assert_true(recs[0].accuracy >= 0.0 && recs[0].accuracy <= 100.0)
  CheckClean(t0)
enddef

def Test_wrong_key()
  var t0 = Fresh()
  g:typing_history_min_keys = 1000
  Origin(['abc'])
  TypingStart
  feedkeys('x', 'xt')
  sleep 20m

  var s = session.State()
  assert_equal('typing', s.phase)
  assert_equal(0, s.st.pos)
  assert_equal(1, s.stats.errors)
  assert_equal(1, s.stats.keystrokes)
  assert_equal(0, s.stats.correct)
  var types = Props(s.buf, 1)
  assert_true(index(types, 'TypingWrong') >= 0, string(types))
  assert_equal([ui.WarnText('a', 'x')],
    getbufline(winbufnr(s.status_id), 1, '$'))

  feedkeys("\<Esc>q", 'xt')
  sleep 20m
  assert_equal('summary', session.State().phase)
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

# The bell is optional; a wrong key must still be consumed when it is on.
def Test_wrong_key_bell()
  var t0 = Fresh()
  g:typing_bell = true
  g:typing_history_min_keys = 1000
  Origin(['abc'])
  TypingStart
  feedkeys('x', 'xt')
  sleep 20m
  var s = session.State()
  assert_equal('typing', s.phase)
  assert_equal(1, s.stats.errors)
  assert_equal([ui.WarnText('a', 'x')],
    getbufline(winbufnr(s.status_id), 1, '$'))
  feedkeys("\<Esc>q", 'xt')
  sleep 20m
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_esc_midway()
  var t0 = Fresh()
  g:typing_history_min_keys = 2
  &t_ve = 'ESCVE'
  Origin(['hello world'])
  TypingStart
  assert_equal('', &t_ve)
  feedkeys('hel', 'xt')
  sleep 20m
  # Esc pauses; q from the paused phase ends the session early.
  feedkeys("\<Esc>", 'xt')
  sleep 20m
  assert_equal('paused', session.State().phase)
  assert_equal('ESCVE', &t_ve)
  feedkeys('q', 'xt')
  sleep 20m

  var s = session.State()
  assert_equal('summary', s.phase)
  assert_equal(false, s.last_record.completed)
  assert_equal(3, s.last_record.chars)
  assert_equal('Typing stopped early', s.last_summary[0])
  assert_true(s.last_saved)

  feedkeys('x', 'xt')
  sleep 20m
  sleep 30m
  assert_equal('idle', session.State().phase)
  assert_equal('ESCVE', &t_ve)
  var recs = history.Load(g:typing_history_file)
  assert_equal(1, len(recs))
  assert_equal(false, recs[0].completed)
  CheckClean(t0)
enddef

# Ctrl-C closes the status popup and reports -1 to its callback. Fall back to a
# short sleep for the deferred summary if Vim defers popup creation there.
def Test_ctrl_c_midway()
  var t0 = Fresh()
  g:typing_history_min_keys = 1000
  Origin(['hello world'])
  TypingStart
  feedkeys('hel', 'xt')
  sleep 20m
  feedkeys("\<C-c>", 'xt')
  sleep 20m
  sleep 30m

  var s = session.State()
  assert_equal('summary', s.phase)
  assert_equal(false, s.last_record.completed)
  assert_equal(3, s.last_record.chars)
  assert_false(s.last_saved)

  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

# The status popup is refreshed by a one-second timer while typing.
def Test_status_tick()
  var t0 = Fresh()
  g:typing_history_min_keys = 1000
  Origin(['abc'])
  TypingStart
  feedkeys('a', 'xt')
  sleep 20m
  var s = session.State()
  var before = getbufline(winbufnr(s.status_id), 1, '$')
  sleep 1300m
  var after = getbufline(winbufnr(s.status_id), 1, '$')
  assert_true(before != after, string(before) .. ' / ' .. string(after))
  assert_match('^00:0[12]', after[0])
  assert_match('33%$', after[0])
  feedkeys("\<Esc>q", 'xt')
  sleep 20m
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_advance_backspace()
  var t0 = Fresh()
  g:typing_on_error = 'advance'
  g:typing_history_min_keys = 1
  Origin(['abc'])
  TypingStart

  feedkeys('ax', 'xt')
  sleep 20m
  assert_equal(2, session.State().st.pos)
  assert_equal([1, 3], [line('.'), col('.')])
  feedkeys("\<BS>", 'xt')
  sleep 20m
  assert_equal(1, session.State().st.pos)
  feedkeys('bc', 'xt')
  sleep 20m

  var s = session.State()
  assert_equal('summary', s.phase)
  assert_equal(true, s.last_record.completed)
  assert_equal('advance', s.last_record.mode)
  assert_equal(1, s.last_record.errors)
  assert_equal(3, s.last_record.chars)
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_restart()
  var t0 = Fresh()
  g:typing_history_min_keys = 1000
  Origin(['abc'])
  TypingStart
  feedkeys('abc', 'xt')
  sleep 20m

  var before = session.State()
  assert_equal('summary', before.phase)
  feedkeys('r', 'xt')
  sleep 20m

  var s = session.State()
  assert_equal('typing', s.phase)
  assert_equal(0, s.st.pos)
  assert_equal(0, s.stats.keystrokes)
  assert_equal('', &t_ve)
  assert_equal(0.0, s.stats.elapsed)
  assert_equal(before.buf, s.buf)
  assert_equal(2, tabpagenr('$'))
  assert_true(s.status_id > 0)
  # The status popup and transparent lifecycle guard both remain active.
  assert_equal(2, len(popup_list()))

  feedkeys('abc', 'xt')
  sleep 20m
  assert_equal('summary', session.State().phase)
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_history_below_min_keys()
  var t0 = Fresh()
  g:typing_history_min_keys = 50
  Origin(['abc'])
  TypingStart
  feedkeys('abc', 'xt')
  sleep 20m

  var s = session.State()
  assert_equal('summary', s.phase)
  assert_false(s.last_saved)
  assert_equal(3, s.last_record.chars)
  assert_false(filereadable(g:typing_history_file))

  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_history_disabled()
  var t0 = Fresh()
  g:typing_history = false
  g:typing_history_min_keys = 1
  Origin(['abc'])
  TypingStart
  feedkeys('abc', 'xt')
  sleep 20m

  var s = session.State()
  assert_equal('summary', s.phase)
  assert_false(s.last_saved)
  assert_equal({}, s.last_record.missed)
  assert_false(filereadable(g:typing_history_file))
  # Without history there is nothing to compare against.
  assert_notmatch('Best WPM\|Last 10', join(s.last_summary, '\n'))

  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

# The summary compares with the sessions saved before this one.
def Test_history_comparison()
  var t0 = Fresh()
  g:typing_history_min_keys = 1
  var old: list<dict<any>> = [
    {time: localtime(), file: 'old.txt', line1: 1, line2: 1, duration: 60.0,
      chars: 300, wpm: 100.0, raw_wpm: 120.0, accuracy: 99.0, errors: 1,
      best_streak: 100, mode: 'stay', completed: true, missed: {}},
    {time: localtime(), file: 'older.txt', line1: 1, line2: 1, duration: 60.0,
      chars: 300, wpm: 90.0, raw_wpm: 110.0, accuracy: 98.0, errors: 2,
      best_streak: 80, mode: 'stay', completed: true, missed: {}}
  ]
  for rec in old
    assert_true(history.Append(g:typing_history_file, rec))
  endfor

  session.SetClock(FakeClock)
  Origin(['abcdef'])
  TypingStart
  for ch in ['a', 'b', 'c', 'd', 'e', 'f']
    feedkeys(ch, 'xt')
  sleep 20m
    fake_now += 1.0
  endfor

  var s = session.State()
  assert_equal('summary', s.phase)
  # Six keys one second apart: five seconds, 6 * 12 / 5 = 14.4 WPM.
  assert_equal(5.0, s.last_record.duration)
  assert_equal(14.4, s.last_record.wpm)
  var best_line = ''
  for line in s.last_summary
    if line =~# '^Best WPM'
      best_line = line
    endif
  endfor
  assert_true(best_line =~# '100\.0', best_line)
  assert_match('Last 10.*95.0 WPM, 98.5% accuracy', join(s.last_summary, '\n'))
  assert_equal(-1, index(s.last_summary, 'New best!'))
  assert_equal(3, len(history.Load(g:typing_history_file)))

  feedkeys('x', 'xt')
  sleep 20m
  session.SetClock(TestClock)
  CheckClean(t0)
enddef

def Test_nothing_to_type()
  var t0 = Fresh()
  enew!
  execute 'silent! %delete _'
  assert_equal([''], getline(1, '$'))
  TypingStart

  assert_equal('idle', session.State().phase)
  assert_equal(1, tabpagenr('$'))
  assert_equal([], popup_list())
  assert_match('nothing to type', execute('messages'))
  CheckClean(t0)
enddef

def Test_range()
  var t0 = Fresh()
  g:typing_history_min_keys = 1
  Origin(['one', 'two', 'three', 'four'])
  execute ':2,3TypingStart'

  var s = session.State()
  assert_equal('typing', s.phase)
  assert_equal(['two', 'three'], s.lines)
  assert_equal(['two', 'three'], getline(1, '$'))

  feedkeys('two three', 'xt')
  sleep 20m
  s = session.State()
  assert_equal('summary', s.phase)
  assert_equal(2, s.last_record.line1)
  assert_equal(3, s.last_record.line2)
  assert_equal(9, s.last_record.chars)

  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_start_twice()
  var t0 = Fresh()
  g:typing_history_min_keys = 1000
  Origin(['abc'])
  TypingStart
  var first = session.State()

  TypingStart
  var second = session.State()
  assert_equal('typing', second.phase)
  assert_equal(first.buf, second.buf)
  assert_equal(first.tabnr, second.tabnr)
  assert_equal(2, tabpagenr('$'))
  assert_equal(0, second.st.pos)
  assert_match('already active', execute('messages'))

  feedkeys('abc', 'xt')
  sleep 20m
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_plug_mappings()
  var t0 = Fresh()
  var normal = maparg('<Plug>(typing-start)', 'n')
  assert_true(normal =~# 'TypingStart', normal)
  var visual = maparg('<Plug>(typing-start)', 'x')
  assert_true(visual =~# 'TypingStart', visual)
  # No default key mapping is added for it.
  assert_equal('', maparg('<Leader>t', 'n'))
  CheckClean(t0)
enddef

# A Visual-mode selection practises only the selected lines, as the Visual
# <Plug> mapping does with its explicit '<,'> range.
def Test_visual_range()
  var t0 = Fresh()
  g:typing_history_min_keys = 1000
  Origin(['one', 'two', 'three'])
  cursor(2, 1)
  feedkeys("Vj\<Plug>(typing-start)", 'xt')
  sleep 20m

  var s = session.State()
  assert_equal('typing', s.phase)
  assert_equal(['two', 'three'], s.lines)
  feedkeys('two three', 'xt')
  sleep 20m
  assert_equal('summary', session.State().phase)
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_abort_on_leaving()
  var t0 = Fresh()
  g:typing_history_min_keys = 1
  &t_ve = 'ABORTVE'
  Origin(['abc'])
  TypingStart
  var practice = session.State().buf
  assert_equal('', &t_ve)
  feedkeys('a', 'xt')
  sleep 20m

  execute 'tabprevious'
  sleep 40m

  var s = session.State()
  assert_equal('idle', s.phase)
  assert_equal(1, tabpagenr('$'))
  assert_false(bufexists(practice))
  assert_equal('ABORTVE', &t_ve)
  assert_equal([], popup_list())

  var recs = history.Load(g:typing_history_file)
  assert_equal(1, len(recs))
  assert_equal(false, recs[0].completed)
  assert_equal(1, recs[0].chars)
  CheckClean(t0)
enddef

def Test_fake_clock()
  var t0 = Fresh()
  g:typing_history_min_keys = 1
  session.SetClock(FakeClock)
  Origin(['abc'])
  TypingStart
  fake_now = 100.0
  feedkeys('a', 'xt')
  sleep 20m
  fake_now = 101.0
  feedkeys('b', 'xt')
  sleep 20m
  fake_now = 102.0
  feedkeys('c', 'xt')
  sleep 20m

  var s = session.State()
  assert_equal('summary', s.phase)
  # Two one-second gaps, three characters: 3 * 12 / 2 = 18 WPM.
  assert_equal(2.0, s.last_record.duration)
  assert_equal(18.0, s.last_record.wpm)
  assert_equal(18.0, s.last_record.raw_wpm)
  assert_equal(100.0, s.last_record.accuracy)
  assert_equal(3, s.last_record.chars)

  feedkeys('x', 'xt')
  sleep 20m
  session.SetClock(TestClock)
  CheckClean(t0)
enddef

def Test_stop_paths()
  var t0 = Fresh()
  g:typing_history_min_keys = 1000
  Origin(['abc'])

  session.Stop()
  assert_match('no typing session', execute('messages'))
  assert_equal('idle', session.State().phase)

  TypingStart
  feedkeys('a', 'xt')
  sleep 20m
  session.Stop()
  assert_equal('summary', session.State().phase)
  assert_equal(false, session.State().last_record.completed)

  session.Stop()
  sleep 30m
  assert_equal('idle', session.State().phase)
  assert_equal(1, tabpagenr('$'))
  assert_equal([], popup_list())

  session.Stop()
  assert_equal('idle', session.State().phase)
  CheckClean(t0)
enddef

def Test_typing_history_view()
  var t0 = Fresh()
  assert_true(history.Append(g:typing_history_file, {
    time: localtime(), file: 'fixture.txt', line1: 1, line2: 2,
    duration: 42.0, chars: 120, wpm: 40.0, raw_wpm: 45.0, accuracy: 97.0,
    errors: 3, best_streak: 30, mode: 'stay', completed: true,
    missed: {e: 2}
  }))

  TypingHistory
  assert_equal('[Typing history]', bufname())
  var lines = getline(1, '$')
  assert_true(len(lines) > 2, string(lines))
  assert_match('fixture.txt', join(lines, "\n"))
  assert_true(&modifiable == false)
  silent! close

  CheckClean(t0)
enddef

# Exactly three physical lines, including indentation and a blank line.
def Test_three_lines()
  var t0 = Fresh()
  Origin(['  ab', '', 'c'])
  TypingStart
  assert_equal('', &t_ve)
  feedkeys("ab c", 'xt')
  sleep 20m
  assert_equal('summary', session.State().phase)
  assert_equal(4, session.State().last_record.chars)
  assert_equal('TESTVE', &t_ve)
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_wipe_and_missing_buffer()
  for missing in [false, true]
    var t0 = Fresh()
    g:typing_blink_ms = 10
    g:typing_history_min_keys = 1
    Origin(['abc'])
    TypingStart
    var b = session.State().buf
    feedkeys('x', 'xt')
    sleep 20m
    assert_equal('', &t_ve)
    if missing
      execute 'noautocmd bwipeout! ' .. b
      session.Stop()
      session.Stop()
    else
      execute 'bwipeout! ' .. b
    endif
    sleep 20m
    assert_false(bufexists(b))
    assert_equal(1, len(history.Load(g:typing_history_file)))
    CheckClean(t0)
  endfor
enddef

def Test_leave_window_and_summary()
  for summary in [false, true]
    var t0 = Fresh()
    Origin(['abc'])
    var ow = win_getid()
    var view = winsaveview()
    var options = [&l:wrap, &l:number, &l:scrolloff]
    &modified = true
    origin_state.modified = true
    TypingStart
    feedkeys(summary ? 'abc' : 'a', 'xt')
    sleep 20m
    win_gotoid(ow)
    sleep 20m
    assert_equal(view, winsaveview())
    assert_equal(options, [&l:wrap, &l:number, &l:scrolloff])
    CheckClean(t0)
  endfor
enddef

def Test_vim_leave_pre()
  var t0 = Fresh()
  g:typing_blink_ms = 10
  g:typing_history_min_keys = 1
  Origin(['abc'])
  TypingStart
  feedkeys('x', 'xt')
  sleep 20m
  assert_equal('', &t_ve)
  doautocmd VimLeavePre
  sleep 20m
  assert_equal(1, len(history.Load(g:typing_history_file)))
  CheckClean(t0)
enddef

def Test_pending_summary_stop()
  var t0 = Fresh()
  Origin(['abc'])
  TypingStart
  session.Stop()
  # Cancel summary creation before the event loop services its timer.
  session.Stop()
  session.Stop()
  sleep 20m
  CheckClean(t0)
enddef

def Test_history_threshold_counts_keys()
  var t0 = Fresh()
  g:typing_history_min_keys = 3
  Origin(['a'])
  TypingStart
  feedkeys('xxa', 'xt')
  sleep 20m
  var s = session.State()
  assert_true(s.last_saved)
  assert_equal(1, s.last_record.chars)
  assert_equal(2, s.last_record.errors)
  assert_equal(1, len(history.Load(g:typing_history_file)))
  feedkeys("\<C-c>", 'xt')
  sleep 20m
  CheckClean(t0)
enddef

def Test_start_failure()
  var t0 = Fresh()
  Origin(['abc'])
  # Fail after cursor hiding to exercise partial-start cleanup.
  session.SetClock((): float => str2float(eval('g:typing_missing_clock_value')))
  TypingStart
  sleep 20m
  session.SetClock(TestClock)
  CheckClean(t0)
enddef

def Test_settings_frozen_on_restart()
  var t0 = Fresh()
  g:typing_equivalents = {'é': 'e'}
  g:typing_history_min_keys = 2
  Origin(['éa'])
  TypingStart
  g:typing_equivalents['é'] = 'x'
  g:typing_on_error = 'advance'
  g:typing_history = false
  g:typing_history_min_keys = 100
  feedkeys('ea', 'xt')
  sleep 20m
  assert_true(session.State().last_saved)
  TypingStart
  assert_equal('summary', session.State().phase)
  feedkeys('r', 'xt')
  sleep 20m
  assert_equal('stay', session.State().st.on_error)
  assert_equal('', &t_ve)
  feedkeys('ea', 'xt')
  sleep 20m
  assert_true(session.State().last_saved)
  assert_equal(2, len(history.Load(g:typing_history_file)))
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

Test_stay_completion()
Test_wrong_key()
Test_wrong_key_bell()
Test_esc_midway()
Test_ctrl_c_midway()
Test_status_tick()
Test_advance_backspace()
Test_restart()
Test_history_below_min_keys()
Test_history_disabled()
Test_history_comparison()
Test_nothing_to_type()
Test_range()
Test_start_twice()
Test_plug_mappings()
Test_visual_range()
Test_abort_on_leaving()
Test_fake_clock()
Test_stop_paths()
Test_typing_history_view()

Test_three_lines()
Test_wipe_and_missing_buffer()
Test_leave_window_and_summary()
Test_vim_leave_pre()
Test_pending_summary_stop()
Test_history_threshold_counts_keys()
Test_start_failure()
Test_settings_frozen_on_restart()
ClearHistory()

# A single drained typeahead batch must never become Normal-mode commands.
# Esc pauses and q ends the session; the rest falls into the transition guard.
def Test_typeahead_escape()
  var t0 = Fresh()
  g:typing_summary_grace_ms = 10000
  var origin = Origin(['abcdef'])
  TypingStart
  var practice = session.State().buf
  feedkeys("abc\<Esc>q:ix\<Esc>", 'xt')
  sleep 20m
  assert_equal('', reg_recording(), 'typeahead escaped the popup key sink')
  assert_equal('n', mode())
  assert_equal('', getcmdwintype())
  assert_equal(['abcdef'], getbufline(practice, 1, '$'))
  assert_equal(['abcdef'], getbufline(origin, 1, '$'))
  assert_false(getbufvar(origin, '&modified'))
  assert_equal('summary', session.State().phase)
  assert_true(session.State().summary_id > 0)
  session.Stop()
  CheckClean(t0)
enddef

Test_typeahead_escape()

# Includes Ctrl-C while only the transition guard is filtering input.
def Test_typeahead_completion()
  for tail in ["rq:ix\<Esc>", "\<C-c>\<C-c>rq:ix\<Esc>"]
    var t0 = Fresh()
    g:typing_summary_grace_ms = 10000
    var origin = Origin(['abc'])
    TypingStart
    var practice = session.State().buf
    feedkeys('abc' .. tail, 'xt')
    sleep 20m
    assert_equal('', reg_recording())
    assert_equal('n', mode())
    assert_equal('', getcmdwintype())
    assert_equal(['abc'], getbufline(practice, 1, '$'))
    assert_equal(['abc'], getbufline(origin, 1, '$'))
    assert_false(getbufvar(origin, '&modified'))
    assert_equal('summary', session.State().phase)
    assert_equal(3, session.State().st.pos)
    assert_true(session.State().summary_id > 0)
    session.Stop()
    CheckClean(t0)
  endfor
enddef

def Test_summary_transition_batches()
  for action in ['x', 'r', "\<C-c>"]
    var t0 = Fresh()
    Origin(['abc'])
    TypingStart
    feedkeys('abc', 'xt')
    sleep 20m
    var practice = session.State().buf
    feedkeys(action .. "\<C-c>q:ix\<Esc>", 'xt')
    # Before the deferred tab close, the entire queued batch is swallowed.
    assert_equal(['abc'], getbufline(practice, 1, '$'))
    assert_equal('', reg_recording())
    assert_equal('', getcmdwintype())
    assert_equal('n', mode())
    sleep 20m
    if action == 'r'
      assert_equal('typing', session.State().phase)
      assert_equal(0, session.State().st.pos)
      session.Stop()
      session.Stop()
    endif
    CheckClean(t0)
    # Keys arriving AFTER the tab is fully closed are ordinary Vim input.
    feedkeys("iZ\<Esc>", 'xt')
    assert_equal(['Zabc'], getline(1, '$'))
    assert_true(&modified)
  endfor
enddef

def Test_summary_grace()
  for grace in [10000, 0, 60]
    var t0 = Fresh()
    g:typing_summary_grace_ms = grace
    Origin(['abc'])
    TypingStart
    # Settings are frozen at Start.
    g:typing_summary_grace_ms = 0
    feedkeys('abc', 'xt')
    sleep 20m
    if grace > 0
      feedkeys('rx', 'xt')
      sleep 5m
      assert_equal('summary', session.State().phase)
      assert_equal(3, session.State().st.pos)
      if grace == 10000
        feedkeys("\<C-c>q:ix\<Esc>", 'xt')
        sleep 20m
        assert_equal('summary', session.State().phase)
        assert_true(!empty(popup_getpos(session.State().summary_id)))
      else
        sleep 80m
        feedkeys('x', 'xt')
        sleep 20m
        assert_equal('idle', session.State().phase)
      endif
    else
      feedkeys('x', 'xt')
      sleep 20m
      assert_equal('idle', session.State().phase)
    endif
    if session.State().phase != 'idle'
      session.Stop()
    endif
    CheckClean(t0)
  endfor
enddef

Test_typeahead_completion()
Test_summary_transition_batches()
Test_summary_grace()

# The default is 500 ms, measured from appearance, with no extra grace timer.
def Test_summary_default_clock()
  var t0 = Fresh()
  unlet g:typing_summary_grace_ms
  session.SetClock(FakeClock)
  fake_now = 10.0
  Origin(['abc'])
  TypingStart
  feedkeys('abc', 'xt')
  sleep 20m
  fake_now = 10.499
  feedkeys('r', 'xt')
  sleep 20m
  assert_equal('summary', session.State().phase)
  assert_equal(3, session.State().st.pos)
  assert_equal([], timer_info())
  fake_now = 10.501
  feedkeys('x', 'xt')
  sleep 20m
  CheckClean(t0)
enddef

Test_summary_default_clock()
