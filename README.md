# Massive Bioinformatics Assessment

## Project Overview

This project analyzes an unknown bacterial isolate using raw Oxford Nanopore Technologies (ONT) sequencing reads.

The objectives of this analysis are to:

- Identify the bacterial species.
- Determine its sequence type (MLST).
- Detect antimicrobial resistance genes.
- Investigate whether important resistance genes are likely plasmid-associated.
- Identify major virulence factors.
- Produce a reproducible bioinformatics workflow.

The isolate was identified as **Klebsiella pneumoniae ST258** carrying multiple antimicrobial resistance genes, including **blaKPC-3**.

---

## Project Structure

```text
massive-bioinformatics-assessment/
├── README.md
├── findings.md
├── notes.md
├── code/
│   └── analysis_commands.sh
├── data/
│   └── unknown_isolate.fastq.gz
├── references/
│   └── references.md
└── results/
    ├── qc/
    ├── assembly/
    ├── amr/
    ├── plasmid/
    └── virulence/
```

The raw sequencing data is not included in the repository because of its size.

---

## Requirements

The workflow was developed in a Linux environment using Conda.

Required software:

- NanoPlot
- NanoStat
- SeqKit
- Flye
- mlst
- AMRFinderPlus
- PlasmidFinder
- Kleborate

Species confirmation was additionally performed using the NCBI BLAST web interface.

---

## Input Data

Place the raw sequencing file in:

```text
data/unknown_isolate.fastq.gz
```

---

## Activate the Environment

```bash
conda activate bioinfo
```

---

## Run the Workflow

Make the script executable:

```bash
chmod +x code/analysis_commands.sh
```

Run the workflow:

```bash
bash code/analysis_commands.sh
```

---

## Workflow

The workflow performs the following analyses:

1. Raw-read quality assessment
2. Genome assembly
3. Assembly statistics
4. Preparation of the longest contig for manual NCBI BLAST confirmation
5. MLST sequence typing
6. AMRFinderPlus analysis
7. PlasmidFinder analysis
8. Kleborate analysis

---

## Manual BLAST Step

The longest assembled contig was used for manual species confirmation using the NCBI BLAST web interface.

Recommended settings:

- Database: **Nucleotide collection (nt)**
- Program: **Megablast**

The BLAST result should be interpreted together with the MLST and Kleborate analyses.

---

## Main Output Files

### Quality assessment

```text
results/qc/
```

### Genome assembly

```text
results/assembly/assembly.fasta
```

### Assembly statistics

```text
results/assembly/assembly_info.txt
```

### Antimicrobial resistance

```text
results/amr/amrfinder.tsv
```

### Plasmid analysis

```text
results/plasmid/
```

### Virulence analysis

```text
results/virulence/klebsiella_pneumo_complex_output.txt
```

---

## Final Report

The complete interpretation of the analysis is available in:

```text
findings.md
```

The report includes:

- Species identification
- MLST sequence type
- Antimicrobial resistance profile
- Plasmid-associated resistance analysis
- Virulence analysis
- Limitations
- A plain-language note for Professor Kılıç

---

## Limitations

This workflow produces a draft genome assembly rather than a complete closed genome.

The presence of **blaKPC-3** and an **IncI2** plasmid replicon on the same contig suggests that the resistance gene is likely plasmid-associated. However, this does not prove that the gene is located on a complete plasmid.

Genomic predictions should be confirmed using routine antimicrobial susceptibility testing before making clinical treatment decisions.
