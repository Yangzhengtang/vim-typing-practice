vim9script
# Statistics for a typing session: counters, clock, WPM/accuracy and missed keys.
# Pure: no buffer, window, popup, timer, g: variable or real-clock access. The
# caller supplies `now` in seconds. See PLAN.md sections 4 and 5.1.

const DEFAULT_IDLE_SECONDS = 5.0

# opts: idle_seconds (float, default 5.0), total and pos (numbers, default 0).
export def New(opts: dict<any> = {}): dict<any>
  return {
    idle_seconds: get(opts, 'idle_seconds', DEFAULT_IDLE_SECONDS) + 0.0,
    elapsed: 0.0,
    started: false,
    last: 0.0,
    frozen: false,
    resting: false,
    keystrokes: 0,
    correct: 0,
    errors: 0,
    streak: 0,
    best_streak: 0,
    pos: get(opts, 'pos', 0),
    total: get(opts, 'total', 0),
    standing: 0,
    banked: 0,
    passed: 0,
    finished: false,
    attempts: {},
    misses: {},
    typed: {}
  }
enddef

# Consume one event from engine.Feed. `ignored` events change nothing at all;
# `back` moves the clock but is not a keystroke; `correct` and `wrong` are;
# `jump` moves the clock and adds its `lost` count to the banked characters.
export def Record(s: dict<any>, ev: dict<any>, now: float): void
  var kind = get(ev, 'kind', 'ignored')
  if kind != 'correct' && kind != 'wrong' && kind != 'back' && kind != 'jump'
    return
  endif

  # Clock: it starts at the first non-ignored event; each later event adds the
  # gap since the previous one only when that gap is at most idle_seconds. The
  # first event after a Pause only ends the rest and adds nothing.
  if !s.started
    s.started = true
    s.last = now
  elseif !s.frozen
    if s.resting
      s.resting = false
    else
      var gap: float = now - s.last
      if gap >= 0.0 && gap <= s.idle_seconds
        s.elapsed += gap
      endif
    endif
    s.last = now
  endif

  # Progress values come from the most recent non-ignored event.
  var prev_pos: number = s.pos
  s.pos = get(ev, 'pos', s.pos)
  s.total = get(ev, 'total', s.total)
  s.standing = get(ev, 'standing', s.standing)
  if get(ev, 'done', false)
    s.finished = true
    s.frozen = true
  endif

  if kind == 'correct' || kind == 'wrong'
    s.keystrokes += 1
    var expected: string = get(ev, 'expected', '')
    s.attempts[expected] = get(s.attempts, expected, 0) + 1
    if kind == 'correct'
      s.correct += 1
      s.streak += 1
      if s.streak > s.best_streak
        s.best_streak = s.streak
      endif
    else
      s.errors += 1
      s.streak = 0
      s.misses[expected] = get(s.misses, expected, 0) + 1
      var typed_key: string = get(ev, 'typed', '')
      var tally: dict<any> = get(s.typed, expected, {})
      tally[typed_key] = get(tally, typed_key, 0) + 1
      s.typed[expected] = tally
    endif
  endif

  if kind == 'jump'
    s.banked += get(ev, 'lost', 0)
  endif

  # Targets passed by typing: the position advanced or a back key was pressed.
  if kind == 'correct' || kind == 'wrong'
    if s.pos > prev_pos
      s.passed += 1
    endif
  elseif kind == 'back'
    s.passed = s.passed > 0 ? s.passed - 1 : 0
  endif
enddef

# Stop the clock: close the open gap under the idle rule, then leave the clock
# resting so neither Snapshot nor a later event adds the paused time.
export def Pause(s: dict<any>, now: float): void
  if !s.started || s.frozen || s.resting
    return
  endif
  var gap: float = now - s.last
  if gap < 0.0
    gap = 0.0
  endif
  if gap <= s.idle_seconds
    s.elapsed += gap
  endif
  s.resting = true
  s.last = now
enddef

export def Snapshot(s: dict<any>, now: float): dict<any>
  var elapsed: float = s.elapsed
  var paused = false
  if s.started && !s.frozen
    if s.resting
      # Paused: the clock stands still, no open gap is added.
      paused = true
    else
      # The open gap follows the same rule; a gap longer than idle_seconds is
      # not added and leaves the session paused instead.
      var gap: float = now - s.last
      if gap < 0.0
        gap = 0.0
      endif
      if gap <= s.idle_seconds
        elapsed += gap
      else
        paused = true
      endif
    endif
  endif

  var keystrokes: number = s.keystrokes
  var correct: number = s.correct
  var standing: number = s.standing
  var banked: number = s.banked
  var total: number = s.total
  var accuracy: float = keystrokes == 0 ? 100.0 : correct * 100.0 / keystrokes
  var raw_wpm: float = elapsed == 0.0 ? 0.0 : keystrokes * 60.0 / 5.0 / elapsed
  var wpm: float = elapsed == 0.0 ? 0.0 : (standing + banked) * 60.0 / 5.0 / elapsed
  var cpm: float = wpm * 5.0
  var progress: float = total == 0 ? 0.0 : s.pos * 100.0 / total

  return {
    elapsed: elapsed,
    keystrokes: keystrokes,
    correct: correct,
    errors: s.errors,
    accuracy: accuracy,
    raw_wpm: raw_wpm,
    wpm: wpm,
    cpm: cpm,
    streak: s.streak,
    best_streak: s.best_streak,
    pos: s.pos,
    total: total,
    standing: standing,
    banked: banked,
    passed: s.passed,
    progress: progress,
    started: s.started,
    paused: paused,
    finished: s.finished
  }
enddef

# Most frequent first; ties by key ascending so the order is deterministic.
def CompareTyped(a: list<any>, b: list<any>): number
  if a[1] != b[1]
    return b[1] - a[1]
  endif
  if a[0] == b[0]
    return 0
  endif
  return a[0] < b[0] ? -1 : 1
enddef

# Misses descending, then miss rate descending, then char ascending.
def CompareMissed(a: dict<any>, b: dict<any>): number
  if a.misses != b.misses
    return b.misses - a.misses
  endif
  var rate_a: float = a.attempts == 0 ? 0.0 : a.misses * 1.0 / a.attempts
  var rate_b: float = b.attempts == 0 ? 0.0 : b.misses * 1.0 / b.attempts
  if rate_a != rate_b
    return rate_a < rate_b ? 1 : -1
  endif
  if a.char == b.char
    return 0
  endif
  return a.char < b.char ? -1 : 1
enddef

# Top `n` missed characters: {char, misses, attempts, typed}; typed is a list
# of [key, count] pairs, most frequent first.
export def TopMissed(s: dict<any>, n: number = 5): list<dict<any>>
  var top: list<dict<any>> = []
  if n <= 0
    return top
  endif
  for c in keys(s.misses)
    var misses: number = get(s.misses, c, 0)
    if misses <= 0
      continue
    endif
    var pairs: list<any> = []
    var tally: dict<any> = get(s.typed, c, {})
    for k in keys(tally)
      add(pairs, [k, tally[k]])
    endfor
    sort(pairs, CompareTyped)
    add(top, {
      char: c,
      misses: misses,
      attempts: get(s.attempts, c, 0),
      typed: pairs
    })
  endfor
  sort(top, CompareMissed)
  return top[: n - 1]
enddef

# expected char -> misses, only characters with at least one miss.
export def MissedCounts(s: dict<any>): dict<number>
  var counts: dict<number> = {}
  for [char, misses] in items(s.misses)
    if misses > 0
      counts[char] = misses
    endif
  endfor
  return counts
enddef
