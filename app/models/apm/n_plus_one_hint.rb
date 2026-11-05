# The generic advice under a trace's N+1 detail (docs/ARCHITECTURE.md
# §13.9): preload the association the repeated query loads, named after the
# first table it reads ("products" → includes(:product)).
#
#   hint = Apm::NPlusOneHint.new('SELECT "products".* FROM "products" WHERE "products"."id" = $1')
#   hint.lead  # => "Load the products in one query instead:"
#   hint.code  # => "….includes(:product)"
class Apm::NPlusOneHint
  GENERIC = "Preload the association with includes so it loads in one query.".freeze

  def initialize(sql)
    @table = Apm::SqlSummary.new(sql).table
  end

  def lead = @table ? "Load the #{@table.humanize(capitalize: false)} in one query instead:" : GENERIC

  def code = @table && "….includes(:#{@table.singularize})"
end
