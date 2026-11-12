vim9script
# Unit tests for autoload/typing/ui.vim (PLAN.md section 5.1).
# The formatting functions are pure; the popup tests drive real popups with
# feedkeys(..., 'xt') and a short sleep for the warning timer.

import autoload 'typing/ui.vim'
import autoload 'typing/stats.vim'

# Snapshot shape from stats.Snapshot, with overrides for each test.
def Snap(over: dict<any> = {}): dict<any>
  var s: dict<any> = {
    elapsed: 0.0, keystrokes: 0, correct: 0, errors: 0, accuracy: 100.0,
    raw_wpm: 0.0, wpm: 0.0, cpm: 0.0, streak: 0, best_streak: 0,
    pos: 0, total: 0, standing: 0, progress: 0.0, started: false,
    paused: false, finished: false
  }
  extend(s, over)
  return s
enddef

# Event shape returned by engine.Feed.
def Ev(kind: string, expected: string = '', typed: string = '',
    pos: number = 0, total: number = 0, standing: number = 0,
    done: bool = false): dict<any>
  return {
    kind: kind,
    changed: [],
    expected: expected,
    typed: typed,
    pos: pos,
    total: total,
    standing: standing,
    done: done
  }
enddef

def Correct(expected: string, pos: number, total: number,
    standing: number): dict<any>
  return Ev('correct', expected, expected, pos, total, standing)
enddef

def Wrong(expected: string, typed: string, pos: number, total: number,
    standing: number): dict<any>
  return Ev('wrong', expected, typed, pos, total, standing)
enddef

# Script-local popup callbacks. Tests reset the lists before using them.
var got_keys: list<string> = []
var closes: list<any> = []
var summary_keys: list<string> = []

def CollectKey(id: number, key: string): bool
  add(got_keys, key)
  return true
enddef

def CollectClose(id: number, result: any): void
  add(closes, result)
enddef

def CollectSummaryKey(key: string): void
  add(summary_keys, key)
enddef

def PopupText(id: number): list<string>
  return getbufline(winbufnr(id), 1, '$')
enddef

def CheckBottomRight(id: number, winid: number)
  var p = popup_getpos(id)
  var sp = win_screenpos(winid)
  assert_true(get(p, 'visible', 0) != 0, 'popup is visible')
  assert_equal(sp[0] + winheight(winid) - 1, p.line + p.height - 1,
    'popup bottom row')
  assert_equal(sp[1] + winwidth(winid) - 1, p.col + p.width - 1,
    'popup right column')
enddef

def Fresh()
  popup_clear()
  silent! only
  enew!
enddef

def Test_format_time()
  assert_equal('00:00', ui.FormatTime(0.0))
  assert_equal('00:59', ui.FormatTime(59.0))
  assert_equal('01:00', ui.FormatTime(60.0))
  assert_equal('01:23', ui.FormatTime(83.4))
  # Sub-second parts are truncated, not rounded up.
  assert_equal('01:23', ui.FormatTime(83.9))
  assert_equal('59:59', ui.FormatTime(3599.0))
  assert_equal('60:00', ui.FormatTime(3600.0))
  assert_equal('62:03', ui.FormatTime(3723.0))
  # Negative times have no meaning here.
  assert_equal('00:00', ui.FormatTime(-0.5))
  assert_equal('00:00', ui.FormatTime(-5.7))
enddef

def Test_status_text()
  var snap = Snap({
    elapsed: 83.4, wpm: 54.4, accuracy: 96.4, errors: 7, progress: 42.0,
    started: true
  })
  assert_equal('01:23  54 wpm  96.4%  7 err  42%', ui.StatusText(snap))

  snap.paused = true
  assert_equal('01:23  54 wpm  96.4%  7 err  42%  paused', ui.StatusText(snap))

  # Before the first keystroke every figure has its neutral value.
  var fresh = ui.StatusText(Snap())
  assert_equal('00:00  0 wpm  100.0%  0 err  0%', fresh)

  # Values are rounded: WPM and progress to integers, accuracy to one decimal.
  var rounded = Snap({
    elapsed: 1.0, wpm: 54.5, accuracy: 66.66, errors: 1, progress: 42.5,
    started: true
  })
  assert_equal('00:01  55 wpm  66.7%  1 err  43%', ui.StatusText(rounded))

  # An empty total keeps progress at zero and the text is still valid.
  var empty = Snap({started: true, paused: true})
  assert_equal('00:00  0 wpm  100.0%  0 err  0%  paused', ui.StatusText(empty))
enddef

def Test_key_name()
  assert_equal('e', ui.KeyName('e'))
  assert_equal('中', ui.KeyName('中'))
  assert_equal('“', ui.KeyName('“'))
  assert_equal('↵', ui.KeyName("\n"))
  assert_equal('↵', ui.KeyName("\r"))
  assert_equal('␣', ui.KeyName(' '))
  assert_equal('⇥', ui.KeyName("\t"))
  # Anything else is shown as it is.
  assert_equal("\<Esc>", ui.KeyName("\<Esc>"))
enddef

def Test_warn_text()
  assert_equal('✗ expected "e", typed "r"', ui.WarnText('e', 'r'))
  assert_equal('✗ expected "↵", typed "x"', ui.WarnText("\n", 'x'))
  assert_equal('✗ expected "␣", typed "⇥"', ui.WarnText(' ', "\t"))
  assert_equal('✗ expected "中", typed "“"', ui.WarnText('中', '“'))
enddef

def Test_summary_finished()
  var snap = Snap({
    elapsed: 83.4, keystrokes: 68, correct: 61, errors: 7,
    accuracy: 96.4, raw_wpm: 60.6, wpm: 54.4, cpm: 272.0,
    streak: 12, best_streak: 42, pos: 42, total: 100, standing: 42,
    progress: 42.0, started: true, finished: true
  })
  var top = [{char: 'e', misses: 4, attempts: 12,
    typed: [['r', 3], ['w', 1]]}]
  var hist = {count: 12, best_wpm: 60.0, avg_wpm: 51.2,
    avg_accuracy: 97.1, missed: []}
  assert_equal([
    'Typing finished',
    'Time            01:23',
    'WPM (net)       54.4',
    'Raw WPM         60.6',
    'CPM             272.0',
    'Accuracy        96.4%',
    'Keystrokes      68',
    'Errors          7',
    'Longest streak  42',
    'Characters      42/100  (42%)',
    'Most-missed keys',
    '  e  ×4 of 12  (typed r ×3, w ×1)',
    'Comparison',
    'Best WPM        60.0',
    'Last 10         51.2 WPM, 97.1% accuracy',
    '',
    'r  restart    any other key  close'
  ], ui.SummaryLines(snap, top, hist, true))
enddef

def Test_summary_stopped_early()
  var snap = Snap({
    elapsed: 600.0, keystrokes: 20, correct: 18, errors: 2,
    accuracy: 90.0, raw_wpm: 24.0, wpm: 70.0, cpm: 350.0,
    best_streak: 10, pos: 5, total: 10, standing: 5,
    progress: 50.0, started: true
  })
  var hist = {count: 3, best_wpm: 60.0, avg_wpm: 51.3,
    avg_accuracy: 97.1, missed: []}
  var lines = ui.SummaryLines(snap, [], hist, false)
  assert_equal([
    'Typing stopped early',
    'Time            10:00',
    'WPM (net)       70.0',
    'Raw WPM         24.0',
    'CPM             350.0',
    'Accuracy        90.0%',
    'Keystrokes      20',
    'Errors          2',
    'Longest streak  10',
    'Characters      5/10  (50%)',
    'Most-missed keys',
    '  no mistakes',
    'Comparison',
    'Best WPM        60.0',
    'Last 10         51.3 WPM, 97.1% accuracy',
    '',
    'r  restart    any other key  close'
  ], lines)
  # Not completed, so a higher WPM is not announced as a new best.
  assert_equal(-1, index(lines, 'New best!'))
enddef

def Test_summary_no_mistakes_and_no_history()
  var snap = Snap({
    elapsed: 5.0, keystrokes: 10, correct: 10, accuracy: 100.0,
    raw_wpm: 24.0, wpm: 24.0, cpm: 120.0, best_streak: 10,
    pos: 10, total: 10, standing: 10, progress: 100.0,
    started: true, finished: true
  })
  # {} must be treated as "no history".
  assert_equal([
    'Typing finished',
    'Time            00:05',
    'WPM (net)       24.0',
    'Raw WPM         24.0',
    'CPM             120.0',
    'Accuracy        100.0%',
    'Keystrokes      10',
    'Errors          0',
    'Longest streak  10',
    'Characters      10/10  (100%)',
    'Most-missed keys',
    '  no mistakes',
    '',
    'r  restart    any other key  close'
  ], ui.SummaryLines(snap, [], {}, true))
enddef

def Test_summary_new_best()
  # A finished session above the previous best gets the line; an equal one
  # does not (the comparison is strict).
  var base = Snap({
    elapsed: 60.0, keystrokes: 300, correct: 300, accuracy: 100.0,
    raw_wpm: 60.0, wpm: 60.5, cpm: 302.5, best_streak: 300,
    pos: 300, total: 300, standing: 300, progress: 100.0,
    started: true, finished: true
  })
  var hist = {count: 4, best_wpm: 60.0, avg_wpm: 51.3,
    avg_accuracy: 97.1, missed: []}
  var lines = ui.SummaryLines(base, [], hist, true)
  assert_true(index(lines, 'New best!') >= 0, 'new best line')

  var equal = Snap(extend(copy(base), {wpm: 60.0, cpm: 300.0}))
  var same = ui.SummaryLines(equal, [], hist, true)
  assert_equal(-1, index(same, 'New best!'))
enddef

def Test_summary_special_keys()
  var snap = Snap({started: true, finished: true})
  var top = [
    {char: "\n", misses: 2, attempts: 3, typed: [["\t", 1], [' ', 1]]},
    {char: '中', misses: 1, attempts: 2, typed: [['x', 1]]}
  ]
  var lines = ui.SummaryLines(snap, top, {}, true)
  var i = index(lines, 'Most-missed keys')
  assert_true(i >= 0, 'most-missed heading')
  assert_equal('  ↵  ×2 of 3  (typed ⇥ ×1, ␣ ×1)', lines[i + 1])
  assert_equal('  中  ×1 of 2  (typed x ×1)', lines[i + 2])
enddef

def Test_summary_real_stats()
  # A real stats snapshot: two correct keys and one wrong key in one second.
  var s = stats.New({total: 10})
  stats.Record(s, Correct('a', 1, 10, 1), 0.0)
  stats.Record(s, Wrong('b', 'x', 1, 10, 1), 0.5)
  stats.Record(s, Correct('b', 2, 10, 2), 1.0)
  var snap = stats.Snapshot(s, 1.0)

  assert_equal('00:01  24 wpm  66.7%  1 err  20%', ui.StatusText(snap))

  var lines = ui.SummaryLines(snap, stats.TopMissed(s), {}, true)
  assert_equal('Typing finished', lines[0])
  assert_equal('Time            00:01', lines[1])
  assert_equal('WPM (net)       24.0', lines[2])
  assert_equal('Raw WPM         36.0', lines[3])
  assert_equal('CPM             120.0', lines[4])
  assert_equal('Accuracy        66.7%', lines[5])
  assert_equal('Keystrokes      3', lines[6])
  assert_equal('Errors          1', lines[7])
  assert_equal('Longest streak  1', lines[8])
  assert_equal('Characters      2/10  (20%)', lines[9])
  assert_equal('  b  ×1 of 2  (typed x ×1)', lines[11])
enddef

def Test_open_status()
  Fresh()
  got_keys = []
  closes = []
  var winid = win_getid()
  var id = ui.OpenStatus(winid, CollectKey, CollectClose)
  assert_true(id > 0, 'popup id')

  var opts = popup_getoptions(id)
  assert_equal('TypingStatus', opts.highlight)
  assert_equal(0, opts.mapping)
  assert_equal([0, 1, 0, 1], opts.padding)
  assert_equal(0, opts.wrap)
  assert_equal('botright', opts.pos)
  assert_equal([''], PopupText(id))
  CheckBottomRight(id, winid)

  ui.SetStatus(id, 'hello')
  assert_equal(['hello'], PopupText(id))
  # A wider line keeps the popup's bottom-right corner in place.
  assert_equal(winid, win_getid())
  CheckBottomRight(id, winid)

  ui.CloseStatus(id)
  assert_true(empty(popup_getpos(id)), 'closed by CloseStatus')
  assert_equal([0], closes)
  popup_clear()
enddef

def Test_open_status_vsplit_and_reposition()
  Fresh()
  got_keys = []
  closes = []
  var first = win_getid()
  execute 'vsplit'
  var second = win_getid()
  assert_true(winwidth(first) < &columns, 'window is narrower after vsplit')

  var id = ui.OpenStatus(first, CollectKey, CollectClose)
  CheckBottomRight(id, first)

  # Move to the other (narrow) window, then to a resized one.
  ui.Reposition(id, second)
  CheckBottomRight(id, second)
  execute 'vertical resize 30'
  assert_equal(30, winwidth(second))
  ui.Reposition(id, second)
  CheckBottomRight(id, second)

  # A popup created directly for the narrow window lands there too.
  ui.CloseStatus(id)
  id = ui.OpenStatus(second, CollectKey, CollectClose)
  CheckBottomRight(id, second)
  assert_equal([0], closes)

  ui.CloseStatus(id)
  popup_clear()
  silent! only
enddef

def Test_status_keys_consumed()
  Fresh()
  setline(1, ['original text'])
  nnoremap <buffer> <silent> h :let b:ui_mapped = 1<CR>
  got_keys = []
  closes = []
  var winid = win_getid()
  var id = ui.OpenStatus(winid, CollectKey, CollectClose)

  feedkeys("ab\<CR>", 'xt')
  assert_equal(['a', 'b', "\r"], got_keys)
  assert_equal(['original text'], getline(1, '$'))
  assert_equal(0, exists('b:ui_mapped'))

  # mapping: false keeps the buffer-local mapping from expanding.
  feedkeys('h', 'xt')
  assert_equal(['a', 'b', "\r", 'h'], got_keys)
  assert_equal(0, exists('b:ui_mapped'))
  assert_equal(['original text'], getline(1, '$'))

  ui.CloseStatus(id)
  popup_clear()
  silent! only
enddef

def Test_status_ctrl_c()
  Fresh()
  got_keys = []
  closes = []
  var id = ui.OpenStatus(win_getid(), CollectKey, CollectClose)
  feedkeys("\<C-c>", 'xt')
  assert_equal([-1], closes)
  assert_true(empty(popup_getpos(id)), 'Ctrl-C closed the popup')

  # Closing again must not call the callback a second time.
  ui.CloseStatus(id)
  assert_equal([-1], closes)
  popup_clear()
enddef

def Test_close_status_safe_twice()
  Fresh()
  closes = []
  var winid = win_getid()
  var id = ui.OpenStatus(winid, CollectKey, CollectClose)
  ui.SetStatus(id, 'working')
  ui.CloseStatus(id)
  assert_equal([0], closes)
  assert_true(empty(popup_getpos(id)))

  ui.CloseStatus(id)
  assert_equal([0], closes)
  popup_clear()
enddef

def Test_warn_timer()
  Fresh()
  var id = ui.OpenStatus(win_getid(), CollectKey, CollectClose)
  ui.SetStatus(id, 'base status')
  assert_equal(['base status'], PopupText(id))

  ui.Warn(id, 'bad key', 80)
  assert_equal(['bad key'], PopupText(id))
  assert_equal('TypingStatusWarn', popup_getoptions(id).highlight)

  # A status update during the warning is remembered but not shown yet.
  ui.SetStatus(id, 'updated status')
  assert_equal(['bad key'], PopupText(id))

  sleep 200m
  assert_equal(['updated status'], PopupText(id))
  assert_equal('TypingStatus', popup_getoptions(id).highlight)

  ui.CloseStatus(id)
  popup_clear()
enddef

def Test_warn_replace_and_clear()
  Fresh()
  var id = ui.OpenStatus(win_getid(), CollectKey, CollectClose)
  ui.SetStatus(id, 'base')

  # The second warning replaces the first and cancels its timer.
  ui.Warn(id, 'first', 80)
  ui.Warn(id, 'second', 5000)
  assert_equal(['second'], PopupText(id))
  sleep 200m
  assert_equal(['second'], PopupText(id))
  assert_equal('TypingStatusWarn', popup_getoptions(id).highlight)

  ui.ClearWarn(id)
  assert_equal(['base'], PopupText(id))
  assert_equal('TypingStatus', popup_getoptions(id).highlight)

  # A status set while the warning is up is shown by ClearWarn too.
  ui.SetStatus(id, 'base2')
  ui.Warn(id, 'third', 5000)
  ui.SetStatus(id, 'base3')
  ui.ClearWarn(id)
  assert_equal(['base3'], PopupText(id))

  ui.CloseStatus(id)
  popup_clear()
enddef

def Test_status_functions_noop_after_close()
  Fresh()
  var winid = win_getid()
  var id = ui.OpenStatus(winid, CollectKey, CollectClose)
  ui.CloseStatus(id)

  # None of these may throw or resurrect the popup.
  ui.SetStatus(id, 'late status')
  ui.Warn(id, 'late warning', 10)
  ui.ClearWarn(id)
  ui.Reposition(id, winid)
  ui.CloseStatus(id)
  assert_equal([], popup_list())
  popup_clear()
enddef

def Test_summary_popup()
  Fresh()
  summary_keys = []
  var lines = ['Typing finished', 'WPM (net)  54.4', 'r  restart']
  var id = ui.ShowSummary(lines, CollectSummaryKey)
  assert_true(id > 0, 'summary popup id')
  assert_equal(lines, PopupText(id))

  var opts = popup_getoptions(id)
  assert_equal(' Typing practice ', opts.title)
  assert_equal(0, opts.mapping)
  assert_equal([1, 2, 1, 2], opts.padding)
  assert_equal([], opts.border)
  assert_equal('center', opts.pos)

  # Centred horizontally (within half a cell of the screen centre).
  var p = popup_getpos(id)
  assert_true(abs((p.col * 2 + p.width - 1) - (&columns + 1)) <= 2,
    'summary is centred')

  feedkeys('x', 'xt')
  assert_equal(['x'], summary_keys)
  assert_true(empty(popup_getpos(id)), 'summary closed on a key')
  popup_clear()
enddef

def Test_summary_keys()
  Fresh()
  summary_keys = []
  var lines = ['one', 'two']
  var id = ui.ShowSummary(lines, CollectSummaryKey)
  feedkeys('r', 'xt')
  assert_equal(['r'], summary_keys)
  assert_true(empty(popup_getpos(id)), 'r closed the summary')

  # A multi-byte key is passed through whole.
  summary_keys = []
  id = ui.ShowSummary(lines, CollectSummaryKey)
  feedkeys('中', 'xt')
  assert_equal(['中'], summary_keys)
  assert_true(empty(popup_getpos(id)), 'multi-byte key closed the summary')
  popup_clear()
enddef

def Test_summary_ctrl_c()
  Fresh()
  summary_keys = []
  var id = ui.ShowSummary(['one', 'two'], CollectSummaryKey)
  feedkeys("\<C-c>", 'xt')
  assert_equal(["\<C-c>"], summary_keys)
  assert_equal(1, len(summary_keys))
  assert_true(empty(popup_getpos(id)), 'Ctrl-C closed the summary')
  popup_clear()
enddef

Test_format_time()
Test_status_text()
Test_key_name()
Test_warn_text()
Test_summary_finished()
Test_summary_stopped_early()
Test_summary_no_mistakes_and_no_history()
Test_summary_new_best()
Test_summary_special_keys()
Test_summary_real_stats()
Test_open_status()
Test_open_status_vsplit_and_reposition()
Test_status_keys_consumed()
Test_status_ctrl_c()
Test_close_status_safe_twice()
Test_warn_timer()
Test_warn_replace_and_clear()
Test_status_functions_noop_after_close()
Test_summary_popup()
Test_summary_keys()
Test_summary_ctrl_c()

def Test_choice()
  for keys in ["\<CR>", "j\<CR>", "\<Esc>", "\<C-c>"]
    var picks: list<number> = []
    var id = ui.ShowChoice('Choose', ['Resume', 'Start over'],
      (pick: number) => {
        add(picks, pick)
      })
    feedkeys(keys, 'xt')
    sleep 20m
    assert_equal([keys == "\<CR>" ? 1 : keys == "j\<CR>" ? 2 : 0], picks)
    assert_equal({}, popup_getpos(id))
    popup_close(id)
    assert_equal(1, len(picks))
    assert_equal([], popup_list())
  endfor
enddef

def Test_summary_saved_position()
  var plain = ui.SummaryLines(Snap(), [], {}, false)
  var saved = 'Position saved: line 12 (37%)'
  var with_saved = ui.SummaryLines(Snap(), [], {}, false, saved)
  assert_equal(-1, index(plain, saved))
  assert_equal(1, count(with_saved, saved))
  assert_equal(plain, filter(with_saved, (_, line) => line != saved))
enddef

Test_choice()
Test_summary_saved_position()

# The paused hint names the four session keys and fits a narrow window.
def Test_paused_text()
  var text = ui.PausedText()
  assert_equal('PAUSED  move · Enter type here · Esc back · q finish', text)
  assert_true(strdisplaywidth(text) <= 66, string(strdisplaywidth(text)))
  for word in ['PAUSED', 'Enter', 'Esc', 'q finish']
    assert_match('\V' .. word, text)
  endfor
enddef

Test_paused_text()
