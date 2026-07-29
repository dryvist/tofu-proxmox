
# OpenBao Raft voter concentration (advisory).
#
# Raft tolerates losing voters, not losing HOSTS. OpenBao's own
# autopilot `failure_tolerance` counts servers and is blind to which node each
# voter sits on, so it reports healthy while one node quietly carries enough
# voters that losing it drops the cluster to exactly quorum — zero headroom,
# and the next voter loss seals it. This check is that blind spot made explicit.
#
# The arithmetic is unintuitive, so spell it out. For N voters quorum is
# floor(N/2)+1, and adding a single voter usually does NOT help, because it
# raises quorum in lockstep. With 3 voters concentrated on one node:
#
#   N=7  quorum 4  survivors 4  -> 4 > 4 false, no headroom
#   N=8  quorum 5  survivors 5  -> 5 > 5 false, no headroom (one added voter buys nothing)
#   N=9  quorum 5  survivors 6  -> 6 > 5 true, one voter of slack
#
# Note what that table is really saying: it holds the concentration fixed at 3
# and adds voters, which is the expensive way out. Spreading is the cheap way,
# and it inverts the conclusion — with voters over FOUR nodes instead of three,
# no node carries more than 2:
#
#   N=8 over 4 nodes  quorum 5  survivors 6  -> 6 > 5 true, one voter of slack
#
# So the same headroom the table only reaches at N=9 is available at N=8 simply
# by using a node that currently carries none. Reducing concentration beats
# adding voters; reach for a wider spread before a larger count.
#
# A hard limit is worth stating because it is not obvious and no voter count
# escapes it: surviving the loss of K of M nodes needs the remaining M-K nodes to
# hold a majority, so tolerating 2 of 4 is impossible (half is never a majority)
# and tolerating 4 requires M >= 9. Beyond one-node tolerance the answer is more
# nodes, or an out-of-band restore path — not more voters.
#
# Advisory `check` rather than a hard validation: a hard error would block the
# very applies that fix the spread, and would fail closed on a cluster that is
# merely suboptimal rather than broken.
locals {
  # The node each OpenBao voter lands on. node_name is optional on a container
  # and falls back to the stack default, exactly as the container resource does.
  openbao_voter_nodes = [
    for name, c in var.containers :
    coalesce(c.node_name, var.proxmox_node)
    if contains(coalesce(c.tags, []), "openbao")
  ]
  openbao_voter_count = length(local.openbao_voter_nodes)
  openbao_quorum      = floor(local.openbao_voter_count / 2) + 1
  # Voters still standing after losing the one node that carries the most of
  # them. concat([0], ...) keeps max() defined when there are no voters at all.
  openbao_voters_after_worst_node_loss = local.openbao_voter_count - max(concat([0], [
    for node in distinct(local.openbao_voter_nodes) :
    length([for n in local.openbao_voter_nodes : n if n == node])
  ])...)
}

check "openbao_voter_concentration" {
  assert {
    condition = (
      local.openbao_voter_count == 0 ||
      local.openbao_voters_after_worst_node_loss > local.openbao_quorum
    )
    error_message = "OpenBao Raft voter concentration: ${local.openbao_voter_count} voters need a quorum of ${local.openbao_quorum}, but losing the single node carrying the most of them leaves only ${local.openbao_voters_after_worst_node_loss}. Spread voters over more nodes until a one-node loss leaves at least one voter above quorum. Adding one voter typically does not help — it raises quorum too."
  }
}
