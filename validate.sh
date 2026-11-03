#!/usr/bin/env bash
#
# validate.sh - tests a check.sh (and script.sh) for ILC 7
#
# Usage:  bash validate.sh [path-to-repo]       (default: current directory)
#
# Output: one "TestcaseN: PASS" line for every Testcase folder where all tests pass.
#         For a Testcase where something fails, only the failing tests are printed.
#
# For every Testcase folder it checks:
#   script.sh : TestcaseNDiff/ exists when the Testcase has differences (and not otherwise),
#               and the files inside have the correct `diff -u` output
#   check.sh  : exits 0 and prints "TestcaseN: PASS" on the correct output, and prints
#               "TestcaseN: FAIL" (exit non-zero) when, for that Testcase,
#                 - TestcaseNDiff/ is missing although it should exist
#                 - a file inside TestcaseNDiff/ has the wrong contents
#                 - an output file exists for a pair that is identical
#                 - TestcaseNDiff/ exists although nothing differs
#
# Only the given Testcase files are used; nothing is added except by editing/removing the
# output folders in a temp copy. The repo itself is never modified.
#
# Exit status: 0 if every test passes, 1 otherwise, 2 on a setup problem.

set -u

REPO="$(cd "${1:-.}" 2>/dev/null && pwd)" || { echo "Usage: bash $0 [path-to-repo]"; exit 2; }
[ -f "$REPO/check.sh" ] || { echo "No check.sh found in $REPO"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run() { if command -v timeout >/dev/null 2>&1; then timeout 30 "$@"; else "$@"; fi; }

# ---- results are collected per Testcase (0 = general, not tied to one Testcase) ----
RES_N=(); RES_OK=(); RES_MSG=()
record() { RES_N+=("$1"); RES_OK+=("$2"); RES_MSG+=("$3"); }   # <testcase> <1|0> <message>

# Match files with the same name but different number endings.
pairs_for_dir() {   # <base> <dir>  ->  "key|fileA|fileB" (paths relative to base)
    local base=$1 dir=$2 f b key suf i n
    local keys=() files=() lines=""
    lines=$(
        cd "$base" || exit
        for f in "$dir"/*.txt; do
            [ -f "$f" ] || continue
            b=$(basename "$f" .txt)
            if [[ $b =~ ^(.*)\.([0-9]+)$ ]]; then key=${BASH_REMATCH[1]}; suf=${BASH_REMATCH[2]}
            else key=$b; suf=0; fi
            key=${key// /}
            printf '%s|%s|%s\n' "$key" "$suf" "$f"
        done | LC_ALL=C sort -V
    )
    [ -n "$lines" ] || return 0
    while IFS='|' read -r key suf f; do keys+=("$key"); files+=("$f"); done <<< "$lines"
    n=${#keys[@]}; i=0
    while [ "$i" -lt "$n" ]; do
        if [ $((i + 1)) -lt "$n" ] && [ "${keys[i]}" = "${keys[i + 1]}" ] \
           && { [ $((i + 2)) -ge "$n" ] || [ "${keys[i + 2]}" != "${keys[i]}" ]; }; then
            printf '%s|%s|%s\n' "${keys[i]}" "${files[i]}" "${files[i + 1]}"
            i=$((i + 2))
        else
            i=$((i + 1))
        fi
    done
}

testcase_dirs() {   # <base> -> Testcase1 Testcase2 ... (input folders only, sorted)
    local d
    for d in "$1"/Testcase*; do
        [ -d "$d" ] && [[ $(basename "$d") =~ ^Testcase[0-9]+$ ]] && basename "$d"
    done | LC_ALL=C sort -V
}

make_golden() {     # <base>  writes the correct TestcaseNDiff/ folders into <base>
    local base=$1 t n key a b
    for t in $(testcase_dirs "$base"); do
        n=${t#Testcase}
        rm -rf "${base:?}/Testcase${n}Diff"
        while IFS='|' read -r key a b; do
            [ -n "$key" ] || continue
            if ! cmp -s "$base/$a" "$base/$b"; then
                mkdir -p "$base/Testcase${n}Diff"
                (cd "$base" && diff -u "$a" "$b" > "Testcase${n}Diff/${key}Diff.txt")
            fi
        done < <(pairs_for_dir "$base" "$t")
    done
}

listing_tc() { (cd "$1" && find . -mindepth 1 -path "./Testcase$2Diff*" | LC_ALL=C sort); }

# Compare the generated files, ignoring the first two diff header lines.
same_output_tc() {  # <goodbase> <otherbase> <n>: same files/dirs and contents (ignoring 2 header lines)
    local g=$1 o=$2 n=$3 f
    [ "$(listing_tc "$g" "$n")" = "$(listing_tc "$o" "$n")" ] || return 1
    while IFS= read -r f; do
        [ -f "$g/$f" ] || continue
        diff <(tail -n +3 "$g/$f") <(tail -n +3 "$o/$f") >/dev/null 2>&1 || return 1
    done < <(listing_tc "$g" "$n")
    return 0
}

# ---------------------------------------------------------------------------------------------
# Setup: copy only what is needed (Testcase folders + the two scripts), build the good output
# ---------------------------------------------------------------------------------------------
copy_inputs() {     # <dest>
    local t
    mkdir -p "$1"
    for t in $TESTCASES; do cp -a "$REPO/$t" "$1/"; done
    cp -a "$REPO/check.sh" "$1/"
    [ -f "$REPO/script.sh" ] && cp -a "$REPO/script.sh" "$1/"
    return 0
}

TESTCASES="$(testcase_dirs "$REPO")"
[ -n "$TESTCASES" ] || { echo "No TestcaseN/ folders found in $REPO"; exit 2; }
GOOD="$TMP/good"; copy_inputs "$GOOD"; make_golden "$GOOD"

RC=0; OUT=""
run_check() { OUT="$(cd "$1" && run bash check.sh 2>/dev/null)"; RC=$?; }

expect_fail() {     # <label> <testcase number>   (runs check.sh in $GOOD, which is currently broken)
    run_check "$GOOD"
    if [ "$RC" -eq 0 ]; then
        record "$2" 0 "$1 (not detected: check.sh exited 0)"
    elif ! grep -q "^Testcase$2: FAIL" <<< "$OUT"; then
        record "$2" 0 "$1 (exit $RC, but no 'Testcase$2: FAIL' line printed)"
    else
        record "$2" 1 "$1"
    fi
}

# ------------------------------- 1. script.sh: folder exists when it should, files correct -------------------------------
if [ -f "$REPO/script.sh" ]; then
    REGEN="$TMP/regen"; copy_inputs "$REGEN"
    (cd "$REGEN" && run bash script.sh >/dev/null 2>&1)
    for t in $TESTCASES; do
        n=${t#Testcase}
        if same_output_tc "$GOOD" "$REGEN" "$n"; then
            record "$n" 1 "script.sh output"
        elif [ -d "$GOOD/Testcase${n}Diff" ] && [ ! -d "$REGEN/Testcase${n}Diff" ]; then
            record "$n" 0 "script.sh did not create Testcase${n}Diff/"
        elif [ ! -d "$GOOD/Testcase${n}Diff" ] && [ -d "$REGEN/Testcase${n}Diff" ]; then
            record "$n" 0 "script.sh created Testcase${n}Diff/ but nothing differs in $t"
        else
            record "$n" 0 "script.sh: files in Testcase${n}Diff/ are missing or have the wrong contents"
        fi
    done
else
    record 0 0 "script.sh not found"
fi

# ------------------------------- 2. check.sh on correct output -------------------------------
run_check "$GOOD"
if [ "$RC" -eq 0 ]; then record 0 1 "check.sh exits 0 on correct output"
else record 0 0 "check.sh exits 0 on correct output (got $RC)"; fi
for t in $TESTCASES; do
    n=${t#Testcase}
    nlines=$(grep -c "^Testcase$n: " <<< "$OUT")
    if [ "$nlines" -eq 1 ] && grep -q "^Testcase$n: PASS" <<< "$OUT"; then
        record "$n" 1 "check.sh prints one PASS line on correct output"
    else
        record "$n" 0 "check.sh should print exactly one 'Testcase$n: PASS' line on correct output (found $nlines line(s) for it)"
    fi
done

# ------------------------------- 3. check.sh on broken output -------------------------------
# Each case breaks $GOOD in place, runs check.sh, then restores it (no extra copies).
for t in $TESTCASES; do
    n=${t#Testcase}; out="$GOOD/Testcase${n}Diff"
    if [ -d "$out" ]; then
        # folder missing although it should exist
        mv "$out" "$TMP/saved_dir"
        expect_fail "folder missing: Testcase${n}Diff/" "$n"
        mv "$TMP/saved_dir" "$out"

        # wrong contents in a file inside the folder (first file)
        f="$(cd "$out" && ls -1 | LC_ALL=C sort -V | head -n 1)"
        cp -p "$out/$f" "$TMP/saved_file"
        echo "THIS LINE SHOULD NOT BE HERE" >> "$out/$f"
        expect_fail "wrong contents: Testcase${n}Diff/$f" "$n"
        cp -p "$TMP/saved_file" "$out/$f"

        # output file for an identical pair (first identical pair in this Testcase, if any)
        while IFS='|' read -r key a b; do
            [ -n "$key" ] || continue
            if cmp -s "$GOOD/$a" "$GOOD/$b"; then
                echo "should not exist" > "$out/${key}Diff.txt"
                expect_fail "output file for identical pair: Testcase${n}Diff/${key}Diff.txt" "$n"
                rm -f "$out/${key}Diff.txt"
                break
            fi
        done < <(pairs_for_dir "$GOOD" "$t")
    else
        # folder present although nothing differs
        mkdir "$out"
        expect_fail "folder Testcase${n}Diff/ exists but nothing differs" "$n"
        rmdir "$out"
    fi
done

# ------------------------------- report -------------------------------
echo "Validating: $REPO"
BAD_TC=0

# tests not tied to one Testcase are only shown if they failed
general_failed=0
for i in "${!RES_N[@]}"; do
    if [ "${RES_N[i]}" -eq 0 ] && [ "${RES_OK[i]}" -eq 0 ]; then
        [ "$general_failed" -eq 0 ] && echo "General: FAIL"
        general_failed=1
        echo "    - ${RES_MSG[i]}"
    fi
done
[ "$general_failed" -eq 1 ] && BAD_TC=$((BAD_TC + 1))

for t in $TESTCASES; do
    n=${t#Testcase}
    failed=0
    for i in "${!RES_N[@]}"; do
        [ "${RES_N[i]}" -eq "$n" ] && [ "${RES_OK[i]}" -eq 0 ] && failed=$((failed + 1))
    done
    if [ "$failed" -eq 0 ]; then
        echo "Testcase$n: PASS"
    else
        BAD_TC=$((BAD_TC + 1))
        echo "Testcase$n: FAIL"
        for i in "${!RES_N[@]}"; do
            [ "${RES_N[i]}" -eq "$n" ] && [ "${RES_OK[i]}" -eq 0 ] && echo "    - ${RES_MSG[i]}"
        done
    fi
done

[ "$BAD_TC" -eq 0 ]
