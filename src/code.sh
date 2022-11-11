#!/bin/bash
# fusion_inspector 1.0.0
# Extracts a pair of genes from the genome, creates a mini-contig,
# aligns reads to the mini-contig, and extracts the fusion reads as a separate tier for vsiualization

# fail on any error
set -exo pipefail

mkdir -p out/fi_outputs/

# download all inputs, untar plug-n-play resources, and get its path
mark-section "download inputs"
dx-download-all-inputs
tar xf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/
lib_dir=$(find . -type d -name "*CTAT_lib*")

# move each FASTQ into a more sensible directory
# by default every fastq in the array goes into a numbered dir on its own
mkdir /home/dnanexus/r1_fastqs
mkdir /home/dnanexus/r2_fastqs
find ./in/r1_fastqs -type f -name "*R1*" -print0 | xargs -0 -I {} mv {} ./r1_fastqs
find ./in/r2_fastqs -type f -name "*R2*" -print0 | xargs -0 -I {} mv {} ./r2_fastqs

# set up 1 or more fastq files in a list
# TODO: /data/ only getting added to first read 1 entry at the moment - xarg?
read_1=$(find ./r1_fastqs/ -type f -name "*" -name "*R1*.fastq*" | \
sed 's/\.\///g' | sed -e 's/^/\/data\//' | paste -sd, -)
read_2=$(find ./r2_fastqs/ -type f -name "*" -name "*R2*.fastq*" | \
sed 's/\.\///g' | sed -e 's/^/\/data\//' | paste -sd, -)
echo "$read_1"
echo "$read_2"

# get names of fusion files for Docker
known_fusions_name=$(find /home/dnanexus/in/known_fusions -type f -printf "%f\n")
sr_predictions_name=$(find /home/dnanexus/in/sr_predictions -type f -printf "%f\n")

# Get FusionInspector Docker image by its ID
docker load -i /home/dnanexus/in/fi_docker/*.tar.gz
DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^trinityctat/fusioninspector" | cut -d' ' -f2)

# get the sample name from the chimeric file, then rename to generic
prefix=$(echo "$sr_predictions_name" | cut -d '.' -f 1)

# TODO: sanity checking on prefix - check all prefixes match!
# TODO: sanity checking on lanes - stop lane recurring more than once per read

# Extracts the fusion pairs from the predictions file (unfiltered)
cut -f 1 /home/dnanexus/in/sr_predictions/"${sr_predictions_name}" \
| grep -v '#FusionName' > /home/dnanexus/in/sr_predictions/predicted_fusions.txt

# Set up fastq paths for Docker
left_fastqs="${read_1::-1}"
right_fastqs="${read_2::-1}"

mark-section "run FusionInspector"

# Runs fusion inspector using known_fusions and predicted_fusions files
sudo docker run -v "$(pwd)":/data --rm \
       "${DOCKER_IMAGE_ID}" \
       FusionInspector  \
       --fusions /data/in/known_fusions/"${known_fusions_name}",/data/in/sr_predictions/predicted_fusions.txt \
       -O /data/out/fi_outputs \
       --left_fq "${left_fastqs}" \
       --right_fq "${right_fastqs}" \
       --out_prefix "${prefix}" \
       --genome_lib_dir "/data/${lib_dir}/ctat_genome_lib_build_dir" \
       --vis \
       --include_Trinity \
       --examine_coding_effect \
       --extract_fusion_reads_file "${prefix}".FusionInspector-pe_samples/fusion_reads

mark-section "move all output files to a named directory, and add sample names"
# create output directory to move to
final_dir="/home/dnanexus/out/${prefix}_FusionInspector"
mkdir -p "${final_dir}"
# rename and move files
find /home/dnanexus/out/fi_outputs -type f -name "*" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/out/{} "${final_dir}"/"${prefix}"_{}
mark-section "upload outputs"

dx-upload-all-outputs --parallel

mark-success

