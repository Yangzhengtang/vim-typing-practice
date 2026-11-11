vim9script
# Tests for autoload/typing/history.vim (PLAN.md sections 4 and 5.1).
# Only files under tempname() are read or written: the real history file is
# private user data and must never be touched by the tests.

import autoload 'typing/history.vim'

const TOL = 1.0e-9

# A complete record, as appended by a session (PLAN.md section 5.1).
def Rec(over: dict<any> = {}): dict<any>
  var rec: dict<any> = {
    time: 1700000000,
    file: 'notes.txt',
    line1: 1,
    line2: 3,
    duration: 60.0,
    chars: 300,
    wpm: 60.0,
    raw_wpm: 65.0,
    accuracy: 95.0,
    errors: 5,
    best_streak: 20,
    mode: 'stay',
    completed: true,
    missed: {}
  }
  extend(rec, over)
  return rec
enddef

# Floats must stay floats, so compare with a tolerance but reject other types.
def Near(got: any, want: float, label: string)
  if type(got) != v:t_float
    assert_true(false, $'{label}: not a float: {string(got)}')
    return
  endif
  assert_true(abs(got - want) <= TOL, $'{label}: want {want}, got {got}')
enddef

def FindLine(lines: list<string>, needle: string): number
  var i = 0
  for line in lines
    if stridx(line, needle) >= 0
      return i
    endif
    i += 1
  endfor
  return -1
enddef

def TrendLine(lines: list<string>): string
  for line in lines
    if stridx(line, 'WPM trend:') == 0
      return line
    endif
  endfor
  return ''
enddef

def Test_default_file()
  var saved = g:typing_history_file
  unlet g:typing_history_file
  var want = expand('~/.vim/typing-practice/history.jsonl')
  assert_equal(want, history.DefaultFile())

  var override = tempname() .. '.jsonl'
  g:typing_history_file = override
  assert_equal(override, history.DefaultFile())
  remove(g:, 'typing_history_file')
  assert_equal(want, history.DefaultFile())
  g:typing_history_file = saved
enddef

def Test_append_creates_dirs_and_one_line_per_call()
  var root = tempname()
  var file = root .. '/nested/deep/history.jsonl'
  var first = Rec({file: 'a.txt', wpm: 10.5})
  var second = Rec({file: 'b.txt', wpm: 20, completed: false})

  assert_true(history.Append(file, first))
  assert_true(history.Append(file, second))
  assert_true(filereadable(file), 'history file was not created')

  var lines = readfile(file)
  assert_equal(2, len(lines), 'one JSON line per Append')
  for line in lines
    assert_equal(v:t_dict, type(json_decode(line)), 'line is not a JSON object')
  endfor
  assert_equal(first, json_decode(lines[0]))
  assert_equal(second, json_decode(lines[1]))
  delete(root, 'rf')
enddef

def Test_append_failure_returns_false()
  var root = tempname()
  writefile(['a regular file, not a directory'], root)
  var target = root .. '/history.jsonl'
  var ok = true
  try
    ok = history.Append(target, Rec())
  catch
    assert_true(false, 'Append threw: ' .. v:exception)
    delete(root)
    return
  endtry
  assert_false(ok, 'Append should fail when the parent is a regular file')
  delete(root)
enddef

def Test_load_missing_file()
  var file = tempname() .. '/does-not-exist.jsonl'
  assert_equal([], history.Load(file))
enddef

def Test_load_skips_bad_lines()
  var file = tempname()
  writefile(['{"a": 1}', '', '   ', 'not json', '[1, 2]', '"text"',
    '42', '{"b": 2}', '{"c": '], file)
  try
    assert_equal([{'a': 1}, {'b': 2}], history.Load(file))
  finally
    delete(file)
  endtry
enddef

def Test_roundtrip_all_keys()
  var file = tempname()
  var rec = Rec({
    file: '日本語 notes.txt',
    duration: 12.5,
    wpm: 54,
    raw_wpm: 61.25,
    accuracy: 96.4,
    missed: {"\n": 2, ' ': 3, 'é': 1, '中': 4}
  })
  assert_true(history.Append(file, rec))
  var got = history.Load(file)
  assert_equal(1, len(got))
  assert_equal(sort(keys(rec)), sort(keys(got[0])), 'all record keys survive')
  assert_equal(rec, got[0])
  assert_equal('日本語 notes.txt', got[0].file)
  assert_equal(12.5, got[0].duration)
  assert_equal(54, got[0].wpm)
  assert_equal(96.4, got[0].accuracy)
  assert_equal({"\n": 2, ' ': 3, 'é': 1, '中': 4}, got[0].missed)
  delete(file)
enddef

def Test_summarize_empty()
  var s = history.Summarize([])
  assert_equal(['avg_accuracy', 'avg_wpm', 'best_wpm', 'count', 'missed'],
    sort(keys(s)))
  assert_equal(0, s.count)
  Near(s.best_wpm, 0.0, 'best_wpm')
  Near(s.avg_wpm, 0.0, 'avg_wpm')
  Near(s.avg_accuracy, 0.0, 'avg_accuracy')
  assert_equal([], s.missed)
enddef

def Test_summarize_fewer_than_ten()
  # Mixed Number and Float values, as json_decode can produce.
  var s = history.Summarize([
    Rec({wpm: 30, accuracy: 90}),
    Rec({wpm: 60.0, accuracy: 80.0}),
    Rec({wpm: 90, accuracy: 70})
  ])
  assert_equal(3, s.count)
  Near(s.best_wpm, 90.0, 'best_wpm')
  Near(s.avg_wpm, 60.0, 'avg_wpm')
  Near(s.avg_accuracy, 80.0, 'avg_accuracy')
  assert_equal([], s.missed)
enddef

def Test_summarize_more_than_ten()
  var records: list<dict<any>> = []
  var i = 1
  while i <= 12
    add(records, Rec({wpm: i, accuracy: i <= 2 ? 0 : 100}))
    i += 1
  endwhile
  var s = history.Summarize(records)
  assert_equal(12, s.count)
  Near(s.best_wpm, 12.0, 'best_wpm is over all records')
  # The last ten records have wpm 3..12 and accuracy 100.
  Near(s.avg_wpm, 7.5, 'avg_wpm uses the last ten')
  Near(s.avg_accuracy, 100.0, 'avg_accuracy uses the last ten')
enddef

def Test_summarize_tolerates_missing_keys()
  var s = history.Summarize([{'wpm': 50}, {}, {'accuracy': 80.0}])
  assert_equal(3, s.count)
  Near(s.best_wpm, 50.0, 'best_wpm')
  Near(s.avg_wpm, 50.0 / 3.0, 'avg_wpm with missing keys')
  Near(s.avg_accuracy, 80.0 / 3.0, 'avg_accuracy with missing keys')
  assert_equal([], s.missed)
enddef

def Test_summarize_missed_top_five()
  var s = history.Summarize([
    Rec({missed: {'e': 3, 'a': 1}}),
    Rec({missed: {'e': 2, ' ': 4, "\n": 5}}),
    Rec({missed: {'z': 1, 'a': 2, 'q': 1}})
  ])
  # Summed: \n 5, e 5, space 4, a 3, q 1, z 1. Ties sort by char ascending,
  # so the top five stop before z.
  assert_equal([["\n", 5], ['e', 5], [' ', 4], ['a', 3], ['q', 1]], s.missed)
enddef

def Test_lines_empty()
  var lines = history.Lines([])
  assert_equal(1, len(lines))
  assert_true(stridx(lines[0], 'No history yet') >= 0, lines[0])
enddef

def Test_lines_rows_newest_first()
  var records = [
    Rec({time: 1700000000, file: 'old.txt', duration: 83.0, wpm: 10,
      raw_wpm: 12, accuracy: 90.0, errors: 2, best_streak: 7, mode: 'stay'}),
    Rec({time: 1700003600, file: 'mid.txt', duration: 100.0, wpm: 20,
      raw_wpm: 22, accuracy: 92.5, errors: 3, best_streak: 9, mode: 'stay'}),
    Rec({time: 1700007200, file: 'new.txt', duration: 125.0, wpm: 30,
      raw_wpm: 33, accuracy: 96.4, errors: 4, best_streak: 12,
      mode: 'advance', completed: false})
  ]
  var lines = history.Lines(records)
  assert_equal('Typing history', lines[0])

  var header = lines[1]
  for column in ['Date', 'File', 'Time', 'WPM', 'Raw', 'Acc%', 'Err', 'Streak',
      'Mode', 'State']
    assert_true(stridx(header, column) >= 0, 'header is missing ' .. column)
  endfor

  var iold = FindLine(lines, 'old.txt')
  var imid = FindLine(lines, 'mid.txt')
  var inew = FindLine(lines, 'new.txt')
  assert_true(iold > 0 && imid > 0 && inew > 0, 'a session row is missing')
  assert_true(inew < imid && imid < iold, 'rows are not newest first')

  assert_true(stridx(lines[iold], strftime('%Y-%m-%d %H:%M', 1700000000)) == 0)
  assert_true(stridx(lines[iold], '01:23') >= 0, 'duration as MM:SS')
  assert_true(stridx(lines[iold], '90.0%') >= 0, 'accuracy percent')
  assert_true(stridx(lines[iold], 'stay') >= 0, 'mode')
  assert_true(stridx(lines[inew], '96.4%') >= 0)
  assert_true(stridx(lines[inew], '02:05') >= 0)

  # The unfinished session is marked, the finished ones are not.
  assert_true(stridx(lines[inew], 'unfinished') >= 0)
  assert_true(stridx(lines[iold], 'done') >= 0)
  assert_true(stridx(lines[iold], 'unfinished') < 0)
enddef

def Test_lines_limit()
  var records: list<dict<any>> = []
  var i = 1
  while i <= 5
    add(records, Rec({time: 1700000000 + i * 60, file: $'f{i}.txt',
      wpm: i * 10}))
    i += 1
  endwhile
  var lines = history.Lines(records, 2)
  assert_true(FindLine(lines, 'f5.txt') >= 0)
  assert_true(FindLine(lines, 'f4.txt') >= 0)
  assert_equal(-1, FindLine(lines, 'f3.txt'))
  assert_equal(-1, FindLine(lines, 'f1.txt'))
  var trend = TrendLine(lines)
  assert_equal(2, strchars(strpart(trend, len('WPM trend: '))))
enddef

def Test_lines_totals_and_missed()
  var lines = history.Lines([
    Rec({wpm: 40.0, accuracy: 90.0, missed: {'e': 3, ' ': 2}}),
    Rec({wpm: 60.0, accuracy: 80.0, missed: {"\n": 1, 'e': 1}})
  ])
  var totals = lines[FindLine(lines, 'Sessions:')]
  assert_true(stridx(totals, 'Sessions: 2') == 0, totals)
  assert_true(stridx(totals, 'Best WPM: 60.0') >= 0, totals)
  assert_true(stridx(totals, '50.0 WPM') >= 0, totals)
  assert_true(stridx(totals, '85.0% accuracy') >= 0, totals)

  var missed = lines[FindLine(lines, 'Most missed:')]
  assert_true(stridx(missed, 'e ×4') >= 0, missed)
  assert_true(stridx(missed, '␣ ×2') >= 0, missed)
  assert_true(stridx(missed, '↵ ×1') >= 0, missed)
  # Most missed comes before the less frequent ones.
  assert_true(stridx(missed, 'e ×4') < stridx(missed, '␣ ×2'))
enddef

def Test_lines_sparkline_rising()
  var records = [Rec({wpm: 10}), Rec({wpm: 20}), Rec({wpm: 30}),
    Rec({wpm: 40})]
  assert_equal('WPM trend: ▁▃▆█', TrendLine(history.Lines(records)))
enddef

def Test_lines_sparkline_flat()
  var records = [Rec({wpm: 50}), Rec({wpm: 50}), Rec({wpm: 50})]
  assert_equal('WPM trend: ▄▄▄', TrendLine(history.Lines(records)))
enddef

def Test_lines_sparkline_single()
  assert_equal('WPM trend: ▄', TrendLine(history.Lines([Rec({wpm: 50})])))
enddef

def Test_lines_multibyte_alignment()
  # Durations chosen so the strings cannot occur in a HH:MM date.
  var records = [
    Rec({time: 1700000000, file: '日本語.txt', duration: 3599.0}),
    Rec({time: 1700000060, file: 'plain.txt', duration: 3598.0})
  ]
  var lines = history.Lines(records)
  var wide = lines[FindLine(lines, '日本語.txt')]
  var plain = lines[FindLine(lines, 'plain.txt')]
  var header = lines[1]

  var wide_col = strdisplaywidth(strpart(wide, 0, stridx(wide, '59:59')))
  var plain_col = strdisplaywidth(strpart(plain, 0, stridx(plain, '59:58')))
  var header_col = strdisplaywidth(strpart(header, 0, stridx(header, 'Time')))
  assert_equal(wide_col, plain_col, 'multi-byte file name shifts the columns')
  assert_equal(wide_col, header_col, 'header is not aligned with the rows')
enddef

def Test_show_scratch_buffer()
  var file = tempname()
  writefile([json_encode(Rec({file: 'shown.txt', wpm: 42.0}))], file)
  setline(1, ['original text'])
  set nomodified
  var orig_buf = bufnr('%')
  var orig_win = win_getid()
  var wins_before = winnr('$')
  try
    history.Show(file)
    assert_equal(wins_before + 1, winnr('$'), 'Show did not split the window')
    assert_equal('[Typing history]', bufname('%'))
    assert_equal('nofile', &buftype)
    assert_equal('wipe', &bufhidden)
    assert_false(&swapfile)
    assert_false(&buflisted)
    assert_false(&modifiable)
    assert_equal('Typing history', getline(1))
    assert_true(FindLine(getline(1, '$'), 'shown.txt') >= 0)

    var mapping = maparg('q', 'n', false, true)
    assert_equal(1, get(mapping, 'buffer', 0), 'q is not buffer-local')
    assert_true(stridx(get(mapping, 'rhs', ''), 'close') >= 0,
      'q does not close the window')

    # The original buffer and window are untouched.
    assert_equal(['original text'], getbufline(orig_buf, 1, '$'))
    assert_false(getbufvar(orig_buf, '&modified'))

    execute 'normal q'
    assert_equal(wins_before, winnr('$'), 'q did not close the history window')
    assert_equal(orig_win, win_getid())
    assert_equal(orig_buf, bufnr('%'))
  finally
    if winnr('$') > wins_before
      execute 'close'
    endif
    delete(file)
  endtry
enddef

def Test_show_uses_default_file()
  var saved = g:typing_history_file
  var file = tempname()
  writefile([json_encode(Rec({file: 'default-path.txt'}))], file)
  g:typing_history_file = file
  setline(1, ['unchanged'])
  var wins_before = winnr('$')
  try
    history.Show()
    assert_equal('[Typing history]', bufname('%'))
    assert_true(FindLine(getline(1, '$'), 'default-path.txt') >= 0)
    execute 'close'
  finally
    g:typing_history_file = saved
    if winnr('$') > wins_before
      execute 'close'
    endif
    delete(file)
  endtry
enddef

def Test_show_twice_reuses_window()
  var first = tempname()
  var second = tempname()
  writefile([json_encode(Rec({file: 'first.txt'}))], first)
  writefile([json_encode(Rec({file: 'second.txt'}))], second)
  setline(1, ['keep me'])
  var wins_before = winnr('$')
  try
    history.Show(first)
    var bnr = bufnr('%')
    assert_true(FindLine(getline(1, '$'), 'first.txt') >= 0)

    history.Show(second)
    assert_equal(bnr, bufnr('%'), 'Show replaced the buffer instead of reusing it')
    assert_equal(wins_before + 1, winnr('$'), 'Show opened a second window')
    assert_equal('[Typing history]', bufname('%'))
    assert_true(FindLine(getline(1, '$'), 'second.txt') >= 0)
    assert_equal(-1, FindLine(getline(1, '$'), 'first.txt'))
    assert_false(&modifiable)

    execute 'close'
    assert_equal(wins_before, winnr('$'))
  finally
    if winnr('$') > wins_before
      execute 'close'
    endif
    delete(first)
    delete(second)
  endtry
enddef

Test_default_file()
Test_append_creates_dirs_and_one_line_per_call()
Test_append_failure_returns_false()
Test_load_missing_file()
Test_load_skips_bad_lines()
Test_roundtrip_all_keys()
Test_summarize_empty()
Test_summarize_fewer_than_ten()
Test_summarize_more_than_ten()
Test_summarize_tolerates_missing_keys()
Test_summarize_missed_top_five()
Test_lines_empty()
Test_lines_rows_newest_first()
Test_lines_limit()
Test_lines_totals_and_missed()
Test_lines_sparkline_rising()
Test_lines_sparkline_flat()
Test_lines_sparkline_single()
Test_lines_multibyte_alignment()
Test_show_scratch_buffer()
Test_show_uses_default_file()
Test_show_twice_reuses_window()
