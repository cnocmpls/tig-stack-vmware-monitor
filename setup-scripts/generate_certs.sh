#!/bin/sh
# Script to generate internal TLS certificates (CA, InfluxDB, Grafana)
# if they don't exist. Uses temporary file for extensions.
# Expects OUTPUT_DIR environment variable (e.g., /output)

set -e

# --- Configuration ---
CERT_OUTPUT_BASE_DIR="${OUTPUT_DIR}/certs"
INTERNAL_CERT_DIR="${CERT_OUTPUT_BASE_DIR}/internal"
DAYS_VALID=730 # 2 years

# --- Certificate Generation Function ---
generate_internal_certs() {
    local ca_key="${INTERNAL_CERT_DIR}/ca.key"
    local ca_pem="${INTERNAL_CERT_DIR}/ca.pem"
    local influx_key="${INTERNAL_CERT_DIR}/influxdb.key"
    local influx_pem="${INTERNAL_CERT_DIR}/influxdb.pem"
    local grafana_key="${INTERNAL_CERT_DIR}/grafana.key"
    local grafana_pem="${INTERNAL_CERT_DIR}/grafana.pem"
    local INFLUXDB_GID=1000 # GID for influxdb user in container

    # Temp file for openssl extensions
    local ext_file="/tmp/openssl_ext.$$.conf" # Use $$ and RANDOM for better temp name uniqueness
    ext_file="/tmp/openssl_ext.$$_$RANDOM.conf"


    # Check if all certs/keys already exist
    if [ -f "$ca_pem" ] && [ -f "$ca_key" ] && \
       [ -f "$influx_pem" ] && [ -f "$influx_key" ] && \
       [ -f "$grafana_pem" ] && [ -f "$grafana_key" ] ; then
        echo "$(date): All Internal certificates already exist, skipping generation."
        # Ensure permissions are still set correctly on existing keys
         if [ -f "$influx_key" ]; then chmod 640 "$influx_key"; chown root:${INFLUXDB_GID} "$influx_key"; fi
         if [ -f "$grafana_key" ]; then chmod 644 "$grafana_key"; chown root:root "$grafana_key"; fi # Keep 644 diagnostic permission
         if [ -f "$ca_key" ]; then chmod 600 "$ca_key"; chown root:root "$ca_key"; fi
        return 0
    fi

    echo "$(date): Generating internal self-signed TLS certificates in $INTERNAL_CERT_DIR ..."
    mkdir -p "$INTERNAL_CERT_DIR"

    # --- Generation Steps ---
    # 1. Generate CA Key
    openssl genrsa -out "$ca_key" 4096
    # 2. Generate CA Certificate
    openssl req -x509 -new -nodes -key "$ca_key" -sha256 -days $DAYS_VALID -out "$ca_pem" \
      -subj "/C=XX/ST=Internal/L=Docker/O=Compose/CN=InternalComposeCA"

    # 3. Generate InfluxDB Key and CSR
    openssl genrsa -out "$influx_key" 2048
    openssl req -new -key "$influx_key" -out "${influx_key%.key}.csr" \
      -subj "/C=XX/ST=Internal/L=Docker/O=Compose/CN=influxdb"

    # 4. Create InfluxDB Extension File
    echo "subjectAltName=DNS:influxdb,DNS:localhost" > "$ext_file"
    # 5. Sign InfluxDB Cert with CA using extfile (Rely on default digest)
    openssl x509 -req -in "${influx_key%.key}.csr" -CA "$ca_pem" -CAkey "$ca_key" -CAcreateserial \
      -out "$influx_pem" -days $DAYS_VALID \
      -extfile "$ext_file" # Use the temp file

    # 6. Generate Grafana Key and CSR
    openssl genrsa -out "$grafana_key" 2048
    openssl req -new -key "$grafana_key" -out "${grafana_key%.key}.csr" \
      -subj "/C=XX/ST=Internal/L=Docker/O=Compose/CN=grafana"

    # 7. Create Grafana Extension File (overwrite temp file)
    echo "subjectAltName=DNS:grafana,DNS:localhost" > "$ext_file"
    # 8. Sign Grafana Cert with CA using extfile (Rely on default digest)
    openssl x509 -req -in "${grafana_key%.key}.csr" -CA "$ca_pem" -CAkey "$ca_key" -CAcreateserial \
      -out "$grafana_pem" -days $DAYS_VALID \
       -extfile "$ext_file" # Use the temp file
    # --- End Generation Steps ---

    # Cleanup CSRs, serial file, and extension file
    rm -f "${INTERNAL_CERT_DIR}"/*.csr "${INTERNAL_CERT_DIR}"/*.srl "$ext_file"

    # Set Permissions and Ownership (Keep 644 diagnostic for Grafana key)
    echo "Setting permissions and group ownership for certificates and keys..."
    chmod 644 ${INTERNAL_CERT_DIR}/*.pem
    # Use 640 and correct GID for InfluxDB key
    chmod 640 ${INTERNAL_CERT_DIR}/influxdb.key
    echo "Setting ownership for influxdb.key to root:${INFLUXDB_GID}"
    chown root:${INFLUXDB_GID} "${influx_key}" || echo "Warning: chown influxdb.key failed."
    # Use 644 for Grafana key (diagnostic setting) - ensure owned by root:root
    chmod 644 ${INTERNAL_CERT_DIR}/grafana.key
    echo "Setting ownership for grafana.key to root:root" # Ownership less critical with 644
    chown root:root "${grafana_key}" || echo "Warning: chown grafana.key failed."

    # Ensure CA key is owned by root:root and has strict permissions
    echo "Setting ownership for ca.key to root:root"
    chown root:root "${ca_key}" || echo "Warning: chown ca.key failed."
    chmod 600 "${ca_key}" # Keep CA key strict

    echo "$(date): Internal TLS certificate generation complete."
}

# --- Main Execution (Corrected) ---
echo "Starting Certificate Generation Script..."

# Ensure needed tools are installed first
echo "Checking/installing required packages: openssl..."
if ! command -v openssl &> /dev/null; then
    if ! apk add --no-cache openssl; then
         echo "Error: Failed to install openssl. Exiting." >&2
         exit 1
    fi
fi
echo "Packages checked/installed."

# Check required environment variable
if [ -z "$OUTPUT_DIR" ]; then
  echo "Error: OUTPUT_DIR environment variable not set." >&2
  exit 1
fi

# Call the main function
generate_internal_certs # Run the function that does the work

echo "$(date): Certificate setup script finished."
exit 0