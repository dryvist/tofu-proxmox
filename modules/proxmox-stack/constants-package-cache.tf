# Package-cache ports shared by inventory publication and guest firewall rules.
locals {
  package_cache_ports = {
    pypi_cache = 3141
    npm_cache  = 4873
    raw_cache  = 8081
  }
}
