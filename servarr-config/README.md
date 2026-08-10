# Servarr Configuration Workspace

The `tofu-proxmox-servarr-config` Terrakube workspace manages Sonarr and Radarr
root folders with the devopsarr providers. Terrakube obtains OpenBao identity
natively; ephemeral KV reads supply the application endpoints and API keys.

qBittorrent download-client wiring is intentionally owned by the existing
`ansible-servarr` `servarr_wiring` role. The prior state entries are
forgotten with `destroy = false`, so migration does not remove live clients and
provider limitations cannot persist the qBittorrent password in state.

Local validation is backend-free:

```bash
tofu init -backend=false
tofu validate
```

Credentialed plan, import, and apply operations run only in Terrakube.
