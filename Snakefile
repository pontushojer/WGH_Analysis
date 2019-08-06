from snakemake.utils import validate, available_cpu_count
import itertools
import os
import sys

configfile: "config.yaml"
validate(config, "config.schema.yaml")

# Create list of files to be created in cdhitprep
indexes = ["".join(tuple) for tuple in itertools.product("ATCG", repeat=config["index_nucleotides"])] \
                if config["index_nucleotides"] > 0 else ["all"]

def get_jobs_given():
    """
    Get the number of jobs/cores specfied in command.
    :return: integer
    """
    arguments = sys.argv
    for item in ['-j','--jobs','--cores']:
        try:
            index = arguments.index(item)
        except ValueError:
            continue
        return int(arguments[index + 1])
    return 0

if get_jobs_given() >= 3:
    #
    # Piped trimming of reads, executed if -j/--jobs/--cores is given with number larger
    # then or equal to 3 as there are 3 processes in the pipe. Intermediate fastqs are interleaved.
    #
    rule trim_r1_handle:
        #Trim away E handle on R1 5'. Also removes reads shorter than 85 bp.
        output:
            interleaved_fastq=pipe("{dir}/trimmed-a.fastq")
        input:
            r1_fastq="{dir}/reads.1.fastq.gz",
            r2_fastq="{dir}/reads.2.fastq.gz"
        log: "{dir}/trimmed-a.log"
        threads: int(available_cpu_count()/3)
        group: "piped-trim"
        shell:
            "cutadapt"
            " -g ^CAGTTGATCATCAGCAGGTAATCTGG"
            " -e 0.2"
            " --discard-untrimmed"
            " -j {threads}"
            " -m 65"
            " -o {output.interleaved_fastq}"
            " --interleaved "
            " {input.r1_fastq}"
            " {input.r2_fastq}"
            " > {log}"

    rule extract_barcodes:
        output:
            interleaved_fastq=pipe("{dir}/unbarcoded.fastq")
        input:
            interleaved_fastq="{dir}/trimmed-a.fastq"
        log: "{dir}/extractbarcode.log"
        group: "piped-trim"
        shell:
            # BDHVBDVHBDVHBDVH
            "blr extractbarcode"
            " {input.interleaved_fastq}"
            " -o1 {output.interleaved_fastq}"
            " 2> {log}"

    rule final_trim:
        # Cut H1691' + TES sequence from 5' of R1. H1691'=CATGACCTCTTGGAACTGTC, TES=AGATGTGTATAAGAGACAG.
        # Cut 3' TES' sequence from R1 and R2. TES'=CTGTCTCTTATACACATCT
        # Discard untrimmed.
        output:
            r1_fastq="{dir}/trimmed-c.1.fastq.gz",
            r2_fastq="{dir}/trimmed-c.2.fastq.gz"
        input:
            interleaved_fastq="{dir}/unbarcoded.fastq"
        log: "{dir}/trimmed-b.log"
        threads: int(available_cpu_count()/3)
        group: "piped-trim"
        shell:
            "cutadapt"
            " -a ^CATGACCTCTTGGAACTGTCAGATGTGTATAAGAGACAG...CTGTCTCTTATACACATCT "
            " -A CTGTCTCTTATACACATCT "
            " -e 0.2"
            " --discard-untrimmed"
            " --pair-filter 'first'"
            " -j {threads}"
            " -m 25"
            " -o {output.r1_fastq}"
            " -p {output.r2_fastq}"
            " {input.interleaved_fastq}"
            " --interleaved"
            " > {log}"

else:
    #
    # Serial trimming of reads.
    #
    rule trim_r1_handle:
        #Trim away E handle on R1 5'. Also removes reads shorter than 85 bp.
        output:
            r1_fastq="{dir}/trimmed-a.1.fastq.gz",
            r2_fastq="{dir}/trimmed-a.2.fastq.gz"
        input:
            r1_fastq="{dir}/reads.1.fastq.gz",
            r2_fastq="{dir}/reads.2.fastq.gz"
        log: "{dir}/trimmed-a.log"
        threads: 20
        shell:
            "cutadapt"
            " -g ^CAGTTGATCATCAGCAGGTAATCTGG"
            " -e 0.2"
            " --discard-untrimmed"
            " -j {threads}"
            " -m 65"
            " -o {output.r1_fastq}"
            " -p {output.r2_fastq}"
            " {input.r1_fastq}"
            " {input.r2_fastq}"
            " > {log}"


    rule extract_barcodes:
        output:
            r1_fastq=temp("{dir}/unbarcoded.1.fastq"),
            r2_fastq=temp("{dir}/unbarcoded.2.fastq")
        input:
            r1_fastq="{dir}/trimmed-a.1.fastq.gz",
            r2_fastq="{dir}/trimmed-a.2.fastq.gz"
        log: "{dir}/extractbarcode.log"
        shell:
            # BDHVBDVHBDVHBDVH
            "blr extractbarcode"
            " {input.r1_fastq} {input.r2_fastq}"
            " -o1 {output.r1_fastq} -o2 {output.r2_fastq}"
            " 2> {log}"


    rule compress:
        output: "{dir}/{sample}.fastq.gz"
        input: "{dir}/{sample}.fastq"
        shell:
            "pigz < {input} > {output}"


    rule final_trim:
        # Cut H1691' + TES sequence from 5' of R1. H1691'=CATGACCTCTTGGAACTGTC, TES=AGATGTGTATAAGAGACAG.
        # Cut 3' TES' sequence from R1 and R2. TES'=CTGTCTCTTATACACATCT
        # Discard untrimmed.
        output:
            r1_fastq="{dir}/trimmed-c.1.fastq.gz",
            r2_fastq="{dir}/trimmed-c.2.fastq.gz"
        input:
            r1_fastq="{dir}/unbarcoded.1.fastq.gz",
            r2_fastq="{dir}/unbarcoded.2.fastq.gz"
        log: "{dir}/trimmed-b.log"
        threads: 20
        shell:
            "cutadapt"
            " -a ^CATGACCTCTTGGAACTGTCAGATGTGTATAAGAGACAG...CTGTCTCTTATACACATCT "
            " -A CTGTCTCTTATACACATCT "
            " -e 0.2"
            " --discard-untrimmed"
            " --pair-filter 'first'"
            " -j {threads}"
            " -m 25"
            " -o {output.r1_fastq}"
            " -p {output.r2_fastq}"
            " {input.r1_fastq}"
            " {input.r2_fastq}"
            " > {log}"

# If the number of index nucleotide is 0 only on file will be created.
if config["index_nucleotides"] == 0:
    rule cdhitprep:
        # Create fasta containing aggregates barcode sequences from fastq file headers.
        output:
            "{dir}/unique_bc/all.fa"
        input:
            r1_fastq = "{dir}/trimmed-c.1.fastq.gz"
        log:
            stdout = "{dir}/cdhit_prep.stdout",
            stderr = "{dir}/cdhit_prep.stderr"
        shell:
            "blr cdhitprep "
            " {input.r1_fastq}"
            " {output}"
            " -f 0 > {log.stdout} 2> {log.stderr}"
else:
    rule cdhitprep:
        # Create fasta containing aggregates barcode sequences from fastq file headers.
        output:
            expand("{{dir}}/unique_bc/{sample}.fa", sample=indexes)
        input:
            r1_fastq = "{dir}/trimmed-c.1.fastq.gz"
        params:
            dir = "{dir}/unique_bc/"
        log:
            stdout = "{dir}/cdhit_prep.stdout",
            stderr = "{dir}/cdhit_prep.stderr"
        shell:
            "blr cdhitprep "
            " {input.r1_fastq}"
            " {params.dir}"
            " -i {config[index_nucleotides]}"
            " -f 0 > {log.stdout} 2> {log.stderr}"


rule barcode_clustering:
    # Barcode clustering using cd-hit-454
    input:
       "{dir}/unique_bc/{sample}.fa"
    output:
        "{dir}/unique_bc/{sample}.clustered",
        "{dir}/unique_bc/{sample}.clustered.clstr"
    threads: 20
    log: "{dir}/unique_bc/{sample}.clustering.log"
    params:
        prefix= lambda wc,output: os.path.splitext(output[1])[0]
    shell:
        " (cd-hit-454 "
        " -i {input} "
        " -o {params.prefix} "
        " -T {threads} "
        " -c 0.9 -gap 100 -g 1 -n 3 -M 0) >> {log}"

rule concat_files:
    # Concatenate all the .clstr files into one single file.
    output:
        "{dir}/barcodes.clstr"
    input:
        expand("{{dir}}/unique_bc/{sample}.clustered.clstr", sample=indexes)
    shell:
        "cat {input} >> {output}"

rule bowtie2_mapping:
    # Mapping of trimmed fastq to reference using bowtie2
    output:
        bam = "{dir}/mapped.bam"
    input:
        r1_fastq = "{dir}/trimmed-c.1.fastq.gz",
        r2_fastq = "{dir}/trimmed-c.2.fastq.gz"
    threads: 20
    params:
        reference = config["bowtie2_reference"]
    log: "{dir}/bowtie2_mapping.log"
    shell:
        " (bowtie2 "
        "    -1 {input.r1_fastq} "
        "    -2 {input.r2_fastq} "
        "    -x {params.reference} "
        "    --maxins 2000 "
        "    -p {threads} | "
        "    samtools view  - "
        "        -@ {threads} "
        "        -bh > {output.bam}) 2> {log}"

rule sort_bam:
    # Sort bam file using samtools
    output:
        bam = "{dir}/mapped.sorted.bam"
    input:
        bam = "{dir}/mapped.bam"
    threads: 20
    shell:
        "samtools sort "
        " {input.bam} "
        " -@ {threads} > {output.bam}"

rule tagbam:
    # Add barcode information to bam file using custom script
    output:
        bam = "{dir}/mapped.sorted.tag.bam"
    input:
        bam = "{dir}/mapped.sorted.bam",
        clstr = "{dir}/barcodes.clstr"
    log: "{dir}/tag_bam.stderr"
    shell:
        "(blr tagbam "
        " {input.bam} "
        " {input.clstr}"
        " {output.bam}"
        " -bc {config[cluster_tag]}) 2> {log} "

rule duplicates_removal:
    # Remove duplicates within barcode clusters using picard.
    output:
        bam = "{dir}/mapped.sorted.tag.rmdup.bam"
    input:
        bam = "{dir}/mapped.sorted.tag.bam"
    log:
        metrics = "{dir}/picard_rmdup_metrics.log",
        stderr = "{dir}/4_rmdup.log"
    params:
        picard_command = config["picard_command"],
        heap_space=config["heap_space"]
    shell:
        "({params.picard_command} -Xms{params.heap_space}g MarkDuplicates "
        " I={input.bam} "
        " O={output.bam} "
        " M={log.metrics} "
        " ASSUME_SORT_ORDER=coordinate "
        " REMOVE_DUPLICATES=true "
        " BARCODE_TAG={config[cluster_tag]}) 2> {log.stderr} "

rule duplicates_marking:
    # Mark duplicates between barcode clusters using picard
    output:
        bam = "{dir}/mapped.sorted.tag.rmdup.mkdup.bam"
    input:
        bam = "{dir}/mapped.sorted.tag.rmdup.bam"
    log:
        metrics = "{dir}/picard_mkdup_metrics.log",
        stderr = "{dir}/4_rmdup.log"
    params:
        picard_command = config["picard_command"],
        heap_space=config["heap_space"]
    shell:
        "({params.picard_command} -Xms{params.heap_space}g MarkDuplicates "
        " I={input.bam} "
        " O={output.bam} "
        " M={log.metrics} "
        " ASSUME_SORT_ORDER=coordinate) 2> {log.stderr} "

rule clusterrmdup_and_index:
    # Removes cluster duplicates and indexes output
    output:
        bam = "{dir}/mapped.sorted.tag.rmdup.x2.bam",
        bai = "{dir}/mapped.sorted.tag.rmdup.x2.bam.bai"
    input:
        bam = "{dir}/mapped.sorted.tag.rmdup.mkdup.bam"
    log: "{dir}/4_rmdup.log"
    shell:
        "blr clusterrmdup "
        " {input.bam}"
        " - "
        " -bc {config[cluster_tag]} 2>> {log} | tee {output.bam} | samtools index - {output.bai} "

rule filterclusters:
    # Filter clusters based on parameters
    output:
        bam = "{dir}/mapped.sorted.tag.rmdup.x2.filt.bam",
        stat1 = "{dir}/cluster_stats/x2.stats.molecules_per_bc",
        stat2 = "{dir}/cluster_stats/x2.stats.molecule_stats"
    input:
        bam = "{dir}/mapped.sorted.tag.rmdup.x2.bam"
    log: "{dir}/4_rmdup.log"
    params:
        stats = "{dir}/cluster_stats/x2.stats"
    shell:
        "(blr filterclusters "
        " -M 260"
        " -s {params.stats} "
        " -bc {config[cluster_tag]} "
        " {input.bam}"
        " {output.bam}) 2>> {log}"

rule bam_to_fastq:
    # Convert final bam file to fastq files for read 1 and 2
    output:
        r1_fastq = "{dir}/reads.1.final.fastq",
        r2_fastq = "{dir}/reads.2.final.fastq"
    input:
        bam = "{dir}/mapped.sorted.tag.rmdup.x2.filt.bam"
    log: "{dir}/picard_samtofastq.log"
    params:
        picard_command = config["picard_command"],
        heap_space=config["heap_space"]
    shell:
        "({params.picard_command} -Xms{params.heap_space}g SamToFastq "
        " I={input.bam} "
        " FASTQ={output.r1_fastq} "
        " VALIDATION_STRINGENCY=SILENT"
        " SECOND_END_FASTQ={output.r2_fastq}) 2>> {log}"