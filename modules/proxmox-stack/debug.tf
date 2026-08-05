data "external" "proxmox_lxc" {
  program = ["bash", "-c", <<EOF
    eval "$(jq -r '@sh "PROXMOX_VE_API_TOKEN=\(.api_token)"')"
    RES=$(curl -s -k -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" https://pve540.jacobpevans.com:8006/api2/json/cluster/resources)
    TRAEFIK=$(echo "$RES" | jq -r '[.data[] | select(.type == "lxc" and (.name | contains("traefik")))]')
    jq -n --arg t "$TRAEFIK" '{"data": $t}'
EOF
  ]
  query = {
    api_token = data.vault_kv_secret_v2.proxmox.data["PROXMOX_VE_API_TOKEN"]
  }
}

output "proxmox_lxc_resources" {
  value = data.external.proxmox_lxc.result.data
}
