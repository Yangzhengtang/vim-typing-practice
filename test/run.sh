#!/bin/sh
# Run every test/test_*.vim (or the files given as arguments) in a clean,
# headless Vim: no vimrc, no viminfo, only this plugin on the runtimepath.
# Exits non-zero if any test file reports a failure. Each file is killed after
# TEST_TIMEOUT seconds (default 120) so a Vim waiting for input cannot hang the run.

cd "$(dirname "$0")/.." || exit 1
# The render tests compare screen attributes, which need a colour terminal type
# even though no terminal is attached.
case "${TERM:-dumb}" in dumb|unknown) TERM=xterm-256color; export TERM ;; esac
root=$(pwd)
[ $# -eq 0 ] && set -- test/test_*.vim

# Vim ignores SIGALRM, so a small perl parent kills it when the time is up.
watchdog='my $t = shift; my $pid = fork; if (!$pid) { exec @ARGV or exit 127 }
$SIG{ALRM} = sub { kill "KILL", $pid }; alarm $t; waitpid $pid, 0;
exit($? & 127 ? 124 : $? >> 8)'

failed=0
for t in "$@"; do
  out=$(mktemp)
  perl -e "$watchdog" "${TEST_TIMEOUT:-120}" \
    vim -Nu NONE -i NONE --not-a-term \
    --cmd "set runtimepath^=$root" \
    --cmd "let g:test_file = '$t'" \
    --cmd "let g:test_out = '$out'" \
    -S test/harness.vim >/dev/null 2>&1 </dev/null
  status=$?
  if [ $status -eq 0 ] && [ ! -s "$out" ]; then
    echo "ok    $t"
  else
    failed=1
    [ $status -eq 124 ] && echo "timed out" >>"$out"
    echo "FAIL  $t (vim exit $status)"
    sed 's/^/      /' "$out"
  fi
  rm -f "$out"
done
exit $failed
