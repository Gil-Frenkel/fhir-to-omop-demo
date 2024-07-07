#!/bin/bash
#
# Translate FHIR ndjson to OMOPCDM, saving TSV data for later loading.
#
source "$( dirname "${0}" )/../vars"

export PATH="${PATH}:${FHIR_JQ_BIN}"

set -e
set -o pipefail
set -u

# Create local links to the source and destinations.
rm -f data-fhir && ln -s ${FHIR_IN} $_
rm -f data-omop && ln -s ${OMOP_OUT} $_

#
# The list of FHIR resources to process in order.
#
# TODO Consult: https://build.fhir.org/ig/HL7/cdmh/profiles.html#omop-52-to-fhir-r4-mappings
#
RESOURCES=(
  "AllergyIntolerance"        #     ~500
  # Maps to OMOP tables:
  #   condition_occurrence    #     ~100

#  "CarePlan"                  #   ~6,500
#  "CareTeam"                  #   ~6,500
#  "Claim"                     # ~353,500
#  "Condition"                 #  ~16,000
#  "Device"                    #     ~500
#  "DiagnosticReport"          # ~201,500
#  "DocumentReference"         # ~144,000
#  "Encounter"                 # ~144,000
#  "ExplanationOfBenefit"      # ~144,000
#  "ImagingStudy"              #   ~4,000
#  "Immunization"              #  ~12,000
  "Location"                   #   ~1,500
  # Maps to OMOP tables:
  #   care_site                #   ~1,000
  #   location                 #   ~1,000

#  "Media"                     #   ~1,500
#  "MedicationAdministration"  #   ~1,500
#  "MedicationRequest"         # ~209,500
#  "Medication"                #   ~1,500
  "Observation"               # ~670,000
  # Maps to OMOP tables:
  #   condition_occurrence    #       ~0
  #   device_exposure         #       ~0
  #   drug_exposure           #       ~0
  #   measurement             # ~645,000
  #   observation             #  ~25,000
  #   procedure_occurrence    #   ~1,000

  "Organization"              #   ~1,500
  # Maps to OMOP tables:
  #   care_site               #   ~1,000

#  "Patient"                   #   ~1,500
  "PractitionerRole"           #   ~1,500
  # Maps to OMOP tables:
  #   provider                 #   ~1,000

  "Practitioner"               #   ~1,500
  # Maps to OMOP tables:
  #   provider

#  "Procedure"                 #  ~56,500
#  "Provenance"                #   ~1,500
)


# Process the resource types in the order they are declared.
echo "Converting FHIR R4 to OMOP CDM 5.4..."
for resource_type in ${RESOURCES[@]}; do
  # Sanity check that there's a mapping for a type.
  if [ ! -e "./map/${resource_type}.jq" ]; then
    echo "no mapping for resource type: ${resource_type}"
    continue
  fi

  echo "    MAPPING ${resource_type}..."

  # Find all the ndjson files for a FHIR Resource type and pass them through
  # The fhir-jq filter using xargs to process multiple files per invocation.
  # The resulting OMOP staging data are emitted into the OMOP_OUT directory.
  find ${FHIR_IN} -type f -name "${resource_type}_*.ndjson" \
    | xargs -P${CONCURRENCY} fhir-jq -r "$( cat ./map/${resource_type}.jq )" \
    > ${OMOP_OUT}/stg-${resource_type}.tsv
done


# Reduce the tsv and load into the cdm.db.
./reduce.sh
