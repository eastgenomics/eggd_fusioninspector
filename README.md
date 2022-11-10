# FusionInspector v1.0.0

## What does this app do?
Runs FusionInspector v2.8.0, a tool which in silico validates fusion predictions by recovering and re-scoring fusion evidence. This app is set up to process the '.fusion_predictions.tsv' file produced by the earlier STAR-Fusion alignment step. It produces a summary file 'inspector.FusionInspector.fusions.abridged.tsv' and a 'final' file with more detailed information.

## What inputs are required for this app to run?
* The DNA Nexus file ID of a saved FusionInspector Docker image, which should be a compressed '.tar.gz'
* The file IDs for the Read 1 file(s), provided as an array.
* The file IDs for the Read 2 file(s), provided as an array.
* The file ID of a 'known fusions' file. These are regions which should always have fusion evidence checked by FusionInspector, regardless of whether or not they appear in the STAR-Fusion predictions file. They may include commonly-implicated fusion loci for the condition under investigation.
* The file ID of the STAR-Fusion predicted fusions, which ends '.fusion_predictions.tsv'. The fusions will be validated by FusionInspector.
* The file ID of a STAR genome resource, which should be a compressed '.tar.gz' file - from https://data.broadinstitute.org/Trinity/CTAT_RESOURCE_LIB/
    * This must have the string "CTAT_lib" in its directory name, in order to be detected by the script.


## How does this app work?
* Downloads all inputs and unzips/untars the STAR genome resource
* Moves the FASTQ files into 'R1' and 'R2' directories
* Formats arguments for FusionInspector: reads, known fusions, and STAR-Fusion predictions
* Loads and runs the FusionInspector Docker image
    * Arguments not already mentioned as inputs are: --vis, --include_Trinity, and --examine_coding_effect
    * Production versions of this app will need to point to a controlled Docker image in 'references' on DNAnexus to ensure that the same version is run each time
* Prefixes output file names with the sample name
* Uploads the output files to DNA Nexus


## What does this app output?


## Notes
* This app is not ready for production use

## This app was made by East GLH