
# datainc-iac

Ansible playbooks to provision a small Docker Swarm and deploy a lakehouse-ish stack (Traefik + Spark + Nessie + Garage + Jupyter) on top.

**What this builds**

```
Internet
  |
  | 80/443
  v
[Traefik (Swarm, manager)]  <-- Let's Encrypt + basic auth
  |\
  | \-- https://traefik.<domain>     (Traefik dashboard)
  | \-- https://portainer.<domain>   (Portainer)
  | \-- https://spark.<domain>       (Spark master UI)
  | \-- https://thrift.<domain>      (Spark Thrift Server UI)
  | \-- https://notebook.<domain>    (JupyterLab)
  | \-- https://nessie.<domain>      (Nessie API)
  | \-- https://s3.<domain>          (Garage S3 endpoint)
  |
  v
[Docker Swarm overlay network: traefik-public]
  |
  +-- Spark standalone cluster
  |     - spark_master (manager)
  |     - spark_worker (global on workers)
  |     - spark_thrift (manager, publishes 10000)
  |
  +-- Nessie (catalog)
  +-- Garage (S3-compatible object storage)
  +-- Notebook (JupyterLab + PySpark client)
```

Notes:
- Container-to-container connectivity uses the shared overlay network `traefik-public`.
- This repo adds explicit service DNS aliases `nessie` and `garage` on that network.

Where you can deploy this

- Any Linux VMs that Ansible can SSH into (typical: cloud VPS instances).
- The `datainc/playbooks/docker-dependencies.yml` playbook is written for Ubuntu "noble" (24.04) Docker apt repo.

Node count / sizing

- Minimum: 1 manager node (Traefik + Spark master + Thrift + Notebook) and 1 worker node.
- Typical small cluster: 1 manager + 2 workers (matches `datainc/inventory.yml`).
- You can add more workers by extending the `worker` group in `datainc/inventory.yml`.

Ports / DNS you must provide

- Public inbound to the manager (or wherever Traefik runs): `80/tcp`, `443/tcp`.
- If you submit dbt/JDBC to Spark Thrift from outside the cluster: `10000/tcp` (published by `spark_thrift`).
- Create DNS A records (or CNAMEs) pointing to the Traefik public IP:
  - `traefik_domain`
  - `portainer_domain`
  - `garage_domain`
  - `nessie_domain`
  - `spark_domain`
  - `spark_thrift_ui_domain`
  - `notebook_domain`

Inputs (extra vars)

Edit `datainc/extra-vars.yml`:

- `main_node`: Swarm node name to pin stateful services to (labels).

Traefik:
- `traefik_username`: basic auth username
- `traefik_password`: plaintext password (the playbook hashes it with `openssl passwd -apr1`)
- `traefik_email`: Let's Encrypt email
- `traefik_domain`: domain for the Traefik dashboard

Portainer:
- `portainer_domain`

Garage (S3):
- `garage_domain`
- `garage_rpc_secret`: random 32-byte hex recommended (used by Garage RPC)
- `garage_key_id`, `garage_secret_key`: S3 credentials for Spark (must exist in Garage)

Nessie:
- `nessie_domain`
- `nessie_node`: node hostname to label for Nessie placement

Spark:
- `spark_domain`: Spark master UI domain
- `spark_thrift_ui_domain`: Thrift Server UI domain (Traefik-routed)

Notebook:
- `notebook_domain`

How to run

From your workstation:

1) Configure inventory: `datainc/inventory.yml`
2) Configure vars: `datainc/extra-vars.yml`
3) Run playbooks (order matters):

```bash
ansible-playbook -i datainc/inventory.yml datainc/playbooks/docker-dependencies.yml
ansible-playbook -i datainc/inventory.yml datainc/playbooks/swarm-master.yml
ansible-playbook -i datainc/inventory.yml datainc/playbooks/swarm-worker.yml

ansible-playbook -i datainc/inventory.yml datainc/playbooks/traefik/traefik.yml -e @datainc/extra-vars.yml
ansible-playbook -i datainc/inventory.yml datainc/playbooks/portainer/portainer.yml -e @datainc/extra-vars.yml
ansible-playbook -i datainc/inventory.yml datainc/playbooks/garage/garage.yml -e @datainc/extra-vars.yml
ansible-playbook -i datainc/inventory.yml datainc/playbooks/nessie/nessie.yml -e @datainc/extra-vars.yml
ansible-playbook -i datainc/inventory.yml datainc/playbooks/spark/spark.yml -e @datainc/extra-vars.yml
ansible-playbook -i datainc/inventory.yml datainc/playbooks/notebook/notebook.yml -e @datainc/extra-vars.yml

Or run all with (in the datainc directory):
ansible-playbook -i inventory.yml main.yml -e @extra-vars.yml
```

Service URLs

- Traefik dashboard: `https://<traefik_domain>`
- Portainer: `https://<portainer_domain>`
- Spark UI: `https://<spark_domain>`
- Spark Thrift UI: `https://<spark_thrift_ui_domain>`
- JupyterLab: `https://<notebook_domain>`
- Nessie API: `https://<nessie_domain>`
- Garage S3 endpoint: `https://<garage_domain>`

dbt (Spark Thrift) + Nessie catalog

This repo deploys a Spark Thrift Server (`spark_thrift`) on port `10000`. You can use it with dbt's Spark adapter (`method: thrift`) and write Spark SQL against the Nessie-backed Iceberg catalog.

Notes:
- dbt connects to the Thrift Server over raw TCP (`host` + `port 10000`).
- Make sure `10000/tcp` is reachable from your dbt runner to the Swarm node publishing that port (typically the manager).
- The Spark stack configures a Nessie catalog named `nessie` via `spark-defaults.conf`.

Sanitized dbt profile example

```yaml
prod:
  type: spark
  method: thrift
  schema: raw
  host: spark-thrift.example.com
  port: 10000
  poll_interval: 5
  query_retries: 3
  query_timeout: 6000
  threads: 1
```

Querying with the Nessie catalog

In Spark SQL (and therefore from dbt models), you can reference Nessie/Iceberg tables using the `nessie` catalog name.

If you want to avoid prefixing every table with `nessie.`, set `spark.sql.defaultCatalog=nessie` for the Thrift Server (or in `spark-defaults.conf`).

Examples:

```sql
-- Create a namespace (database)
CREATE NAMESPACE IF NOT EXISTS nessie.raw;

-- Create an Iceberg table in Nessie
CREATE TABLE IF NOT EXISTS nessie.raw.users (
  user_id STRING,
  created_at TIMESTAMP
) USING iceberg;

-- Query it like a normal table
SELECT count(*) AS n FROM nessie.raw.users;
```

Branch/tag workflow (optional)

Nessie lets you work on branches similarly to git. If you want dbt to target a non-default ref, set `spark.sql.catalog.nessie.ref` in Spark (or in `spark-defaults.conf`):

```sql
-- Example: switch to a branch (requires Nessie ref support in your Spark/Nessie setup)
-- ALTER TABLE/CREATE TABLE statements will then write to that ref.
-- (Exact ref switching syntax can vary by engine/version.)
```
