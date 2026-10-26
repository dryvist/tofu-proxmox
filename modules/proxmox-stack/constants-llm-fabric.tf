# LLM fabric service ports, merged into pipeline_constants.service_ports.
# Split out to keep constants.tf under the shared 12 KB file-size gate.
locals {
  llm_fabric_ports = {
    # Local LLM fabric. llm_fast_api is llama-swap; llm_gpu_serving_api is the
    # tag-selected GPU small-router endpoint; llm_fast_trial_api is the
    # side-by-side small-model trial endpoint,
    # llm_classify_api is the classifier API, llm_router_api is the LiteLLM proxy, and
    # open_webui_web is the chat UI. ollama_api is retained through the
    # retirement phase (superseded by llama-swap on llm_fast_api).
    llm_fast_api        = 10434
    llm_gpu_serving_api = 10440
    llm_fast_trial_api  = 10436
    llm_classify_api    = 8000
    llm_router_api      = 4000
    ollama_api          = 11434
    # llm_cluster_api = the serving host's gated Cluster Mode endpoint (the
    # two-Mac distributed brain); mirrors the loopback cluster port the same
    # way ollama_api mirrors the standalone proxy.
    llm_cluster_api   = 11440
    open_webui_web    = 8080
    docling_serve_api = 5001
  }
}
