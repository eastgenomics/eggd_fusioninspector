#!/bin/bash

# fail on any error
set -exo pipefail

mark-section "Installing Python packages"
export PATH=$PATH:/home/dnanexus/.local/bin  # pip installs some packages here, add to path
sudo -H python3 -m pip install --no-index --no-deps packages/*

# download all inputs, untar plug-n-play resources, and get its path
mark-section "Download inputs and set up initial directories and values"
dx-download-all-inputs
tar -xf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/
lib_dir=$(find . -type d -name "*CTAT_lib*")

# move array:file uploads into more sensible directories
# this is done to make finding files easier because, by default, every file in the array goes into a numbered dir on its own
mkdir /home/dnanexus/r1_fastqs
mkdir /home/dnanexus/r2_fastqs
mkdir /home/dnanexus/known_fusions
mkdir /home/dnanexus/sr_predictions

find ./in/r1_fastqs -type f -name "*R1*" -print0 | xargs -0 -I {} mv {} ./r1_fastqs
find ./in/r2_fastqs -type f -name "*R2*" -print0 | xargs -0 -I {} mv {} ./r2_fastqs
find ./in/known_fusions -type f -name "*.txt*" -print0 | xargs -0 -I {} mv {} ./known_fusions
find ./in/sr_predictions -type f -print0 | xargs -0 -I {} mv {} ./sr_predictions

# form array:file uploads in a comma-separated list - prepend '/data/' path, for use in Docker
read_1=$(find ./r1_fastqs/ -type f -name "*" -name "*R1*.f*" | \
sed 's/\.\///g' | sed -e 's/^/\/data\//' | paste -sd, -)
read_2=$(find ./r2_fastqs/ -type f -name "*" -name "*R2*.f*" | \
sed 's/\.\///g' | sed -e 's/^/\/data\//' | paste -sd, -)
known_fusions=$(find ./known_fusions/ -type f -name "*" | \
sed 's/\.\///g' | sed -e 's/^/\/data\//' | paste -sd, -)

# remove header line from STAR-Fusion predicted fusions for Docker
sr_predictions_name=$(find /home/dnanexus/sr_predictions -type f -printf "%f\n")

# Get FusionInspector Docker image by its ID
docker load -i /home/dnanexus/in/fi_docker/*.tar.gz
DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^trinityctat/fusioninspector" | cut -d' ' -f2)

# get the sample name from the chimeric file
prefix=$(echo "$sr_predictions_name" | cut -d '.' -f 1)

# Obtain instance information to set CPU flexibly
INSTANCE=$(dx describe --json $DX_JOB_ID | jq -r '.instanceType')  # Extract instance type
NUMBER_THREADS=${INSTANCE##*_x}


## Tests
mark-section "Running tests to sense-check R1/R2 arrays and file prefixes"
# Check that there are the same number of R1s as R2s
cd /home/dnanexus/r1_fastqs
R1=($(ls *R1*))
cd /home/dnanexus/r2_fastqs
R2=($(ls *R2*))
cd /home/dnanexus
if [[ ${#R1[@]} -ne ${#R2[@]} ]]; then 
       echo "The number of R1 and R2 files for this sample are not equal - exiting"
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
              echo "Suffixes of fastq files not recognised as .fq.gz or .fastq.gz - exiting"
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

# Test that the start of the read files (without lanes), begin with the expected 'prefix' taken from the 
#STAR-Fusion predictions
_compare_fastq_name_to_prefix () {
       # Takes an array of FASTQ names with reads and file-endings already cut out.
       # Identify and cut out the sample name. Compare rest of name to StarFusion file prefix. Exit if mismatch.
       local fastq_array=("$@")
       local prefix=$1
       for i in "${fastq_array[@]}"; do
              lane_cut_off=$(echo $i | cut -d '_' -f 1)
              if [[ ! "$lane_cut_off" == "$prefix" ]]; then 
                     echo "Start of filename does not match expected prefix taken from STAR-Fusion file: $i - exiting"  
                     exit 1
              fi
       done
}

_compare_fastq_name_to_prefix "$prefix" ${R1_test}
_compare_fastq_name_to_prefix "$prefix" ${R2_test}


# make temporary and final output dirs
mark-section "Make temporary and final output directories"
mkdir "/home/dnanexus/temp_out"
mkdir -p "/home/dnanexus/out/fi_abridged"
mkdir "/home/dnanexus/out/fi_full"
mkdir "/home/dnanexus/out/fi_coding"
mkdir "/home/dnanexus/out/fi_frame_filtered"
mkdir "/home/dnanexus/out/fi_html"
mkdir "/home/dnanexus/out/fi_fusion_r1"
mkdir "/home/dnanexus/out/fi_fusion_r2"
if [ "$include_trinity" = "true" ]; then
       mkdir "/home/dnanexus/out/fi_trinity_fasta"
       mkdir "/home/dnanexus/out/fi_trinity_gff"
       mkdir "/home/dnanexus/out/fi_trinity_bed"
fi


# set up the FusionInspector command 
mark-section "Set up basic FusionInspector command prior to running"
wd="$(pwd)"
fusion_ins="docker run -v ${wd}:/data --rm \
       ${DOCKER_IMAGE_ID} \
       FusionInspector \
       --fusions "${known_fusions},/data/sr_predictions/${sr_predictions_name}" \
       -O /data/temp_out \
       --CPU ${NUMBER_THREADS} \
       --left_fq ${read_1} \
       --right_fq ${read_2} \
       --out_prefix ${prefix} \
       --genome_lib_dir /data/${lib_dir}/ctat_genome_lib_build_dir \
       --vis \
       --examine_coding_effect \
       --extract_fusion_reads_file /data/temp_out/${prefix}"


# run FusionInspector, adding an arg to run Trinity if requested by user, and adding optional user-entered parameters if any 
if [ "$include_trinity" = "true" ]; then
       mark-section "Adding Trinity de novo reconstruction option to FusionInspector command"
       fusion_ins="${fusion_ins} --include_Trinity"
fi

if [ -n "$opt_parameters" ]; then
       # Test that there are no banned parameters in --parameters input string
       banned_parameters=(--fusions -O --CPU --left_fq --right_fq --out_prefix --genome_lib_dir --vis \
       --examine_coding_effect --extract_fusion_reads_file --include_Trinity --samples_file)
       for parameter in ${banned_parameters[@]}; do
              if [[ "$opt_parameters" == *"$parameter"* ]]; then
                     echo "The parameter ${parameter} was set as an input. This parameter is set within \
                     the app and cannot be set as an input. Please repeat without this parameter"
                     exit 1
              fi
       done
       mark-section "Adding additional user-entered parameters to FusionInspector command"
       fusion_ins="${fusion_ins} ${opt_parameters}"
fi

mark-section "Running FusionInspector"
eval "${fusion_ins}"

mark-section "Creating a new, filtered file based on 'FusionInspector.fusions.abridged.tsv.coding_effect', \
 by removing rows where the PROT_FUSION_TYPE annotation column indicates it is out-of-frame"

filtered_filepath="/home/dnanexus/temp_out/${prefix}.FusionInspector.fusions.abridged.tsv.coding_effect.filtered"
filtered_filename="${prefix}.FusionInspector.fusions.abridged.tsv.coding_effect.filtered"

abridged_coding_effect=$(find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.abridged.tsv.coding_effect")
/usr/bin/time -v python3 filter_on_frame.py \
--input_file "$abridged_coding_effect" \
--outname "$filtered_filepath"


mark-section "Move results files to their output directories"

find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.abridged.tsv" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_abridged/{}

find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.tsv" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_full/{}

find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.abridged.tsv.coding_effect" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_coding/{} 

find /home/dnanexus/temp_out -type f -name "$filtered_filename" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_frame_filtered/{} 

find /home/dnanexus/temp_out -type f -name "*.fusion_inspector_web.html" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_html/{}

# change fusion_evidence_reads .fq endings to .fastq in place, and zip
find /home/dnanexus/temp_out -type f -name "${prefix}.fusion_evidence_reads_*" \
| grep \.fq$ | sed 'p;s/\.fq/\.fastq/' | xargs -n2 mv

find /home/dnanexus/temp_out -type f -name "${prefix}.fusion_evidence_reads_*.fastq" -exec gzip {} \;

# move fusion_evidence_reads
find /home/dnanexus/temp_out -type f -name "${prefix}.fusion_evidence_reads_*1*.fastq.gz" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_fusion_r1/{}

find /home/dnanexus/temp_out -type f -name "${prefix}.fusion_evidence_reads_*2*.fastq.gz" -printf "%f\n" | \
xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_fusion_r2/{}

if [ "$include_trinity" = "true" ]; then
       find /home/dnanexus/temp_out -type f -name "*.gmap_trinity_GG.fusions.fasta" -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_trinity_fasta/{}

       find /home/dnanexus/temp_out -type f -name "*.gmap_trinity_GG.fusions.gff3" -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_trinity_gff/{}

       find /home/dnanexus/temp_out -type f -name "*.gmap_trinity_GG.fusions.gff3.bed.sorted.bed.gz" \
       -printf "%f\n" | xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_trinity_bed/{}
fi

mark-section "Upload the final outputs"
dx-upload-all-outputs --parallel
mark-success
