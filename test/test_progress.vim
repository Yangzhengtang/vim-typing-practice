vim9script
import autoload 'typing/progress.vim'

def Test_default_file()
  var saved = g:typing_progress_file
  unlet g:typing_progress_file
  assert_equal(expand('~/.vim/typing-practice/progress.json'), progress.DefaultFile())
  g:typing_progress_file = saved
  assert_equal(saved, progress.DefaultFile())
enddef

def Test_fingerprint()
  assert_equal(sha256("one\ntwo"), progress.Fingerprint(['one', 'two']))
  assert_equal(progress.Fingerprint(['中', '']), progress.Fingerprint(['中', '']))
  assert_notequal(progress.Fingerprint(['a', 'b']), progress.Fingerprint(['ab']))
  assert_notequal(progress.Fingerprint(['a']), progress.Fingerprint(['A']))
enddef

def Test_roundtrip()
  var dir = tempname()
  var file = dir .. '/nested/progress.json'
  var entry = {line1: 1, line2: 5, pos: 3, total: 20, lnum: 2,
    hash: progress.Fingerprint(['abc']), time: 123}
  try
    assert_equal({}, progress.Load(file))
    assert_equal({}, progress.Get(file, '/missing'))
    for path in ['/one', '/with spaces/file name', '/中/文']
      assert_true(progress.Save(file, path, entry))
      assert_equal(entry, progress.Get(file, path))
    endfor
    assert_equal(3, len(progress.Load(file)))
    var updated = extend(copy(entry), {pos: 4}, 'force')
    assert_true(progress.Save(file, '/one', updated))
    assert_equal(updated, progress.Get(file, '/one'))
    assert_equal(entry, progress.Get(file, '/中/文'))
    assert_true(progress.Remove(file, '/one'))
    assert_equal({}, progress.Get(file, '/one'))
    assert_equal(2, len(progress.Load(file)))
    assert_true(progress.Remove(file, '/missing'))
    assert_equal(['progress.json'], readdir(dir .. '/nested'))
    for bad in ['{broken', '[]', '42', 'null']
      writefile([bad], file)
      assert_equal({}, progress.Load(file))
    endfor
    writefile(['{"bad": 12}'], file)
    assert_equal({}, progress.Get(file, 'bad'))
  finally
    delete(dir, 'rf')
  endtry
enddef

def Test_failure_cleanup()
  var dir = tempname()
  mkdir(dir)
  var blocker = dir .. '/file'
  writefile(['block'], blocker)
  try
    assert_false(progress.Save(blocker .. '/impossible', '/one', {}))
    # Writing a temporary file succeeds, but renaming onto a directory fails.
    assert_false(progress.Save(dir, '/one', {}))
    assert_equal(['file'], readdir(dir))
    assert_equal([], glob(fnamemodify(dir, ':h') .. '/.typing-progress-*', false, true))
    assert_equal(['block'], readfile(blocker))
  finally
    delete(dir, 'rf')
  endtry
enddef

Test_default_file()
Test_fingerprint()
Test_roundtrip()
Test_failure_cleanup()
