# Declarative Sonarr/Radarr structural config via the devopsarr providers — the
# CI-reachable replacement for the hand-rolled servarr wiring. `tofu plan`
# doubles as drift detection. Prowlarr lives behind the download-vpn killswitch
# and is handled separately (see README); TRaSH custom-formats/quality come from
# Configarr.

provider "vault" {
  skip_child_token = true
}

# Terrakube supplies a short-lived OpenBao token from its workload identity.
# The media credentials exist only for this run and never enter plan or state.
ephemeral "vault_kv_secret_v2" "media" {
  mount = var.openbao_kv_mount
  name  = var.openbao_media_path
}

provider "sonarr" {
  url     = ephemeral.vault_kv_secret_v2.media.data["SONARR_URL"]
  api_key = ephemeral.vault_kv_secret_v2.media.data["SONARR_API_KEY"]
}

provider "radarr" {
  url     = ephemeral.vault_kv_secret_v2.media.data["RADARR_URL"]
  api_key = ephemeral.vault_kv_secret_v2.media.data["RADARR_API_KEY"]
}

# --- Sonarr ------------------------------------------------------------------
resource "sonarr_root_folder" "tv" {
  path = var.tv_root_folder
}

removed {
  from = sonarr_download_client_qbittorrent.qbittorrent

  lifecycle {
    destroy = false
  }
}

# --- Radarr ------------------------------------------------------------------
resource "radarr_root_folder" "movies" {
  path = var.movie_root_folder
}

removed {
  from = radarr_download_client_qbittorrent.qbittorrent

  lifecycle {
    destroy = false
  }
}

# Secret-bearing qBittorrent wiring is owned by ansible-servarr's
# servarr_wiring role. The provider does not expose ephemeral/write-only fields
# for this resource, so keeping it here would copy OpenBao values into state.
