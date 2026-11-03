#!/usr/bin/bash

for i in {1..4}; do

    outdir="Testcase${i}Diff"
    indir="Testcase${i}"
    rm -rf "$outdir"

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

        if [[ -f "${file2}" ]]; then
            if [[ ! -d "$outdir" ]]; then
                mkdir "$outdir"
            fi

            diff -u "$file1" "$file2" > "$outfile"

            if [[ "$?" -eq 0 ]]; then
                rm "${outfile}"
            fi
        fi
    done

    if [[ -d "$outdir" && -z "$(ls -A "$outdir")" ]]; then
        rm -rf $outdir
    fi
done
