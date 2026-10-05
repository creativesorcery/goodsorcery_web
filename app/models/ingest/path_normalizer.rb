# Rewrites backtrace paths so they are stable across hosts and free of
# personal directory names: gem paths become `gems/<name>-<version>/...`,
# deploy roots are stripped to app-relative paths and home dirs become `~/`.
class Ingest::PathNormalizer
  RULES = [
    [ %r{\A.*?(?:\A|/)gems/([^/]+-[^/]+)/(.+)\z}, 'gems/\1/\2' ],
    [ %r{\A/.*/lib/ruby/(\d[^/]*)/(.+)\z}, 'ruby/\1/\2' ],
    [ %r{\A/.*?/(?:releases/[^/]+|current)/(.+)\z}, '\1' ],
    [ %r{\A(?:/|~/).*?/((?:app|lib|config)/.+)\z}, '\1' ],
    [ %r{\A/(?:Users|home)/[^/]+/(.*)\z}, '~/\1' ],
    [ %r{\A/root/(.*)\z}, '~/\1' ]
  ].freeze

  def normalize(path)
    path = path.to_s.strip
    pattern, replacement = RULES.find { |rule, _| path.match?(rule) }
    pattern ? path.sub(pattern, replacement) : path
  end
end
