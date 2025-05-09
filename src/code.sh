#!/bin/bash

# prefixes all lines of commands written to stdout with datetime
PS4='\000[$(date)]\011'
export TZ=Europe/London
set -exo pipefail

# set frequency of instance usage in logs to 30 seconds
kill $(ps aux | grep pcp-dstat | head -n1 | awk '{print $2}')
/usr/bin/dx-dstat 30

_compare_fastq_name_to_prefix() {
       # Test that the start of the read files (without lanes), begin with the expected 'prefix' taken from the 
       #STAR-Fusion predictions
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


_trim_fastq_endings() {
       : '''
       Check that each R1 has a matching R2.
       Remove "R1" and "R2" and the file suffix from all file names
       Trims the endings off R1 or R2 file names in an array, and returns as an array.
       Identify and cut off suffixes. Export suffix for later use.
       '''

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


_sense_check_fastq_arrays() {
       : '''
       Running tests to sense-check R1/R2 arrays and file prefixes
       '''
       # Check that there are the same number of R1s as R2s
       readarray -t R1 < <(find /home/dnanexus/in/ -maxdepth 3 -name '*_R1_*' -printf '%f\n')
       readarray -t R2 < <(find /home/dnanexus/in/ -maxdepth 3 -name '*_R2_*' -printf '%f\n')
       if [[ ${#R1[@]} -ne ${#R2[@]} ]]; then 
              echo "The number of R1 and R2 files for this sample are not equal - exiting"
              exit 1
       fi

       R1_test=$(_trim_fastq_endings "_R1_" "${R1[@]}")
       R2_test=$(_trim_fastq_endings "_R2_" "${R2[@]}")

       # Test that when "R1" and "R2" are removed the two arrays have identical file names
       for i in "${!R1_test[@]}"; do
              if [[ ! ${R2_test} =~ ${R1_test[$i]} ]]; then
                     echo "Each R1 FASTQ does not appear to have a matching R2 FASTQ"
                     echo "${R2_test} ${R1_test[$i]}"
                     exit 1
              fi
       done

       _compare_fastq_name_to_prefix "$prefix" "${R1_test[@]}"
       _compare_fastq_name_to_prefix "$prefix" "${R2_test[@]}"

}

_scatter() {
       : '''
       Run FusionInspector per fusion list

       This function will be launched as a sub job within the scope of
       the main FusionInspector job, it sets up the job environment, runs the
       FusionInspector command and uploads output to the parent job container to
       then continue create the combined files and html report.
       '''
       set -exo pipefail

       # prefixes all lines of commands written to stdout with datetime
       PS4='\000[$(date)]\011'
       export TZ=Europe/London
       set -exo pipefail

       # create valid empty JSON file for job output
       echo "{}" > job_output.json

       # Extract instance type
       NUMBER_THREADS=$(nproc --all)

       time dx-download-all-inputs
       tar -xf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/
       lib_dir=$(find . -type d -name "*CTAT_lib*")

       # get FusionInspector Docker image by its ID
       docker load -i /home/dnanexus/in/docker/*.tar.gz
       DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^trinityctat/fusioninspector" | cut -d' ' -f2)

       SECONDS=0

       # set up the FusionInspector command
       wd="$(pwd)"
       out_filename=${samplename}_${fusions_name%.*}

       duration=$SECONDS
       fusion_ins="docker run -v ${wd}:/data --rm \
              ${DOCKER_IMAGE_ID} \
              FusionInspector \
              --fusions /data/in/fusions/${fusions_name},/data/in/star_fusion/${star_fusion_name}  \
              -O /data/temp_out \
              --CPU ${NUMBER_THREADS} \
              --left_fq /data/in/left_fq_1/${left_fq_1_name},/data/in/left_fq_2/${left_fq_2_name}  \
              --right_fq /data/in/right_fq_1/${right_fq_1_name},/data/in/right_fq_2/${right_fq_2_name} \
              --out_prefix ${out_filename} \
              --genome_lib_dir /data/${lib_dir}/ctat_genome_lib_build_dir \
              --examine_coding_effect --vis \
              --extract_fusion_reads_file /data/temp_out/${out_filename}"


       # run FusionInspector, adding an arg to run Trinity if requested by user, and adding optional user-entered parameters if any 
       if [ "$include_trinity" = "true" ]; then
              mark-section "Adding Trinity de novo reconstruction option to FusionInspector command"
              fusion_ins="${fusion_ins} --include_Trinity"
       fi

       if [ -n "$opt_parameters" ]; then
              # Test that there are no banned parameters in --parameters input string
              banned_parameters=(--fusions -O --CPU --left_fq --right_fq --out_prefix --genome_lib_dir --vis \
              --examine_coding_effect --extract_fusion_reads_file --include_Trinity)
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

    {
       echo "Starting FusionInspector for ${fusion_name}"
       SECONDS=0
       echo $fusion_ins
       eval $fusion_ins

       echo scatter complete
    } || {
        # some form of error occured in running that raised non-zero exit code
        code=$?
        echo "ERROR: one or more errors occured running workflow"
        echo "Process exited with code: ${code}"
        exit 1
    }


    duration="$SECONDS"
    echo "Scatter job complete for ${fusions_name} in $(($duration / 60))m$(($duration % 60))s"

    _sub_job_upload_outputs
}


_sub_job_upload_outputs() {
    : '''
    Util function for _sub_job().

    Uploads required output back to container to be downloaded back to parent job for post processing.
    Since this is >10 files for each sub job we will create a single tar to upload to reduce the
    amount of API queries and avoid rate limits, this will then be downloaded and unpacked in the
    parent job
    '''
    mark-section "Uploading sub job output"

    mkdir -p FI_outputs
    mv /home/dnanexus/temp_out FI_outputs/

    total_files=$(find FI_outputs/ -type f | wc -l)
    total_size=$(du -sh FI_outputs/ | cut -f 1)

    SECONDS=0
    echo "Creating tar from ${total_files} output files (${total_size}) to upload to parent job"

    name=$(jq -r '.name' dnanexus-job.json )
    time tar -cf "${fusions_name}.tar" FI_outputs/
    time dx upload "${fusions_name}.tar" --parents --brief --path FI_outputs/

    duration=$SECONDS
    echo "Created and uploaded ${fusions_name}.tar in $(($duration / 60))m$(($duration % 60))s"
}


main() {
       # fail on any error
       set -exo pipefail

       # Install packages
       export PATH=$PATH:/home/dnanexus/.local/bin  # pip installs some packages here, add to path
       sudo -H python3 -m pip install --no-index --no-deps packages/*

       time dx-download-all-inputs

       lib_dir=$(find . -type d -name "*CTAT_lib*")

       mkdir -p /home/dnanexus/out/fi_abridged \
              /home/dnanexus/out/fi_full \
              /home/dnanexus/out/fi_coding \
              /home/dnanexus/out/fi_html \
              /home/dnanexus/out/fi_inspected_fusions \
              /home/dnanexus/out/fi_missed_fusions

       # samtools in htslib doesn't work as its missing a library, so
       # will install the missing libraries from the downloaded deb files
       # (so as to not use internet)
       sudo dpkg -i libtinfo5_6.2-0ubuntu2_amd64.deb
       sudo dpkg -i libncurses5_6.2-0ubuntu2_amd64.deb

       # get FusionInspector Docker image by its ID
       docker load -i /home/dnanexus/in/fi_docker/*.tar.gz
       DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^trinityctat/fusioninspector" | cut -d' ' -f2)

       # remove header line from STAR-Fusion predicted fusions for Docker
       sr_predictions_name=$(find /home/dnanexus/in/sr_predictions -type f -printf "%f\n")
       prefix=$(echo "$sr_predictions_name" | cut -d '.' -f 1)

       # running tests to sense-check R1/R2 arrays and file prefixes"
       _sense_check_fastq_arrays

       mark-section "Setting subjobs to run FusionInspector"

       # variables to input into the app
       prefix=$(echo "$sr_predictions_name" | cut -d '.' -f 1)
       known_fusion_file="${known_fusions_name[@]}"
       echo $known_fusion_file
       docker_file=${fi_docker_name##*/}

       # make array of fusions list from sr_prediction & known_fusions
       fusion_lists=()
       fusion_lists+=(${known_fusion_file})
       echo "${fusion_lists[@]}"

       for fusion in "${fusion_lists[@]}"; do
              echo $fusion
              dx-jobutil-new-job _scatter \
                     -isamplename="$prefix" \
                     -istar_fusion="${sr_predictions}" \
                     -ifusions="${fusion}" \
                     -igenome_lib="$genome_lib" \
                     -ileft_fq_1="${r1_fastqs[0]}" \
                     -ileft_fq_2="${r1_fastqs[1]}" \
                     -iright_fq_1="${r2_fastqs[0]}" \
                     -iright_fq_2="${r2_fastqs[1]}" \
                     -iopt_parameters="$opt_parameters" \
                     -iinclude_trinity="$include_trinity" \
                     -idocker="$docker_file" \
                     --instance-type="$scatter_instance" \
                     --extra-args='{"priority": "high"}' \
                     --name "_scatter [${fusion}]" >> job_ids
       done

       # wait until all scatter jobs complete
       SECONDS=0
       echo "$(wc -l job_ids) jobs launched, holding job until all to complete..."
       dx wait --from-file job_ids

       duration=$SECONDS
       echo "All subjobs completed in $(($duration / 60))m$(($duration % 60))s"#
       IO_PROCESSES=$(nproc --all)

       mark-section "Downloading files from subjobs to the parent job"
       mkdir subjob_output

       # wait 30 seconds before trying to download all files as some files
       # can still be in an open state due to parallel uploading still
       # commencing even after subjobs have completed successful
       echo "Waiting 30 seconds to ensure all files are hopefully in a closed state"
       sleep 30

       for fusion in "${fusion_lists[@]}"; do
	       echo ${fusion%.*}
	       tar_name=$prefix_$fusion.tar
              mkdir subjob_output/inputs_${fusion%.*}
              # download the subjob files currently living in the container
              sub_job_tars=$(dx find data --json --name $tar_name --path "$DX_WORKSPACE_ID:/FI_outputs" | jq -r '.[].id')
              # check the file state again
              file_state=$(dx describe $sub_job_tars --json | jq -r '.state')
              if [ "$file_state" = "open" ]; then
                     sleep 30
              fi
              # try to put all subjob_output folder
              echo "$sub_job_tars" | xargs -P $IO_PROCESSES -n1 -I{} sh -c "dx cat $DX_WORKSPACE_ID:{} | tar xf - -C subjob_output/inputs_${fusion%.*}"
       done


       mark-section "Merging fusions tsv files"
       mkdir temp_output_files

       find subjob_output -type f -name "*.FusionInspector.fusions.tsv" -print0 | xargs -0 awk '(FNR == 1 && NR != 1) { next } { print }' >> temp_output_files/$prefix.FusionInspector.fusions.tsv
       find subjob_output -type f -name "*.FusionInspector.fusions.abridged.tsv" -print0 | xargs -0 awk '(FNR == 1 && NR != 1) { next } { print }' >> temp_output_files/$prefix.FusionInspector.fusions.abridged.tsv
       # need to merge all the coding effect files, move to all the coding files to a temporary file
       mkdir coding_effect_files
       find subjob_output -type f -name "*.FusionInspector.fusions.abridged.tsv.coding_effect" -print0 | xargs -0 -I {} mv {} ./coding_effect_files
       python3 merge_fusions_tsv.py -a coding_effect_files/*.coding_effect -o temp_output_files

       mark-section "Check what fusion contigs were selected from the BAM file"
       
       find subjob_output -name "*.consolidated.bam.frag_coords" -exec cat '{}' + -quit >> temp_output_files/$prefix.consolidated.bam.frag_coords
       cut -f 1 temp_output_files/$prefix.consolidated.bam.frag_coords | sort | uniq > temp_output_files/${prefix}_fusion_contigs_inspected.txt
       # combine all the fusions we wanted to inspect
       awk 'NR==1 {header=$_} FNR==1 && NR!=1 { $_ ~ $header getline; } {print}' in/known_fusions/*/* | sort > temp_output_files/fusion_rescue_list.txt
       # find fusions that were missed
       comm -13 temp_output_files/${prefix}_fusion_contigs_inspected.txt temp_output_files/fusion_rescue_list.txt > temp_output_files/${prefix}_missed_fusion_contigs.txt

       mark-section "Move results files to their output directories"

       find /home/dnanexus/temp_output_files -type f -name ${prefix}_fusion_contigs_inspected.txt -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_output_files/{} /home/dnanexus/out/fi_inspected_fusions/{}

       find /home/dnanexus/temp_output_files -type f -name ${prefix}_missed_fusion_contigs.txt -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_output_files/{} /home/dnanexus/out/fi_missed_fusions/{}

       find /home/dnanexus/temp_output_files -type f -name ${prefix}.FusionInspector.fusions.abridged.tsv -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_output_files/{} /home/dnanexus/out/fi_abridged/{}

       find /home/dnanexus/temp_output_files -type f -name ${prefix}.FusionInspector.fusions.tsv -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_output_files/{} /home/dnanexus/out/fi_full/{}

       find /home/dnanexus/temp_output_files -type f -name ${prefix}.FusionInspector.fusions.abridged.coding_effect.merged.tsv -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_output_files/{} /home/dnanexus/out/fi_coding/{}

       find subjob_output -type f -name ${prefix}*.fusion_inspector_web.html | \
       xargs -I{} mv {} /home/dnanexus/out/fi_html/

       mark-section "Upload the final outputs"
       time dx-upload-all-outputs --parallel
       mark-success

}