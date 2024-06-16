#!/bin/bash
#
# Reduces translated OMOPCDM data into loadable rows
#
source "$( dirname "${0}" )/../vars"

set -e
set -o pipefail
set -u

echo "Resetting cdm.db..." && cp -v "${CDM_DB}" ./cdm.db # XXX - testing


##
# Gets the OMOPCDM table_name -> FHIR Resource names from mapping files.
#
function omop_fhir_mappings() {
  # Inspect the mapping files to determine which FHIR resources produce rows
  # of OMOPCDM and list the destination table name followed by all the
  # possible FHIR Resource types that generate input for that table.
  #
  # For example:
  #   provider Practitioner PractitionerRole
  #
  grep -A1 '^\[' map/*.jq \
    | grep -v '\[' \
    | grep '^map' \
    | sed -e 's:^map/\(.*\).jq-[ ]*"\([^"]*\)",.*:\2 \1:' \
    | sort -u \
    | awk '
# Print the accumulated omop table mappings.
func emit() {
  if (omop) {
    print omop " " fhir
  }
  omop = $1
  fhir = $2
}

# Process each row, accumulating new source resource mappings.
{
  if ($1 == omop) {
    fhir = fhir " " $2
  } else {
    emit()
  }
}

# Emit the final accumulated row.
END { emit() }
'
}


##
# Gets the staged source filenames for a list of resource types.
#
function get_resource_filenames() {
  for fhir in ${@}; do
    local stg=data-omop/stg-${fhir}.tsv
    [ -e "${stg}" ] && echo "${stg}"
  done
}


##
# Extract and reduce the entries for a table from staged source files.
#
function reduce() {
  local table_name=${1}
  local resource_files=$( get_resource_filenames ${2} )
  [ -z "${resource_files}" ] && return
  sed -n "s/^${table_name}\t//p" ${resource_files} \
    | sort -n \
    | awk '
BEGIN { FS = "\t" }

func emit() {
  # Print the merged row.
  ORS=""; print row[1]; for (i = 2; i <= NF; ++i) print FS row[i];
  ORS="\n"; print ""
  # Copy the current row into 'row'.
  for (i = 1; i <= NF; ++i) row[i] = $i
}

func merge() {
  for (i = 1; i <= NF; ++i) {
    if (row[i] == "") {
      row[i] = $i
    } else if ($i != "" && row[i] != $i) {
      system("echo MERGE CONFLICT: " $i " != " row[i] " 1>&2")
    }
  }
}

{
  # Initialize row for the first line of input.
  if (row[1] == "") { row[1] = $1 }

  # Reduce this line into the previous one.
  if ($1 == row[1]) { merge() } else { emit() }
}

END { emit() }
' \
  > data-omop/${table_name}.tsv

  # Load the data into the database.
  sqlite3 cdm.db <<SQL
.mode ascii
.separator "\t" "\n"
.import data-omop/${table_name}.tsv ${table_name}
SQL
}


# Get the mapped table_names to source files for reducing.
omop_fhir_mappings | while read omop resources; do
  echo "Coalescing ${omop} data..."
  reduce "${omop}" "${resources}"
done