# list_occurrences: the stored occurrences of one issue, newest first, paged
# by a keyset cursor (the last id seen). Host and transaction come from each
# decrypted payload, so the page size is capped at 50. Two queries: the
# issue and the page.
class Mcp::Tools::ListOccurrences < Mcp::Tools::Base
  DEFAULT_LIMIT = 20

  self.tool_name = "list_occurrences"
  self.title = "List occurrences"
  self.scope = "read"
  self.captures_data = true
  self.annotations = READ_ONLY
  self.description = "List the stored occurrences (individual events) of an issue, newest first: time, environment, " \
                     "release, host, transaction and occurrence id (for get_occurrence). Only the newest " \
                     "#{Occurrence::RETAINED_PER_ISSUE} per issue are kept, within the app's retention."
  self.input_schema = {
    properties: { issue: ID_SCHEMA, limit: limit_schema(default: DEFAULT_LIMIT), cursor: cursor_schema },
    required: %w[issue], additionalProperties: false
  }

  private
    def issue = @issue ||= context.issue!(arguments[:issue])

    def build_payload
      { issue: issue.short_id, events_total: issue.events_count, occurrences: rows, next_cursor: }
    end

    def text_lines
      [ "#{rows.size} stored #{'occurrence'.pluralize(rows.size)} of #{issue.short_id} (newest first):",
        *rows.map { |row| "#{row[:id]} · #{row[:occurred_at]} · #{row[:environment]} · release #{row[:release] || '–'} · " \
                          "host #{row[:host] || '–'} · #{row[:transaction] || '–'}" },
        ("More: pass cursor \"#{next_cursor}\"." if next_cursor) ]
    end

    def rows
      @rows ||= page.first(limit(DEFAULT_LIMIT)).map do |occurrence|
        { id: occurrence.uuid, occurred_at: time(occurrence.occurred_at), environment: occurrence.environment,
          release: occurrence.release, host: Mcp::Captured.string(occurrence.context["host"].presence, 100).presence,
          transaction: occurrence.transaction_name || issue.transaction_name }
      end
    end

    def page
      @page ||= begin
        scope = issue.occurrences.latest_first.limit(limit(DEFAULT_LIMIT) + 1)
        before = Mcp::Cursor.decode(arguments[:cursor], :before_id)
        (before.positive? ? scope.where(id: ...before) : scope).to_a
      end
    end

    def next_cursor
      Mcp::Cursor.encode(before_id: page[limit(DEFAULT_LIMIT) - 1].id) if page.size > limit(DEFAULT_LIMIT)
    end
end
