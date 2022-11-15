#!/bin/bash
# fusion_inspector 1.0.0
# Extracts a pair of genes from the genome, creates a mini-contig,
# aligns reads to the mini-contig, and extracts the fusion reads as a separate tier for vsiualization

# fail on any error
set -exo pipefail

mkdir -p out/fi_outputs/

# download all inputs, untar plug-n-play resources, and get its path
mark-section "download inputs and set up initial directories"
dx-download-all-inputs
tar xf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/
lib_dir=$(find . -type d -name "*CTAT_lib*")

# move array:file uploads into more sensible directories
# this is done to make finding files easier because, by default, every file in the array goes into a numbered dir on its own
mkdir /home/dnanexus/r1_fastqs
mkdir /home/dnanexus/r2_fastqs
mkdir /home/dnanexus/known_fusions

find ./in/r1_fastqs -type f -name "*R1*" -print0 | xargs -0 -I {} mv {} ./r1_fastqs
find ./in/r2_fastqs -type f -name "*R2*" -print0 | xargs -0 -I {} mv {} ./r2_fastqs
find ./in/known_fusions -type f -name "*.txt*" -print0 | xargs -0 -I {} mv {} ./known_fusions

# form array:file uploads in a comma-separated list - prepend '/data/' path, for use in Docker
read_1=$(find ./r1_fastqs/ -type f -name "*" -name "*R1*.fastq*" | \
sed 's/\.\///g' | sed -e 's/^/\/data\//' | paste -sd, -)
read_2=$(find ./r2_fastqs/ -type f -name "*" -name "*R2*.fastq*" | \
sed 's/\.\///g' | sed -e 's/^/\/data\//' | paste -sd, -)
known_fusions=$(find ./known_fusions/ -type f -name "*" | \
sed 's/\.\///g' | sed -e 's/^/\/data\//' | paste -sd, -)
echo "$known_fusions"
echo "$read_1"
echo "$read_2"

# slightly reformat the STAR-Fusion predicted fusions for Docker
sr_predictions_name=$(find /home/dnanexus/in/sr_predictions -type f -printf "%f\n")
cut -f 1 /home/dnanexus/in/sr_predictions/"${sr_predictions_name}" \
| grep -v '#FusionName' > /home/dnanexus/in/sr_predictions/predicted_fusions.txt

# Get FusionInspector Docker image by its ID
docker load -i /home/dnanexus/in/fi_docker/*.tar.gz
DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^trinityctat/fusioninspector" | cut -d' ' -f2)

# get the sample name from the chimeric file, then rename to generic
prefix=$(echo "$sr_predictions_name" | cut -d '.' -f 1)

# TODO: sanity checking on prefix - check read prefixes match!


# TODO: sanity checking on lanes - stop lane recurring more than once per read


# make output dir
mkdir -p "/home/dnanexus/out/fi_outputs"

mark-section "run FusionInspector"

# Runs fusion inspector using known_fusions and predicted_fusions files
sudo docker run -v "$(pwd)":/data --rm \
       "${DOCKER_IMAGE_ID}" \
       FusionInspector  \
       --fusions "${known_fusions}",/data/in/sr_predictions/predicted_fusions.txt \
       -O /data/out/fi_outputs \
       --left_fq "${read_1}" \
       --right_fq "${read_2}" \
       --out_prefix "${prefix}" \
       --genome_lib_dir "/data/${lib_dir}/ctat_genome_lib_build_dir" \
       --vis \
       --include_Trinity \
       --examine_coding_effect \
       --extract_fusion_reads_file FusionInspector_fusion_reads

mark-section "add sample names to all files in the output directory"

# rename files in the output directory, using mv
find /home/dnanexus/out/fi_outputs -type f -name "*" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/out/fi_outputs/{} /home/dnanexus/out/fi_outputs/"${prefix}"_{}
mark-section "upload outputs"

dx-upload-all-outputs --parallel

mark-success

