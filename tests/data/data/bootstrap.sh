#!/usr/bin/bash

# Setup Logging -------------------------------------------------------------

log()
{
    >&2 echo $@
}

debug()
{
    [[ "${VERBOSE-0}" -ne 0 ]] && >&2 echo $@
}

set -euo pipefail

if [[ "${VERBOSE-0}" -ne 0 ]]; then
    set -x
fi

psql-uta()
{
    echo "set schema '$VERSION'; $1" \
    | PGPASSWORD=anonymous psql --csv -h uta.biocommons.org -U anonymous -d uta \
    | tail -n +3 \
    | sort
}

pg-list()
{
    result=""
    while [[ $# -ne 0 ]]; do
        if [[ ! -z "${result}" ]]; then
            result="${result}, "
        fi
        result="${result}'$1'"
        shift
    done
    result="(${result})"
    echo $result
}

# Initialization ------------------------------------------------------------

if [[ "$#" -ne 2 ]]; then
    log "USAGE: bootstrap.sh DL_URL VERSION"
    log ""
    log "E.g.: bootstrap.sh http://dl.biocommons.org/uta uta_20180821"
    log ""
    log "Set VERBOSE=1 to increase verbosity."
    exit 1
fi

# path to the directory where the script resides.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Download URL.
DL_URL=$1

# Database name/version.
VERSION=$2

# Destination directory.
DST=$SCRIPT_DIR

# The HGNC symbols of the genes to fetch.
set +e
read -r -d '' GENES <<EOF
AADACL3
ADRA2B
ALG9
AOAH
ASB18
ATM
BAHCC1
BRCA1
BRCA2
CACNA1S
CCNQ
COL1A1
COL3A1
DEFB133
DNAH11
DNMBP-AS1
EGLN1
EGR2
FBN1
FOLR3
H2AW
HMGA1
IRAK3
JRK
L1CAM
LCE2B
LCE3C
LINC00336
MC1R
MECP2
MLH1
MSH6
MYH7
NEFL
OMA1
OPA1
OR9A4
ORAI1
PTEN
PTH2
RET
RMRP
RYR1
RYR2
SCN5A
SELENON
SERPINC1
SIL1
SLC22A5
SRD5A2
SSTR3
TERC
TPM3
TSC2
TSIX
EOF
set -e

# Transform gene list for postgres query.
PG_GENES=$(pg-list $GENES)

# Force consistent sorting.
export LC_ALL=C

# Generate Data for Tests ---------------------------------------------------

cd $DST

# download database dumps

mkdir -p download
cd download
for f in $VERSION.pgd.gz{,.sha1}; do
    test -e $f || wget $DL_URL/$f
done
cd ..

# extract identifiers

psql-uta "select hgnc from gene g where g.hgnc in $PG_GENES;" >download/gene.tsv
psql-uta "select ac from transcript where hgnc in $PG_GENES;" >download/transcript.tsv
psql-uta "select seq_anno_id from seq_anno where ac in (select ac from transcript where hgnc in $PG_GENES);" >download/seq_anno.tsv
psql-uta "select seq_id from seq where seq_id in (select seq_id from seq_anno where ac in (select ac from transcript where hgnc in $PG_GENES));" >download/seq.tsv
psql-uta "select associated_accession_id from associated_accessions where tx_ac in (select ac from transcript where hgnc in $PG_GENES);" >download/associated_accessions.tsv
psql-uta "select exon_set_id from exon_set where tx_ac in (select ac from transcript where hgnc in $PG_GENES);" >download/exon_set.tsv
psql-uta "select exon_id from exon where exon_set_id in (select exon_set_id from exon_set where tx_ac in (select ac from transcript where hgnc in $PG_GENES));" >download/exon.tsv
psql-uta "select exon_aln_id from exon_aln where tx_exon_id in (select exon_id from exon where exon_set_id in (select exon_set_id from exon_set where tx_ac in (select ac from transcript where hgnc in $PG_GENES)));" >download/exon_aln.tsv

# build sql subset

pigz -d -c download/$VERSION.pgd.gz \
| awk -F ' ' -f subset.awk \
| pigz -c \
> $VERSION-subset.pgd.gz
