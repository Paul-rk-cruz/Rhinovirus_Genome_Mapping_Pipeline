#!/usr/bin/env nextflow

/*
========================================================================================
                  Rhinovirus Genome Mapping Pipeline v1.0
========================================================================================
 Github Repo:
 Greninger Lab
 
 Author:
 Paul RK Cruz <kurtisc@uw.edu>
 UW Medicine | Virology
 Department of Laboratory Medicine and Pathology
 University of Washington
 Created: April, 2021
 LICENSE: GNU
----------------------------------------------------------------------------------------

This pipeline was designed to run either single-end or paired end Next-Generation Sequencing reads to identify Human Rhinovirus complete genomes for analysis and Genbank submission.

PIPELINE OVERVIEW:
 - 1. : Trim Reads
 		-Trimmomatic - sequence read trimming of adaptors and low quality reads.
 - 2. : Genome Mapping
 		-BBMap - align to MultiFasta Reference Virus Genome.
 		-Samtools - SAM and BAM file processing.
 - 3. : Reference Fasta Generation
 		-Generate a fasta reference from the genome mapping results.  
 - 4. : Sort Bam
  		-Convert Sam to Bam
        -Sort Bam file by coordinates
        -Generate Statistics about Bam file  
 - 5. : Variant Calling
        -Calculate the read coverage of positions in the genome
        -Detect the single nucleotide polymorphisms (SNPs)
        -Filter and report the SNP variants in variant calling format (VCF)
        CLI Command to view results:   less -S ${base}_final_variants.vcf
 - 6. : Consensus
        -Consensus generation using variants VCF, mapped reference fasta, and
        sorted bam. 
 - 7. : Final Consensus
        -Creates the Final Consensus by editing the fasta header.       
 - 6. : FastQC
 		-Sequence read quality control analysis.

    Dependencies:
    
    trimmomatic
    samtools
    bbtools  
    bcftools
    seqkit
    bgzip
    bedtools
    fastqc

    PIPELINE SETUP

    Setup Multifasta Reference:
    1. REFERENCE_FASTA (must be a multifasta containing concatenated full length RhV genome sequences (6-10K bp) formatted with accession numbers only)
        Current file: rhv_ref_db01_accession_only.fasta - 327 Human Rhinovirus Complete Genome Sequences courtesy of NCBI Genbank, 2021.
            source: https://www.ncbi.nlm.nih.gov/nucleotide/

    2. REFERENCE_FASTA_INDEX
        run:
             samtools faidx <reference.fasta>
        to create a multifasta index file.

    Setup File Paths:
    1. BBMAP_PATH
        Path to your installation of BBTools --> bbmap.sh
    2. trimmomatic_adapters_file_SE
        Path to your Trimmomatic single-end file
    3. trimmomatic_adapters_file_PE
            Path to your Trimmomatic paired-end file

    Setup Trimmomatic Parameters:
    1. params.trimmomatic_adapters_parameters = "2:30:10:1"
    2. params.trimmomatic_window_length = "4"
    3. params.trimmomatic_window_value = "20"
    4. params.trimmomatic_mininum_length = "75"
    

    EXAMPLE USAGE:

        Run Pipeline Help Message:
        nextflow run /Users/Kurtisc/Downloads/CURRENT/Virus_Genome_Mapping_Pipeline/main.nf --helpMsg helpMsg

        Run Pipeline on Single-end sequence reads ((SAMPLE_NAME)_S1_L001_R1_001.fastq, ((SAMPLE_NAME)_S1_L002_R1_001.fastq))
        nextflow run /Users/Kurtisc/Downloads/CURRENT/Virus_Genome_Mapping_Pipeline/RhV_Genome_Mapping_Pipeline/main.nf --reads '/Users/Kurtisc/Downloads/CURRENT/test_fastq_se/' --outdir '/Users/Kurtisc/Downloads/CURRENT/test_output/' --singleEnd singleEnd

        Run Pipeline on Paired-end sequence reads ((SAMPLE_NAME)_S1_L001_R1_001.fastq, ((SAMPLE_NAME)_S1_L001_R2_001.fastq))
        nextflow run /Users/Kurtisc/Downloads/CURRENT/Virus_Genome_Mapping_Pipeline/Virus_Genome_Mapping_Pipeline/main.nf --reads '/Users/Kurtisc/Downloads/CURRENT/test_fastq_pe/' --outdir '/Users/Kurtisc/Downloads/CURRENT/test_output/'

 ----------------------------------------------------------------------------------------
*/

// Pipeline version
version = '1.0'
def helpMsg() {
    log.info"""
	 __________________________________________________
     Rhinovirus Genome Mapping Pipeline :  Version ${version}
	__________________________________________________
    
	Pipeline Usage:

    To run the pipeline, enter the following in the command line:

        nextflow run FILE_PATH/Rhinovirus_Genome_Mapping_Pipeline/main.nf --reads PATH_TO_FASTQ --outdir PATH_TO_OUTPUT_DIR


    Valid CLI Arguments:
    REQUIRED:
      --reads                       Path to input fastq.gz folder).
      --outdir                      The output directory where the results will be saved
    OPTIONAL:
	  --helpMsg						Displays help message in terminal
      --singleEnd                   Specifies that the input fastq files are single end reads
	  --withFastQC					Runs a quality control check on fastq files

    """.stripIndent()
}
// Initialize parameters
params.helpMsg = false
params.virus_index = false
params.virus_fasta = false
REFERENCE_FASTA = file("${baseDir}/virus_ref_db/rhv_ref_db01_accession_only.fasta")
REFERENCE_FASTA_INDEX = file("${baseDir}/virus_ref_db/rhv_ref_db01.fasta.fai")
BBMAP_PATH="/Users/Kurtisc/Downloads/bbmap/"
// // Bowtie2 index name: rhv_ref_db01
// BOWTIE2_DB_PREFIX = file("${baseDir}/virus_ref_db/rhv_ref_db01")
// REF_BT2_INDEX1 = file("${baseDir}/virus_ref_db/rhv_ref_db01.1.bt2")
// REF_BT2_INDEX2 = file("${baseDir}/virus_ref_db/rhv_ref_db01.2.bt2")
// REF_BT2_INDEX3 = file("${baseDir}/virus_ref_db/rhv_ref_db01.3.bt2")
// REF_BT2_INDEX4 = file("${baseDir}/virus_ref_db/rhv_ref_db01.4.bt2")
// REF_BT2_INDEX5 = file("${baseDir}/virus_ref_db/rhv_ref_db01.rev.1.bt2")
// REF_BT2_INDEX6 = file("${baseDir}/virus_ref_db/rhv_ref_db01.rev.2.bt2")
// Show help msg
if (params.helpMsg){
    helpMsg()
    exit 0
}
params.withFastQC = false
// Check Nextflow version
nextflow_req_v = '20.10.0'
try {
    if( ! nextflow.version.matches(">= $nextflow_req_v") ){
        throw GroovyException("> ERROR: The version of Nextflow running on your machine is out dated.\n>Please update to Version $nextflow_req_v")
    }
} catch (all) {
	log.error"ERROR: This version of Nextflow is out of date.\nPlease update to the latest version of Nextflow."
}
// Check for fastq
params.reads = false
if (! params.reads ) exit 1, "> Error: Fastq files not found. Please specify a valid path with --reads"
// Single-end read option
params.singleEnd = false
// Default trimming options
params.trimmomatic_adapters_file_PE = "/Users/Kurtisc/anaconda3/pkgs/trimmomatic-0.39-1/share/trimmomatic-0.39-1/adapters/TruSeq2-PE.fa"
params.trimmomatic_adapters_file_SE = "/Users/Kurtisc/anaconda3/pkgs/trimmomatic-0.39-1/share/trimmomatic-0.39-1/adapters/TruSeq2-SE.fa"
params.trimmomatic_adapters_parameters = "2:30:10:1"
params.trimmomatic_window_length = "4"
params.trimmomatic_window_value = "20"
params.trimmomatic_mininum_length = "75"
trimmomatic_mininum_length = "75"
// log files header
log.info "____________________________________________"
log.info " Rhinovirus Genome Mapping Pipeline :  v${version}"
log.info "____________________________________________"
def summary = [:]
summary['Fastq Files:']               = params.reads
summary['Read type:']           	  = params.singleEnd ? 'Single-End' : 'Paired-End'
summary['Virus Reference:']           = REFERENCE_FASTA
if(workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Current directory path:']        = "$PWD"
summary['Working directory path:']         = workflow.workDir
summary['Output directory path:']          = params.outdir
summary['Pipeline directory path:']          = workflow.projectDir
if (params.singleEnd) {
summary['Trimmomatic adapters:'] = params.trimmomatic_adapters_file_SE
} else {
summary['Trimmomatic adapters:'] = params.trimmomatic_adapters_file_PE
}
summary['Trimmomatic adapter parameters:'] = params.trimmomatic_adapters_parameters
summary["Trimmomatic read length (minimum):"] = params.trimmomatic_mininum_length
summary['Configuration Profile:'] = workflow.profile
log.info summary.collect { k,v -> "${k.padRight(21)}: $v" }.join("\n")
log.info "____________________________________________"
// Create channel for input reads.
// Import reads depending on single end vs. paired end
if(params.singleEnd == false) {
    // Check for R1s and R2s in input directory
    input_read_ch = Channel
        .fromFilePairs("${params.reads}*_R{1,2}*.fastq.gz")
        .ifEmpty { error "> Cannot located paired-end reads in: ${params.reads}.\n> Please enter a valid file path." }
        .map { it -> [it[0], it[1][0], it[1][1]]}
} else {
    // Looks for gzipped files, assumes all separate samples
    input_read_ch = Channel
        .fromPath("${params.reads}*.gz")
        //.map { it -> [ file(it)]}
        .map { it -> file(it)}
}
if(params.virus_index) {
// Channel for virus genome reference indexes
Channel
    .fromPath(params.virus_index)
    .ifEmpty { exit 1, "> Error: Virus index not found: ${params.virus_index}.\n> Please specify a valid file path!"}
    .set { virus_index_files }
}

/*
 * Trim Reads
 * 
 * Processing: Trim adaptors and repetitive bases from sequence reads and remove low quality sequence reads.
 */
if (params.singleEnd) {
	process Trim_Reads_SE {
    errorStrategy 'retry'
    maxRetries 3

    input:
        file R1 from input_read_ch
        file("${base}_results.csv")
        val trimmomatic_mininum_length

    output: 
        tuple env(base),file("*.trimmed.fastq.gz") into Trim_out_ch, Trim_out_fastqc_SE
        file("${base}_results.csv") into Results_trimmed_ch

    publishDir "${params.outdir}trimmed_fastqs", mode: 'copy',pattern:'*.trimmed.fastq*'
    publishDir "${params.outdir}final_results", mode: 'copy',pattern:'*_results.csv*'

    script:
    """
    #!/bin/bash
    base=`basename ${R1} ".fastq.gz"`

	trimmomatic SE -threads ${task.cpus} ${R1} \$base.trimmed.fastq.gz \
	ILLUMINACLIP:${params.trimmomatic_adapters_file_SE}:${params.trimmomatic_adapters_parameters} SLIDINGWINDOW:${params.trimmomatic_window_length}:${params.trimmomatic_window_value} MINLEN:${params.trimmomatic_mininum_length} 2> ${R1}.log

    num_untrimmed=\$((\$(gunzip -c ${R1} | wc -l)/4))
    num_trimmed=\$((\$(gunzip -c \$base'.trimmed.fastq.gz' | wc -l)/4))
    percent_trimmed=\$((100-\$((100*num_trimmed/num_untrimmed))))
    echo Sample_Name,Raw_Reads,Trimmed_Reads,Percent_Trimmed,Mapped_Reads,Mean_Coverage > \$base'_results.csv'
    printf "\$base,\$num_untrimmed,\$num_trimmed,\$percent_trimmed" >> \$base'_results.csv'
    """
} 
} else {
	process Trim_Reads_PE {
    errorStrategy 'retry'
    maxRetries 3

   input:
        tuple val(base), file(R1), file(R2) from input_read_ch
        file("${base}_results.csv")
        val trimmomatic_mininum_length
    output: 
        tuple env(base),file("*.trimmed.fastq.gz") into Trim_out_ch, Trim_out_fastqc_PE
        file("${base}_results.csv") into Results_trimmed_ch

    publishDir "${params.outdir}trimmed_fastqs", mode: 'copy',pattern:'*.trimmed.fastq*'
    
    script:
    """
    #!/bin/bash

    trimmomatic PE -threads ${task.cpus} ${R1} ${R2} ${base}.R1.paired.fastq.gz ${base}.R1.unpaired.fastq.gz ${base}.R2.paired.fastq.gz ${base}.R2.unpaired.fastq.gz \
	ILLUMINACLIP:${params.trimmomatic_adapters_file_PE}:2:30:10:1:true LEADING:3 TRAILING:3 SLIDINGWINDOW:4:20 MINLEN:${params.trimmomatic_mininum_length}

    num_r1_untrimmed=\$(gunzip -c ${R1} | wc -l)
    num_r2_untrimmed=\$(gunzip -c ${R2} | wc -l)
    num_untrimmed=\$((\$((num_r1_untrimmed + num_r2_untrimmed))/4))
    num_r1_paired=\$(gunzip -c ${base}.R1.paired.fastq.gz | wc -l)
    num_r2_paired=\$(gunzip -c ${base}.R2.paired.fastq.gz | wc -l)
    num_paired=\$((\$((num_r1_paired + num_r2_paired))/4))
    num_r1_unpaired=\$(gunzip -c ${base}.R1.unpaired.fastq.gz | wc -l)
    num_r2_unpaired=\$(gunzip -c ${base}.R2.unpaired.fastq.gz | wc -l)
    num_unpaired=\$((\$((num_r1_unpaired + num_r2_unpaired))/4))
    num_trimmed=\$((num_paired + num_unpaired))
    percent_trimmed=\$((100-\$((100*num_trimmed/num_untrimmed))))
    echo Sample_Name,Raw_Reads,Trimmed_Reads,Percent_Trimmed,Mapped_Reads,Mean_Coverage > \$base'_results.csv'
    printf "\$base,\$num_untrimmed,\$num_trimmed,\$percent_trimmed" >> \$base'_results.csv'
    """
}
}
/*
 * Map sequence reads to RhV Genomes using BBMap.
 */
process Genome_Mapping {
	errorStrategy 'retry'
    maxRetries 3

    input: 
        tuple val(base), file("${base}.trimmed.fastq.gz"), file("*_results.csv") from Trim_out_ch
        tuple val(base), file("*_results.csv") from Results_trimmed_ch
        file REFERENCE_FASTA

    output:
        tuple val(base), file("${base}.sam")into Aligned_sam_ch, Sam_Ref_Fasta_ch
        tuple val(base), file("*_results.csv") into Results_mapped_ch
        tuple val (base), file("*") into Dump_ch

    publishDir "${params.outdir}mapping_result_sam_files", mode: 'copy', pattern:'*.sam*'


    script:

    """
    #!/bin/bash

    cat ${base}*.fastq.gz > ${base}_cat.fastq.gz

    ${BBMAP_PATH}bbmap.sh in=${base}.trimmed.fastq.gz outm=${base}.sam ref=${REFERENCE_FASTA} local=true -Xmx6g > bbmap_out.txt 2>&1
    reads_mapped=\$(cat bbmap_out.txt | grep "mapped:" | cut -d\$'\\t' -f3)
    printf ",\$reads_mapped" >> ${base}_results.csv
    """
}
/*
 * Generate Reference Fasta from Mapping Result.
 */
process Reference_Fasta {
	errorStrategy 'retry'
    maxRetries 3

    input: 
    tuple val(base), file("${base}.sam") from Sam_Ref_Fasta_ch
    file REFERENCE_FASTA
    file REFERENCE_FASTA_INDEX

    output:
    tuple val(base), file("${base}_most_mapped_ref.txt") into Mapped_Ref_Id_ch, Mapped_Ref_Final_Cons_Id_ch
    tuple val(base), file("${base}_mapped_ref_genome.fasta") into Mapped_Ref_Gen_ch, Mapped_Ref_Gen_Cons_ch
   
    publishDir "${params.outdir}ref_most_mapped_text", mode: 'copy', pattern:'*_most_mapped_ref.txt*'  
    publishDir "${params.outdir}ref_most_mapped_fasta", mode: 'copy', pattern:'*_mapped_ref_genome.fasta*'    

    script:

    """
    
    samtools view -S -b ${base}.sam > ${base}.bam

    bedtools bamtobed -i ${base}.bam | head -1 > ${base}_most_mapped_ref.txt

    id=\$(awk '{print \$1}' ${base}_most_mapped_ref.txt)

    samtools faidx ${REFERENCE_FASTA} \$id > ${base}_mapped_ref_genome.fasta


    """
}
/*
 * Convert BAM to coordinate sorted BAM
 */
 // Step 1. Convert Sam to Bam
 // Step 2. Sort Bam file by coordinates
 // Step 3. Generate Statistics about Bam file
process Sort_Bam {
	errorStrategy 'retry'
    maxRetries 3

    input: 
    tuple val(base), file("${base}.sam") from Aligned_sam_ch

    output:
    tuple val(base), file("${base}.bam") into Aligned_bam_ch, Bam_ch
    tuple val(base), file("${base}.sorted.bam") into Sorted_bam_ch, Sorted_Cons_Bam_ch
    tuple val(base), file("${base}_flagstats.txt") into Flagstats_ch

    publishDir "${params.outdir}bam_files", mode: 'copy', pattern:'*.bam*'
    publishDir "${params.outdir}sorted_bam_files", mode: 'copy', pattern:'*.sorted.bam*'  
    publishDir "${params.outdir}flagstats", mode: 'copy', pattern:'*_flagstats.txt*'  

    script:
    """
    #!/bin/bash
    samtools view -S -b ${base}.sam > ${base}.bam
    samtools sort -@ ${task.cpus} ${base}.bam > ${base}.sorted.bam
    samtools flagstat ${base}.sorted.bam > ${base}_flagstats.txt

    """
}
/*
 * Variant Calling
 */
 // Step 1: Calculate the read coverage of positions in the genome
 // Step 2: Detect the single nucleotide polymorphisms (SNPs)
 // Step 3: Filter and report the SNP variants in variant calling format (VCF)
 // VIEW RESULTS:   less -S ${base}_final_variants.vcf
process Variant_Calling {
	errorStrategy 'retry'
    maxRetries 3

	input:
    tuple val(base), file("${base}.sorted.bam") from Sorted_bam_ch
    tuple val(base), file("${base}_mapped_ref_genome.fasta") from Mapped_Ref_Gen_ch
    file REFERENCE_FASTA
    file REFERENCE_FASTA_INDEX

	output:
    tuple val(base), file("${base}_variants.vcf") into Variants_vcf_consensus_ch
    tuple val(base), file("${base}_raw.bcf") into Raw_bcf_ch
    tuple val(base), file("${base}_final_variants.vcf") into Final_Variants_ch      

    publishDir "${params.outdir}vcf_variants", mode: 'copy', pattern:'*_variants.vcf*'  
    publishDir "${params.outdir}bcf_raw", mode: 'copy', pattern:'*_raw.bcf*'  
    publishDir "${params.outdir}vcf_final_variants", mode: 'copy', pattern:'*_final_variants.vcf*'  

	script:

	"""
    #!/bin/bash

    bcftools mpileup -O b -o ${base}_raw.bcf \
    -f ${base}_mapped_ref_genome.fasta ${base}.sorted.bam  
    bcftools call --ploidy 1 -m -v -o ${base}_variants.vcf ${base}_raw.bcf 
    vcfutils.pl varFilter ${base}_variants.vcf  > ${base}_final_variants.vcf

	"""
}
/*
 * Consensus
 *
 * Consensus generation using sorted Bam, final_variants.vcf, and mapped_ref_genome.
 */
process Consensus {
	errorStrategy 'retry'
    maxRetries 3

    input:
    tuple val(base), file("${base}_final_variants.vcf") from Final_Variants_ch  
    tuple val(base), file("${base}.sorted.bam") from Sorted_Cons_Bam_ch
    tuple val(base), file("${base}_mapped_ref_genome.fasta") from Mapped_Ref_Gen_Cons_ch

    output:
    tuple val(base), file("${base}_consensus.fasta") into Consensus_Fasta_ch, Consensus_Fasta_Processing_ch
    tuple val(base), file("${base}_consensus_masked.fasta") into Consensus_fasta_Masked_ch
    tuple val(base), file("${base}_bed4mask.bed") into Consensus_bed4mask_ch

    publishDir "${params.outdir}consensus_fasta_files", mode: 'copy', pattern:'*_consensus.fasta*'  
    publishDir "${params.outdir}consensus_masked_fasta_files", mode: 'copy', pattern:'*_consensus_masked.fasta*'  
    publishDir "${params.outdir}bed4mask_bed_files", mode: 'copy', pattern:'*_bed4mask.bed*'  

    script:

    """
    #!/bin/bash

    bgzip -c ${base}_final_variants.vcf > ${base}_final_variants.vcf.gz
    bcftools index ${base}_final_variants.vcf.gz
    cat ${base}_mapped_ref_genome.fasta | bcftools consensus ${base}_final_variants.vcf.gz > ${base}_consensus.fasta
    bedtools genomecov -bga -ibam ${base}.sorted.bam -g ${base}_mapped_ref_genome.fasta | awk '\$4 < 20' | bedtools merge > ${base}_bed4mask.bed
    bedtools maskfasta -fi ${base}_consensus.fasta -bed ${base}_bed4mask.bed -fo ${base}_consensus_masked.fasta

    """
}
/*
 * Final Consensus
 * 
 * Creates final consensus by replacing the RhV Genome consensus fasta header with the Sample name.
 */
process Final_Consensus {
	errorStrategy 'retry'
    maxRetries 3

    input:
    tuple val(base), file("${base}_consensus.fasta") from Consensus_Fasta_Processing_ch 
    tuple val(base), file("${base}_most_mapped_ref.txt") from Mapped_Ref_Final_Cons_Id_ch

    output:
    tuple val(base), file("${base}_consensus_final.fasta") into Consensus_fasta_Complete_ch

    publishDir "${params.outdir}consensus_final", mode: 'copy', pattern:'*_consensus_final.fasta*'  

    script:

    """
    #!/bin/bash

    id=\$(awk '{print \$1}' ${base}_most_mapped_ref.txt)
    
    seqkit replace -p "\$id" -r '${base}' ${base}_consensus.fasta > ${base}_consensus_final.fasta

    """
}
if (params.withFastQC) {

    if (params.singleEnd) {
 /* FastQC
 *
 * Sequence read quality control analysis.
 */
process FastQC_SE {
	errorStrategy 'retry'
    maxRetries 3

    input:
        file R1 from Trim_out_fastqc_SE

    output:
	file '*_fastqc.{zip,html}' into fastqc_results

    publishDir "${params.outdir}fastqc_results", mode: 'copy', pattern:'*_fastqc.{zip,html}*'  

    script:
    """
    #!/bin/bash

    

    """
    }
} else {
process FastQC_PE {
	errorStrategy 'retry'
    maxRetries 3

    input:
        file R1 from Trim_out_fastqc_PE

    output:
	file '*_fastqc.{zip,html}' into fastqc_results

    publishDir "${params.outdir}fastqc_results", mode: 'copy', pattern:'*_fastqc.{zip,html}*'  

    script:
    """
    #!/bin/bash

    fastqc --quiet --threads $task.cpus *.fastq.gz

    """
    }
}
}