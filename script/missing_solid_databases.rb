# Prints the Solid databases whose tables are absent, space separated, for
# bin/prepare-solid-databases to load. Prints nothing when all are present.
#
# Each check runs through that database's own Record class, so it asks the
# same connection the matching db:schema:load would write to. Asking the
# primary connection instead would report "missing" for a deployment whose
# cache, queue and cable really are separate databases -- and the load that
# followed would drop their live tables.
#
# It checks EVERY table the schema file declares, not one sentinel. The queue
# schema declares thirteen, and an earlier version of this file looked only at
# solid_queue_processes. That gap had a destructive failure behind it: if a
# schema load were ever interrupted partway, the next boot would find the
# sentinel missing, declare the whole role absent, and run db:schema:load --
# which DROPS and recreates every table for that role, destroying whatever
# jobs the tables that did exist were holding.
#
# So there are three states, and only two of them are safe to act on:
#   - no tables at all      -> the role needs loading, report it
#   - every table present   -> nothing to do
#   - some tables present   -> raise. This is the state where the repair is
#                              destructive, and no automated guess about it is
#                              worth a queue of real work.
#
# This raises rather than returning a guess when a database cannot be reached,
# too. The caller treats any failure as a reason NOT to run a destructive task.

MODELS = {
  "cache" => SolidCache::Record,
  "queue" => SolidQueue::Record,
  "cable" => SolidCable::Record
}.freeze

# Read the table list out of the schema file itself rather than restating it
# here, so the check cannot drift away from what the load would actually
# create when Rails changes a Solid schema.
def declared_tables(name)
  schema = Rails.root.join("db", "#{name}_schema.rb")
  raise "#{schema} does not exist -- cannot tell which tables #{name} needs" unless schema.exist?

  tables = schema.read.scan(/create_table\s+"([^"]+)"/).flatten
  raise "#{schema} declares no tables -- refusing to guess" if tables.empty?

  tables
end

missing = MODELS.filter_map do |name, model|
  tables = declared_tables(name)
  present = model.connection_pool.with_connection do |connection|
    tables.select { |table| connection.table_exists?(table) }
  end

  case present.size
  when 0            then name
  when tables.size  then nil
  else
    raise "#{name}: #{present.size} of #{tables.size} tables exist " \
          "(missing #{(tables - present).join(', ')}). Loading db/#{name}_schema.rb " \
          "would DROP the tables that are already there. Resolve this by hand."
  end
end

print missing.join(" ")
