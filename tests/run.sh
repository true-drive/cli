#!/bin/sh
# Black-box tests for the truedrive binary. Needs FFmpeg on the PATH.
#
# Usage: sh tests/run.sh <path to the truedrive binary>

if [ "$#" -ne 1 ] || [ ! -x "$1" ]; then
  echo "Usage: sh tests/run.sh <path to the truedrive binary>" >&2
  exit 2
fi

if ! ffmpeg -nostdin -f lavfi -i color=s=16x16:d=0.04 -c:v png -pix_fmt monob -f null - >/dev/null 2>&1; then
  echo "These tests need FFmpeg on the PATH" >&2
  exit 2
fi

BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

STDOUT=$ROOT/.stdout
STDERR=$ROOT/.stderr
checks=0
failures=0
case_number=0
is_windows=false

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) is_windows=true ;;
esac

# Starts a test in its own empty folder.
new_case() {
  case_number=$((case_number + 1))
  CASE_NAME=$1
  cd "$ROOT" || exit 2
  mkdir "case$case_number" || exit 2
  cd "case$case_number" || exit 2
  echo "$CASE_NAME"
}

fail() {
  failures=$((failures + 1))
  echo "  FAIL [$CASE_NAME]: $1"
  if [ -s "$STDERR" ]; then
    sed 's/^/    stderr: /' "$STDERR"
  fi
}

# Sanitizer reports must fail the run even where exit status 1 is expected.
check_sanitizers() {
  checks=$((checks + 1))
  if grep -q -E 'Sanitizer|runtime error' "$STDERR"; then
    fail "sanitizer report"
  fi
}

# Runs the CLI, recording its status and output.
run() {
  "$BIN" "$@" >"$STDOUT" 2>"$STDERR" </dev/null
  STATUS=$?
  check_sanitizers
}

expect_status() {
  checks=$((checks + 1))
  [ "$STATUS" -eq "$1" ] || fail "expected exit status $1, got $STATUS"
}

expect_stderr() {
  checks=$((checks + 1))
  grep -q -- "$1" "$STDERR" || fail "stderr should contain '$1'"
}

expect_no_stderr() {
  checks=$((checks + 1))
  if grep -q -- "$1" "$STDERR"; then
    fail "stderr should not contain '$1'"
  fi
}

expect_stdout() {
  checks=$((checks + 1))
  grep -q -- "$1" "$STDOUT" || fail "stdout should contain '$1'"
}

expect_file() {
  checks=$((checks + 1))
  [ -e "$1" ] || fail "'$1' should exist"
}

expect_no_file() {
  checks=$((checks + 1))
  [ ! -e "$1" ] || fail "'$1' should not exist"
}

expect_same() {
  checks=$((checks + 1))
  cmp -s -- "$1" "$2" || fail "'$1' and '$2' should be identical"
}

# Passes when no folder matching the pattern was left behind.
expect_no_match() {
  checks=$((checks + 1))
  for match in $1; do
    [ -e "$match" ] && fail "'$match' should not exist"
  done
}

# Counts folders matching true_drive_<mode>_*.
count_work_folders() {
  count=0
  for match in true_drive_"$1"_*; do
    [ -d "$match" ] && count=$((count + 1))
  done
  echo "$count"
}

# Encodes then decodes $1 through the output path $2 and compares.
round_trip() {
  run encode -i "$1" -o "$2"
  expect_status 0
  expect_file "$2.mkv"
  run decode -i "$2.mkv" -o "$2.restored"
  expect_status 0
  expect_same "$1" "$2.restored"
}

new_case "usage: wrong argument counts"
run
expect_status 1
expect_stderr "Usage:"
run encode
expect_status 1
expect_stderr "Usage:"
run encode -i a
expect_status 1
expect_stderr "Usage:"
run encode -i a -o b extra
expect_status 1
expect_stderr "Usage:"

new_case "usage: unknown command"
run bogus -i a -o b
expect_status 1
expect_stderr "Invalid command 'bogus'"

new_case "usage: unknown option"
run encode -x a -o b
expect_status 1
expect_stderr "Invalid option '-x'"

new_case "usage: both paths are required"
run encode -i a -i b
expect_status 1
expect_stderr "must be provided"
run encode -o a -o b
expect_status 1
expect_stderr "must be provided"

new_case "encode: output must not have an extension"
echo data >in
run encode -i in -o video.mkv
expect_status 1
expect_stderr "should not have an extension"
expect_no_match "true_drive_*"

new_case "output path needs a file name"
echo data >in
mkdir out
run encode -i in -o out/
expect_status 1
expect_stderr "file name"
expect_no_file out/.mkv
expect_no_match "out/true_drive_*"
run decode -i in.mkv -o out/
expect_status 1
expect_stderr "file name"

new_case "round trip: text"
mkdir out
printf 'hello true drive\n' >in.txt
round_trip in.txt out/video
expect_stdout "out/video.restored"

new_case "round trip: binary"
mkdir out
head -c 700000 /dev/urandom >in.bin
round_trip in.bin out/video

new_case "round trip: exactly one frame of data"
mkdir out
head -c 524288 /dev/urandom >in.bin
round_trip in.bin out/video

new_case "round trip: empty file"
mkdir out
: >empty
round_trip empty out/video

new_case "options work in either order"
mkdir out
echo data >in
run encode -o out/video -i in
expect_status 0
expect_file out/video.mkv

new_case "encode: dots in folders are not extensions"
mkdir -p some.folder/out sub
echo data >in
round_trip in ./some.folder/out/video
cd sub || exit 2
round_trip ../in ../some.folder/out/other

new_case "bare output names land in the current folder"
echo data >in
round_trip in video
expect_file video.mkv

new_case "absolute paths"
mkdir out
echo data >in
round_trip "$PWD/in" "$PWD/out/video"

new_case "encode: reports the video it wrote"
mkdir out
echo data >in
run encode -i in -o out/video
expect_status 0
expect_stdout "out/video.mkv"

new_case "encode: keeps an existing video"
echo data >in
echo precious >video.mkv
cp video.mkv expected
run encode -i in -o video
expect_status 1
expect_stderr "already exists"
expect_same video.mkv expected

new_case "decode: replaces an existing file"
echo data >in
echo old-and-much-longer-than-the-new-contents >restored
run encode -i in -o video
run decode -i video.mkv -o restored
expect_status 0
expect_same in restored

new_case "work folder: created next to the output and kept"
mkdir out
echo data >in
run encode -i in -o out/video
expect_status 0
cd out || exit 2
checks=$((checks + 1))
[ "$(count_work_folders encode)" -eq 1 ] || fail "expected one encode folder"
expect_file true_drive_encode_*/frame1.bmp
cd .. || exit 2
run decode -i out/video.mkv -o out/restored
expect_status 0
cd out || exit 2
checks=$((checks + 1))
[ "$(count_work_folders decode)" -eq 1 ] || fail "expected one decode folder"
expect_file true_drive_decode_*/frame1.bmp

new_case "work folder: runs in the same second get their own"
echo data >in
"$BIN" encode -i in -o a >/dev/null 2>"$STDERR" </dev/null &
pid_a=$!
"$BIN" encode -i in -o b >/dev/null 2>/dev/null </dev/null &
pid_b=$!
"$BIN" encode -i in -o c >/dev/null 2>/dev/null </dev/null &
pid_c=$!
"$BIN" encode -i in -o d >/dev/null 2>/dev/null </dev/null &
pid_d=$!
statuses=0
for pid in "$pid_a" "$pid_b" "$pid_c" "$pid_d"; do
  wait "$pid" || statuses=$((statuses + 1))
done
checks=$((checks + 1))
[ "$statuses" -eq 0 ] || fail "$statuses of 4 simultaneous runs failed"
checks=$((checks + 1))
[ "$(count_work_folders encode)" -eq 4 ] || fail "expected four encode folders"

new_case "work folder: failed runs leave nothing behind"
run encode -i missing -o video
expect_status 1
expect_stderr "encode failed"
expect_no_match "true_drive_*"
expect_no_file video.mkv
run decode -i missing.mkv -o restored
expect_status 1
expect_stderr "decode failed"
expect_no_match "true_drive_*"
expect_no_file restored

new_case "output folder must exist"
echo data >in
run encode -i in -o no/such/video
expect_status 1
expect_stderr "work folder"

new_case "decode: rejects bad videos"
echo data >in
run decode -i in -o restored
expect_status 1
expect_stderr "decode failed"
expect_no_file restored
echo 'not a video' >fake.mkv
run decode -i fake.mkv -o restored
expect_status 1
expect_stderr "not a True Drive video"
expect_no_file restored
ffmpeg -nostdin -loglevel quiet -f lavfi -i color=c=black:s=320x240:d=0.1 -c:v png -pix_fmt monob small.mkv
run decode -i small.mkv -o restored
expect_status 1
expect_stderr "not a True Drive video"
expect_no_file restored

new_case "encode: input limit"
head -c 67108864 /dev/zero >big
run encode -i big -o video
expect_status 1
expect_stderr "64 MiB"
expect_no_file video.mkv

new_case "reports a missing FFmpeg"
echo data >in
PATH=/nonexistent "$BIN" encode -i in -o video >"$STDOUT" 2>"$STDERR" </dev/null
STATUS=$?
check_sanitizers
expect_status 1
expect_stderr "FFmpeg is missing"
expect_no_stderr "not found"
expect_no_file video.mkv

if [ "$is_windows" = false ]; then
  new_case "unusual paths"
  echo data >in
  for name in "with space" "quote'inside" 'double"quote' '$(touch injected)' 'semi;colon' '100%' 'per%dcent' 'co:lon'; do
    mkdir "$name"
    round_trip in "$name/video"
  done
  expect_no_file injected

  new_case "a leading dash is a file name, not an option"
  mkdir -- -out
  echo data >in
  round_trip in -out/video

  new_case "backslashes are ordinary characters on POSIX"
  echo data >in
  round_trip in 'back\slash'
  expect_file 'back\slash.mkv'
  checks=$((checks + 1))
  [ "$(count_work_folders encode)" -eq 1 ] || fail "the work folder should not be split at the backslash"
fi

echo
echo "$checks checks, $failures failed"
[ "$failures" -eq 0 ]
