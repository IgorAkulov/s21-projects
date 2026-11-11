#!/usr/bin/env bash

SUT_ARG=${1:-./s21_cat}
MODE=${2:-full}
MAX_FAIL=${MAX_FAIL:-25}
KEEP=${KEEP:-0}

if [ ! -x "$SUT_ARG" ]; then
  echo "не найден исполняемый файл: $SUT_ARG" >&2
  exit 2
fi
if [ "$MODE" != full ] && [ "$MODE" != quick ]; then
  echo "режим: full или quick" >&2
  exit 2
fi

SUT=$(cd "$(dirname "$SUT_ARG")" && pwd)/$(basename "$SUT_ARG")

REF_CAT=cat
if command -v gnucat > /dev/null 2>&1; then
  REF_CAT=gnucat
fi

if "$REF_CAT" --version 2> /dev/null | head -n 1 | grep -q 'GNU coreutils'; then
  REF=gnu
elif "$REF_CAT" --help 2>&1 | head -n 1 | grep -qi busybox; then
  REF=busybox
else
  REF=other
fi

TMP=$(mktemp -d) || exit 2
if [ "$KEEP" = 1 ]; then
  echo "временная папка сохранена: $TMP"
else
  trap 'rm -rf "$TMP"' EXIT
fi
cd "$TMP" || exit 2
mkdir out dir || exit 2

put() {
  printf '%b' "$2" > "$1"
}

bytes() {
  local i
  for ((i = $1; i <= $2; i++)); do
    printf "\\x$(printf '%02x' "$i")"
  done
}

gen_random() {
  local seed=$1 count=$2 name=$3
  shift 3
  local alphabet=("$@")
  local n=${#alphabet[@]} i
  RANDOM=$seed
  {
    for ((i = 0; i < count; i++)); do
      printf '%b' "${alphabet[RANDOM % n]}"
    done
  } > "$name"
}

put empty ''
put one_char_nonl 'a'
put only_nl '\n'
put many_nl '\n\n\n\n\n'
put text 'one\ntwo\nthree\n'
put text_nonl 'one\ntwo\nthree'
put blank_between 'a\n\nb\n\n\nc\n\n\n\nd\n'
put blank_start '\n\n\nstart\n'
put blank_end 'end\n\n\n\n'
put blank_both '\n\nx\n\n'
put spaces '   \n \t \n  x  \n'
put tabs '\ta\tb\t\n\t\t\n'
put tab_only '\t'
put del 'a\x7fb\n'
put utf8 'привет\nüñí\n日本語\n'
put crlf 'a\r\nb\r\n\r\nc\td\r\n'
put cr_mid 'a\rb\n'
put cr_eof 'a\r'
put cr_only '\r'
put cr_cr_lf 'a\r\r\n'
put cr_cr_cr_lf 'a\r\r\r\n'
put crlf_blank '\r\n\r\n\r\n'
put lf_cr '\n\r\n\r'
put crlf_nonl 'a\r\nb'
put nul 'a\0b\n\0\n'
put -dash 'dash\n'
{ bytes 1 31; printf '\n'; } > ctrl
{ bytes 128 255; printf '\n'; } > high
bytes 1 255 > allbytes
head -c 20000 /dev/zero | tr '\0' 'x' > long_line
seq 1 1500 > many_lines
gen_random 1 3000 rnd_text 'a' 'b' ' ' '\t' '\n' '\n' '\n' 'c'
gen_random 2 3000 rnd_crlf 'a' '\r' '\n' '\r\n' '\r\n' '\t' ' '
gen_random 3 3000 rnd_bin 'a' ' ' '\t' '\n' '\r' '\x01' '\x1b' '\x7f' '\x80' '\xc3\xa9' '\xff' '\0'
if [ "$MODE" = full ]; then
  yes x | head -n 1000010 > big
fi

SINGLE_FILES=()
for f in ./*; do
  [ -f "$f" ] || continue
  [ "$f" = ./big ] && continue
  SINGLE_FILES+=("$f")
done

if [ "$REF" = gnu ]; then
  SHORT=(b e E n s t T v A)
  LONG=(--number --number-nonblank --squeeze-blank --show-all --show-ends
    --show-tabs --show-nonprinting)
  EXTRA=(-u)
  QUICK_PAIR_FLAGS=(-n -b -s -nb -sn -sb -vE -nE -bE -sE -e -A)
  ERR_FLAGS=("" -n -b -s -v -e -A -nb -sn -sb)
  BIG_FLAGS=("" -n -b -s -A -nb -sn)
  DASH_FLAGS="-b -s --"
else
  SHORT=(b e n t v A)
  LONG=()
  EXTRA=()
  QUICK_PAIR_FLAGS=(-n -b -nb -ve -e -A -nv -bv)
  ERR_FLAGS=("" -n -b -v -e -A -nb)
  BIG_FLAGS=("" -n -b -A -nb)
  DASH_FLAGS="-b -n --"
fi

FLAGSETS_1=("")
for c in "${SHORT[@]}"; do
  FLAGSETS_1+=("-$c")
done
FLAGSETS_1+=("${LONG[@]}" "${EXTRA[@]}")

FLAGSETS_2=()
for a in "${SHORT[@]}"; do
  for b in "${SHORT[@]}"; do
    FLAGSETS_2+=("-$a -$b" "-$a$b")
  done
done

FLAGSETS_3=()
count=${#SHORT[@]}
for ((i = 0; i < count; i++)); do
  for ((j = i + 1; j < count; j++)); do
    for ((k = j + 1; k < count; k++)); do
      FLAGSETS_3+=("-${SHORT[i]}${SHORT[j]}${SHORT[k]}"
        "-${SHORT[k]} -${SHORT[j]} -${SHORT[i]}")
    done
  done
done

FLAGSETS_MIXED=()
if [ "$REF" = gnu ]; then
  FLAGSETS_MIXED=("--number --squeeze-blank" "-n --squeeze-blank"
    "--number-nonblank -n" "-b --number" "--show-all -n" "-s --show-all -b"
    "--show-tabs --show-ends" "-vT" "-ET" "-vE" "-e -T" "-t -E"
    "--show-nonprinting --show-ends -s" "-A -s -n" "-A -s -b" "-nbsvET"
    "-sbA" "-n -n" "-bb")
fi

FLAGSETS_PAIRS_SHORT=()
for ((i = 0; i < count; i++)); do
  for ((j = i; j < count; j++)); do
    FLAGSETS_PAIRS_SHORT+=("-${SHORT[i]}${SHORT[j]}")
  done
done

PAIR_FILES=(empty one_char_nonl only_nl text text_nonl blank_between
  blank_start blank_end tabs crlf cr_eof cr_only cr_mid nul)
if [ "$MODE" = quick ]; then
  PAIR_FILES=(empty text_nonl blank_between crlf cr_eof cr_mid)
fi

TOTAL=0
PASSED=0
FAILED=0
LAST_PROGRESS=$SECONDS

report_failure() {
  [ "$FAILED" -le "$MAX_FAIL" ] || return 0
  echo "РАСХОЖДЕНИЕ: ${FLAGS[*]} ${FILES[*]}  (код sut=$rc_sut ref=$rc_ref)"
  cmp out/sut out/ref 2>&1 | head -n 1 | sed 's/^/    /'
  echo "    sut: $(head -c 60 out/sut | od -An -c | tr -s ' ' | tr -d '\n')"
  echo "    ref: $(head -c 60 out/ref | od -An -c | tr -s ' ' | tr -d '\n')"
}

check() {
  read -ra FLAGS <<< "$1"
  read -ra FILES <<< "$2"
  TOTAL=$((TOTAL + 1))
  "$SUT" "${FLAGS[@]}" "${FILES[@]}" < /dev/null \
    > out/sut 2> /dev/null
  rc_sut=$?
  "$REF_CAT" "${FLAGS[@]}" "${FILES[@]}" < /dev/null \
    > out/ref 2> /dev/null
  rc_ref=$?
  if [ "$rc_sut" -eq "$rc_ref" ] && cmp -s out/sut out/ref; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    report_failure
  fi
  if (( TOTAL % 100 == 0 || SECONDS - LAST_PROGRESS >= 5 )); then
    printf 'проверено: %d, удач: %d, расхождений: %d\n' \
      "$TOTAL" "$PASSED" "$FAILED"
    LAST_PROGRESS=$SECONDS
  fi
}

run_single_files() {
  local fs f
  for fs in "$@"; do
    for f in "${SINGLE_FILES[@]}"; do
      check "$fs" "$f"
    done
  done
}

run_file_pairs() {
  local fs a b
  for fs in "$@"; do
    for a in "${PAIR_FILES[@]}"; do
      for b in "${PAIR_FILES[@]}"; do
        check "$fs" "$a $b"
      done
    done
  done
}

run_file_triples() {
  local fs
  for fs in "$@"; do
    check "$fs" "cr_eof empty crlf"
    check "$fs" "cr_eof nofile crlf"
    check "$fs" "cr_eof cr_only cr_only blank_start"
    check "$fs" "text_nonl text_nonl text_nonl"
    check "$fs" "blank_end blank_start blank_end"
    check "$fs" "empty empty empty"
    check "$fs" "one_char_nonl cr_eof tab_only crlf_nonl text"
    check "$fs" "nul ctrl high allbytes rnd_bin"
  done
}

run_errors() {
  local fs
  for fs in "${ERR_FLAGS[@]}"; do
    check "$fs" "text nofile text"
    check "$fs" "nofile"
    check "$fs" "nofile nofile2"
    check "$fs" "dir"
    check "$fs" "text dir text"
    check "$fs" "dir dir"
  done
  for fs in -z --bogus "-n -z" "-z -n" -nz; do
    check "$fs" "text"
    check "$fs" "text crlf"
  done
  check "--" "-dash"
  check "-n --" "-dash"
  check "-n --" "text -dash"
  check "$DASH_FLAGS" "-dash text -dash"
}

echo "эталон: $REF; режим: $MODE; программа: $SUT_ARG"

run_single_files "${FLAGSETS_1[@]}"
run_single_files "${FLAGSETS_2[@]}"
run_single_files "${FLAGSETS_MIXED[@]}"
if [ "$MODE" = full ]; then
  run_single_files "${FLAGSETS_3[@]}"
fi

run_file_pairs "${FLAGSETS_1[@]}"
if [ "$MODE" = full ]; then
  run_file_pairs "${FLAGSETS_PAIRS_SHORT[@]}"
else
  run_file_pairs "${QUICK_PAIR_FLAGS[@]}"
fi

run_file_triples "${FLAGSETS_1[@]}"
run_errors

if [ "$MODE" = full ]; then
  for fs in "${BIG_FLAGS[@]}"; do
    check "$fs" big
  done
fi

echo "всего: $TOTAL, удач: $PASSED, расхождений: $FAILED"
[ "$FAILED" -eq 0 ]

