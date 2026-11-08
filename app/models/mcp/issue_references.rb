# Finds issues of the token's account by the references AI clients pass:
# a short id ("GS-42", any case) or the numeric issue id (42 or "42"). All
# references resolve in one query; anything unknown, malformed or of another
# account is reported as not found, the same way.
#
#   Mcp::IssueReferences.new(context, ["GS-42", 1077]).issues!  # raises Mcp::NotFound naming the misses
class Mcp::IssueReferences
  NUMERIC = /\A\d{1,18}\z/

  def initialize(context, references)
    @context = context
    @references = Array(references).map { |reference| reference.to_s.strip }.uniq
  end

  # The issues in reference order, with their projects attached.
  def issues!
    missing = @references.reject { |reference| found[reference] }
    raise Mcp::NotFound, not_found_message(missing) if missing.any?

    @context.attach_projects(@references.map { |reference| found[reference] }.uniq)
  end

  private
    # { reference => issue } for the references that matched.
    def found
      @found ||= begin
        rows = query ? query.to_a : []
        @references.to_h { |reference| [ reference, rows.find { |issue| matches?(issue, reference) } ] }
      end
    end

    def query
      conditions = @references.filter_map { |reference| condition_for(reference) }
      conditions.reduce { |relation, condition| relation.or(condition) }
    end

    def condition_for(reference)
      return @context.issues.where(id: reference.to_i) if reference.match?(NUMERIC)

      project, number = short_id_parts(reference)
      @context.issues.where(project_id: project.id, number:) if project
    end

    def short_id_parts(reference)
      return unless reference.match?(Issue::SHORT_ID)

      prefix, number = reference.upcase.split("-", 2)
      project = @context.projects.find { |candidate| candidate.issue_prefix == prefix }
      [ project, number.to_i ] if project
    end

    def matches?(issue, reference)
      return issue.id == reference.to_i if reference.match?(NUMERIC)

      project, number = short_id_parts(reference)
      project && issue.project_id == project.id && issue.number == number
    end

    def not_found_message(missing)
      names = missing.first(5).map { |reference| Mcp::Text.quote(reference) }.join(", ")
      "Issue not found: #{names}. Use search_issues to find issue short ids."
    end
end
