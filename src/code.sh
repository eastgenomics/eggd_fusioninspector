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
tar -xf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/
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

# slightly reformat the STAR-Fusion predicted fusions for Docker
sr_predictions_name=$(find /home/dnanexus/in/sr_predictions -type f -printf "%f\n")
cut -f 1 /home/dnanexus/in/sr_predictions/"${sr_predictions_name}" \
| grep -v '#FusionName' > /home/dnanexus/in/sr_predictions/predicted_fusions.txt

# Get FusionInspector Docker image by its ID
docker load -i /home/dnanexus/in/fi_docker/*.tar.gz
DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^trinityctat/fusioninspector" | cut -d' ' -f2)

# get the sample name from the chimeric file
prefix=$(echo "$sr_predictions_name" | cut -d '.' -f 1)


## Tests
# Check that there are the same number of R1s as R2s
cd /home/dnanexus/r1_fastqs
R1=($(ls *R1*))
cd /home/dnanexus/r2_fastqs
R2=($(ls *R2*))
cd /home/dnanexus
if [[ ${#R1[@]} -ne ${#R2[@]} ]]; then 
       echo "The number of R1 and R2 files for this sample are not equal"
       exit 1
fi

# Check that each R1 has a matching R2
# Remove "R1" and "R2" and the file suffix from all file names
_trim_fastq_endings () {
       # Trims the endings off R1 or R2 file names in an array, and returns as an array.
       # Identify and cut off suffixes. Export suffix for later use.
       local fastq_array=("$@")
       local read_to_cut=$1
       if [[ "${fastq_array[1]}" == *".fastq.gz" ]]; then
              fastq_suffix=".fastq.gz"
              export fastq_suffix
       elif [[ "${fastq_array[1]}" == *".fq.gz" ]]; then
              fastq_suffix=".fq.gz"
              export fastq_suffix
       else
              echo "Suffixes of fastq files not recognised as .fq.gz or .fastq.gz"
              exit 1
       fi
       for i in "${!fastq_array[@]}"; do
              fastq_array[$i]=${fastq_array[$i]//$read_to_cut/};
              fastq_array[$i]=${fastq_array[$i]//$fastq_suffix/};
       done
       echo ${fastq_array[@]}
}

R1_test=$(_trim_fastq_endings "R1" ${R1[@]})
R2_test=$(_trim_fastq_endings "R2" ${R2[@]})

# Test that when "R1" and "R2" are removed the two arrays have identical file names
for i in "${!R1_test[@]}"; do
       if [[ ! "${R2_test}" =~ "${R1_test[$i]}" ]]; then 
              echo "Each R1 FASTQ does not appear to have a matching R2 FASTQ"
              echo "${R2_test} ${R1_test[$i]}"
              exit 1 
       fi
done

# TODO: Test that the start of the read files, begin with the expected 'prefix' taken from the STAR-Fusion predictions


# make temporary and final output dirs
mkdir "/home/dnanexus/temp_out"
mkdir -p "/home/dnanexus/out/fi_abridged"
mkdir "/home/dnanexus/out/fi_full"
mkdir "/home/dnanexus/out/fi_coding"
mkdir "/home/dnanexus/out/fi_html"
if [ "$include_trinity" = "true" ]; then
       mkdir "/home/dnanexus/out/fi_trinity_fasta"
       mkdir "/home/dnanexus/out/fi_trinity_gff"
       mkdir "/home/dnanexus/out/fi_trinity_bed"
fi

# Obtain instance information to set CPU flexibly
INSTANCE=$(dx describe --json $DX_JOB_ID | jq -r '.instanceType')  # Extract instance type
NUMBER_THREADS=${INSTANCE##*_x}

# set up the FusionInspector command 
wd="$(pwd)"
fusion_ins="docker run -v ${wd}:/data --rm \
       ${DOCKER_IMAGE_ID} \
       FusionInspector  \
       --fusions ${known_fusions},/data/in/sr_predictions/predicted_fusions.txt \
       -O /data/temp_out \
       -CPU ${NUMBER_THREADS} \
       --left_fq ${read_1} \
       --right_fq ${read_2} \
       --out_prefix ${prefix} \
       --genome_lib_dir /data/${lib_dir}/ctat_genome_lib_build_dir \
       --vis \
       --examine_coding_effect \
       --extract_fusion_reads_file ${prefix}.fusion_reads"


# run FusionInspector, adding an arg to run Trinity if requested by user, and adding optional user-entered parameters if any 
if [ "$include_trinity" = "true" ]; then
       mark-section "Adding Trinity de novo reconstruction option to FusionInspector command"
       fusion_ins="${fusion_ins} --include_Trinity"
fi

if [ -n "$parameters" ]; then
       mark-section "Adding additional user-entered parameters to FusionInspector command"
       fusion_ins="${fusion_ins} ${parameters}"
fi

mark-section "Running FusionInspector"
eval "${fusion_ins}"


mark-section "move results files to their output directories"

find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.abridged.tsv" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_abridged/{}

find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.tsv" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_full/{}

find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.abridged.tsv.coding_effect" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_coding/{} 

find /home/dnanexus/temp_out -type f -name "*.fusion_inspector_web.html" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_html/{}


if [ "$include_trinity" = "true" ]; then
       find /home/dnanexus/temp_out -type f -name "*.gmap_trinity_GG.fusions.fasta" -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_trinity_fasta/{}

       find /home/dnanexus/temp_out -type f -name "*.gmap_trinity_GG.fusions.gff3" -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_trinity_gff/{}

       find /home/dnanexus/temp_out -type f -name "*.gmap_trinity_GG.fusions.gff3.bed.sorted.bed.gz" \
       -printf "%f\n" | xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_trinity_bed/{}
fi

mark-section "upload the outputs"
dx-upload-all-outputs --parallel
mark-success
