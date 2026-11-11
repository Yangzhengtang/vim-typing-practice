vim9script
# The plugin loads in a clean Vim and registers its commands and colours.

assert_equal(1, get(g:, 'loaded_typing_practice', 0))

for cmd in ['TypingStart', 'TypingStop', 'TypingHistory']
  assert_equal(2, exists(':' .. cmd), cmd)
endfor

for group in ['TypingPending', 'TypingWrong', 'TypingFixed', 'TypingCursor',
    'TypingStatus', 'TypingStatusWarn']
  assert_true(hlexists(group), group)
endfor

# Loading must not change the buffer the user is in. Starting a session does not
# change the origin buffer either, and ends back in it.
setline(1, ['some text'])
set nomodified
var origin = bufnr()
TypingStart
TypingStop
TypingStop
sleep 30m
assert_equal(origin, bufnr())
assert_equal(['some text'], getline(1, '$'))
assert_false(&modified)
