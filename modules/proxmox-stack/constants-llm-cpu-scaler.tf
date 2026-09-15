# CPU LLM pool scaler — single identity, derived paths.
#
# The unit name is declared ONCE (var.llm_cpu_scaler.name, default
# "llm-cpu-scaler"). install_dir / config_file / state_file / systemd unit names
# are format()d from that string here so ansible never concatenates them and
# never restates the name. Same reason serving.llm_concurrency lives in
# constants-serving.tf: one published object, many consumers.
locals {
  _llm_cpu_scaler_name = var.llm_cpu_scaler.name
  _llm_cpu_scaler_tags = {
    moe    = try(var.llm_cpu_scaler.tags.moe, "llm-cpu-moe")
    nine_b = try(var.llm_cpu_scaler.tags.nine_b, "llm-cpu-9b")
    warm   = try(var.llm_cpu_scaler.tags.warm, "llm-cpu-warm")
    pool   = try(var.llm_cpu_scaler.tags.pool, "llm-cpu-pool")
  }

  llm_cpu_scaler = {
    name              = local._llm_cpu_scaler_name
    install_dir       = "/opt/${local._llm_cpu_scaler_name}"
    config_dir        = "/etc/${local._llm_cpu_scaler_name}"
    state_dir         = "/var/lib/${local._llm_cpu_scaler_name}"
    config_file       = "/etc/${local._llm_cpu_scaler_name}/config.json"
    state_file        = "/var/lib/${local._llm_cpu_scaler_name}/state.json"
    env_file          = "/etc/${local._llm_cpu_scaler_name}/env"
    unit              = local._llm_cpu_scaler_name
    service           = "${local._llm_cpu_scaler_name}.service"
    timer             = "${local._llm_cpu_scaler_name}.timer"
    script            = "${local._llm_cpu_scaler_name}.py"
    poll_interval_sec = var.llm_cpu_scaler.poll_interval_sec
    idle_teardown_sec = var.llm_cpu_scaler.idle_teardown_sec
    min_free_ram_mb   = var.llm_cpu_scaler.min_free_ram_mb
    tags              = local._llm_cpu_scaler_tags
    # Ordered list for "is this guest in the pool?" checks.
    pool_tags = [
      local._llm_cpu_scaler_tags.moe,
      local._llm_cpu_scaler_tags.nine_b,
    ]
  }
}
