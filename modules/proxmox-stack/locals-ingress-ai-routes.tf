# AI orchestration stack route rows, merged into ingress_services in ingress.tf.
locals {
  ai_stack_routes = merge({
    # AI orchestration stack UIs (ai VLAN) + Langfuse/Phoenix LLM observability (siem VLAN).
    n8n  = { backend = "n8n", port = local.pipeline_constants.service_ports.n8n_web }
    dify = { backend = "dify", port = local.pipeline_constants.service_ports.dify_web }
    # The browser UI and /console/api stay SSO-gated; these machine paths
    # authenticate natively.
    "dify-api-v1"   = { hostname = "dify", path_prefix = "/v1", priority = 100, backend = "dify", port = local.pipeline_constants.service_ports.dify_web, sso = false }                # Dify service API; app API keys; used by agents
    "dify-setup"    = { hostname = "dify", path_prefix = "/console/api/setup", priority = 100, backend = "dify", port = local.pipeline_constants.service_ports.dify_web, sso = false } # Dify first-run setup endpoint
    "dify-files"    = { hostname = "dify", path_prefix = "/files", priority = 100, backend = "dify", port = local.pipeline_constants.service_ports.dify_web, sso = false }             # signed file URLs returned by the service API
    "dify-plugin-e" = { hostname = "dify", path_prefix = "/e/", priority = 100, backend = "dify", port = local.pipeline_constants.service_ports.dify_web, sso = false }                # plugin endpoints called by external services
    langflow        = { backend = "langflow", port = local.pipeline_constants.service_ports.langflow_web }
    langfuse        = { backend = "langfuse", port = local.pipeline_constants.service_ports.langfuse_web }
    # phoenix's OTLP/HTTP ingest path (/v1/traces) is exempted from the Authelia
    # forwardAuth middleware on the Ansible side (a resource regex in
    # ansible-proxmox-apps), the same way Langfuse's ingest path is — this row
    # stays a single sso-gated route, never a second sso = false row, or the
    # whole UI would be exposed unauthenticated.
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
