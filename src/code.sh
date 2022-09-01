#!/bin/bash
# eggd_fusioninspector 1.0.0

main() {
    # TODO add fusion list?
    set -exo pipefail #if any part goes wrong, job will fail

    dx-download-all-inputs # download inputs from json
    
    dx-jobutil-add-output outdir "$outdir" --class=string
}
