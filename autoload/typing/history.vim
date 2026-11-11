vim9script
# Session history: JSONL read/write and the :TypingHistory view.
# See PLAN.md sections 4 (History) and 5.1 (contract).
#
# The history file is private user data. Nothing here invents a path: callers
# write only where g:typing_history_file (or the argument) points.

const DEFAULT_HISTORY_FILE = '~/.vim/typing-practice/history.jsonl'
const BUFFER_NAME = '[Typing history]'
const HEADER = ['Date', 'File', 'Time', 'WPM', 'Raw', 'Acc%', 'Err', 'Streak',
  'Mode', 'State']
const SPARK_GLYPHS = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
const SPARK_FLAT = 3
const LAST_N = 10
const TOP_MISSED = 5

# g:typing_history_file, else the default. The default is expanded so callers
# get a path writefile() can use directly.
export def DefaultFile(): string
  return get(g:, 'typing_history_file', expand(DEFAULT_HISTORY_FILE))
enddef

# json_decode() gives a Float for 54.0 and a Number for 54; the summary always
# reports Floats, so normalise both here.
def AsFloat(v: any): float
  if type(v) == v:t_float
    return v
  elseif type(v) == v:t_number
    return v * 1.0
  endif
  return 0.0
enddef

def AsNumber(v: any): number
  if type(v) == v:t_number
    return v
  elseif type(v) == v:t_float
    return float2nr(round(v))
  endif
  return 0
enddef

def AsString(v: any): string
  return type(v) == v:t_string ? v : string(v)
enddef

def AsBool(v: any): bool
  if type(v) == v:t_bool
    return v
  elseif type(v) == v:t_number
    return v != 0
  endif
  return false
enddef

# Append one JSON line, creating the parent directory when needed. Returns
# false on any failure and never throws.
export def Append(file: string, record: dict<any>): bool
  try
    var dir = fnamemodify(file, ':h')
    if dir != '' && !isdirectory(dir)
      mkdir(dir, 'p')
      if !isdirectory(dir)
        return false
      endif
    endif
    return writefile([json_encode(record)], file, 'a') == 0
  catch
    return false
  endtry
enddef

# Records in file order (oldest first). A missing or unreadable file gives [].
# Blank lines, undecodable lines and JSON that is not an object are skipped.
export def Load(file: string): list<dict<any>>
  var records: list<dict<any>> = []
  if !filereadable(file)
    return records
  endif
  var lines: list<string> = []
  try
    lines = readfile(file)
  catch
    return records
  endtry
  for line in lines
    if line =~ '^\s*$'
      continue
    endif
    try
      var value = json_decode(line)
      if type(value) == v:t_dict
        add(records, value)
      endif
    catch
      # A corrupt line must not hide the rest of the file.
    endtry
  endfor
  return records
enddef

# Misses descending, then char ascending.
def CompareMissed(a: list<any>, b: list<any>): number
  if a[1] != b[1]
    return a[1] > b[1] ? -1 : 1
  endif
  if a[0] ==# b[0]
    return 0
  endif
  # Single characters: case-sensitive byte order, matching char ascending.
  return a[0] <# b[0] ? -1 : 1
enddef

# count = all records; best_wpm = best over all; averages over the last ten;
# missed = [char, misses] pairs over all records, top five.
export def Summarize(records: list<dict<any>>): dict<any>
  var best = 0.0
  var misses: dict<number> = {}
  for rec in records
    var wpm = AsFloat(get(rec, 'wpm', 0.0))
    if wpm > best
      best = wpm
    endif
    var missed = get(rec, 'missed', {})
    if type(missed) == v:t_dict
      for [char, count] in items(missed)
        misses[char] = get(misses, char, 0) + AsNumber(count)
      endfor
    endif
  endfor

  var total = len(records)
  var tail: list<dict<any>> = records
  if total > LAST_N
    tail = records[total - LAST_N :]
  endif
  var sum_wpm = 0.0
  var sum_accuracy = 0.0
  for rec in tail
    sum_wpm += AsFloat(get(rec, 'wpm', 0.0))
    sum_accuracy += AsFloat(get(rec, 'accuracy', 0.0))
  endfor
  var tail_count = len(tail)
  var avg_wpm = tail_count == 0 ? 0.0 : sum_wpm / tail_count
  var avg_accuracy = tail_count == 0 ? 0.0 : sum_accuracy / tail_count

  var top: list<list<any>> = []
  for [char, count] in items(misses)
    if count > 0
      add(top, [char, count])
    endif
  endfor
  sort(top, CompareMissed)

  return {
    count: total,
    best_wpm: best,
    avg_wpm: avg_wpm,
    avg_accuracy: avg_accuracy,
    missed: top[: TOP_MISSED - 1]
  }
enddef

# Pad to a display width, so multi-byte names keep the columns aligned.
def Pad(cell: string, width: number): string
  var used = strdisplaywidth(cell)
  return used >= width ? cell : cell .. repeat(' ', width - used)
enddef

def FormatTime(v: any): string
  return strftime('%Y-%m-%d %H:%M', AsNumber(v))
enddef

def FormatDuration(v: any): string
  var seconds = AsNumber(v)
  if seconds < 0
    seconds = 0
  endif
  return printf('%02d:%02d', seconds / 60, seconds % 60)
enddef

# One table row for one session, in HEADER order.
def SessionRow(rec: dict<any>): list<string>
  return [
    FormatTime(get(rec, 'time', 0)),
    AsString(get(rec, 'file', '')),
    FormatDuration(get(rec, 'duration', 0.0)),
    printf('%.1f', AsFloat(get(rec, 'wpm', 0.0))),
    printf('%.1f', AsFloat(get(rec, 'raw_wpm', 0.0))),
    printf('%.1f%%', AsFloat(get(rec, 'accuracy', 0.0))),
    printf('%d', AsNumber(get(rec, 'errors', 0))),
    printf('%d', AsNumber(get(rec, 'best_streak', 0))),
    AsString(get(rec, 'mode', '')),
    AsBool(get(rec, 'completed', false)) ? 'done' : 'unfinished'
  ]
enddef

# Header plus rows, every column padded to its widest cell. Trailing blanks are
# removed so the lines do not end in invisible whitespace.
def Table(header: list<string>, rows: list<list<string>>): list<string>
  var widths: list<number> = []
  for cell in header
    add(widths, strdisplaywidth(cell))
  endfor
  for row in rows
    var i = 0
    for cell in row
      var used = strdisplaywidth(cell)
      if used > widths[i]
        widths[i] = used
      endif
      i += 1
    endfor
  endfor

  var out: list<string> = []
  for cells in [header] + rows
    var parts: list<string> = []
    var i = 0
    for cell in cells
      add(parts, Pad(cell, widths[i]))
      i += 1
    endfor
    add(out, substitute(join(parts, '  '), '\s\+$', '', ''))
  endfor
  return out
enddef

# Readable forms for the keys that are otherwise invisible or confusing.
def DisplayChar(char: string): string
  if char == "\n"
    return '↵'
  elseif char == ' '
    return '␣'
  elseif char == "\t"
    return '→'
  endif
  return char
enddef

# Scaling between the shown sessions' min and max; a flat series is all one
# middle glyph.
def Sparkline(values: list<float>): string
  if empty(values)
    return ''
  endif
  var low = values[0]
  var high = values[0]
  for v in values
    if v < low
      low = v
    endif
    if v > high
      high = v
    endif
  endfor

  var text = ''
  for v in values
    if high == low
      text ..= SPARK_GLYPHS[SPARK_FLAT]
      continue
    endif
    var idx = float2nr(round((v - low) / (high - low) * 7.0))
    if idx < 0
      idx = 0
    elseif idx > 7
      idx = 7
    endif
    text ..= SPARK_GLYPHS[idx]
  endfor
  return text
enddef

# The history view: title, table (newest first), totals, all-time most missed
# keys and a WPM trend over the shown sessions (oldest to newest).
export def Lines(records: list<dict<any>>, limit: number = 30): list<string>
  if empty(records)
    return ['No history yet.']
  endif

  var n = limit
  if n > len(records)
    n = len(records)
  endif
  if n < 0
    n = 0
  endif
  var shown: list<dict<any>> = []
  if n > 0
    shown = records[len(records) - n :]
  endif

  var rows: list<list<string>> = []
  for rec in reverse(copy(shown))
    add(rows, SessionRow(rec))
  endfor

  var summary = Summarize(records)
  var totals = 'Sessions: ' .. summary.count
    .. '   Best WPM: ' .. printf('%.1f', summary.best_wpm)
    .. '   Last 10: ' .. printf('%.1f', summary.avg_wpm)
    .. ' WPM, ' .. printf('%.1f', summary.avg_accuracy) .. '% accuracy'

  var missed_parts: list<string> = []
  for [char, count] in summary.missed
    add(missed_parts, DisplayChar(char) .. ' ×' .. count)
  endfor
  var missed_line = 'Most missed: '
    .. (empty(missed_parts) ? 'none' : join(missed_parts, '  '))

  var values: list<float> = []
  for rec in shown
    add(values, AsFloat(get(rec, 'wpm', 0.0)))
  endfor

  var out: list<string> = ['Typing history'] + Table(HEADER, rows)
  add(out, '')
  add(out, totals)
  add(out, missed_line)
  add(out, '')
  add(out, 'WPM trend: ' .. Sparkline(values))
  return out
enddef

def HistoryBuffer(): number
  for info in getbufinfo()
    if bufname(info.bufnr) == BUFFER_NAME
      return info.bufnr
    endif
  endfor
  return -1
enddef

# Read-only scratch split. Calling it again reuses the existing window and
# buffer, so :TypingHistory is idempotent.
export def Show(file: string = DefaultFile())
  var lines = Lines(Load(file))
  var bnr = HistoryBuffer()
  if bnr > 0
    var wins = win_findbuf(bnr)
    if empty(wins)
      execute 'split'
      execute 'buffer ' .. bnr
    else
      win_gotoid(wins[0])
    endif
  else
    execute 'split'
    enew
    execute 'silent file ' .. fnameescape(BUFFER_NAME)
  endif

  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal modifiable
  silent! execute '%delete _'
  setline(1, lines)
  setlocal nomodifiable
  setlocal nomodified
  nnoremap <buffer> <silent> q <Cmd>close<CR>
  cursor(1, 1)
enddef
