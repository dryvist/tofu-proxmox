# CPU LLM pool — live deployment.json merge

The four guests, node `logical_id`, and scaler identity live in the private
RustFS `deployment.json`. The committed
[`deployment.json.example`](../../deployment.json.example) shows the shape;
merge before Terrakube apply.

## Prerequisites

- `nodes.<cpu-pool-node>.logical_id` matches the guest `-NM` digit (5 for R540).
- That node is commissioned with a `bulk` dataset for GGUF mounts.
- Chosen VMIDs are free on the ai serving band.
- Top-level `llm_cpu_scaler.name` is set (or omitted to take the module
  default). Paths and tags are derived in tofu and published as
  `constants.llm_cpu_scaler` — do not restate them in ansible.

## Containers to add

Copy the `_llm_cpu_pool_comment` block from `deployment.json.example`
(`llm-moe-50` through `llm-9b-51`). Guest tags must match
`llm_cpu_scaler.tags` (module defaults unless overridden).

After apply:

1. Ansible-proxmox-ai converge — llama.cpp + LiteLLM + scaler.
2. Seed Proxmox API token at `constants.llm_cpu_scaler.env_file` on a router
   guest (manual until OpenBao path exists).
3. Stop cold guests after first converge if terraform started them
   (`start_on_boot: false` guests).
