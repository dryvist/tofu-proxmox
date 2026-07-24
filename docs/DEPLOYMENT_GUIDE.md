# Infrastructure Deployment Guide

**Status**: Production Ready
**Branch**: `main`

## Overview

Deploy Proxmox-based infrastructure with Terraform-managed VMs and manually-managed LXC containers.
Splunk indexers use VMs for I/O performance; all other services use lightweight LXC containers.

## Architecture

### Terraform-Managed Resources

**Splunk Indexer VMs (100-101)**:

- Full lifecycle managed by Terraform
- Enhanced I/O performance for data indexing

**Splunk Management Container (205)**:

- Managed by Terraform
- Lighter weight than VM for management workloads

See [INFRASTRUCTURE_NUMBERING.md](./INFRASTRUCTURE_NUMBERING.md) for complete architecture reference.

### Manually-Managed Containers

These are created via Proxmox UI and **not** managed by Terraform:

- ansible (200)
- cribl-edge-1/2 (210-211)
- claude1 (220)
- Reserved: 221-225

## Prerequisites

1. **Proxmox VE** with:
   - Cloud-init template at VM ID 9000 (Debian 13)
   - Datastores: `local-zfs`, `local`
   - Network bridge: `vmbr0`

2. **Terraform Configuration**:
   - `terraform.tfvars` at repo root with your infrastructure values
   - Symlinked into each worktree: `ln -s ../../terraform.tfvars .`

3. **OpenBao** configured (see your local environment documentation for project and config details):

   ```bash
   OpenBao setup --project <YOUR_PROJECT> --config <YOUR_CONFIG>
   ```

4. **SSH Keys**:
   - Proxmox host: `~/.ssh/id_rsa_pve`
   - VMs: `~/.ssh/id_ed25519`

## Deployment Steps

### 1. Validate Configuration

```bash
# Enter Nix shell (direnv handles this automatically if .envrc is allowed)
# Or enter manually:
nix develop "github:JacobPEvans/nix-devenv?dir=shells/terraform"

# Validate Terraform syntax
tofu validate

# Check what will be created
tofu plan # run in Terrakube
```

### 2. Deploy Terraform-Managed Resources

```bash
# Deploy VMs and managed container
tofu apply # run in Terrakube

# Verify deployment
tofu state list
```

This creates:

- splunk-idx1 VM (100)
- splunk-idx2 VM (101)
- splunk-mgmt LXC (205)
- Resource pool: logging

### 3. Create Manual LXC Containers

Via Proxmox UI, create the following containers:

**ansible (200)**:

- Template: Debian 13
- Cores: 2, RAM: 2GB, Storage: 64GB
- IP: Your network address (see `terraform.tfvars`)

**cribl-edge-1 (210) & cribl-edge-2 (211)**:

- Template: Debian 13
- Cores: 2, RAM: 2GB, Storage: 32GB each
- IPs: Your network addresses

**claude1 (220)**:

- Template: Debian 13
- Cores: 2, RAM: 2GB, Storage: 64GB
- IP: Your network address

### 4. Configure Services

**Splunk Cluster**:

- Topology and VMIDs: see the Splunk section of
  [INFRASTRUCTURE_NUMBERING.md](./INFRASTRUCTURE_NUMBERING.md); the converge
  design (roles, RF/SF, cluster-manager URI) is owned by `ansible-splunk`
  (`docs/SPLUNK_CLUSTER_DESIGN.md`).
- Configure cluster manager URI, replication, search head

**Ansible**:

- Install Ansible in LXC 200
- Configure inventory pointing to all hosts
- See cloud-init examples in `cloud-init/` directory

## Verification

```bash
# Check Terraform state
tofu state list

# Verify VMs via Proxmox API
ssh root@<proxmox-host> 'qm list'

# Verify containers
ssh root@<proxmox-host> 'pct list'

# Test SSH access to VMs
ssh -i ~/.ssh/id_ed25519 debian@<vm-ip>

# Check container access
ssh root@<container-ip>
```

## Updates and Changes

**To modify Terraform-managed resources**:

1. Update `terraform.tfvars` with desired changes
2. Run `tofu plan` to preview
3. Run `tofu apply` to execute
4. Commit `.example` file changes to git (never commit `terraform.tfvars`)

**To modify manual containers**:

- Use Proxmox UI or `pct` CLI commands
- Not managed by Terraform state

## Troubleshooting

See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for:

- State lock issues
- Network connectivity problems
- VM deployment failures
- Performance optimization

## Resource Summary

**Terraform-Managed**:

- 2 VMs: 12 cores, 12GB RAM, 400GB storage
- 1 Container: 3 cores, 3GB RAM, 100GB storage

**Manual Containers**:

- 4 containers: 8 cores, 8GB RAM, 192GB storage

**Total**: 7 resources, 23 cores, 23GB RAM, 692GB storage

See [INFRASTRUCTURE_NUMBERING.md](./INFRASTRUCTURE_NUMBERING.md) for complete details.
