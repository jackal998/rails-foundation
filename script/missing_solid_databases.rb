# Prints the Solid databases whose tables are absent, space separated, for
# bin/prepare-solid-databases to load. Prints nothing when all are present.
#
# Each check runs through that database's own Record class, so it asks the
# same connection the matching db:schema:load would write to. Asking the
# primary connection instead would report "missing" for a deployment whose
# cache, queue and cable really are separate databases -- and the load that
# followed would drop their live tables.
#
# This raises rather than returning a guess when a database cannot be
# reached. The caller treats any failure as a reason NOT to run a
# destructive task.

CHECKS = {
  "cache" => [ SolidCache::Record, "solid_cache_entries" ],
  "queue" => [ SolidQueue::Record, "solid_queue_processes" ],
  "cable" => [ SolidCable::Record, "solid_cable_messages" ]
}.freeze

missing = CHECKS.filter_map do |name, (model, table)|
  name unless model.connection_pool.with_connection { |c| c.table_exists?(table) }
end

print missing.join(" ")
