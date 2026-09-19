# Guest naming law, enforced at plan time.
#
# THE LAW. A guest name is `<app>` or `<app>-<n>`. `<app>` is the bare
# application name — `technitium`, not `technitium-dns`; the protocol is
# redundant when the app IS the protocol — never a hardware, model, or node
# token (`llm-4080`, `docker-540` are illegal). `<n>` is the instance
# ordinal: 1-2 digits, no leading zero, and for each `<app>` the ordinals in
# use are exactly `1..N` with no gaps or duplicates — a suffix always means
# "instance n of N". Placement is NEVER encoded: a node reboot, an HA move,
# or a rebuild never touches a guest's name, so `ha = true` no longer changes
# what is accepted. See docs/GUEST_NAMING.md for the convention in full.
#
# A guest with no suffix is that app's single instance. Adding a second
# instance renames the first to `-1` — a rename is estate policy
# (stateless guests are rebuilt, never renamed in place), not something this
# guard enforces.
locals {
  guest_naming_subjects = concat(
    [for k, v in var.containers : { name = v.hostname, kind = "container" }],
    [for k, v in var.vms : { name = v.name, kind = "vm" }],
  )

  # Split each name into {app, suffix} on its trailing "-<digits>" run, if
  # any. A name with no such tail is bare: app = the whole name.
  guest_naming_split = {
    for g in local.guest_naming_subjects : g.name => merge(g, {
      tail_match = regexall("^(.+)-([0-9]+)$", g.name)
    })
  }

  # Exception-listed names are exempt from every check below.
  guest_naming_judged = {
    for name, g in local.guest_naming_split : name => g
    if !contains(keys(var.guest_naming_exceptions), name)
  }

  # A numeric tail that isn't a 1-2 digit, no-leading-zero ordinal fails
  # outright — this is also what rejects a hardware/model token (a GPU model
  # number is a 3-4 digit tail) without a separate check.
  guest_naming_bad_format = [
    for name, g in local.guest_naming_judged :
    "${g.kind} \"${name}\": numeric suffix \"-${g.tail_match[0][1]}\" must be a 1-2 digit ordinal (\"1\"-\"99\", no leading zero) — it names instance n of the app, never a node or a model."
    if length(g.tail_match) > 0 && !can(regex("^[1-9][0-9]?$", g.tail_match[0][1]))
  ]

  # Well-formed guests only (bad-format ones are already reported above and
  # would otherwise pollute a group they never validly belonged to).
  guest_naming_wellformed = [
    for name, g in local.guest_naming_judged : {
      name   = name
      kind   = g.kind
      app    = length(g.tail_match) > 0 ? g.tail_match[0][0] : name
      suffix = length(g.tail_match) > 0 ? tonumber(g.tail_match[0][1]) : null
    }
    if length(g.tail_match) == 0 || can(regex("^[1-9][0-9]?$", g.tail_match[0][1]))
  ]

  guest_naming_apps = distinct([for r in local.guest_naming_wellformed : r.app])

  # Per app: the ordinals in use (raw, may repeat) and the same set deduped
  # and ascending — `sort()` only orders strings, so ascending order comes
  # from filtering the known 1-99 domain in order instead. "Instance n of N"
  # means the deduped ordinals are exactly 1..N — a gap, a duplicate, or a
  # bare name alongside numbered instances all break that promise.
  guest_naming_raw_ordinals_by_app = {
    for app in local.guest_naming_apps : app => [
      for r in local.guest_naming_wellformed : r.suffix if r.app == app && r.suffix != null
    ]
  }
  guest_naming_ordinals_by_app = {
    for app in local.guest_naming_apps : app => [
      for n in range(1, 100) : n if contains(local.guest_naming_raw_ordinals_by_app[app], n)
    ]
  }
  guest_naming_bare_count_by_app = {
    for app in local.guest_naming_apps : app => length([
      for r in local.guest_naming_wellformed : r if r.app == app && r.suffix == null
    ])
  }

  guest_naming_mixed_form_failures = [
    for app in local.guest_naming_apps :
    "app \"${app}\": has both a bare name and numbered instances — a bare name means a single instance; a second instance renames the first to \"-1\"."
    if local.guest_naming_bare_count_by_app[app] > 0 && length(local.guest_naming_ordinals_by_app[app]) > 0
  ]

  guest_naming_duplicate_bare_failures = [
    for app in local.guest_naming_apps :
    "app \"${app}\": more than one guest with no numeric suffix — a bare name means exactly one instance."
    if local.guest_naming_bare_count_by_app[app] > 1
  ]

  guest_naming_duplicate_suffix_failures = [
    for app in local.guest_naming_apps :
    "app \"${app}\": more than one guest shares suffix ${jsonencode(local.guest_naming_raw_ordinals_by_app[app])} — each ordinal must appear exactly once."
    if length(local.guest_naming_raw_ordinals_by_app[app]) != length(local.guest_naming_ordinals_by_app[app])
  ]

  # Deduped and ascending (by construction above), so "exactly 1..N" holds
  # iff the highest ordinal equals the count — any gap would make the
  # highest ordinal larger than the count.
  guest_naming_gap_failures = [
    for app in local.guest_naming_apps :
    "app \"${app}\": suffixes ${jsonencode(local.guest_naming_ordinals_by_app[app])} are not a contiguous 1..${length(local.guest_naming_ordinals_by_app[app])} — an ordinal means instance n of the app's total, no gaps and no duplicates."
    if length(local.guest_naming_ordinals_by_app[app]) > 0
    && max(local.guest_naming_ordinals_by_app[app]...) != length(local.guest_naming_ordinals_by_app[app])
  ]

  guest_naming_failures = concat(
    local.guest_naming_bad_format,
    local.guest_naming_mixed_form_failures,
    local.guest_naming_duplicate_bare_failures,
    local.guest_naming_duplicate_suffix_failures,
    local.guest_naming_gap_failures,
  )
}

# Guests whose names predate the law and are not renamed by this change. A
# rename is a separate, riskier operation — a guest deriving its cluster
# identity from its hostname rejoins as a NEW peer, leaving the old entry as a
# failed voter — so the renames ride a planned resize instead.
#
# The roster is a real-guest-name list, so it is NOT committed here — a public
# repository is exactly the wrong place for it (same reason node_name-to-guest
# topology never appears in prose). It lives in the private desired state
# alongside the guard's own rule (`deployment.json`'s `guest_naming_exceptions`,
# wired in main.tf), keyed by guest name with the reason as the value so an
# entry cannot be added silently. Only the rule is public; the roster stays
# private. Shrink it; never grow it.
variable "guest_naming_exceptions" {
  description = "Guest names exempted from the guest naming law, name -> reason. Sourced from the private desired state, never committed here — every entry is pre-law debt awaiting a planned rename."
  type        = map(string)
  default     = {}
}

# terraform_data is a provider-less plan-time anchor, the same idiom checks.tf
# and checks-storage.tf use: the precondition is the assertion, and it fails the
# plan rather than warning like a `check` block would.
resource "terraform_data" "guest_naming_guard" {
  input = length(local.guest_naming_failures)

  lifecycle {
    precondition {
      condition     = length(local.guest_naming_failures) == 0
      error_message = "Guest naming law violated (docs/GUEST_NAMING.md):\n  - ${join("\n  - ", local.guest_naming_failures)}"
    }
  }
}
