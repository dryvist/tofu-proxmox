variable "specialist_eval_container_ids" {
  description = "Map of specialist-eval LXC names to IDs and their one platform tag; unrecognised tags receive no service-port rule."
  type = map(object({
    vm_id        = number
    platform_tag = string
  }))
  default = {}
}
