# Heavy-tier LLM serving constants: the per-model concurrency ceiling, and the
# serving host's identity.
#
# Split into its own file (referenced from constants.tf as local.serving) so
# constants.tf stays under the shared _file-size 12 KB error threshold, the same
# reason ai_log_ports and the syslog maps live beside it; locals merge across
# files within the module.
locals {
  # Per-model concurrency for the active GPU serving profile. The model
  # registry owns each profile's slot count; this published value mirrors the
  # active eight-slot profile used by shared serving consumers.
  #
  # MLX has a separate measured admission limit, published below. nix-darwin's
  # flake evaluation is hermetic, so its CI checks serveConcurrency against
  # that matching field.
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
    llm_concurrency     = 8
    mlx_llm_concurrency = 2
    host                = var.llm_large_serving_host
    ip                  = nonsensitive(var.llm_large_serving_ip)
  }
}
