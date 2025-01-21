#!/bin/bash

# Test that the start of the read files (without lanes), begin with the expected 'prefix' taken from the 
#STAR-Fusion predictions
_compare_fastq_name_to_prefix() {
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

# Check that each R1 has a matching R2
# Remove "R1" and "R2" and the file suffix from all file names
_trim_fastq_endings() {
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

_download_all_inputs() {
       : '''
       Download all inputs, untar plug-n-play resources, and get its path
       '''
       dx-download-all-inputs
       # tar -xf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/

}

_sense_check_fastq_arrays() {
       : '''
       Running tests to sense-check R1/R2 arrays and file prefixes
       '''
       # Check that there are the same number of R1s as R2s
       cd /home/dnanexus/r1_fastqs
       R1=($(ls *_R1_*))
       cd /home/dnanexus/r2_fastqs
       R2=($(ls *_R2_*))
       cd /home/dnanexus
       if [[ ${#R1[@]} -ne ${#R2[@]} ]]; then 
              echo "The number of R1 and R2 files for this sample are not equal - exiting"
              exit 1
       fi

       R1_test=$(_trim_fastq_endings "_R1_" ${R1[@]})
       R2_test=$(_trim_fastq_endings "_R2_" ${R2[@]})

       # Test that when "R1" and "R2" are removed the two arrays have identical file names
       for i in "${!R1_test[@]}"; do
              if [[ ! "${R2_test}" =~ "${R1_test[$i]}" ]]; then 
                     echo "Each R1 FASTQ does not appear to have a matching R2 FASTQ"
                     echo "${R2_test} ${R1_test[$i]}"
                     exit 1 
              fi
       done

       _compare_fastq_name_to_prefix "$prefix" ${R1_test}
       _compare_fastq_name_to_prefix "$prefix" ${R2_test}

}
_make_output_folder() {

       mkdir "/home/dnanexus/temp_out"
       mkdir -p "/home/dnanexus/out/fi_abridged"
       mkdir "/home/dnanexus/out/fi_full"
       mkdir "/home/dnanexus/out/fi_coding"
       mkdir "/home/dnanexus/out/fi_html"
       mkdir "/home/dnanexus/out/fi_fusion_r1"
       mkdir "/home/dnanexus/out/fi_fusion_r2"
       mkdir "/home/dnanexus/out/fi_inspected_fusions"
       mkdir "/home/dnanexus/out/fi_missed_fusions"
       if [ "$include_trinity" = "true" ]; then
              mkdir "/home/dnanexus/out/fi_trinity_fasta"
              mkdir "/home/dnanexus/out/fi_trinity_gff"
              mkdir "/home/dnanexus/out/fi_trinity_bed"
       fi
}


_scatter() {
       set -exo pipefail

       # set frequency of instance usage in logs to 30 seconds
       kill $(ps aux | grep pcp-dstat | head -n1 | awk '{print $2}')
       /usr/bin/dx-dstat 30

       # control how many operations to open in parallel for download / upload
       THREADS=$(nproc --all)

       # create valid empty JSON file for job output
       echo "{}" > job_output.json

       INSTANCE=$(dx describe --json $DX_JOB_ID | jq -r '.instanceType')  # Extract instance type
       NUMBER_THREADS=${INSTANCE##*_x}

       dx-download-all-inputs
       tar -xf /home/dnanexus/in/genome_lib/*.tar.gz -C /home/dnanexus/
       lib_dir=$(find . -type d -name "*CTAT_lib*")

       # get FusionInspector Docker image by its ID
       docker load -i /home/dnanexus/in/docker/*.tar.gz
       DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^trinityctat/fusioninspector" | cut -d' ' -f2)

       SECONDS=0

       set +x

       # download files

       # set up the FusionInspector command
       wd="$(pwd)"
       out_filename=${samplename}_${fusions_name%.*}


       duration=$SECONDS
       fusion_ins="docker run -v ${wd}:/data --rm \
              ${DOCKER_IMAGE_ID} \
              FusionInspector \
              --fusions /data/in/fusions/${fusions_name} \
              -O /data/temp_out \
              --CPU ${NUMBER_THREADS} \
              --left_fq /data/in/left_fq/${left_fq_name} \
              --right_fq /data/in/right_fq/${right_fq_name} \
              --out_prefix ${out_filename} \
              --genome_lib_dir /data/${lib_dir}/ctat_genome_lib_build_dir \
              --examine_coding_effect \
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
    Since this is >1000 files for each sub job we will create a single tar to upload to reduce the
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

_create_fusion_inspector_report() {
       ## create report command:

       docker run -v /home/dnanexus:/data --rm $DOCKER_IMAGE_ID  /usr/local/bin/util/create_fusion_inspector_igvjs.py \
       --fusion_inspector_directory /data/combined_files \
       --json_outfile /data/combined_files/$prefix.fusion_inspector_web.json \
       --file_prefix $prefix \
       --include_Trinity


       docker run -v /home/dnanexus:/data --rm $DOCKER_IMAGE_ID  /usr/local/bin/fusion-reports/create_fusion_report.py \
       --html_template /usr/local/bin/util/fusion_report_html_template/igvjs_fusion.html \
       --fusions_json /data/combined_files/$prefix.fusion_inspector_web.json \
       --input_file_prefix $prefix \
       --html_output /data/combined_files/$prefix.fusion_inspector_web.html
}


#_combine_fusion_inspector_coding_effect() {
       # python script here?
#}

main() {
       # fail on any error
       set -exo pipefail

       _download_all_inputs
       lib_dir=$(find . -type d -name "*CTAT_lib*")

       # get FusionInspector Docker image by its ID
       docker load -i /home/dnanexus/in/fi_docker/*.tar.gz
       DOCKER_IMAGE_ID=$(docker images --format="{{.Repository}} {{.ID}}" | grep "^trinityctat/fusioninspector" | cut -d' ' -f2)

       # obtain instance information to set CPU flexibly
       INSTANCE=$(dx describe --json $DX_JOB_ID | jq -r '.instanceType')  # Extract instance type
       NUMBER_THREADS=${INSTANCE##*_x}

       # remove header line from STAR-Fusion predicted fusions for Docker
       sr_predictions_name=$(find /home/dnanexus/in/sr_predictions -type f -printf "%f\n")

       # running tests to sense-check R1/R2 arrays and file prefixes"
       # _sense_check_fastq_arrays

       # make temporary and final output directories
       _make_output_folder

       mark-section "Running FusionInspector"
       # start up job for every fusionlist in scatter mode to run analysis

       # variables to input itnto the app
       prefix=$(echo "$sr_predictions_name" | cut -d '.' -f 1)
       known_fusion_file=$known_fusions_name
       docker_file=${fi_docker_name##*/}

       # make array of fusions list from sr_prediction & known_fusions
       fusion_lists=()
       fusion_lists+=(${known_fusion_file})
       fusion_lists+=(${sr_predictions_name})
       echo "${fusion_lists[@]}"

       for fusion in "${fusion_lists[@]}"; do
              echo $fusion
              dx-jobutil-new-job _scatter \
                     -isamplename="$prefix" \
                     -ifusions="${fusion}" \
                     -igenome_lib="$genome_lib" \
                     -ileft_fq="$r1_fastqs" \
                     -iright_fq="$r2_fastqs" \
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

       for fusion in "${fusion_lists[@]}"; do
	       echo $fusion
	       echo ${fusion%.*}
	       tar_name=$prefix_$fusion.tar
              mkdir inputs_${fusion%.*}
              # download the subjob files currently living in the container
              sub_job_tars=$(dx find data --json --name $tar_name --path "$DX_WORKSPACE_ID:/FI_outputs" | jq -r '.[].id')
              echo "$sub_job_tars" | xargs -P $IO_PROCESSES -n1 -I{} sh -c "dx cat $DX_WORKSPACE_ID:{} | tar xf - -C inputs_${fusion%.*}"
       done

       ### merge files to generate the html file

       mkdir combined_files

       find . -type f -name 'cytoBand.txt' -exec cat {} + >> combined_files/cytoBand.txt
       find . -type f -name '*.bed' -exec cat {} + >> combined_files/$prefix.bed
       find . -type f -name '*.fa' -exec cat {} + >> combined_files/$prefix.fa
       find . -type f -name '*.gmap_trinity_GG.fusions.gff3.bed.sorted.bed' -exec cat {} + >> combined_files/$prefix.gmap_trinity_GG.fusions.gff3.bed.sorted.bed
       find . -type f -name "*.FusionInspector.fusions.abridged.tsv" -print0 | xargs -0 awk 'NR==1 {header=$_} FNR==1 && NR!=1 { $_ ~ $header getline; } {print}' >> combined_files/$prefix.FusionInspector.fusions.abridged.tsv

       find . -type f -name '*.junction_reads.bam' -exec samtools merge combined_files/$prefix.junction_reads.bam {} +
       find . -type f -name '*.spanning_reads.bam' -exec samtools merge combined_files/$prefix.spanning_reads.bam {} +
       find . -type f -name '*.star.sortedByCoord.out.bam' -exec samtools merge combined_files/$prefix.star.sortedByCoord.out.bam {} +

       _create_fusion_inspector_report

       ls combined_files/

       # _combine_fusion_inspector_coding_effect

       #### download all input files


       echo "Code managed to run this far woopwoop!"

       mark-section "Check what fusion contigs were selected from the BAM file"
       cut -f 1 /home/dnanexus/temp_out/*.consolidated.bam.frag_coords | sort | uniq > ${out_filename}_fusion_contigs_inspected.txt
       tail -n +2 /home/dnanexus/sr_predictions/${sr_predictions_name}  | cut -f 1 | cat /home/dnanexus/known_fusions/${fusion_list} - | sort | uniq > fusion_rescue_list.txt

       comm -13 ${out_filename}_fusion_contigs_inspected.txt fusion_rescue_list.txt > ${out_filename}_missed_fusion_contigs.txt

       mark-section "Move results files to their output directories"

       find /home/dnanexus -type f -name ${out_filename}_fusion_contigs_inspected.txt -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/{} /home/dnanexus/out/fi_inspected_fusions/{}

       find /home/dnanexus -type f -name ${out_filename}_missed_fusion_contigs.txt -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/{} /home/dnanexus/out/fi_missed_fusions/{}

       find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.abridged.tsv" -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_abridged/{}

       find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.tsv" -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_full/{}

       find /home/dnanexus/temp_out -type f -name "*.FusionInspector.fusions.abridged.tsv.coding_effect" -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_coding/{} 

       find /home/dnanexus/temp_out -type f -name "*.fusion_inspector_web.html" -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_html/{}

       # change fusion_evidence_reads .fq endings to .fastq in place, and zip
       find /home/dnanexus/temp_out -type f -name "${out_filename}.fusion_evidence_reads_*" \
       | grep \.fq$ | sed 'p;s/\.fq/\.fastq/' | xargs -n2 mv

       find /home/dnanexus/temp_out -type f -name "${out_filename}.fusion_evidence_reads_*.fastq" -exec gzip {} \;

       # move fusion_evidence_reads
       find /home/dnanexus/temp_out -type f -name "${out_filename}.fusion_evidence_reads_*1*.fastq.gz" -printf "%f\n" | \
       xargs -I{} mv /home/dnanexus/temp_out/{} /home/dnanexus/out/fi_fusion_r1/{}

       find /home/dnanexus/temp_out -type f -name "${out_filename}.fusion_evidence_reads_*2*.fastq.gz" -printf "%f\n" | \
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

}