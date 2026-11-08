# add_note: a note on an issue's activity feed, as the token's member and
# marked "via MCP" (the same encrypted IssueActivity notes as the issue
# page). Recorded in the token's audit log without its text. Needs the
# triage scope.
class Mcp::Tools::AddNote < Mcp::Tools::Base
  MAX_BODY = 2_000

  self.tool_name = "add_note"
  self.title = "Add note"
  self.scope = "triage"
  self.annotations = TRIAGE.merge(idempotent_hint: false)
  self.description = "Add a note (up to #{MAX_BODY} characters of plain text) to an issue's activity feed, shown to " \
                     "the team as written by the token's owner via MCP."
  self.input_schema = {
    properties: { issue: ID_SCHEMA, body: { type: "string", minLength: 1, maxLength: MAX_BODY, description: "The note text." } },
    required: %w[issue body], additionalProperties: false
  }

  private
    def issue = @issue ||= context.issue!(arguments[:issue])

    def build_payload
      note = issue.activities.note.new(body: arguments[:body].to_s.strip, user: context.user, via: "mcp")
      raise Mcp::InvalidArgument, "The note couldn't be saved: #{note.errors.full_messages.to_sentence}." unless note.save

      AccessTokenActivity.record(context.token, "note", [ issue.id ])
      { issue: issue.short_id, note_id: note.id, created_at: time(note.created_at), url: context.issue_url(issue) }
    end

    def text_lines = [ "Added a note to #{issue.short_id}: #{payload[:url]}" ]
end
