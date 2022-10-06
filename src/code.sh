#!/bin/bash
# fusion_inspector 1.0.0
# Extracts a pair of genes from the genome, creates a mini-contig,
# aligns reads to the mini-contig, and extracts the fusion reads as a separate tier for vsiualization


# Output each line as it is executed (-x) and don't stop if any non zero exit codes are seen (+e)
set -x +e

mkdir -p out/fi_outputs/

# download all inputs, untar plug-n-play resources, and get its path
mark-section "download inputs"
dx download "$left_fq" -o R1.fastq.gz
dx download "$right_fq" -o R2.fastq.gz
dx download "$known_fusions" -o fusions_list.txt
dx download "$sr_predictions"
dx download "$genome_lib"
tar xf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus
lib_dir=$(find . -type d -name "GR*plug-n-play")

# Get FusionInspector Docker image by its ID
docker load -i /home/dnanexus/in/fi_docker/*.tar.gz
DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^trinityctat/fusioninspector" | cut -d' ' -f2)

# get the sample name from the chimeric file, then rename to generic
sample_name=$(echo "$sr_predictions" | cut -d '_' -f 1)
mv /home/dnanexus/sr_predictions/*.tsv /home/dnanexus/sr_predictions.tsv

# Prefix for sample naming - to be fixed once workflow is added
prefix="${sample_name/'_R1_concat'/''}"

# Extracts the fusion pairs from the predictions file (unfiltered)
cut -f 1 predicted_fusions.tsv | grep -v '#FusionName' > predicted_fusions.txt

mark-section "run FusionInspector"

# Runs fusion inspector using known_fusions and predicted_fusions files
sudo docker run -v "$(pwd)":/data --rm \
       "${DOCKER_IMAGE_ID}" \
       FusionInspector  \
       --fusions /data/fusions_list.txt,/data/predicted_fusions.txt \
       -O /data/out/fi_outputs/"${prefix}" \
       --left_fq /data/R1.fastq.gz \
       --right_fq /data/R2.fastq.gz \
       --out_prefix "${prefix}"\
       --genome_lib_dir /data/"${lib_dir}"/ctat_genome_lib_build_dir \
       --vis \
       --include_Trinity \
       --examine_coding_effect \
       --extract_fusion_reads_file "${prefix}".FusionInspector-pe_samples/fusion_reads

mark-section "upload outputs"
# upload all outputs
dx-upload-all-outputs --parallel

mark-success

