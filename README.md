# FusionInspector v1.0.0

## What does this app do?
Runs FusionInspector v2.8.0, a tool which in silico validates fusion predictions by recovering and re-scoring fusion evidence. This app is set up to process the '.fusion_predictions.tsv' file produced by the earlier STAR-Fusion alignment step. It produces a summary file 'inspector.FusionInspector.fusions.abridged.tsv' and a 'final' file with more detailed information.

FusionInspector's GitHub repository and wiki are available at the following URLs:
https://github.com/FusionInspector/FusionInspector
https://github.com/FusionInspector/FusionInspector/wiki

## What inputs are required for this app to run?
* The DNA Nexus file ID of a saved FusionInspector Docker image, which should be a compressed '.tar.gz'
* The file IDs for the Read 1 FASTQ file(s), provided as an array.
* The file IDs for the Read 2 FASTQ file(s), provided as an array.
* The file IDs for 'known fusions' file(s), provided as an array. Files are expected to end '*.txt'. The known fusion files contain regions which should always have fusion evidence checked by FusionInspector, regardless of whether or not they appear in the STAR-Fusion predictions file. They may include commonly-implicated fusion loci for the condition under investigation. 
    * Fusions must be written in the format geneA--geneB.
    * Known fusions may contain multiple tab-separated columns, but only the first column will be used by the app.
* The file ID of the STAR-Fusion predicted fusions, which ends '.fusion_predictions.tsv'. The fusions will be validated by FusionInspector.
* The file ID of a STAR genome resource, which should be a compressed '.tar.gz' file - from https://data.broadinstitute.org/Trinity/CTAT_RESOURCE_LIB/
    * This must have the string "CTAT_lib" in its directory name, in order to be accessed by the script.
* A string value for 'include_trinity', either 'true' if Trinity should be run, or 'false' if it should be skipped.


## How does this app work?
* Downloads all inputs and unzips/untars the STAR genome resource.
* Moves the FASTQ files into 'R1' and 'R2' directories, and known fusions into a 'known_fusion' directory.
* Formats arguments for FusionInspector: reads, known fusions, and STAR-Fusion predictions.
* Makes minor format corrections to the STAR-Fusion predictions.
* Loads and runs the FusionInspector Docker image:
    * The argument '--include_trinity' will be run in the command if the user selected it.
    * Optional parameter '--vis' is run, to produce a HTML report of fusion results.
    * Optional parameter '--examine_coding_effect' is run, to produce a tsv file with details of possible coding region impacts of each fusion.
    * Production versions of this app will need to point to a controlled Docker image in 'references' on DNAnexus to ensure that the same version is run each time.
* Prefixes output file names with the sample name.
* Uploads the output files to DNA Nexus.


## What does this app output?
* The following outputs are produced both with and without Trinity being run:
    * fi_full: a full set of outputs from FusionInspector, as a tsv file.
    * fi_abridged: an abridged version of the FusionInspector output, as a tsv file.
    * fi_coding: the abridged FusionInspector output containing additional information about potential coding effect, a tsv file 
    * fi_html: a HTML of fusion evidence which can be viewed in-browser.
* The following outputs are only produced if 'include_trinity' is set to 'true' at run time:
    * fi_trinity_fasta: a FASTA file of de novo assembled transcript sequences.
    * fi_trinity_gff: a GFF3 file of reconstructed fusion transcript alignments.
    * fi_trinity_bed: a BED file of reconstructed fusion transcript alignments.

## Notes
* This app is not ready for production use

## This app was made by East GLH