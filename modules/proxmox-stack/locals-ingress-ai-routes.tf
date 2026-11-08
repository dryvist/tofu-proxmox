# AI orchestration stack route rows, merged into ingress_services in ingress.tf.
locals {
  ai_stack_routes = merge({
    # AI orchestration stack UIs (ai VLAN) + Langfuse/Phoenix LLM observability (siem VLAN).
    n8n = { backend = "n8n", port = local.pipeline_constants.service_ports.n8n_web }
    # Dify Community has no SSO, so the whole host skips the forwardAuth gate and
    # Dify's own login protects the UI, console API and machine paths alike.
    dify     = { backend = "dify", port = local.pipeline_constants.service_ports.dify_web, sso = false }
    langflow = { backend = "langflow", port = local.pipeline_constants.service_ports.langflow_web }
    langfuse = { backend = "langfuse", port = local.pipeline_constants.service_ports.langfuse_web }
    # Langfuse OTLP ingest (/api/public/) on the langfuse hostname, routed
    # without the forwardAuth gate. Langfuse authenticates this path with its
    # own key pair, and the Authelia bypass for ^/api/public is unchanged. The
    # browser UI stays on the row above, which remains sso-gated.
    "langfuse-otlp" = { hostname = "langfuse", path_prefix = "/api/public/", priority = 100, backend = "langfuse", port = local.pipeline_constants.service_ports.langfuse_web, sso = false }
    # phoenix's OTLP/HTTP ingest path (/v1/traces) is exempted from the Authelia
    # forwardAuth middleware on the Ansible side (a resource regex in
    # ansible-proxmox-apps) — this row stays a single sso-gated route. A second
    # sso = false row on a host is allowed only for one narrow machine API path
    # (langfuse-otlp), never a whole-host row, or the whole UI would be exposed
    # unauthenticated. Dify is the one whole-host exception, above.
    phoenix = { backend = "phoenix", port = local.pipeline_constants.service_ports.phoenix_web }
    # docling-serve — Open WebUI's content-extraction (OCR/layout) backend. The
    # only caller is Open WebUI's server-side loader posting to /v1/convert/file,
    # so sso = false: an SSO redirect would break a machine-to-machine POST.
    "docling-serve" = { backend = "docling-serve", port = local.pipeline_constants.service_ports.docling_serve_api, sso = false }
    }, length(local.docker_ai_backends) == 0 ? {
    # Keep the legacy single guest until a docker-ai-tagged pool is declared.
    hatchet = { backend = "hatchet", port = local.pipeline_constants.service_ports.hatchet_web }
  } : {})
}
