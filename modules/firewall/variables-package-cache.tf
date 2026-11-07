variable "package_cache_destinations" {
  description = "Cache guest addresses allowed from Pepper, derived from the tagged guests that supply the published cache URLs."
  type        = list(string)
  default     = []
}
