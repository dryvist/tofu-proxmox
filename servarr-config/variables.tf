# Runtime endpoints and credentials are read ephemerally from OpenBao by the
# Terrakube job. Only the non-secret path contract is configured here.

variable "openbao_kv_mount" {
  type        = string
  description = "OpenBao KV v2 mount containing the media application contract"
  default     = "secret"
}

variable "openbao_sonarr_path" {
  type        = string
  description = "OpenBao path holding the Sonarr URL and API key"
  default     = "sonarr/main/rw"
}

variable "openbao_radarr_path" {
  type        = string
  description = "OpenBao path holding the Radarr URL and API key"
  default     = "radarr/main/rw"
}

variable "tv_root_folder" {
  type        = string
  default     = "/data/media/tv"
  description = "Sonarr root folder (unified /data hardlink layout)."
}

variable "movie_root_folder" {
  type        = string
  default     = "/data/media/movies"
  description = "Radarr root folder (unified /data hardlink layout)."
}
