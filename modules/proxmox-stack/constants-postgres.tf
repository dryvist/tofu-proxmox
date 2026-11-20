# PostgreSQL exporter ports merged into pipeline_constants.service_ports.
# Split from constants.tf to preserve the shared 12 KB file-size limit.

locals {
  postgres_ports = {
    pgbackrest_exporter = 9854
  }
}
