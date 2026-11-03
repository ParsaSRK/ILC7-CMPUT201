#!/usr/bin/bash

ret=0
for i in {1..4}; do
    outdir="Testcase${i}Diff"
    indir="Testcase${i}"

    pass=1
    any=0
    for file in "${indir}"/*.1.txt; do
        if [[ ! -f "$file" ]]; then
            continue
        fi

        name="${file##*/}"
        name="${name%.1.txt}"

        name1="${name}.1.txt"
        name2="${name}.2.txt"
        outname="${name}Diff.txt"

        file1="${indir}/${name1}"
        file2="${indir}/${name2}"
        outfile="${outdir}/${outname}"

        if [[ -f "$file2" ]]; then
            diff -u "$file1" "$file2" > /dev/null
            if [[ "$?" -ne 0 ]]; then
                any=1
                if [[ ! -f "$outfile" ]]; then
                    echo "File should exist $outfile" >&2
                    pass=0
                else 
                    diff -u \
                        <(tail -n +3 "$outfile") \
                        <(diff -u "$file1" "$file2" | tail -n +3) \
                        > /dev/null
                    if [[ "$?" -ne 0 ]]; then
                        echo "Diff not correct for $outfile" >&2
                        pass=0
                    fi
                fi
            else
                if [[ -f "$outfile" ]]; then
                    echo "File should not exist: $outfile" >&2
                    pass=0
                fi
            fi
        fi
    done

    if [[ "$any" -ne 0 && ! -d "$outdir" ]]; then
        echo "Dir should exist $outdir" >&2
        pass=0
    fi

    if [[ "$any" -eq 0 && -d "$outdir" ]]; then
        echo "Dir should not exist $outdir" >&2
        pass=0
    fi

    if [[ "$pass" -eq 0 ]]; then
        echo "Testcase${i}: FAIL"
        ret=1
    else
        echo "Testcase${i}: PASS"
    fi
done

exit $ret
