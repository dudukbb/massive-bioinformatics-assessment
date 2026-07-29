

q
#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Analysis of an Unknown Oxford Nanopore Bacterial Isolate
#
# This workflow performs:
#   1. Raw-read quality assessment
#   2. Long-read genome assembly
#   3. Assembly statistics
#   4. MLST sequence typing
#   5. AMRFinderPlus analysis
#   6. PlasmidFinder analysis
#   7. Separate analysis of contig_17
#   8. Kleborate analysis
#   9. Preparation of a sequence for manual NCBI BLAST analysis
#  10. Recording of tool and database versions
###############################################################################

# Stop with a clear message when an error occurs.
trap 'echo "ERROR: The workflow stopped at line ${LINENO}." >&2' ERR

###############################################################################
# Configuration
###############################################################################

THREADS="${THREADS:-8}"

DATA_DIR="data"
RESULTS_DIR="results"

QC_DIR="${RESULTS_DIR}/qc"
ASSEMBLY_DIR="${RESULTS_DIR}/assembly"
TAXONOMY_DIR="${RESULTS_DIR}/taxonomy"
TYPING_DIR="${RESULTS_DIR}/typing"
AMR_DIR="${RESULTS_DIR}/amr"
PLASMID_DIR="${RESULTS_DIR}/plasmid"
VIRULENCE_DIR="${RESULTS_DIR}/virulence"
LOG_DIR="${RESULTS_DIR}/logs"

READS="${DATA_DIR}/unknown_isolate.fastq.gz"
ASSEMBLY="${ASSEMBLY_DIR}/assembly.fasta"
CONTIG_17="${PLASMID_DIR}/contig_17.fasta"
BLAST_QUERY="${TAXONOMY_DIR}/blast_query_longest_contig.fasta"

# Change this value only if the PlasmidFinder database is located elsewhere.
PLASMID_DB="${PLASMID_DB:-/home/dudu/miniforge3/envs/bioinfo/share/plasmidfinder-2.1.6/database}"

###############################################################################
# Helper functions
###############################################################################

log() {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" |
        tee -a "${LOG_DIR}/workflow.log"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: Required command '$1' was not found." >&2
        echo "Activate the bioinfo environment and install the missing tool." >&2
        exit 1
    fi
}

###############################################################################
# Create output directories
###############################################################################

mkdir -p \
    "${QC_DIR}/nanoplot" \
    "${ASSEMBLY_DIR}" \
    "${TAXONOMY_DIR}" \
    "${TYPING_DIR}" \
    "${AMR_DIR}" \
    "${PLASMID_DIR}/whole_assembly" \
    "${PLASMID_DIR}/contig_17" \
    "${VIRULENCE_DIR}" \
    "${LOG_DIR}"

: > "${LOG_DIR}/workflow.log"

###############################################################################
# Check input data and required programs
###############################################################################

if [[ ! -f "${READS}" ]]; then
    echo "ERROR: Input file was not found: ${READS}" >&2
    echo "Place unknown_isolate.fastq.gz inside the data/ directory." >&2
    exit 1
fi

require_command NanoPlot
require_command NanoStat
require_command seqkit
require_command flye
require_command mlst
require_command amrfinder
require_command kleborate

# PlasmidFinder may be installed under either command name.
if command -v plasmidfinder.py >/dev/null 2>&1; then
    PLASMIDFINDER_CMD="plasmidfinder.py"
elif command -v plasmidfinder >/dev/null 2>&1; then
    PLASMIDFINDER_CMD="plasmidfinder"
else
    echo "ERROR: PlasmidFinder was not found." >&2
    exit 1
fi

if [[ ! -d "${PLASMID_DB}" ]]; then
    echo "ERROR: PlasmidFinder database was not found at:" >&2
    echo "  ${PLASMID_DB}" >&2
    echo "Set its location before running the script, for example:" >&2
    echo "  PLASMID_DB=/path/to/plasmidfinder_db bash code/analysis_commands.sh" >&2
    exit 1
fi

###############################################################################
# Step 1: Raw-read quality assessment
###############################################################################

log "Step 1/9: Running raw-read quality assessment."

NanoPlot \
    --fastq "${READS}" \
    --outdir "${QC_DIR}/nanoplot" \
    --threads "${THREADS}" \
    2>&1 | tee "${LOG_DIR}/nanoplot.log"

NanoStat \
    --fastq "${READS}" \
    > "${QC_DIR}/nanostat.txt" \
    2> "${LOG_DIR}/nanostat.log"

seqkit stats \
    --threads "${THREADS}" \
    "${READS}" \
    > "${QC_DIR}/seqkit_read_stats.tsv" \
    2> "${LOG_DIR}/seqkit_reads.log"

log "Raw-read quality assessment completed."

###############################################################################
# Step 2: Genome assembly
###############################################################################

log "Step 2/9: Running Flye genome assembly."

# --nano-raw was used because the input consists of raw ONT reads.
flye \
    --nano-raw "${READS}" \
    --out-dir "${ASSEMBLY_DIR}" \
    --threads "${THREADS}" \
    2>&1 | tee "${LOG_DIR}/flye.log"

if [[ ! -s "${ASSEMBLY}" ]]; then
    echo "ERROR: Flye did not produce ${ASSEMBLY}." >&2
    exit 1
fi

log "Genome assembly completed."

###############################################################################
# Step 3: Assembly statistics
###############################################################################

log "Step 3/9: Calculating assembly statistics."

seqkit stats \
    --all \
    --threads "${THREADS}" \
    "${ASSEMBLY}" \
    > "${ASSEMBLY_DIR}/assembly_stats.tsv" \
    2> "${LOG_DIR}/seqkit_assembly.log"

log "Assembly statistics completed."

###############################################################################
# Step 4: Species-confirmation file and MLST analysis
###############################################################################

log "Step 4/9: Preparing species-confirmation input and running MLST."

# The longest assembled contig is saved for manual species confirmation
# through the NCBI BLAST web interface.
seqkit sort \
    --by-length \
    --reverse \
    "${ASSEMBLY}" |
    seqkit head \
        --number 1 \
        > "${BLAST_QUERY}"

cat > "${TAXONOMY_DIR}/NCBI_BLAST_INSTRUCTIONS.txt" <<BLASTEOF
NCBI BLAST was used through its web interface.

Input file:
${BLAST_QUERY}

Suggested database:
Nucleotide collection (nt)

Suggested program:
Megablast

Purpose:
Species confirmation by comparison of the longest assembled contig with
reference nucleotide sequences.

The BLAST result should be interpreted together with the MLST and Kleborate
results. The web-interface result is not generated automatically by this
script.
BLASTEOF

mlst "${ASSEMBLY}" \
    > "${TYPING_DIR}/mlst.tsv" \
    2> "${LOG_DIR}/mlst.log"

log "MLST analysis and BLAST query preparation completed."

###############################################################################
# Step 5: Antimicrobial resistance analysis
###############################################################################

log "Step 5/9: Running AMRFinderPlus."

# --plus includes selected stress-response, biocide, virulence and other
# additional genes together with the core antimicrobial-resistance results.
amrfinder \
    --nucleotide "${ASSEMBLY}" \
    --organism Klebsiella_pneumoniae \
    --plus \
    --threads "${THREADS}" \
    --output "${AMR_DIR}/amrfinder.tsv" \
    2> "${LOG_DIR}/amrfinder.log"

log "AMRFinderPlus analysis completed."

###############################################################################
# Step 6: PlasmidFinder analysis of the complete assembly
###############################################################################

log "Step 6/9: Running PlasmidFinder on the complete assembly."

"${PLASMIDFINDER_CMD}" \
    -i "${ASSEMBLY}" \
    -o "${PLASMID_DIR}/whole_assembly" \
    -p "${PLASMID_DB}" \
    -x \
    2>&1 | tee "${LOG_DIR}/plasmidfinder_whole_assembly.log"

log "Whole-assembly PlasmidFinder analysis completed."

###############################################################################
# Step 7: Separate analysis of contig_17
###############################################################################

log "Step 7/9: Extracting and analyzing contig_17."

seqkit grep \
    --pattern "contig_17" \
    "${ASSEMBLY}" \
    > "${CONTIG_17}"

if [[ ! -s "${CONTIG_17}" ]]; then
    echo "ERROR: contig_17 was not found in ${ASSEMBLY}." >&2
    exit 1
fi

seqkit stats \
    --all \
    "${CONTIG_17}" \
    > "${PLASMID_DIR}/contig_17_stats.tsv"

"${PLASMIDFINDER_CMD}" \
    -i "${CONTIG_17}" \
    -o "${PLASMID_DIR}/contig_17" \
    -p "${PLASMID_DB}" \
    -x \
    2>&1 | tee "${LOG_DIR}/plasmidfinder_contig_17.log"

# Save the AMRFinderPlus records located on contig_17.
awk -F '\t' '
    NR == 1 || $2 == "contig_17"
' "${AMR_DIR}/amrfinder.tsv" \
    > "${AMR_DIR}/contig_17_amr.tsv"

log "contig_17 analysis completed."

###############################################################################
# Step 8: Kleborate analysis
###############################################################################

log "Step 8/9: Running Kleborate."

kleborate \
    --assemblies "${ASSEMBLY}" \
    --output "${VIRULENCE_DIR}/kleborate.tsv" \
    2> "${LOG_DIR}/kleborate.log"

log "Kleborate analysis completed."

###############################################################################
# Step 9: Record software and database versions
###############################################################################

log "Step 9/9: Recording software and database versions."

{
    echo "Analysis date: $(date --iso-8601=seconds)"
    echo
    echo "NanoPlot:"
    NanoPlot --version 2>&1 || true
    echo
    echo "NanoStat:"
    NanoStat --version 2>&1 || true
    echo
    echo "SeqKit:"
    seqkit version 2>&1 || true
    echo
    echo "Flye:"
    flye --version 2>&1 || true
    echo
    echo "mlst:"
    mlst --version 2>&1 || true
    echo
    echo "AMRFinderPlus:"
    amrfinder --version 2>&1 || true
    echo
    echo "AMRFinderPlus database:"
    amrfinder --database_version 2>&1 || true
    echo
    echo "PlasmidFinder:"
    "${PLASMIDFINDER_CMD}" --version 2>&1 || true
    echo
    echo "PlasmidFinder database path:"
    echo "${PLASMID_DB}"
    echo
    echo "Kleborate:"
    kleborate --version 2>&1 || true
} > "${LOG_DIR}/tool_versions.txt"

###############################################################################
# Completion message
###############################################################################

log "All automated analyses completed successfully."

cat <<SUMMARY

Analysis completed.

Main outputs:
  Quality control:
    ${QC_DIR}/

  Assembly:
    ${ASSEMBLY}

  Assembly statistics:
    ${ASSEMBLY_DIR}/assembly_stats.tsv

  BLAST query:
    ${BLAST_QUERY}

  MLST:
    ${TYPING_DIR}/mlst.tsv

  AMRFinderPlus:
    ${AMR_DIR}/amrfinder.tsv

  AMR findings on contig_17:
    ${AMR_DIR}/contig_17_amr.tsv

  PlasmidFinder:
    ${PLASMID_DIR}/whole_assembly/
    ${PLASMID_DIR}/contig_17/

  Kleborate:
    ${VIRULENCE_DIR}/kleborate.tsv

  Tool versions:
    ${LOG_DIR}/tool_versions.txt

Manual step:
  Upload ${BLAST_QUERY} to the NCBI BLAST web interface for species
  confirmation and record the result in findings.md.

SUMMARY

