variable "llm_gpu_engine" {
  description = "The single selected engine for the GPU serving guest pair."
  type        = string
  default     = "llama_cpp"

  validation {
    condition     = contains(["llama_cpp", "vllm"], var.llm_gpu_engine)
    error_message = "llm_gpu_engine must be llama_cpp or vllm."
  }
}
