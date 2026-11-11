vim9script
# Unit tests for autoload/typing/engine.vim (PLAN.md section 5.1).
# Pure logic only: no window, buffer or popup is involved.

import autoload 'typing/engine.vim'

def FeedAll(st: dict<any>, keys: list<string>): list<dict<any>>
  var evs: list<dict<any>> = []
  for k in keys
    add(evs, engine.Feed(st, k))
  endfor
  return evs
enddef

def States(st: dict<any>): list<string>
  return mapnew(st.targets, (_, t) => t.state)
enddef

def Chars(st: dict<any>): list<string>
  return mapnew(st.targets, (_, t) => t.char)
enddef

def Cols(st: dict<any>): list<number>
  return mapnew(st.targets, (_, t) => t.col)
enddef

def Lens(st: dict<any>): list<number>
  return mapnew(st.targets, (_, t) => t.len)
enddef

def Test_default_equivalents()
  assert_equal({
    "\u2019": "'",
    "\u2018": "'",
    "\u201c": '"',
    "\u201d": '"',
    "\u2013": '-',
    "\u2014": '-',
    "\u2026": '.',
    "\u00a0": ' '
  }, engine.DefaultEquivalents())
  assert_equal(8, len(engine.DefaultEquivalents()))
enddef

def Test_indent_skipped_but_counted_in_columns()
  var st = engine.Build(['  ab', "\tcd"])
  assert_equal(['a', 'b', "\n", 'c', 'd'], Chars(st))
  assert_equal([3, 4, 5, 2, 3], Cols(st))
  assert_equal([1, 1, 1, 2, 2], mapnew(st.targets, (_, t) => t.lnum))
  assert_equal(5, len(st.targets))
  assert_equal(0, st.pos)
  assert_equal(0, st.standing)
  assert_false(st.done)
enddef

def Test_trailing_whitespace_ignored()
  var st = engine.Build(['ab  ', '   '])
  assert_equal(['a', 'b'], Chars(st))
  assert_equal(2, len(st.targets))
  # The break of a line goes just after its last non-blank character.
  st = engine.Build(['ab   ', 'c'])
  assert_equal(['a', 'b', "\n", 'c'], Chars(st))
  assert_equal([1, 2, 3, 1], Cols(st))
enddef

def Test_blank_lines_skipped()
  var st = engine.Build(['', '   ', "\t", 'x', ''])
  assert_equal(['x'], Chars(st))
  assert_equal([4], mapnew(st.targets, (_, t) => t.lnum))
  assert_equal(1, len(st.targets))
  assert_false(st.done)
enddef

def Test_breaks_between_lines_only()
  var st = engine.Build(['a', 'b', 'c'])
  assert_equal(['a', "\n", 'b', "\n", 'c'], Chars(st))
  assert_equal(['char', 'break', 'char', 'break', 'char'],
    mapnew(st.targets, (_, t) => t.kind))
  assert_equal([1, 1, 2, 2, 3], mapnew(st.targets, (_, t) => t.lnum))
  assert_equal([1, 2, 1, 2, 1], Cols(st))
  assert_equal([1, 0, 1, 0, 1], Lens(st))
  assert_equal(["\r", ' '], st.targets[1].accept)
  # Blank lines between content do not add breaks.
  st = engine.Build(['a', '', '   ', 'b'])
  assert_equal(['a', "\n", 'b'], Chars(st))
enddef

def Test_line_end_values()
  var st = engine.Build(['a', 'b'])
  assert_equal(["\r", ' '], st.targets[1].accept)
  assert_equal('correct', engine.Feed(st, 'a').kind)
  assert_equal('correct', engine.Feed(st, ' ').kind)
  assert_equal(2, st.pos)
  assert_equal('correct', engine.Feed(st, 'b').kind)
  assert_true(st.done)

  st = engine.Build(['a', 'b'], {line_end: 'enter'})
  assert_equal(["\r"], st.targets[1].accept)
  engine.Feed(st, 'a')
  var ev = engine.Feed(st, ' ')
  assert_equal('wrong', ev.kind)
  assert_equal(1, st.pos)
  assert_equal('wrong', st.targets[1].state)
  assert_equal('correct', engine.Feed(st, "\r").kind)

  st = engine.Build(['a', 'b'], {line_end: 'space'})
  assert_equal([' '], st.targets[1].accept)
  engine.Feed(st, 'a')
  assert_equal('wrong', engine.Feed(st, "\r").kind)
  assert_equal('correct', engine.Feed(st, ' ').kind)

  # Unknown values fall back to the default.
  st = engine.Build(['a', 'b'], {line_end: 'nonsense'})
  assert_equal(["\r", ' '], st.targets[1].accept)
enddef

def Test_equivalents_default_table()
  var pairs = [
    ["\u2019", "'"],
    ["\u2018", "'"],
    ["\u201c", '"'],
    ["\u201d", '"'],
    ["\u2013", '-'],
    ["\u2014", '-'],
    ["\u2026", '.'],
    ["\u00a0", ' '],
  ]
  for [ch, key] in pairs
    var st = engine.Build([ch])
    assert_equal(1, len(st.targets), ch)
    assert_equal(ch, st.targets[0].char)
    assert_equal([ch, key], st.targets[0].accept, ch)
    assert_equal('correct', engine.Feed(st, key).kind, ch)
    # The character itself is always accepted too.
    var st2 = engine.Build([ch])
    assert_equal('correct', engine.Feed(st2, ch).kind, ch)
  endfor
enddef

def Test_equivalents_custom_and_empty()
  var st = engine.Build(['x'], {equivalents: {'x': 'y'}})
  assert_equal(['x', 'y'], st.targets[0].accept)
  assert_equal('correct', engine.Feed(st, 'y').kind)

  st = engine.Build(["\u201c"], {equivalents: {}})
  assert_equal(["\u201c"], st.targets[0].accept)
  assert_equal('wrong', engine.Feed(st, '"').kind)

  st = engine.Build(["\u00a0"], {equivalents: {}})
  assert_equal(["\u00a0"], st.targets[0].accept)
enddef

def Test_tab_accepts_tab_or_space()
  var st = engine.Build(["a\tb"])
  assert_equal(['a', "\t", 'b'], Chars(st))
  assert_equal([1, 2, 3], Cols(st))
  assert_equal([1, 1, 1], Lens(st))
  assert_equal(["\t", ' '], st.targets[1].accept)
  assert_equal('char', st.targets[1].kind)
  assert_equal('correct', engine.Feed(st, 'a').kind)
  assert_equal('correct', engine.Feed(st, ' ').kind)

  st = engine.Build(["a\tb"])
  assert_equal('correct', engine.Feed(st, 'a').kind)
  assert_equal('correct', engine.Feed(st, "\t").kind)
  assert_equal('correct', engine.Feed(st, 'b').kind)
  assert_true(st.done)
enddef

def Test_skip_non_ascii()
  var st = engine.Build(["a\u4e2db"])
  assert_equal(['a', "\u4e2d", 'b'], Chars(st))
  assert_equal([1, 2, 5], Cols(st))
  assert_equal([1, 3, 1], Lens(st))

  st = engine.Build(["a\u4e2db"], {skip_non_ascii: true})
  assert_equal(['a', 'b'], Chars(st))
  assert_equal([1, 5], Cols(st))
  assert_equal(2, len(st.targets))

  # A character with an equivalent is kept even when non-ASCII is skipped.
  st = engine.Build(["a\u4e2db"], {skip_non_ascii: true, equivalents: {"\u4e2d": 'z'}})
  assert_equal(['a', "\u4e2d", 'b'], Chars(st))
  assert_equal(["\u4e2d", 'z'], st.targets[1].accept)
  assert_equal('correct', FeedAll(st, ['a', 'z'])[1].kind)

  # nbsp has a default equivalent, so skipping leaves it in place.
  st = engine.Build(["\u00a0"], {skip_non_ascii: true})
  assert_equal(1, len(st.targets))

  # A line whose characters are all skipped has no targets, hence no break.
  st = engine.Build(["\u4e2d", 'a'], {skip_non_ascii: true, equivalents: {}})
  assert_equal(['a'], Chars(st))
  assert_equal(['char'], mapnew(st.targets, (_, t) => t.kind))
  st = engine.Build(['a', "\u4e2d", 'b'], {skip_non_ascii: true, equivalents: {}})
  assert_equal(['a', "\n", 'b'], Chars(st))
enddef

def Test_multibyte_byte_columns()
  var st = engine.Build(["\u00e9\u4e2dx"])
  assert_equal(["\u00e9", "\u4e2d", 'x'], Chars(st))
  assert_equal([1, 3, 6], Cols(st))
  assert_equal([2, 3, 1], Lens(st))
  assert_equal('correct', engine.Feed(st, "\u00e9").kind)
  assert_equal('correct', engine.Feed(st, "\u4e2d").kind)
  assert_equal(2, st.pos)
  assert_equal('correct', engine.Feed(st, 'x').kind)
  assert_true(st.done)

  # Composing characters stay attached to their base character.
  st = engine.Build(["e\u0301x"])
  assert_equal(["e\u0301", 'x'], Chars(st))
  assert_equal([1, 4], Cols(st))
  assert_equal([3, 1], Lens(st))
enddef

def Test_stay_mode_wrong_keeps_position()
  var st = engine.Build(['ab'])
  var ev = engine.Feed(st, 'x')
  assert_equal('wrong', ev.kind)
  assert_equal(0, ev.pos)
  assert_equal(0, ev.standing)
  assert_equal(2, ev.total)
  assert_false(ev.done)
  assert_equal('a', ev.expected)
  assert_equal('x', ev.typed)
  assert_equal([0], ev.changed)
  assert_equal('wrong', st.targets[0].state)
  assert_true(st.targets[0].missed)

  # A second wrong key changes no state but is still a wrong event.
  ev = engine.Feed(st, 'y')
  assert_equal('wrong', ev.kind)
  assert_equal([], ev.changed)
  assert_equal(0, st.pos)
  assert_equal(0, st.standing)

  ev = engine.Feed(st, 'a')
  assert_equal('correct', ev.kind)
  assert_equal([0], ev.changed)
  assert_equal('fixed', st.targets[0].state)
  assert_equal(1, st.pos)
  assert_equal(1, ev.standing)

  ev = engine.Feed(st, 'b')
  assert_equal('correct', ev.kind)
  assert_equal('correct', st.targets[1].state)
  assert_equal(2, st.pos)
  assert_equal(2, ev.standing)
  assert_true(ev.done)
  assert_true(st.done)
enddef

def Test_stay_mode_backspace_ignored()
  var st = engine.Build(['ab'])
  engine.Feed(st, 'a')
  for k in ["\x08", "\x7f", "\<BS>"]
    var ev = engine.Feed(st, k)
    assert_equal('ignored', ev.kind, k)
    assert_equal([], ev.changed)
    assert_equal('', ev.expected)
    assert_equal('', ev.typed)
    assert_equal(1, st.pos, k)
    assert_equal('correct', st.targets[0].state, k)
  endfor
enddef

def Test_advance_mode_wrong_advances()
  var st = engine.Build(['abc'], {on_error: 'advance'})
  assert_equal('advance', st.on_error)
  var ev = engine.Feed(st, 'x')
  assert_equal('wrong', ev.kind)
  assert_equal(1, ev.pos)
  assert_equal(0, ev.standing)
  assert_equal([0], ev.changed)
  assert_equal('wrong', st.targets[0].state)
  assert_true(st.targets[0].missed)

  ev = engine.Feed(st, 'b')
  assert_equal('correct', ev.kind)
  assert_equal(2, ev.pos)
  assert_equal(1, ev.standing)
enddef

def Test_advance_mode_backspace()
  var st = engine.Build(['abc'], {on_error: 'advance'})
  FeedAll(st, ['a', 'b'])
  assert_equal(2, st.pos)
  assert_equal(2, st.standing)

  # Backspace returns the target to pending; missed was never set here.
  var ev = engine.Feed(st, "\<BS>")
  assert_equal('back', ev.kind)
  assert_equal(1, ev.pos)
  assert_equal(1, ev.standing)
  assert_equal([1], ev.changed)
  assert_equal('', ev.expected)
  assert_equal('', ev.typed)
  assert_equal('pending', st.targets[1].state)
  assert_false(st.targets[1].missed)
  assert_false(ev.done)

  # Retyping a target that was only stepped back over is correct, not fixed.
  ev = engine.Feed(st, 'b')
  assert_equal('correct', ev.kind)
  assert_equal('correct', st.targets[1].state)
  assert_equal(2, st.pos)
  assert_equal(2, ev.standing)

  # Backspace at position 0 is ignored.
  var st0 = engine.Build(['abc'], {on_error: 'advance'})
  for k in ["\<BS>", "\x08", "\x7f"]
    ev = engine.Feed(st0, k)
    assert_equal('ignored', ev.kind, k)
    assert_equal(0, ev.pos, k)
    assert_equal([], ev.changed, k)
  endfor
enddef

def Test_advance_mode_backspace_over_wrong()
  var st = engine.Build(['ab'], {on_error: 'advance'})
  var ev = engine.Feed(st, 'x')
  assert_equal('wrong', ev.kind)
  assert_equal(1, st.pos)
  assert_equal('wrong', st.targets[0].state)

  ev = engine.Feed(st, "\x7f")
  assert_equal('back', ev.kind)
  assert_equal(0, st.pos)
  assert_equal('pending', st.targets[0].state)
  assert_true(st.targets[0].missed)
  assert_equal([0], ev.changed)

  ev = engine.Feed(st, 'a')
  assert_equal('fixed', st.targets[0].state)
  assert_equal(1, ev.standing)
enddef

def Test_standing_values()
  var st = engine.Build(['ab', 'cd'], {on_error: 'advance'})
  assert_equal(5, len(st.targets))
  assert_equal(0, st.standing)
  var evs = FeedAll(st, ['a', 'x'])
  assert_equal(['correct', 'wrong'], mapnew(evs, (_, e) => e.kind))
  assert_equal([1, 1], mapnew(evs, (_, e) => e.standing))
  assert_equal(2, st.pos)

  # Back over a wrong target: standing does not move, missed is kept.
  var ev = engine.Feed(st, "\<BS>")
  assert_equal('back', ev.kind)
  assert_equal(1, ev.standing)
  assert_equal(1, st.pos)
  assert_true(st.targets[1].missed)

  evs = FeedAll(st, ['b', ' '])
  assert_equal(['correct', 'correct'], mapnew(evs, (_, e) => e.kind))
  assert_equal([2, 3], mapnew(evs, (_, e) => e.standing))
  assert_equal(3, st.pos)
  assert_equal('fixed', st.targets[1].state)

  evs = FeedAll(st, ['y', 'd'])
  assert_equal([3, 4], mapnew(evs, (_, e) => e.standing))
  assert_equal(['correct', 'fixed', 'correct', 'wrong', 'correct'], States(st))
  assert_equal(4, st.standing)
  assert_true(st.done)

  # Backspace over correct targets lowers standing.
  st = engine.Build(['abc'], {on_error: 'advance'})
  FeedAll(st, ['a', 'b'])
  assert_equal(2, st.standing)
  ev = engine.Feed(st, "\<BS>")
  assert_equal('back', ev.kind)
  assert_equal(1, st.standing)
  assert_equal('pending', st.targets[1].state)
  assert_false(ev.done)
  ev = engine.Feed(st, "\<BS>")
  assert_equal('back', ev.kind)
  assert_equal(0, st.standing)
  assert_equal('pending', st.targets[0].state)
  assert_equal(0, st.pos)
  ev = engine.Feed(st, 'a')
  assert_equal('correct', ev.kind)
  assert_equal(1, st.standing)
enddef

def Test_event_fields()
  var st = engine.Build(['a'])
  var ev = engine.Feed(st, 'z')
  for k in ['kind', 'changed', 'expected', 'typed', 'pos', 'total',
      'standing', 'done']
    assert_true(has_key(ev, k), k)
  endfor
  assert_equal(v:t_string, type(ev.kind))
  assert_equal(v:t_list, type(ev.changed))
  assert_equal(v:t_string, type(ev.expected))
  assert_equal(v:t_string, type(ev.typed))
  assert_equal(v:t_number, type(ev.pos))
  assert_equal(v:t_number, type(ev.total))
  assert_equal(v:t_number, type(ev.standing))
  assert_equal(v:t_bool, type(ev.done))
  assert_equal(1, ev.total)
  assert_equal('a', ev.expected)
  assert_equal('z', ev.typed)

  ev = engine.Feed(st, 'a')
  assert_true(ev.done)
  assert_equal(1, ev.pos)
  assert_equal(1, ev.standing)
enddef

def Test_ignored_keys()
  var keys = ["\<Up>", "\<F1>", "\<Esc>", "\<LeftMouse>", "\<C-a>", "\x1b",
    "\x01"]
  var st = engine.Build(['ab'], {on_error: 'advance'})
  for k in keys
    var ev = engine.Feed(st, k)
    assert_equal('ignored', ev.kind, k)
    assert_equal([], ev.changed, k)
    assert_equal('', ev.expected, k)
    assert_equal('', ev.typed, k)
    assert_equal(0, st.pos, k)
    assert_equal(0, st.standing, k)
    assert_false(ev.done, k)
    assert_equal('pending', st.targets[0].state, k)
    assert_false(st.targets[0].missed, k)
  endfor
  # They are not counted as wrong either: the target is still typeable.
  assert_equal('correct', engine.Feed(st, 'a').kind)
enddef

def Test_newline_normalised_to_cr()
  var st = engine.Build(['a', 'b'])
  assert_equal('correct', engine.Feed(st, 'a').kind)
  var ev = engine.Feed(st, "\n")
  assert_equal('correct', ev.kind)
  assert_equal("\r", ev.typed)
  assert_equal("\n", ev.expected)
  assert_equal('correct', engine.Feed(st, 'b').kind)
  assert_true(st.done)

  st = engine.Build(['ab'])
  ev = engine.Feed(st, "\n")
  assert_equal('wrong', ev.kind)
  assert_equal("\r", ev.typed)
  assert_equal('a', ev.expected)
enddef

def Test_enter_mid_line_is_wrong()
  var st = engine.Build(['ab'])
  var ev = engine.Feed(st, "\r")
  assert_equal('wrong', ev.kind)
  assert_equal(0, st.pos)
  assert_equal('wrong', st.targets[0].state)
  assert_equal([0], ev.changed)
enddef

def Test_empty_input_done()
  for lines in [[], [''], ['   ', "\t", '']]
    var st = engine.Build(lines)
    assert_equal([], st.targets)
    assert_equal(0, st.pos)
    assert_equal(0, st.standing)
    assert_true(st.done)
    var ev = engine.Feed(st, 'a')
    assert_equal('ignored', ev.kind)
    assert_true(ev.done)
    assert_equal(0, ev.total)
  endfor
enddef

def Test_keys_after_done_ignored()
  var st = engine.Build(['a'], {on_error: 'advance'})
  engine.Feed(st, 'a')
  assert_true(st.done)
  var before = States(st)
  for k in ['b', "\r", ' ', "\<Up>", "\<BS>", "\x08", "\<Esc>"]
    var ev = engine.Feed(st, k)
    assert_equal('ignored', ev.kind, k)
    assert_equal([], ev.changed, k)
    assert_equal(1, ev.pos, k)
    assert_equal(1, ev.standing, k)
    assert_true(ev.done, k)
  endfor
  assert_equal(before, States(st))
enddef

def Test_build_does_not_modify_lines()
  var lines = ['  ab', '', "\tcd"]
  var copy = copy(lines)
  engine.Build(lines)
  assert_equal(copy, lines)
enddef

def Test_unknown_options_default()
  var st = engine.Build(['a', 'b'], {on_error: 'nonsense'})
  assert_equal('stay', st.on_error)
  var ev = engine.Feed(st, 'x')
  assert_equal(0, ev.pos)
enddef

Test_default_equivalents()
Test_indent_skipped_but_counted_in_columns()
Test_trailing_whitespace_ignored()
Test_blank_lines_skipped()
Test_breaks_between_lines_only()
Test_line_end_values()
Test_equivalents_default_table()
Test_equivalents_custom_and_empty()
Test_tab_accepts_tab_or_space()
Test_skip_non_ascii()
Test_multibyte_byte_columns()
Test_stay_mode_wrong_keeps_position()
Test_stay_mode_backspace_ignored()
Test_advance_mode_wrong_advances()
Test_advance_mode_backspace()
Test_advance_mode_backspace_over_wrong()
Test_standing_values()
Test_event_fields()
Test_ignored_keys()
Test_newline_normalised_to_cr()
Test_enter_mid_line_is_wrong()
Test_empty_input_done()
Test_keys_after_done_ignored()
Test_build_does_not_modify_lines()
Test_unknown_options_default()
