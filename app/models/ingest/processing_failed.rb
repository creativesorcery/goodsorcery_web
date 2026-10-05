# Stands in for database errors raised while processing an inbound event.
# Postgres error details can quote row values ("Failing row contains ..."), and
# job errors are stored in Redis and logs, so only the class name is kept.
class Ingest::ProcessingFailed < StandardError
end
