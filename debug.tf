data "http" "proxmox_lxc" {
  url = "https://pve540.jacobpevans.com:8006/api2/json/cluster/resources"
  request_headers = {
    Authorization = "PVEAPIToken=${data.vault_kv_secret_v2.proxmox.data["PROXMOX_VE_API_TOKEN"]}"
  }
  insecure = true
}

output "proxmox_lxc_resources" {
  value = [
    for item in jsondecode(data.http.proxmox_lxc.response_body).data : item
    if item.type == "lxc" && length(regexall("traefik", try(item.name, ""))) > 0
  ]
}
