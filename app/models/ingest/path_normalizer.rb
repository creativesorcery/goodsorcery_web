# Rewrites backtrace paths so they are stable across hosts and free of
# personal directory names. Clients should send app-relative paths; this is
# the fallback for absolute ones: package paths become
# `gems/<name>-<version>/...` (RubyGems) or `crates/<name>-<version>/...`
# (Cargo registry), deploy and container roots are stripped to app-relative
# paths and home dirs become `~/`. Anything else is left as sent.
class Ingest::PathNormalizer
  RULES = [
    [ %r{\A.*?(?:\A|/)gems/([^/]+-[^/]+)/(.+)\z}, 'gems/\1/\2' ],
    [ %r{\A.*?/registry/src/[^/]+/([^/]+-\d[^/]*)/(.+)\z}, 'crates/\1/\2' ],
    [ %r{\A/.*/lib/ruby/(\d[^/]*)/(.+)\z}, 'ruby/\1/\2' ],
    [ %r{\A/.*?/(?:releases/[^/]+|current)/(.+)\z}, '\1' ],
    [ %r{\A(?:/|~/).*?/((?:app|lib|config)/.+)\z}, '\1' ],
    [ %r{\A/(?:app|rails)/(.+)\z}, '\1' ],
    [ %r{\A/(?:Users|home)/[^/]+/(.*)\z}, '~/\1' ],
    [ %r{\A/root/(.*)\z}, '~/\1' ]
  ].freeze

  def normalize(path)
    path = path.to_s.strip
    pattern, replacement = RULES.find { |rule, _| path.match?(rule) }
    pattern ? path.sub(pattern, replacement) : path
  end
end
