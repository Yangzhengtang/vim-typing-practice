vim9script
# Local resume positions, replaced atomically in the destination directory.

export def DefaultFile(): string
  return get(g:, 'typing_progress_file',
    expand('~/.vim/typing-practice/progress.json'))
enddef

export def Fingerprint(lines: list<string>): string
  return sha256(join(lines, "\n"))
enddef

export def Load(file: string): dict<any>
  try
    var value = json_decode(join(readfile(file), "\n"))
    return type(value) == v:t_dict ? value : {}
  catch
    return {}
  endtry
enddef

export def Get(file: string, path: string): dict<any>
  var entry = get(Load(file), path, {})
  return type(entry) == v:t_dict ? entry : {}
enddef

def Write(file: string, entries: dict<any>): bool
  var tmp = ''
  try
    var dir = fnamemodify(file, ':h')
    if !isdirectory(dir)
      mkdir(dir, 'p')
    endif
    # tempname supplies a unique basename; keep the file on the same filesystem.
    tmp = dir .. '/.typing-progress-' .. getpid() .. '-'
      .. fnamemodify(tempname(), ':t')
    if writefile([json_encode(entries)], tmp) != 0
      return false
    endif
    return rename(tmp, file) == 0
  catch
    return false
  finally
    if tmp != ''
      try
        delete(tmp)
      catch
      endtry
    endif
  endtry
  return false
enddef

export def Save(file: string, path: string, entry: dict<any>): bool
  try
    var entries = Load(file)
    entries[path] = entry
    return Write(file, entries)
  catch
    return false
  endtry
enddef

export def Remove(file: string, path: string): bool
  try
    var entries = Load(file)
    if !has_key(entries, path)
      return true
    endif
    remove(entries, path)
    return Write(file, entries)
  catch
    return false
  endtry
enddef
