#!/bin/bash
# eggd_fusioninspector 1.0.0

main() {
    set -e -x -v -o pipefail

    mark-section "download the input files"
    dx-download-all-inputs
    
    mark-section "install sentieon, run license setup script"
    tar xvzf /home/dnanexus/in/sentieon_tar/sentieon-genomics-*.tar.gz -C /usr/local
    tar xvzf /home/dnanexus/in/genome_indexes/*.tar.gz -C /home/dnanexus/genomeDir #transcript data from that release of gencode
    tar xvzf /home/dnanexus/in/reference_genome/*tar.gz -C /home/dnanexus/reference_genome

    source /home/dnanexus/license_setup.sh
    export SENTIEON_INSTALL_DIR=/usr/local/sentieon-genomics-*
    SENTIEON_BIN_DIR="$SENTIEON_INSTALL_DIR/bin"
    export PATH="$SENTIEON_BIN_DIR:$PATH"

    mark-section "set up parameters and run FusionInspector"
    export STAR_REFERENCE=/home/dnanexus/genomeDir/*.plug-n-play/ctat_genome_lib_build_dir/ref_genome.fa.star.idx/
    
    senteion FusionInspector --fusions "${fusion_candidates}" \
    --genome_lib /path/to/CTAT_genome_lib \
    --left_fq "${left_fq}" \
    --right_fq "${right_fq}" \
    --out_dir "${outdir}" \
    --out_prefix "fusion_inspector" \
    --include_Trinity \
    --vis

    mark-section "preparing the outputs for upload"
	mv ~/"${outdir}" ~/out/"${outdir}"
    mark-success

    # TODO add rescuing of common candidate fusions
}
