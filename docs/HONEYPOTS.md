# Honeypots & Deception Fabric

Network-wide deception sensors that fire an **immediate phone alert** the moment
anything touches a fake service, plus a forensic copy into Splunk. This repo
(the **infrastructure layer**) provisions the guests, firewall, and inventory;
the honeypot software itself is deployed by the downstream **ansible-proxmox-apps**
roles (`opencanary`, `apprise`, `tpot`).

## Why

An attacker who lands inside any VLAN should trip something loud. Before this,
nothing in the lab watched lateral movement. The design gives **every VLAN a
tripwire**, a **deep sensor** for breadth + threat-intel, and a **dedicated
notification gateway** that pages you on Slack and your phone in seconds.

## Architecture

```text
            EVERY live VLAN gets its own OpenCanary tripwire (DHCP/DNS-first LXC)
  Default Mgmt DNS  Core Storage Data Obs/Sec AI Apps Media Home Untrusted
    │      │    │    │     │      │     │     │   │     │     │       │
    └──────┴────┴────┴─────┴──────┴─────┴─────┴───┴─────┴─────┴───┐   │  T-Pot deep-sensor VM
                                                                  │   │  (nonprod/untrusted)
  On every honeypot HIT, two parallel paths fire:                 │   │
                                                                  ▼   ▼
  (A) INSTANT   ── HTTP POST ─► honeypot-notify (apprise-api) ─► Slack + phone push
  (B) FORENSIC  ── syslog 519 ─► HAProxy ─► Cribl Edge ─► Cribl Stream ─► Splunk `honeypot` index
```

- **Path A (instant):** OpenCanary's webhook handler and a T-Pot
  ElastAlert/Logstash output POST one JSON to the apprise-api gateway, which
  fans it to Slack **and** a phone-push service (ntfy/Pushover). Sub-second,
  independent of Splunk.
- **Path B (forensic):** the same events ride the existing syslog pipeline
  (frontend **519** → backend **1519**, added to `syslog_port_map` in
  `constants.tf`) into the dedicated `honeypot` Splunk index for history,
  dashboards, and correlation. See [SPLUNK_INDEXES.md](./SPLUNK_INDEXES.md).

## Sensors (popular + maintained, June 2026)

| Sensor | Role | Where |
| --- | --- | --- |
| **OpenCanary** (thinkst) | Low-interaction multi-service tripwire: SSH, Telnet, FTP, HTTP(S), SMB, RDP, MSSQL, MySQL, Postgres, Redis, VNC, SNMP, SIP, TFTP, NTP, git, TCP-banner | **Every VLAN** (one LXC each) |
| **T-Pot** (telekom-security) — bundles **Cowrie** (SSH/Telnet), **Dionaea** (SMB/malware), **Conpot** (ICS/SCADA), **Heralding**, **Honeytrap**, **Mailoney**, **Adbhoney**, **CiscoASA**, **CitrixHoneypot**, **ElasticPot**, **RedisHoneypot**, **Dicompot/Medpot**, **IPPHoney/Miniprint**, **Log4pot**, **ddospot**, **Endlessh/Go-pot/Hellpot/Glutton** tarpits, **H0neytr4p**, **Honeyaml**, and the **Beelzebub** + **Galah** LLM pots | Deep, medium/high-interaction breadth + Elastic attack-map dashboard | **nonprod** decoy VM |
| **Apprise API** (caronc) | Notification gateway (Path A) — *not* a honeypot | `honeypot-notify` LXC |

Adding a standalone pot later (e.g. a dedicated Cowrie/Dionaea LXC on one VLAN)
uses the exact same Docker-in-LXC pattern as a tripwire — tag it `honeypot`.

## VMID & addressing convention

Honeypots follow the current 6-7-digit positional scheme
(`[Tier][Sub-tier][Crit][OS][Instance][Env]`, see
[INFRASTRUCTURE_NUMBERING.md](./INFRASTRUCTURE_NUMBERING.md)) and are
**DHCP/DNS-first** (`dhcp: true` and nothing else about the address — a plain
pool lease; reached by `{hostname}.{subdomain}`). VMs now support this too — `locals.tf` short-circuits
`cidrhost()` for any guest with `dhcp = true` or a static `ip_config`, so a VM
can carry a 7-digit positional VMID (the T-Pot VM does).

Honeypot digit choices: **sub-tier `9`** (deception), **crit `5`** for tripwires
(`2` for the alert-critical notify gateway), **OS `0`** (LXC; the T-Pot VM uses
the VM OS-digit `1`), **instance/env `0`**. A tripwire adopts the **tier of the
VLAN it defends** (tier = VLAN ÷ 10; special VLANs 1/5/53 use the 7-digit prefix
form), so the number tells you which segment it watches.

> The VMIDs in `deployment.json.example` are **illustrative** — reconcile every
> value against the live (gitignored) `deployment.json` for collisions before
> applying. Addresses need no reconciling: these guests take pool leases and
> declare no address at all.

## Per-VLAN tripwire map

Rule: **one OpenCanary LXC per entry in the live `network_cidrs` / `vlan_ids`
map**, so coverage tracks the real topology regardless of doc/code drift.

| Tier / VLAN | Proposed VMID | Emphasis (OpenCanary modules) |
| --- | --- | --- |
| Default (1) | 0195000 | SSH, HTTP, FTP, Telnet, SMB |
| Management (5) | 0595000 | SSH, HTTPS, SNMP, RDP, VNC |
| DNS (53) | 5395000 | NTP, SNMP, SSH, HTTP |
| 1 Core (10) | 195000 | SSH, HTTP, MySQL, Redis, SMB |
| 2 Storage (20) | 295000 | SSH, SMB, FTP, MSSQL |
| 3 Data/pipeline (30) | 395000 | MySQL, MSSQL, Redis, SSH, TCP-banner (fake syslog/HEC) |
| 4 Observability/Security (40) | 495000 | SSH, HTTP, MSSQL, Redis |
| 5 AI/ML (50) | 595000 | HTTP, SSH, Redis, TCP-banner (fake model API) |
| 6 Apps (60) | 695000 | HTTP, HTTPS, SSH, FTP, MySQL |
| 7 Media (70) | 795000 | HTTP, SMB, FTP, SSH |
| 8 Home/IoT (80) | 895000 | HTTP, SSH, Telnet, SIP |
| 9 Untrusted (90) | 995000 | SSH, HTTP, SMB, Telnet |

If the live topology still carries the extra `variables-network.tf` keys
(`bmc`, `pipeline`, `media_svc`, `homeauto`, `nonprod`), add a tripwire for each
of those too — one per live VLAN.

## Node placement

Node roles (`deployment.json` → `nodes`): **proxmox-1** = fast/CPU
(amd-desktop), **proxmox-2** = default workhorse (R410), **proxmox-3** =
normally shut down (R710, `commissioned: false`) for backups/warm.

- **proxmox-1 (CPU/high-speed):** primary **T-Pot VM** (Elastic + many
  containers) **plus 2 tripwires** (highest-value VLANs, e.g. Core + Obs/Sec).
- **proxmox-2:** the `honeypot-notify` gateway + all remaining tripwires
  (lightweight, always-on, live sensors).
- **proxmox-3 (normally off → backups/warm):** **warm-standby T-Pot** and
  **warm-standby notify** (`start_on_boot: false`). No primary live sensors — a
  powered-off node can't alert; these are DR copies brought up during failover
  or backup windows.

## Firewall posture

Tag-driven, wired through `modules/firewall` (see `honeypot_rules.tf`,
`vm_rules.tf`, `security_groups.tf`):

- **Tripwires** (`honeypot` tag): input DROP + the `honeypot-svc` group
  (ACCEPT+log the decoy ports, logged at `info`). Egress restricted to internal
  only (`outbound-internal`) — a poked sensor reaches the notify gateway + syslog
  519 but **never the internet**.
- **Notify gateway** (`honeypot` + `notify` tags): input DROP + `honeypot-notify-svc`
  (apprise port 8000); **open egress** so it can reach Slack/Pushover/ntfy.sh.
  Kept out of `notification_container_ids` (Mailpit/ntfy) so it is never
  double-claimed by two `firewall_options` resources.
- **T-Pot VM** (`tpot` tag): input **ACCEPT** (a deliberate wide-net sensor that
  manages its own dockerized firewall; logged), egress DROP + internal + HTTPS
  (image/update + threat-intel pulls) so captured malware can't beacon out.

## Alerting setup (secrets)

The apprise gateway loads its targets from OpenBao at runtime — **never
committed**:

- `SLACK_WEBHOOK_URL` (or `APPRISE_SLACK_*`) — Slack incoming webhook.
- `NTFY_*` / `PUSHOVER_*` — phone-push token.

Honeypots POST to `http://honeypot-notify.<domain>:8000/notify/<config>` (or the
Traefik route `https://honeypot-notify.<domain>`). The apprise UI is in the
ingress table (`ingress.tf`).

## Adding / removing a sensor

1. **Tripwire:** add a `honeypot-tw-<vlan>` container in `deployment.json`
   (clone the `honeypot-tw-nonprod` example) with `dhcp: true`, the VLAN's
   positional VMID, tags `["terraform","container","docker","honeypot"]`,
   `pool_id: "security"`. No address to pick: the firewall + inventory follow
   from the tags, and the guest's name resolves off its lease.
2. **Notify gateway / T-Pot:** already in the example — adjust `node_name` and
   resources to taste.
3. Remove by deleting the entry; the tag-driven maps shrink automatically.

The `opencanary` Ansible role renders each tripwire's `opencanary.conf` from the
inventory (modules per the map above) and wires the webhook handler (Path A) +
syslog handler to 519 (Path B).

## T-Pot dashboard

T-Pot serves its own authenticated HTTPS dashboard (attack map, Kibana). Reach
it directly at `https://tpot.<domain>` (DNS-first FQDN). The `tpot` Ansible role
runs the installer, selects the edition compose, and adds the ElastAlert →
apprise rule so new attacks also page you instantly.

## Operational note

This is a **deception system**: inbound connections on the decoy ports are
expected and are the signal. Tripwire egress is internal-only and T-Pot egress
is restricted, but treat the T-Pot VM as hostile-by-design — it lives on the
untrusted segment and never holds anything real.

## Verification

1. `tofu fmt -check`, `tofu validate`, `tofu test` (root + `modules/firewall`).
2. `tofu plan` — expect the tripwire LXCs + notify CTs + T-Pot VMs + the
   `honeypot-svc`/`honeypot-notify-svc` groups + `security` pool, with
   `node_name` per the placement table and no changes to existing resources.
3. **End-to-end:** from a host on any VLAN, `nmap -sT <tripwire-fqdn>` or
   `ssh fakeuser@<tripwire-fqdn>`. Within seconds expect (a) a Slack message +
   phone push, and (b) the event in Splunk's `honeypot` index. Repeat against the
   T-Pot VM (e.g. Cowrie SSH) for the deep-sensor path.

## Related

- [INFRASTRUCTURE_NUMBERING.md](./INFRASTRUCTURE_NUMBERING.md) — VMID scheme
- [SPLUNK_INDEXES.md](./SPLUNK_INDEXES.md) — the `honeypot` index
- [LOGGING_PIPELINE.md](./LOGGING_PIPELINE.md) — syslog → Cribl → Splunk
- Upstream:
  [T-Pot](https://github.com/telekom-security/tpotce) ·
  [OpenCanary](https://github.com/thinkst/opencanary) ·
  [Apprise](https://github.com/caronc/apprise) ·
  [awesome-honeypots](https://github.com/paralax/awesome-honeypots)
