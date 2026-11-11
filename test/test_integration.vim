vim9script
g:typing_resume = 'never'
# Real engine events consumed by stats, with independently calculated figures.
import autoload 'typing/engine.vim'
import autoload 'typing/stats.vim'
import autoload 'typing/session.vim'
g:typing_history_file = tempname()

def CheckClean()
  assert_equal('idle', session.State().phase)
  assert_equal(1, tabpagenr('$'))
  assert_equal([], popup_list())
  assert_equal([], timer_info())
enddef

def Test_engine_stats_stay()
  var st = engine.Build(['  ab', '', 'c'])
  var s = stats.New()
  # Ignore an arrow, miss a, correct it, type b, cross the line, finish c.
  # The 8-second idle gap contributes nothing: elapsed = 1 + 1 + 0 + 2 = 4.
  var keys = ["\<Left>", 'x', 'a', 'b', "\n", 'c']
  var times = [0.0, 10.0, 11.0, 12.0, 20.0, 22.0]
  for i in range(len(keys))
    stats.Record(s, engine.Feed(st, keys[i]), times[i])
  endfor
  var snap = stats.Snapshot(s, 100.0)
  assert_equal({elapsed: 4.0, keystrokes: 5, correct: 4, errors: 1,
    accuracy: 80.0, raw_wpm: 15.0, wpm: 12.0, cpm: 60.0,
    streak: 4, best_streak: 4, pos: 4, total: 4, standing: 4,
    progress: 100.0, started: true, paused: false, finished: true}, snap)
  assert_equal('fixed', st.targets[0].state)
  assert_equal([{char: 'a', misses: 1, attempts: 2, typed: [['x', 1]]}],
    stats.TopMissed(s))
  assert_equal({a: 1}, stats.MissedCounts(s))
  CheckClean()
enddef

def Test_engine_stats_advance()
  var st = engine.Build(['abcd'], {on_error: 'advance'})
  var s = stats.New()
  # Backspace removes a correct target as well as a wrong one; neither counts
  # as a keystroke. Five judged keys, four correct, six seconds elapsed.
  var keys = ['a', 'x', "\<BS>", "\<BS>", 'a', 'b', 'c']
  for i in range(len(keys))
    stats.Record(s, engine.Feed(st, keys[i]), i * 1.0)
  endfor
  var snap = stats.Snapshot(s, 6.0)
  assert_equal(6.0, snap.elapsed)
  assert_equal(5, snap.keystrokes)
  assert_equal(4, snap.correct)
  assert_equal(1, snap.errors)
  assert_equal(80.0, snap.accuracy)
  assert_equal(10.0, snap.raw_wpm)
  assert_equal(6.0, snap.wpm)
  assert_equal(30.0, snap.cpm)
  assert_equal(3, snap.standing)
  assert_equal(3, snap.pos)
  assert_equal(4, snap.total)
  assert_equal(75.0, snap.progress)
  assert_equal(3, snap.best_streak)
  assert_false(snap.finished)
  assert_equal('fixed', st.targets[1].state)
  assert_equal({b: 1}, stats.MissedCounts(s))
  stats.Record(s, engine.Feed(st, 'd'), 8.0)
  snap = stats.Snapshot(s, 999.0)
  assert_equal(8.0, snap.elapsed)
  assert_equal(9.0, snap.raw_wpm)
  assert_equal(6.0, snap.wpm)
  assert_equal(100.0, snap.progress)
  assert_true(snap.finished)
  CheckClean()
enddef

Test_engine_stats_stay()
Test_engine_stats_advance()
