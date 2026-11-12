vim9script
g:typing_summary_grace_ms = 0
import autoload 'typing/session.vim'
import autoload 'typing/progress.vim'
import autoload 'typing/history.vim'
import autoload 'typing/stats.vim'

def Keys(keys: string)
  feedkeys(keys, 'xt')
  sleep 20m
enddef

def Clean()
  sleep 20m
  assert_equal('idle', session.State().phase)
  assert_equal(0, session.State().start)
  assert_equal(-1, session.State().prompt_id)
  assert_equal(1, tabpagenr('$'))
  assert_equal([], popup_list())
  assert_equal([], timer_info())
  assert_equal('RESUMEVE', &t_ve)
  assert_notmatch('OnLeave\|OnWipeout\|OnVimLeave\|OnResized',
    execute('autocmd TypingPracticeSession'))
enddef

def Fresh(text: list<string> = ['abc', 'defg'], named: bool = true): string
  assert_equal('idle', session.State().phase)
  enew!
  setline(1, text)
  if named
    execute 'silent file ' .. fnameescape(tempname() .. ' 中 file.txt')
  endif
  &modified = false
  &t_ve = 'RESUMEVE'
  g:typing_resume = 'ask'
  g:typing_blink_ms = 0
  g:typing_history = true
  g:typing_history_min_keys = 1
  g:typing_on_error = 'stay'
  g:typing_progress_file = tempname()
  g:typing_history_file = tempname()
  return named ? fnamemodify(bufname(), ':p') : ''
enddef

def Close()
  session.Stop()
  sleep 20m
  if session.State().phase == 'summary'
    session.Stop()
  endif
  Clean()
enddef

def Seed(path: string, pos: number = 5, lnum: number = 2,
    line1: number = 1, line2: number = 2)
  assert_true(progress.Save(g:typing_progress_file, path,
    {line1: line1, line2: line2, pos: pos, total: 8, lnum: lnum,
      hash: progress.Fingerprint(['abc', 'defg']), time: 123}))
enddef

def Test_save_prompt_resume()
  var path = Fresh()
  var origin = bufnr()
  TypingStart
  Keys("abc d\<Esc>q")
  assert_equal('summary', session.State().phase)
  var saved = progress.Get(g:typing_progress_file, path)
  assert_equal(5, saved.pos)
  assert_equal(2, saved.lnum)
  assert_equal(8, saved.total)
  assert_equal(progress.Fingerprint(['abc', 'defg']), saved.hash)
  assert_match('Position saved: line 2 (63%)', join(session.State().last_summary))
  Keys('x')
  Clean()
  TypingStart
  var s = session.State()
  assert_equal('prompt', s.phase)
  assert_equal(path, s.path)
  assert_equal(1, tabpagenr('$'))
  assert_true(s.prompt_id > 0)
  assert_equal(['Resume at line 2 (63%)', 'Start from the beginning'],
    getbufline(winbufnr(s.prompt_id), 1, '$'))
  session.Start(1, 2)
  assert_equal(s.prompt_id, session.State().prompt_id)
  # The lines and options are captured at Start, before the eventual choice.
  setbufline(origin, 2, 'changed')
  g:typing_resume = 'never'
  Keys("\<CR>")
  s = session.State()
  assert_equal('typing', s.phase)
  assert_equal(['abc', 'defg'], s.lines)
  assert_equal(5, s.start)
  assert_equal(5, s.st.pos)
  assert_equal(repeat(['skipped'], 5),
    mapnew(s.st.targets[: 4], (_, t) => t.state))
  assert_equal(0, s.stats.keystrokes)
  assert_equal(62.5, stats.Snapshot(s.stats, 0.0).progress)
  assert_equal([], filter(prop_list(1, {bufnr: s.buf}),
    (_, p) => p.type == 'TypingPending' || p.type == 'TypingCursor'))
  assert_equal([], filter(prop_list(2, {bufnr: s.buf}), (_, p) => p.col == 1))
  Keys("e\<Esc>q")
  assert_equal(1, session.State().stats.keystrokes)
  assert_equal(1, session.State().st.standing)
  assert_equal(5, session.State().last_record.start)
  assert_equal(1, session.State().last_record.chars)
  var records = history.Load(g:typing_history_file)
  assert_equal(5, records[-1].start)
  assert_equal(1, records[-1].chars)
  assert_equal(6, progress.Get(g:typing_progress_file, path).pos)
  Keys('r')
  assert_equal(5, session.State().st.pos)
  assert_equal(0, session.State().stats.keystrokes)
  Keys('efg')
  assert_equal('summary', session.State().phase)
  assert_equal({}, progress.Get(g:typing_progress_file, path))
  assert_notmatch('Position saved:', join(session.State().last_summary))
  Keys('x')
  Clean()
enddef

def Test_start_over_cancel_stop()
  var path = Fresh()
  Seed(path)
  for cancel in ["\<Esc>", "\<C-c>"]
    TypingStart
    assert_equal('prompt', session.State().phase)
    Keys(cancel)
    Clean()
    assert_equal(5, progress.Get(g:typing_progress_file, path).pos)
  endfor
  TypingStart
  session.Stop()
  Clean()
  TypingStart
  Keys("j\<CR>")
  assert_equal(0, session.State().start)
  assert_equal(0, session.State().st.pos)
  Close()
  assert_equal(5, progress.Get(g:typing_progress_file, path).pos)
enddef

def Test_modes_bang_and_range()
  var path = Fresh()
  Seed(path)
  g:typing_resume = 'always'
  TypingStart
  assert_equal('typing', session.State().phase)
  assert_equal(5, session.State().start)
  Close()
  assert_equal(5, progress.Get(g:typing_progress_file, path).pos)
  TypingStart!
  assert_equal(0, session.State().start)
  Close()
  g:typing_resume = 'ask'
  TypingStart!
  assert_equal('typing', session.State().phase)
  assert_equal(0, session.State().start)
  Close()
  g:typing_resume = 'never'
  TypingStart
  assert_equal(0, session.State().start)
  Keys("ab\<Esc>q")
  assert_notmatch('Position saved:', join(session.State().last_summary))
  Close()
  assert_equal(5, progress.Get(g:typing_progress_file, path).pos)
  TypingStart
  Keys('abc defg')
  Close()
  assert_equal(5, progress.Get(g:typing_progress_file, path).pos)
  g:typing_resume = 'ask'
  session.Start(2, 2)
  assert_equal('typing', session.State().phase)
  assert_equal(0, session.State().start)
  Close()
enddef

def Test_changed_text()
  var path = Fresh(['abc', '', 'xyz'])
  Seed(path, 5, 2, 1, 3)
  TypingStart
  assert_equal('prompt', session.State().phase)
  assert_match('Resume at line 2 (text changed)', join(getbufline(
    winbufnr(session.State().prompt_id), 1, '$')))
  Keys("\<CR>")
  assert_equal(4, session.State().start)
  assert_equal(3, session.State().st.targets[4].lnum)
  Close()
  # Same total but different fingerprint still resumes at a line boundary.
  path = Fresh(['abc', 'wxyz'])
  Seed(path)
  g:typing_resume = 'always'
  TypingStart
  assert_equal(4, session.State().start)
  Close()
  # A changed first line can validly resume at index zero.
  Seed(path, 2, 1)
  TypingStart
  assert_equal(0, session.State().start)
  Close()
  # No target at or after the saved line: no offer.
  path = Fresh(['abc', ''])
  Seed(path)
  TypingStart
  assert_equal('typing', session.State().phase)
  assert_equal(0, session.State().start)
  Close()
enddef

def Test_invalid_positions()
  var path = Fresh()
  for pos in [0, -1, 8, 90]
    Seed(path, pos)
    TypingStart
    assert_equal('typing', session.State().phase)
    assert_equal(0, session.State().start)
    Close()
  endfor
  assert_true(progress.Save(g:typing_progress_file, path, {pos: 'bad'}))
  TypingStart
  assert_equal('typing', session.State().phase)
  Close()
enddef

def Test_unnamed_and_abort()
  Fresh(['abcdef'], false)
  TypingStart
  Keys("ab\<Esc>q")
  assert_equal({}, progress.Load(g:typing_progress_file))
  assert_false(filereadable(g:typing_progress_file))
  Close()
  var path = Fresh()
  TypingStart
  Keys('ab')
  tabprevious
  sleep 20m
  assert_equal(2, progress.Get(g:typing_progress_file, path).pos)
  Clean()
  TypingStart
  Keys("\<CR>")
  Keys("c\<C-c>")
  assert_equal(3, progress.Get(g:typing_progress_file, path).pos)
  Close()
enddef

def Test_advance_limit_and_no_movement()
  var path = Fresh()
  Seed(path)
  g:typing_resume = 'always'
  g:typing_on_error = 'advance'
  TypingStart
  Keys("\<BS>e\<BS>\<BS>\<Esc>q")
  assert_equal(5, session.State().st.pos)
  assert_equal(0, session.State().st.standing)
  assert_equal(5, progress.Get(g:typing_progress_file, path).pos)
  assert_equal(123, progress.Get(g:typing_progress_file, path).time)
  assert_notmatch('Position saved:', join(session.State().last_summary))
  Close()
enddef

Test_save_prompt_resume()
Test_start_over_cancel_stop()
Test_modes_bang_and_range()
Test_changed_text()
Test_invalid_positions()
Test_unnamed_and_abort()
Test_advance_limit_and_no_movement()

def Test_range_line_numbers_and_save_failure()
  var path = Fresh(['ignored', 'ab', 'cde'])
  session.Start(2, 3)
  Keys("ab c\<Esc>q")
  assert_equal(3, progress.Get(g:typing_progress_file, path).lnum)
  assert_equal(2, progress.Get(g:typing_progress_file, path).line1)
  Close()
  session.Start(2, 3)
  assert_equal('prompt', session.State().phase)
  Keys("\<CR>")
  assert_equal(4, session.State().start)
  Close()
  setline(3, 'xyz')
  session.Start(2, 3)
  Keys("\<CR>")
  assert_equal(3, session.State().start)
  Close()

  path = Fresh()
  var blocker = tempname()
  writefile(['block'], blocker)
  g:typing_progress_file = blocker .. '/progress.json'
  try
    TypingStart
    Keys("ab\<Esc>q")
    assert_notmatch('Position saved:', join(session.State().last_summary))
    Close()
    assert_equal(['block'], readfile(blocker))
  finally
    delete(blocker)
  endtry
enddef

Test_range_line_numbers_and_save_failure()

def Test_choice_typeahead()
  for choice in ["\<CR>", "j\<CR>", "\<Esc>", "\<C-c>"]
    var path = Fresh()
    Seed(path)
    var origin = bufnr()
    TypingStart
    feedkeys(choice .. "\<C-c>q:ix\<Esc>", 'xt')
    sleep 20m
    assert_equal('', reg_recording())
    assert_equal('n', mode())
    assert_equal('', getcmdwintype())
    assert_equal(['abc', 'defg'], getbufline(origin, 1, '$'))
    assert_false(getbufvar(origin, '&modified'))
    if choice == "\<CR>" || choice == "j\<CR>"
      assert_equal('typing', session.State().phase)
      assert_equal(choice == "\<CR>" ? 5 : 0, session.State().st.pos)
      assert_equal(0, session.State().stats.keystrokes)
      assert_equal(['abc', 'defg'], getline(1, '$'))
      Close()
    else
      Clean()
    endif
  endfor
enddef

Test_choice_typeahead()
