#!/bin/bash
#
# Start a local HAPI FHIR server.
#
source "$( realpath $( dirname "${0}" ) )/../vars"
REPO="https://github.com/barabo/fhir-to-omop-demo"
FILE="demo/hapi/start.sh"

set -e
set -o pipefail
set -u

# Create a local folder for the H2 database that will be used by HAPI.
H2="${DATA_DIR}/hapi/h2"
mkdir -p "${H2}"

# Can be disabled for more performant loads.
[[ "${1:-slow}" == "loading" ]] && SAFE="false" || SAFE="true"
[[ "${SAFE}" == "false" ]] && MASS_INGESTION="true" && echo "LOAD MODE ENABLED"

# This is where the local folder will appear inside the container.
MOUNT_TARGET="/persisted"

# docker container name.
NAME="fhir-to-omop-demo-hapi-server"


##
# Run docker with or without sudo, depending on your settings in demo/vars.
#
function _docker() {
  if [ "${SUDO_DOCKER}" == "true"  ]; then
    # Enable root-run docker to create and read the h2 database files.
    chmod 777 "${DATA_DIR}/hapi/h2"
    sudo docker "${@}"
  elif [ "${SUDO_DOCKER}" == "false" ]; then
    docker "${@}"
  else
    echo "Unknown setting for SUDO_DOCKER in ${DEMO_DIR}/vars!"
    exit 1
  fi
}


# Launch the server, saving resources to the local DB.
function start_server() {
  _docker run \
    --detach \
    --interactive \
    --tty \
    --name ${NAME} \
    --publish ${FHIR_PORT}:8080 \
    --mount "type=bind,src=${H2},target=${MOUNT_TARGET}" \
    --env "hapi.fhir.allow_cascading_deletes=${SAFE}" \
    --env "hapi.fhir.allow_multiple_delete=${SAFE}" \
    --env "hapi.fhir.bulk_export_enabled=${SAFE}" \
    --env "hapi.fhir.bulk_import_enabled=true" \
    --env "hapi.fhir.mass_ingestion_enabled=${MASS_INGESTION:-false}" \
    --env "hapi.fhir.delete_expunge_enabled=${SAFE}" \
    --env "hapi.fhir.enforce_referential_integrity_on_delete=${SAFE}" \
    --env "hapi.fhir.enforce_referential_integrity_on_write=${SAFE}" \
    --env "spring.datasource.hikari.maximum-pool-size=800" \
    --env "spring.datasource.max-active=8" \
    --env "spring.datasource.url=jdbc:h2:file:${MOUNT_TARGET}/h2" \
    --env "spring.jpa.properties.hibernate.search.enabled=${SAFE}" \
    hapiproject/hapi:latest
}


# Ignore invocations if the server is already running.
if _docker ps --format '{{.Names}}' | grep -q "^${NAME}$"; then
  cat <<EOM
The ${NAME} container is already running.

If you want to stop it, do this:
  docker container stop ${NAME}

Before you can restart it again, prune the stopped containers.
  docker container rm ${NAME}

EOM
else
  start_server
  echo -n "Waiting for server to start..."
  while true; do
    if ! curl ${FHIR_SERVER}/ &>/dev/null; then
      sleep 1
      echo -n .
    else
      echo -e "\r$( tput el )"
      break
    fi
  done
  cat <<EOM
 0/ - Visit your local FHIR server at: ${FHIR_SERVER}
<Y
/ >
EOM
fi
