# Managing Real Infrastructure Values

**Critical Security Pattern**: This repository uses placeholder values in all committed files.
Real infrastructure details are maintained locally and never committed to git.

## The Pattern

### Committed Files (Public/Safe)

- `terraform.tfvars.example` - Placeholder RFC 1918 addresses (192.168.1.x)
- All documentation uses example IPs and names
- No real infrastructure topology exposed

### Local Files (Private/Gitignored)

- `terraform.tfvars` - Your real IP addresses, hostnames, and configuration
- Protected by `.gitignore` entries: `*.tfvars` and `terraform.tfvars`

## Initial Setup Workflow

### 1. Copy the Example File

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Replace Placeholder Values

Edit `terraform.tfvars` and replace ALL placeholder values:

```hcl
# Example file shows:
proxmox_api_endpoint = "https://proxmox.example.com:8006/api2/json"
vms = {
  "splunk-idx1" = {
    vm_id = 100
    ipv4_address = "192.168.1.100/24"
    # ...
  }
}

# Your real file should have:
proxmox_api_endpoint = "https://<proxmox-host>.<your-domain>.local:8006/api2/json"
vms = {
  "splunk-idx1" = {
    vm_id = 100
    ipv4_address = "YOUR_REAL_IP/24"  # Your actual network address
    # ...
  }
}
```

### 3. Verify Protection

```bash
# Verify terraform.tfvars is gitignored
git status | grep terraform.tfvars
# Should show NOTHING (file is properly ignored)

# Double-check .gitignore
grep tfvars .gitignore
# Should show: *.tfvars and terraform.tfvars
```

## What Values to Replace

### Network Configuration

- **IP Addresses**: Replace all 192.168.1.x placeholder addresses with your actual network addresses
- **Subnet Mask**: Use /24 for standard LAN (matches your network's actual CIDR)
- **Gateway**: Replace example gateway with your actual gateway
- **DNS**: Update DNS servers if specified

### Proxmox Configuration

- **API Endpoint**: Your actual Proxmox hostname or IP address
- **Node Name**: Your actual Proxmox node name (check Proxmox UI)
- **Domain**: Your actual internal domain name

### VM/Container IDs

- **IDs**: Use the v2.0 numbering scheme as-is, or adjust if you have existing VMs with ID conflicts
- **Names**: Modify if you prefer different naming conventions

## Environment-Specific Configurations

### Method 1: Multiple tfvars Files (Legacy)

For multiple environments (dev/staging/prod), use different tfvars files:

```bash
# Development
terraform.tfvars.dev  # Gitignored via *.tfvars

# Production
terraform.tfvars.prod # Gitignored via *.tfvars

# Use with:
tofu plan -var-file=terraform.tfvars.dev
```

Note there is no `tofu apply` line here: applies are Terrakube jobs, refused at
the API for any CLI caller (`allowRemoteApply = false`). A var-file selects what
a *plan* evaluates; the job that applies it carries the workspace's own
variables.

### Method 2: Worktree-Based Configuration (Recommended)

**As of v2.1**, OpenTofu automatically loads environment-specific variables from `.env/terraform.tfvars`:

```bash
# Repository structure with worktrees
~/git/tofu-proxmox/
├── .git/                    # Shared git directory (bare repo)
├── .env/terraform.tfvars    # Shared environment config (gitignored)
├── main/                    # Main branch worktree
├── feature/feature-name/    # Feature branch worktree
└── bugfix/bug-fix/          # Fix branch worktree

# Each worktree references the shared .env/terraform.tfvars via symlink
~/git/tofu-proxmox/feature/feature-name/.env -> ../../.env
```

**Configuration precedence** (highest to lowest):

1. CLI `-var` flags
2. `-var-file` explicit files
3. `.env/terraform.tfvars` (environment-specific, loaded automatically)
4. `terraform.tfvars.example` (placeholder template, NOT loaded)

**Benefits**:

- Single source of truth for environment values (`.env/terraform.tfvars`)
- All worktrees share the same environment configuration
- No need to specify `-var-file` on every command
- Supports rapid development across multiple feature branches

**Setup**:

```bash
# Create .env directory at repo root (if not exists)
mkdir -p ~/git/tofu-proxmox/.env

# Copy your real values to .env/terraform.tfvars
cp terraform.tfvars.example .env/terraform.tfvars
# Edit .env/terraform.tfvars with your real values

# Create symlink in each worktree
cd ~/git/tofu-proxmox/feat/your-branch
ln -s ../../.env .env

# OpenTofu now automatically loads .env/terraform.tfvars
tofu plan  # No -var-file needed!
```

## OpenBao Integration (Optional)

For secret values (API tokens, passwords), use OpenBao:

```bash
# Secrets via OpenBao (never in tfvars)
tofu plan # run in Terrakube

# TF_VAR_* environment variables automatically injected:
# - TF_VAR_proxmox_api_token
# - TF_VAR_proxmox_ssh_private_key
# - etc.
```

## Safety Checks

### Before Every Commit

```bash
# Check for accidentally staged tfvars files
git status | grep tfvars

# Verify only example files are staged
git diff --staged --name-only | grep tfvars
# Should ONLY show: terraform.tfvars.example (if any)

# Manual review of staged changes
git diff --staged | less
# Visually inspect for any real IPs, hostnames, or infrastructure details
```

### Pre-commit Hook (Recommended)

**Automated Installation**:

```bash
# Install the safety hook automatically
./scripts/install-safety-hooks.sh
```

This will create/update `.git/hooks/pre-commit` to prevent committing real .tfvars files.

**Manual Installation**:

If you prefer to add it manually, add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Prevent committing real tfvars files
if git diff --cached --name-only | grep -E "\.tfvars$" | grep -v "\.example$"; then
  echo "ERROR: Attempting to commit .tfvars file!"
  echo "Only .tfvars.example files should be committed."
  exit 1
fi
```

## Documentation Strategy

### Example Values in Docs

All documentation uses **example values only**:

- IPs: 192.168.1.x (RFC 1918 private range)
- Domains: example.com, proxmox-1.example.com
- Hostnames: Generic names (proxmox-1, proxmox-2)

### Real Values Documentation

Document your real infrastructure in:

- **Private notes** (not in git)
- **Password manager** (Bitwarden, 1Password, etc.)
- **Separate private repo** (if needed)
- **Local markdown files** (gitignored via `*_LOCAL.md` pattern)

## Troubleshooting

### "My changes aren't being applied"

Check if you're editing the example file instead of the real one:

```bash
ls -la terraform.tfvars*
# Should show both:
# - terraform.tfvars         (gitignored, contains real values)
# - terraform.tfvars.example (committed, contains placeholders)
```

### "Accidentally committed real IPs"

If you've committed real values:

```bash
# Remove from last commit (if not pushed yet)
git reset HEAD~1
git add terraform.tfvars.example  # Only add example file
git commit -m "your message"

# If already pushed - contact repo maintainer
# May need to force-push or rotate credentials
```

## Best Practices

1. **Never edit `terraform.tfvars.example` with real values** - Always edit `terraform.tfvars`
2. **Update example file structure only** - When adding new variables, update .example with placeholders
3. **Use consistent placeholder patterns** - 192.168.1.x, example.com, etc.
4. **Document real topology separately** - Keep network diagrams/details in private notes
5. **Regular audits** - Periodically check git history for accidental leaks

## Summary

```text
✅ Committed:     terraform.tfvars.example (192.168.1.x placeholders)
❌ Never commit:  terraform.tfvars (your real IP addresses)
✅ Gitignored:    *.tfvars, terraform.tfvars
✅ Secret values: Via OpenBao (TF_VAR_* environment variables)
```

This pattern ensures your public repository reveals no sensitive infrastructure details
while maintaining a clear template for users.
