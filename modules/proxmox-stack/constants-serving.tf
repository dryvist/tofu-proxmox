# Heavy-tier LLM serving constants: the per-model concurrency ceiling, and the
# serving host's identity.
#
# Split into its own file (referenced from constants.tf as local.serving) so
# constants.tf stays under the shared _file-size 12 KB error threshold, the same
# reason ai_log_ports and the syslog maps live beside it; locals merge across
# files within the module.
locals {
  # Per-model serving concurrency ceiling for the LLM serving tier. THE
  # single numeric definition of this value repo-wide — previously it was
  # ALSO a bare literal in ansible-proxmox-ai's inventory/group_vars/all.yml
  # (ai_llm_concurrency) and nix-darwin's lib/hosts/mac-studio.nix
  # (serveConcurrency), "kept in sync by convention." ansible-proxmox-ai now
  # derives ai_llm_concurrency from tofu_data.constants.serving.llm_concurrency
  # via the existing tofu_data channel (dryvist.homelab.inventory_resolve) —
  # the same mechanism every other pipeline_constants family already uses.
  # nix-darwin's flake evaluation is hermetic (no network access), so it
  # cannot derive this the same way; instead its CI runs a parity check
  # (.github/workflows/_llm-concurrency-parity.yml in dryvist/nix-darwin)
  # against this repo's `main` branch and fails the build on drift. Raising
  # this value requires raising serveConcurrency in the SAME change (or the
  # parity check fails) — mechanically enforced now, not by convention.
  #
  # host/ip identify the serving host itself. They are published here for the
  # same reason llm_concurrency is: both consuming Ansible repositories
  # (ansible-proxmox-ai's llm_router, ansible-proxmox-apps' technitium_dns)
  # previously carried their own byte-identical copies of these two values,
  # "kept in sync by convention" — the same failure mode, one layer up.
  #
  # Unlike llm_concurrency they carry NO committed value: they come from the
  # private deployment object at apply time (see variables-serving.tf) and
  # publish as empty strings when it does not describe them. Empty means
  # "not described" and consumers must fail loudly on it. Deriving an address
  # from a guess is strictly worse than having none, because the guess fails
  # later, somewhere else, as a timeout rather than as a missing value.
  #
  # nonsensitive(): the variable is marked sensitive so the address never
  # prints in plan output, but it has to reach the published inventory
  # artifact for consumers to read at all — the same trade every derived
  # guest address in this module already makes (see locals.tf, where each
  # cidrhost() result is unwrapped for exactly this reason). The artifact
  # lands in private object storage, not git, so publishing it there is not
  # what this design is protecting against; committing it is.
  serving = {
    # 4 since 2026-08-16 (was 2 since 2026-08-06, was 1 before that). Raised
    # under real router-tier saturation (2-slot tier queuing/429ing a
    # steady 3-concurrent load). Memory-safe because cacheMemoryMb=16384 on
    # the resident already provisions for 4 full-65536-token concurrent
    # streams (65536 tokens x 64 KiB/token x 4 = 16 GiB): N=2/3/4 share an
    # identical worst-case peak, so this costs nothing over today. Sizing
    # and memory reasoning: dryvist/nix-darwin lib/hosts/mac-studio.md
    # "Serving concurrency".
    llm_concurrency = 4
    host            = var.llm_large_serving_host
    ip              = nonsensitive(var.llm_large_serving_ip)
  }
}
