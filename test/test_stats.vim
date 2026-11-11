vim9script
# Unit tests for autoload/typing/stats.vim (PLAN.md sections 4 and 5.1).
# The stats module is pure and takes an injected clock. Events are built by hand
# from the shape documented for engine.Feed, so engine.vim is not imported.

import autoload 'typing/stats.vim'

const TOL = 1.0e-9

# Event shape returned by engine.Feed (PLAN.md section 5.1).
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

def Correct(expected: string, pos: number, total: number, standing: number,
    done: bool = false): dict<any>
  return Ev('correct', expected, expected, pos, total, standing, done)
enddef

def Wrong(expected: string, typed: string, pos: number, total: number,
    standing: number, done: bool = false): dict<any>
  return Ev('wrong', expected, typed, pos, total, standing, done)
enddef

# Floats must stay floats, so compare with a tolerance but reject other types.
def Near(got: any, want: float, label: string)
  if type(got) != v:t_float
    assert_true(false, $'{label}: not a float: {string(got)}')
    return
  endif
  assert_true(abs(got - want) <= TOL, $'{label}: want {want}, got {got}')
enddef

def Test_no_events_yet()
  var s = stats.New({total: 10})
  var snap = stats.Snapshot(s, 42.0)
  assert_equal(0.0, snap.elapsed)
  assert_equal(0, snap.keystrokes)
  assert_equal(0, snap.correct)
  assert_equal(0, snap.errors)
  assert_equal(100.0, snap.accuracy)
  assert_equal(0.0, snap.raw_wpm)
  assert_equal(0.0, snap.wpm)
  assert_equal(0.0, snap.cpm)
  assert_equal(0, snap.streak)
  assert_equal(0, snap.best_streak)
  assert_equal(0, snap.pos)
  assert_equal(10, snap.total)
  assert_equal(0, snap.standing)
  assert_equal(0.0, snap.progress)
  assert_false(snap.started, 'started before any event')
  assert_false(snap.paused, 'paused before any event')
  assert_false(snap.finished, 'finished before any event')
  assert_equal(['accuracy', 'best_streak', 'correct', 'cpm', 'elapsed',
    'errors', 'finished', 'keystrokes', 'paused', 'pos', 'progress',
    'raw_wpm', 'standing', 'started', 'streak', 'total', 'wpm'],
    sort(keys(snap)))

  # total defaults to 0, and progress is 0.0 without a denominator.
  var empty = stats.Snapshot(stats.New(), 1.0)
  assert_equal(0, empty.total)
  assert_equal(0.0, empty.progress)
enddef

def Test_single_keystroke()
  var s = stats.New({total: 10})
  stats.Record(s, Correct('a', 1, 10, 1), 100.0)
  var snap = stats.Snapshot(s, 100.0)
  assert_equal(0.0, snap.elapsed)
  assert_equal(1, snap.keystrokes)
  assert_equal(1, snap.correct)
  assert_equal(0, snap.errors)
  assert_equal(100.0, snap.accuracy)
  assert_equal(0.0, snap.raw_wpm)
  assert_equal(0.0, snap.wpm)
  assert_equal(0.0, snap.cpm)
  assert_equal(1, snap.streak)
  assert_equal(1, snap.best_streak)
  assert_equal(1, snap.pos)
  assert_equal(10, snap.total)
  assert_equal(1, snap.standing)
  assert_equal(10.0, snap.progress)
  assert_true(snap.started)
  assert_false(snap.paused)
  assert_false(snap.finished)

  # One second later the speed figures are defined and use the same clock.
  var one = stats.Snapshot(s, 101.0)
  assert_equal(1.0, one.elapsed)
  Near(one.raw_wpm, 12.0, 'raw_wpm after one second')
  Near(one.wpm, 12.0, 'wpm after one second')
  Near(one.cpm, 60.0, 'cpm after one second')
enddef

def Test_normal_run()
  var s = stats.New({total: 10})
  stats.Record(s, Correct('a', 1, 10, 1), 10.0)
  stats.Record(s, Correct('b', 2, 10, 2), 10.5)
  stats.Record(s, Wrong('c', 'x', 2, 10, 2), 11.5)
  stats.Record(s, Correct('c', 3, 10, 3), 12.0)
  stats.Record(s, Correct('d', 4, 10, 4), 13.0)
  stats.Record(s, Correct('e', 5, 10, 5), 13.5)
  var snap = stats.Snapshot(s, 13.5)
  assert_equal(3.5, snap.elapsed)
  assert_equal(6, snap.keystrokes)
  assert_equal(5, snap.correct)
  assert_equal(1, snap.errors)
  Near(snap.accuracy, 5 * 100.0 / 6, 'accuracy')
  Near(snap.raw_wpm, 6 * 60.0 / 5.0 / 3.5, 'raw_wpm')
  Near(snap.wpm, 5 * 60.0 / 5.0 / 3.5, 'wpm')
  Near(snap.cpm, 5 * 60.0 / 5.0 / 3.5 * 5.0, 'cpm')
  assert_equal(3, snap.streak)
  assert_equal(3, snap.best_streak)
  assert_equal(5, snap.pos)
  assert_equal(10, snap.total)
  assert_equal(5, snap.standing)
  assert_equal(50.0, snap.progress)
  assert_true(snap.started)
  assert_false(snap.paused)
  assert_false(snap.finished)

  # One wrong key on 'c', typed as 'x'.
  var top = stats.TopMissed(s)
  assert_equal(1, len(top))
  assert_equal('c', top[0].char)
  assert_equal(1, top[0].misses)
  assert_equal(2, top[0].attempts)
  assert_equal([['x', 1]], top[0].typed)
  assert_equal({'c': 1}, stats.MissedCounts(s))
enddef

def Test_idle_gap_excluded()
  var s = stats.New({total: 10})
  stats.Record(s, Correct('a', 1, 10, 1), 0.0)
  stats.Record(s, Wrong('b', 'x', 1, 10, 1), 20.0)
  # The 20 s gap is longer than idle_seconds (5) and is not counted.
  assert_equal(0.0, stats.Snapshot(s, 20.0).elapsed)
  stats.Record(s, Correct('b', 2, 10, 2), 21.0)
  # The 1 s gap after the excluded one is counted.
  assert_equal(1.0, stats.Snapshot(s, 21.0).elapsed)

  # The open gap follows the same rule.
  var open = stats.Snapshot(s, 30.0)
  assert_equal(1.0, open.elapsed)
  assert_true(open.paused, '9 s open gap pauses')
  var open_ok = stats.Snapshot(s, 25.0)
  assert_equal(5.0, open_ok.elapsed)
  assert_false(open_ok.paused)
enddef

def Test_gap_exactly_idle_counted()
  var s = stats.New({idle_seconds: 5.0})
  stats.Record(s, Correct('a', 1, 4, 1), 0.0)
  stats.Record(s, Correct('b', 2, 4, 2), 5.0)
  assert_equal(5.0, stats.Snapshot(s, 5.0).elapsed)
  # An open gap exactly equal to idle_seconds is still counted.
  assert_equal(10.0, stats.Snapshot(s, 10.0).elapsed)
  # A longer open gap is not, and it pauses the display.
  var over = stats.Snapshot(s, 10.5)
  assert_equal(5.0, over.elapsed)
  assert_true(over.paused)
enddef

def Test_custom_idle_seconds()
  var s = stats.New({idle_seconds: 2.0, total: 4})
  stats.Record(s, Correct('a', 1, 4, 1), 0.0)
  stats.Record(s, Correct('b', 2, 4, 2), 2.5)
  # 2.5 s > 2.0 s is excluded.
  assert_equal(0.0, stats.Snapshot(s, 2.5).elapsed)
  stats.Record(s, Correct('c', 3, 4, 3), 3.0)
  assert_equal(0.5, stats.Snapshot(s, 3.0).elapsed)
  assert_equal(1.5, stats.Snapshot(s, 4.0).elapsed)
  var paused = stats.Snapshot(s, 5.5)
  assert_equal(0.5, paused.elapsed)
  assert_true(paused.paused)

  # An integer option is accepted and compared as a float.
  var i = stats.New({idle_seconds: 2})
  stats.Record(i, Correct('a', 1, 4, 1), 0.0)
  stats.Record(i, Correct('b', 2, 4, 2), 3.0)
  assert_equal(0.0, stats.Snapshot(i, 3.0).elapsed)
enddef

def Test_clock_frozen_after_done()
  var s = stats.New({total: 2})
  stats.Record(s, Correct('a', 1, 2, 1), 0.0)
  stats.Record(s, Correct('b', 2, 2, 2, true), 1.0)
  var snap = stats.Snapshot(s, 1.0)
  assert_equal(1.0, snap.elapsed)
  assert_true(snap.finished)
  assert_equal(2, snap.keystrokes)
  assert_equal(100.0, snap.accuracy)
  assert_equal(100.0, snap.progress)

  var later = stats.Snapshot(s, 1000.0)
  assert_equal(1.0, later.elapsed)
  assert_false(later.paused)
  assert_true(later.finished)
  Near(later.wpm, 2 * 60.0 / 5.0 / 1.0, 'wpm after done')

  # A later ignored event changes nothing either.
  stats.Record(s, Ev('ignored'), 2000.0)
  assert_equal(1.0, stats.Snapshot(s, 2000.0).elapsed)
enddef

def Test_back_moves_clock_only()
  var s = stats.New({total: 2})
  stats.Record(s, Correct('a', 1, 2, 1), 0.0)
  stats.Record(s, Ev('back', '', '', 0, 2, 0), 2.0)
  stats.Record(s, Correct('a', 1, 2, 1), 3.0)
  var snap = stats.Snapshot(s, 3.0)
  assert_equal(3.0, snap.elapsed)
  assert_equal(2, snap.keystrokes)
  assert_equal(2, snap.correct)
  assert_equal(0, snap.errors)
  assert_equal(100.0, snap.accuracy)
  assert_equal(2, snap.streak)
  assert_equal(2, snap.best_streak)
  assert_equal(1, snap.pos)
  assert_equal(1, snap.standing)
  assert_equal(50.0, snap.progress)
  Near(snap.raw_wpm, 2 * 60.0 / 5.0 / 3.0, 'raw_wpm with a back key')
  Near(snap.wpm, 1 * 60.0 / 5.0 / 3.0, 'wpm with a back key')
  Near(snap.cpm, 1 * 60.0 / 5.0 / 3.0 * 5.0, 'cpm with a back key')

  # A back event is not a keystroke but it does start the clock.
  var b = stats.New()
  stats.Record(b, Ev('back', '', '', 0, 6, 0), 5.0)
  var bs = stats.Snapshot(b, 5.0)
  assert_true(bs.started)
  assert_equal(0.0, bs.elapsed)
  assert_equal(0, bs.keystrokes)
  assert_equal(100.0, bs.accuracy)
  assert_equal(0, bs.streak)
  assert_equal(1.0, stats.Snapshot(b, 6.0).elapsed)
enddef

def Test_ignored_changes_nothing()
  var s = stats.New({total: 5})
  # Even a malformed ignored event with other values and done set changes nothing.
  stats.Record(s, Ev('ignored', '', '', 99, 99, 99, true), 100.0)
  var snap = stats.Snapshot(s, 200.0)
  assert_false(snap.started)
  assert_equal(0.0, snap.elapsed)
  assert_equal(0, snap.keystrokes)
  assert_equal(0, snap.pos)
  assert_equal(5, snap.total)
  assert_equal(0, snap.standing)
  assert_equal(0.0, snap.progress)
  assert_false(snap.paused)
  assert_false(snap.finished)

  # The ignored event did not start the clock; the first key starts it later.
  stats.Record(s, Correct('a', 1, 5, 1), 300.0)
  var after = stats.Snapshot(s, 300.0)
  assert_true(after.started)
  assert_equal(0.0, after.elapsed)
  assert_equal(1, after.keystrokes)
  assert_equal(20.0, after.progress)
enddef

def Test_accuracy()
  var s = stats.New({total: 10})
  stats.Record(s, Correct('a', 1, 10, 1), 0.0)
  stats.Record(s, Correct('b', 2, 10, 2), 1.0)
  stats.Record(s, Wrong('c', 'x', 2, 10, 2), 2.0)
  stats.Record(s, Correct('c', 3, 10, 3), 3.0)
  stats.Record(s, Correct('d', 4, 10, 4), 4.0)
  var snap = stats.Snapshot(s, 4.0)
  assert_equal(5, snap.keystrokes)
  assert_equal(4, snap.correct)
  assert_equal(1, snap.errors)
  assert_equal(80.0, snap.accuracy)
enddef

def Test_raw_wpm_vs_wpm_vs_cpm()
  var s = stats.New({idle_seconds: 100.0, total: 10})
  stats.Record(s, Correct('a', 1, 10, 1), 0.0)
  stats.Record(s, Wrong('b', 'x', 1, 10, 1), 20.0)
  stats.Record(s, Correct('b', 2, 10, 2), 40.0)
  stats.Record(s, Correct('c', 3, 10, 3), 60.0)
  var snap = stats.Snapshot(s, 60.0)
  assert_equal(60.0, snap.elapsed)
  assert_equal(4, snap.keystrokes)
  assert_equal(3, snap.standing)
  assert_equal(75.0, snap.accuracy)
  # Keystrokes per minute over 5: 4 / 5 / 1 min = 0.8.
  Near(snap.raw_wpm, 0.8, 'raw_wpm')
  # Correct characters standing per minute over 5: 3 / 5 / 1 min = 0.6.
  Near(snap.wpm, 0.6, 'wpm')
  # CPM is net WPM times five.
  Near(snap.cpm, 3.0, 'cpm')
  assert_equal(3, snap.pos)
  assert_equal(10, snap.total)
  assert_equal(30.0, snap.progress)
enddef

def Test_streak_and_best_streak()
  var s = stats.New({total: 10})
  stats.Record(s, Correct('a', 1, 10, 1), 0.0)
  stats.Record(s, Correct('b', 2, 10, 2), 1.0)
  stats.Record(s, Correct('c', 3, 10, 3), 2.0)
  stats.Record(s, Wrong('d', 'x', 3, 10, 3), 3.0)
  stats.Record(s, Correct('d', 4, 10, 4), 4.0)
  stats.Record(s, Correct('e', 5, 10, 5), 5.0)
  stats.Record(s, Wrong('f', 'q', 5, 10, 5), 6.0)
  stats.Record(s, Correct('f', 6, 10, 6), 7.0)
  stats.Record(s, Correct('g', 7, 10, 7), 8.0)
  stats.Record(s, Correct('h', 8, 10, 8), 9.0)
  stats.Record(s, Correct('i', 9, 10, 9), 10.0)
  stats.Record(s, Correct('j', 10, 10, 10), 11.0)
  var snap = stats.Snapshot(s, 11.0)
  # Streaks: 3, then 2, then 5; the two wrong keys reset the current streak.
  assert_equal(5, snap.streak)
  assert_equal(5, snap.best_streak)
  assert_equal(12, snap.keystrokes)
  assert_equal(10, snap.correct)
  assert_equal(2, snap.errors)
  Near(snap.accuracy, 10 * 100.0 / 12, 'accuracy')
  assert_equal(100.0, snap.progress)
enddef

def Test_progress()
  var s = stats.New({total: 4})
  assert_equal(0.0, stats.Snapshot(s, 0.0).progress)
  stats.Record(s, Correct('a', 1, 4, 1), 0.0)
  assert_equal(25.0, stats.Snapshot(s, 0.0).progress)
  stats.Record(s, Correct('b', 2, 4, 2), 1.0)
  assert_equal(50.0, stats.Snapshot(s, 1.0).progress)
  stats.Record(s, Correct('c', 3, 4, 3), 2.0)
  assert_equal(75.0, stats.Snapshot(s, 2.0).progress)
  stats.Record(s, Correct('d', 4, 4, 4, true), 3.0)
  assert_equal(100.0, stats.Snapshot(s, 3.0).progress)

  # Progress is characters passed, not characters correct: in advance mode a
  # text finished with an uncorrected error still reaches 100%.
  var adv = stats.New({total: 2})
  stats.Record(adv, Wrong('a', 'x', 1, 2, 0), 0.0)
  assert_equal(50.0, stats.Snapshot(adv, 0.0).progress)
  stats.Record(adv, Correct('b', 2, 2, 1, true), 1.0)
  assert_equal(100.0, stats.Snapshot(adv, 1.0).progress)
enddef

# State with misses chosen to exercise every TopMissed tie-break:
# a: 3/4 (rate .75), b: 2/2 (1.0), c: 1/1 (1.0), d: 2/4 (.5), e: 0/3.
def MissState(): dict<any>
  var s = stats.New({total: 30})
  var t = 0.0
  stats.Record(s, Wrong('a', 'x', 0, 30, 0), t)
  t += 1.0
  stats.Record(s, Wrong('a', 'x', 0, 30, 0), t)
  t += 1.0
  stats.Record(s, Wrong('a', 'y', 0, 30, 0), t)
  t += 1.0
  stats.Record(s, Correct('a', 1, 30, 1), t)
  t += 1.0
  stats.Record(s, Wrong('b', 'z', 1, 30, 1), t)
  t += 1.0
  stats.Record(s, Wrong('b', 'z', 1, 30, 1), t)
  t += 1.0
  stats.Record(s, Wrong('c', 'w', 1, 30, 1), t)
  t += 1.0
  stats.Record(s, Wrong('d', 'q', 1, 30, 1), t)
  t += 1.0
  stats.Record(s, Wrong('d', 'r', 1, 30, 1), t)
  t += 1.0
  stats.Record(s, Correct('d', 2, 30, 2), t)
  t += 1.0
  stats.Record(s, Correct('d', 3, 30, 3), t)
  t += 1.0
  stats.Record(s, Correct('e', 4, 30, 4), t)
  t += 1.0
  stats.Record(s, Correct('e', 5, 30, 5), t)
  t += 1.0
  stats.Record(s, Correct('e', 6, 30, 6), t)
  return s
enddef

def Test_top_missed_ordering()
  var top = stats.TopMissed(MissState(), 5)
  assert_equal(4, len(top))
  var chars: list<string> = []
  for e in top
    add(chars, e.char)
  endfor
  # Misses descending, then rate descending (b 1.0 before d 0.5), then char.
  assert_equal(['a', 'b', 'd', 'c'], chars)
  assert_equal(['attempts', 'char', 'misses', 'typed'], sort(keys(top[0])))
  assert_equal('a', top[0].char)
  assert_equal(3, top[0].misses)
  assert_equal(4, top[0].attempts)
  assert_equal([['x', 2], ['y', 1]], top[0].typed)
  assert_equal('b', top[1].char)
  assert_equal(2, top[1].misses)
  assert_equal(2, top[1].attempts)
  assert_equal([['z', 2]], top[1].typed)
  assert_equal('d', top[2].char)
  assert_equal(2, top[2].misses)
  assert_equal(4, top[2].attempts)
  assert_equal([['q', 1], ['r', 1]], top[2].typed)
  assert_equal('c', top[3].char)
  assert_equal(1, top[3].misses)
  assert_equal(1, top[3].attempts)
  assert_equal([['w', 1]], top[3].typed)
enddef

def Test_top_missed_limit()
  var s = MissState()
  var two = stats.TopMissed(s, 2)
  assert_equal(2, len(two))
  assert_equal('a', two[0].char)
  assert_equal('b', two[1].char)
  assert_equal(0, len(stats.TopMissed(s, 0)))
  assert_equal(4, len(stats.TopMissed(s, 10)))
  # The default limit is 5; only four characters have a miss.
  assert_equal(4, len(stats.TopMissed(s)))
enddef

def Test_top_missed_char_tiebreak()
  var s = stats.New({total: 20})
  var t = 0.0
  # p and o both miss twice in four attempts: equal misses, equal rate.
  stats.Record(s, Wrong('p', 'x', 0, 20, 0), t)
  t += 1.0
  stats.Record(s, Wrong('p', 'y', 0, 20, 0), t)
  t += 1.0
  stats.Record(s, Correct('p', 1, 20, 1), t)
  t += 1.0
  stats.Record(s, Correct('p', 2, 20, 2), t)
  t += 1.0
  stats.Record(s, Wrong('o', 'x', 2, 20, 2), t)
  t += 1.0
  stats.Record(s, Wrong('o', 'y', 2, 20, 2), t)
  t += 1.0
  stats.Record(s, Correct('o', 3, 20, 3), t)
  t += 1.0
  stats.Record(s, Correct('o', 4, 20, 4), t)
  var top = stats.TopMissed(s, 5)
  assert_equal(2, len(top))
  # The character name breaks the tie, ascending.
  assert_equal('o', top[0].char)
  assert_equal('p', top[1].char)
enddef

def Test_missed_counts()
  var counts = stats.MissedCounts(MissState())
  assert_equal({'a': 3, 'b': 2, 'c': 1, 'd': 2}, counts)
  assert_false(has_key(counts, 'e'))
  assert_equal({}, stats.MissedCounts(stats.New()))
enddef

Test_no_events_yet()
Test_single_keystroke()
Test_normal_run()
Test_idle_gap_excluded()
Test_gap_exactly_idle_counted()
Test_custom_idle_seconds()
Test_clock_frozen_after_done()
Test_back_moves_clock_only()
Test_ignored_changes_nothing()
Test_accuracy()
Test_raw_wpm_vs_wpm_vs_cpm()
Test_streak_and_best_streak()
Test_progress()
Test_top_missed_ordering()
Test_top_missed_limit()
Test_top_missed_char_tiebreak()
Test_missed_counts()
