# TIG Stack for VMware Monitoring with Docker Compose

This repository provides a Docker Compose setup for running a TIG stack (Telegraf, InfluxDB v2, Grafana) specifically configured to monitor VMware vSphere environments.

It features automated setup for InfluxDB (user, org, bucket, token), dynamic generation of Telegraf output and Grafana datasource configurations, and dynamic processing of downloaded Grafana dashboards to link them to the provisioned datasource.

**Features:**

* **InfluxDB v2:** Latest version, automated initial setup.
* **Telegraf:** Latest version, pre-configured `vsphere` input plugin (realtime & historical).
* **Grafana:** Latest version, automated datasource provisioning, automated dashboard loading.
* **Dynamic Configuration:** Uses a setup container to generate configurations and process dashboards, minimizing manual steps after initial setup.
* **Environment Variable Driven:** Uses a `.env` file for sensitive and site-specific configuration.

**Prerequisites:**

* Docker Engine ([Install Docker](https://docs.docker.com/engine/install/))
* Docker Compose ([Install Docker Compose](https://docs.docker.com/compose/install/))
* Git (for cloning the repository)
* Access to a VMware vCenter Server with a dedicated monitoring user account.
* `dos2unix` utility (optional but recommended for `setup.sh`): `sudo apt install dos2unix` or `sudo yum install dos2unix`.
* `jq` utility (optional, for manual JSON inspection): `sudo apt install jq` or `sudo yum install jq`.

**Setup Instructions:**

1.  **Clone Repository:**
    ```bash
    git clone https://github.com/cnocmpls/tig-stack-vmware-monitor tig-stack-vmware-monitor
    cd tig-stack-vmware-monitor
    ```

2.  **Prepare Environment File:**
    * Copy the example environment file:
        ```bash
        cp .env.example .env
        ```
    * **Generate a Strong InfluxDB Token:** Use one of the methods below (or your preferred method) and paste the result into the `.env` file for `INFLUXDB_TOKEN`.
        ```bash
        # Option 1: openssl
        openssl rand -base64 48

        # Option 2: /dev/urandom
        head -c 48 /dev/urandom | base64

        # Option 3: Python 3
        python3 -c 'import secrets; print(secrets.token_urlsafe(48))'
        ```
    * **Edit `.env`:** Open the `.env` file and replace **all** placeholder values (`ReplaceWith...`, `your-vcenter...`, etc.) with your actual InfluxDB credentials, vCenter details, Grafana admin password, and the generated InfluxDB token.

3.  **Download Grafana Dashboards:**
    * Download the JSON models for the desired VMware dashboards from [Grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards/). Some awesome dashboards by jorgedelacruz are included here with IDs: `8159`, `8168`, `8165`, `8162`.
    * Place the downloaded `.json` files directly inside the `grafana/dashboards/` directory.

4.  **Make Setup Script Executable:**
    * Ensure correct line endings (especially if you edited the script on Windows):
        ```bash
        dos2unix ./influxdb-setup/setup.sh
        ```
    * Set execute permissions:
        ```bash
        chmod +x ./influxdb-setup/setup.sh
        ```

5.  **Start the Stack:**
    * Run Docker Compose in detached mode:
        ```bash
        docker compose up -d
        ```
    * This will:
        * Pull the latest images.
        * Start InfluxDB and perform initial setup using `.env` variables (including the specified token).
        * Start the `influxdb-setup` container, which waits for InfluxDB, generates Telegraf/Grafana configs, processes the dashboard JSONs (replacing datasource variable), and writes them to `./config-output/`.
        * Start Telegraf, loading its base config and the generated output config.
        * Start Grafana, provisioning the datasource and loading the processed dashboards.

6.  **Access Grafana:**
    * Wait a minute or two for services to stabilize and data collection to begin.
    * Open your browser and go to `http://<your-docker-host-ip>:3000`.
    * Log in with:
        * Username: `admin`
        * Password: The `GRAFANA_ADMIN_PASSWORD` you set in your `.env` file.
    * Navigate to Dashboards -> Browse. You should find a "VMware" folder containing the imported dashboards, correctly linked to the `InfluxDB-VMware` datasource.

**Stopping the Stack:**

```bash
docker compose down
```
**Cleaning Up (Removes Containers, Networks, Data Volumes):**

```bash
# Stop and remove containers/networks/volumes
docker compose down -v
```

## Troubleshooting

* **Check Logs**: Use `docker compose logs -f <service_name>` (e.g., `influxdb`, `influxdb-setup`, `telegraf`, `grafana`) to view logs for specific containers.
* **.env Values**: Double-check all values in your `.env` file, especially passwords, tokens, and vCenter details.
* **File Permissions**: Ensure `setup.sh` is executable (`chmod +x setup.sh`) and Docker has permissions to read project files and write to `./config-output/`. Check SELinux/AppArmor logs (`/var/log/audit/audit.log` or `syslog`) on the host if mounts fail unexpectedly.
* **Dashboard JSON Processing**: If dashboards don't work, check the logs of `influxdb-setup` for errors during the `process_dashboards` phase. Examine the generated JSON files in `./config-output/grafana-dashboards/` to see if the UID replacement occurred correctly. Ensure the fixed UID matches between `setup.sh` and the check in the processing step.

## Structure Explained

* **`docker-compose.yml`**: Defines the services (InfluxDB, Telegraf, Grafana, Setup Helper).
* **`.env.example` / `.env`**: Stores configuration secrets and parameters. `.env` is ignored by git. Copy `.env.example` to `.env` and fill in your details.
* **`influxdb-setup/`**: Contains the helper script (`setup.sh`) that automates configuration generation and dashboard processing.
* **`config-output/`**: A directory (ignored by git) where the `setup.sh` script writes the generated configuration files (Telegraf output, Grafana datasource) and the processed dashboard JSONs. These generated files are then mounted into the actual Telegraf and Grafana containers.
* **`telegraf/`**: Contains the base Telegraf configuration (`telegraf.conf`) defining inputs and agent settings. The output configuration is generated dynamically by the setup script.
* **`grafana/dashboards/`**: You place the *original* downloaded Grafana dashboard JSON files here. This directory is mounted read-only into the `influxdb-setup` container for processing. Contains `.gitkeep` so the empty directory can be added to git.
* **`provisioning/dashboards/`**: Contains Grafana's dashboard provider configuration (`vmware-dashboards.yml`), telling Grafana where to find the *processed* dashboard files located in `./config-output/grafana-dashboards/`.
