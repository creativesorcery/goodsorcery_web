# Raised instead of a database or parse error while processing a
# performance batch, carrying only the error class and the batch id.
class Apm::ProcessingFailed < StandardError; end
