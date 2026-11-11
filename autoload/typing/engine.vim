vim9script
# Pure typing logic: build the list of targets from lines of text and judge keys.
# This module touches no buffer, window, popup, timer or g: variable, so it can
# be unit-tested directly. See PLAN.md section 5.1 for the contract.

# Typographic punctuation accepts its keyboard equivalent (PLAN.md section 4).
export def DefaultEquivalents(): dict<string>
  return {
    "\u2019": "'",
    "\u2018": "'",
    "\u201c": '"',
    "\u201d": '"',
    "\u2013": '-',
    "\u2014": '-',
    "\u2026": '.',
    "\u00a0": ' '
  }
enddef

def IsGood(state: string): bool
  return state == 'correct' || state == 'fixed'
enddef

# Change a target's state, keeping st.standing in step. Returns true when the
# state actually changed.
def SetState(st: dict<any>, t: dict<any>, newstate: string): bool
  if t.state == newstate
    return false
  endif
  if IsGood(t.state) && !IsGood(newstate)
    st.standing -= 1
  elseif !IsGood(t.state) && IsGood(newstate)
    st.standing += 1
  endif
  t.state = newstate
  return true
enddef

def BreakAccept(line_end: string): list<string>
  if line_end == 'enter'
    return ["\r"]
  elseif line_end == 'space'
    return [' ']
  endif
  return ["\r", ' ']
enddef

def CharAccept(ch: string, equivalents: dict<any>): list<string>
  var accept = [ch]
  if has_key(equivalents, ch)
    var eq = equivalents[ch]
    if type(eq) == v:t_string && index(accept, eq) < 0
      add(accept, eq)
    endif
  endif
  if ch == "\t" && index(accept, ' ') < 0
    add(accept, ' ')
  endif
  return accept
enddef

def NewTarget(lnum: number, col: number, chlen: number, char: string,
    kind: string, accept: list<string>): dict<any>
  return {
    lnum: lnum,
    col: col,
    len: chlen,
    char: char,
    kind: kind,
    accept: accept,
    state: 'pending',
    missed: false
  }
enddef

# Build the state for lines. opts: on_error, line_end, equivalents,
# skip_non_ascii; every key is optional.
export def Build(lines: list<string>, opts: dict<any> = {}): dict<any>
  var on_error = get(opts, 'on_error', 'stay') == 'advance' ? 'advance' : 'stay'

  var line_end = 'either'
  var le = get(opts, 'line_end', 'either')
  if le == 'enter' || le == 'space'
    line_end = le
  endif

  var equivalents: dict<any> = DefaultEquivalents()
  if has_key(opts, 'equivalents')
    var eqv = opts.equivalents
    if type(eqv) == v:t_dict
      equivalents = eqv
    endif
  endif

  var skip_non_ascii: bool = get(opts, 'skip_non_ascii', false)

  var targets: list<dict<any>> = []
  var pending_break: dict<any> = {}
  var have_break = false
  var lnum = 0
  for line in lines
    lnum += 1
    # Leading whitespace makes no targets but still counts towards byte columns.
    var lead = matchstr(line, '^\s*')
    var text = substitute(strpart(line, len(lead)), '\s\+$', '', '')
    if text == ''
      continue
    endif
    var before = len(targets)
    var col = len(lead) + 1
    for ch in split(text, '\zs')
      var chlen = len(ch)
      var accept = CharAccept(ch, equivalents)
      # A non-ASCII character with no equivalent is skipped when asked.
      if !(skip_non_ascii && char2nr(ch) > 0x7f && len(accept) == 1)
        add(targets, NewTarget(lnum, col, chlen, ch, 'char', accept))
      endif
      col += chlen
    endfor
    # A line with no characters left has no targets, so it also has no break.
    if len(targets) == before
      continue
    endif
    if have_break
      insert(targets, pending_break, before)
    endif
    pending_break = NewTarget(lnum, len(lead) + len(text) + 1, 0, "\n",
      'break', BreakAccept(line_end))
    have_break = true
  endfor

  return {
    targets: targets,
    pos: 0,
    standing: 0,
    on_error: on_error,
    done: empty(targets)
  }
enddef

def Event(st: dict<any>, kind: string, changed: list<number>,
    expected: string, typed: string): dict<any>
  var total = len(st.targets)
  return {
    kind: kind,
    changed: changed,
    expected: expected,
    typed: typed,
    pos: st.pos,
    total: total,
    standing: st.standing,
    done: st.pos >= total
  }
enddef

# True for keys that are judged against the current target: Enter, Tab and any
# single printable character (including multi-byte). Special keys, mouse events
# and other control characters are not judged.
def IsJudged(k: string): bool
  if k == "\r" || k == "\t"
    return true
  endif
  if strchars(k) != 1
    return false
  endif
  var nr = char2nr(k)
  # Control characters, DEL and a lone K_SPECIAL lead byte are not text.
  return nr >= 0x20 && nr != 0x7f && nr != 0x80
enddef

# True for the three backspace spellings: the raw control bytes and the
# special-key form that vim9script produces for "\<BS>".
def IsBackspace(k: string): bool
  return k == "\x08" || k == "\x7f" || keytrans(k) ==# '<BS>'
enddef

export def Feed(st: dict<any>, key: string): dict<any>
  var total = len(st.targets)
  if get(st, 'done', false) || st.pos >= total
    return Event(st, 'ignored', [], '', '')
  endif

  # Enter arrives as "\n" from some sources; treat it as "\r".
  var k = key == "\n" ? "\r" : key

  if IsBackspace(k)
    if st.on_error != 'advance' || st.pos <= 0
      return Event(st, 'ignored', [], '', '')
    endif
    var changed: list<number> = []
    st.pos -= 1
    if SetState(st, st.targets[st.pos], 'pending')
      add(changed, st.pos)
    endif
    st.done = st.pos >= total
    return Event(st, 'back', changed, '', '')
  endif

  if !IsJudged(k)
    return Event(st, 'ignored', [], '', '')
  endif

  var t = st.targets[st.pos]
  var changed: list<number> = []
  var kind = ''
  if index(t.accept, k) >= 0
    if SetState(st, t, t.missed ? 'fixed' : 'correct')
      add(changed, st.pos)
    endif
    st.pos += 1
    kind = 'correct'
  else
    t.missed = true
    if SetState(st, t, 'wrong')
      add(changed, st.pos)
    endif
    if st.on_error == 'advance'
      st.pos += 1
    endif
    kind = 'wrong'
  endif
  st.done = st.pos >= total
  return Event(st, kind, changed, t.char, k)
enddef
