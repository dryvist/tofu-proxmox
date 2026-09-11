# Logging Pipeline Architecture

## Overview

This document describes the syslog and NetFlow logging pipelines from network devices through to Splunk Enterprise for security monitoring and analysis.

## Data Flow

```text
Syslog Sources              Load Balancer       Syslog Collectors      Processing         Destination
+----------------+          +----------+        +---------------+      +-----------+      +--------+
| UniFi (1514)   |          |          |        | cribl-edge-01 |      |           |      |        |
| Palo Alto (1515) |   --->   | HAProxy  |  --->  |               | ---> | Cribl     | ---> | Splunk |
| Cisco (1516)   |          | :1514-18 |        | cribl-edge-02 |      | Stream    |      | HEC    |
| Linux (1517)   |          +----------+        +---------------+      +-----------+      +--------+
| Windows (1518) |                                   |                       |
+----------------+                                   v                       v
                                              100GB queue disk         Persistent queue
                                              (survives outages)       for reliability

NetFlow Sources             Load Balancer       Collectors            Processing         Destination
+----------------+          +----------+        +---------------+      +-----------+      +---------+
| UniFi IPFIX    |          |          |        | cribl-edge-01 |      |           |      |         |
| (2055 UDP)     |   --->   | HAProxy  |  --->  |               | ---> | Cribl     | ---> | Splunk  |
|                |          | :2055 UDP|        | cribl-edge-02 |      | Stream    |      | netflow |
+----------------+          +----------+        +---------------+      +-----------+      +---------+
```

## Components

### 1. Log Sources

#### Syslog Sources

Network devices and hosts configured to send syslog to `<internal-domain>`.

| Source                | Port | Protocol | Index    |
| --------------------- | ---- | -------- | -------- |
| UniFi Network Device  | 1514 | UDP/TCP  | unifi    |
| Palo Alto             | 1515 | UDP/TCP  | firewall |
| Cisco ASA             | 1516 | UDP/TCP  | firewall |
| Linux/macOS hosts     | 1517 | UDP/TCP  | os       |
| Windows hosts         | 1518 | UDP/TCP  | os       |

#### NetFlow/IPFIX Sources

| Source         | Port | Protocol | Index   |
| -------------- | ---- | -------- | ------- |
| UniFi (IPFIX)  | 2055 | UDP      | netflow |

The `netflow` Splunk index receives NetFlow/IPFIX data from UniFi for traffic analysis.
See the ansible-splunk role's index registry (`roles/splunk_docker/defaults/main/`) for index retention settings.

#### UniFi Network Device Configuration

**Location**: Settings > CyberSecure > Traffic Logging

**Syslog Settings**:

- Activity Logging: SIEM Server
- Server Address: `<internal-domain>` (HAProxy)
- Port: 1514

**Log Categories Enabled (12)**:

- Gateway, Access Points, Switches
- Admin Activity, Clients, Critical
- Devices, Security Detections, Triggers
- Updates, VPN, Firewall Default Policy

**Additional Settings**:

- Flow Logging: All Traffic (includes Gateway DNS, UniFi Services)
- Data Retention: 365 days
- Collect Historical Client Data: Enabled
- Debug Logs: Disabled
- NetFlow (IPFIX): Enabled (UDP 2055 → HAProxy → Cribl Edge → `netflow` index)

#### UniFi Log Format (CEF)

UniFi exports logs using **Common Event Format (CEF)**, an industry-standard structure
compatible with most SIEM platforms.

**CEF Version Timeline**:

| Version  | CEF Support                          |
| -------- | ------------------------------------ |
| < 8.5.1  | No CEF support                       |
| 8.5.1    | IDS/IPS and firewall logs            |
| 9.3.43   | Full system log export               |
| 9.4.x    | Timestamp fixes (UNIFIutcTime field) |

**Architecture Note**: UniFi devices send syslog directly to the collector.
The UniFi Network Application only configures settings; it does not forward logs.

**Reference**: [UniFi System Logs & SIEM Integration](https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration)

### 2. HAProxy Load Balancer

- **Host**: haproxy (LXC container)
- **IP**: `<haproxy-ip>`
- **Function**: Round-robin load balancing to Cribl Edge nodes
- **Health checks**: Every 5 seconds
- **Stats**: Port 8404

### 3. Cribl Edge (Syslog Collectors)

Two-node cluster for high availability and horizontal scaling.

| Node          | IP                   |
| ------------- | -------------------- |
| cribl-edge-01 | `<cribl-edge-01-ip>` |
| cribl-edge-02 | `<cribl-edge-02-ip>` |

**Features**:

- Syslog parsing and normalization
- 100GB persistent queue disk for outage survival
- Forwards to Cribl Stream for central processing

### 4. Cribl Stream (Central Processor)

- **Host**: cribl-stream (LXC container)
- **IP**: `<cribl-stream-ip>`
- **Function**: Central log processing, routing, and enrichment
- **Output**: Splunk HEC over HTTPS

### 5. Splunk Enterprise

- **Host**: splunk (VM)
- **IP**: `<splunk-ip>`
- **Web UI**: Port 8000
- **HEC Endpoint**: Port 8088 (TLS)

## Network Ports

| Port | Service       | Protocol | Purpose              |
| ---- | ------------- | -------- | -------------------- |
| 1514 | HAProxy/Cribl | UDP/TCP  | UniFi syslog         |
| 1515 | HAProxy/Cribl | UDP/TCP  | Palo Alto syslog     |
| 1516 | HAProxy/Cribl | UDP/TCP  | Cisco ASA syslog     |
| 1517 | HAProxy/Cribl | UDP/TCP  | Linux syslog         |
| 1518 | HAProxy/Cribl | UDP/TCP  | Windows syslog       |
| 2055 | HAProxy/Cribl | UDP      | NetFlow/IPFIX        |
| 8000 | Splunk        | TCP      | Web interface        |
| 8088 | Splunk        | TCP/TLS  | HEC endpoint         |
| 8404 | HAProxy       | TCP      | Statistics page      |

## Reliability Features

1. **Load balancing**: HAProxy distributes load across Cribl Edge nodes
2. **Health checks**: 5-second intervals detect node failures
3. **Persistent queues**: 100GB disk survives Splunk outages
4. **TLS encryption**: HEC traffic encrypted end-to-end

## Deployment

```bash
# Deploy all components via Ansible
cd ~/git/ansible-proxmox-apps
ansible-playbook playbooks/site.yml # native OpenBao lookups resolve secrets
```

## Validation

```bash
# Test syslog delivery
logger -n <internal-domain> -P 1514 "Test message $(date +%s)"

# Check HAProxy stats
curl http://<haproxy-ip>:8404/stats

# Verify Splunk received event
splunk search 'index=unifi earliest=-5m'
```

## Related Documentation

- Splunk index definitions are in the ansible-splunk role (`roles/splunk_docker/defaults/main/`)
- [ansible-proxmox-apps README](https://github.com/JacobPEvans/ansible-proxmox-apps) - Ansible roles
