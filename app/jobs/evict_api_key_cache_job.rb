# Deletes a rotated key's cached credential once more, shortly after the
# rotation. An ingest request that read the old row just before the rotation
# committed can write it back to the cache after the first delete; this
# second delete closes that window. The argument is the old key's SHA-256
# digest only, never a token.
class EvictApiKeyCacheJob < ApplicationJob
  DELAY = 5.seconds

  queue_as :default

  def perform(digest)
    Rails.cache.delete(ApiKey.cache_key_for(digest))
  end
end
