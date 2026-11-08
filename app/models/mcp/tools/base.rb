# The shape every MCP tool shares (docs/ARCHITECTURE.md §14.3). A tool class
# declares its name, description, JSON Schema, annotations and the scope it
# needs; an instance answers one call through #response: a short text block
# plus the same facts as structuredContent. Subclasses implement
# #build_payload (a Hash, memoized as #payload) and #text_lines.
#
# Tools that return captured data (captures_data true) start both halves with
# Mcp::UNTRUSTED_NOTICE. Lookups outside the token's account raise
# Mcp::NotFound and bad arguments Mcp::InvalidArgument; both become tool
# errors (isError) with a plain message.
#
# The SDK runs tools as classes with a `call` class method; .sdk_tool
# builds that adapter, the one sanctioned `call` (like Rack middleware).
class Mcp::Tools::Base
  READ_ONLY = { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }.freeze
  TRIAGE = { read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false }.freeze
  ID_SCHEMA = { type: %w[string integer], maxLength: 40,
                description: "An issue short id such as GS-42 (from search_issues), or the numeric issue id." }.freeze
  LIMIT_MAX = 50

  class_attribute :tool_name, :title, :description, :input_schema, :annotations, :scope, :captures_data,
    instance_writer: false, default: nil

  class << self
    def sdk_tool
      tool = self
      @sdk_tool ||= MCP::Tool.define(name: tool_name, title:, description:, input_schema:,
                                     annotations: annotations.merge(title:)) do |server_context:, **arguments|
        tool.new(server_context.mcp_context, arguments).response
      end
    end

    def limit_schema(default:, max: LIMIT_MAX)
      { type: "integer", minimum: 1, maximum: max, default:, description: "How many to return (1-#{max}, default #{default})." }
    end

    def cursor_schema = { type: "string", maxLength: 200, description: "The next_cursor of a previous result, for the next page." }
  end

  attr_reader :context, :arguments

  def initialize(context, arguments)
    @context = context
    @arguments = arguments.to_h.symbolize_keys
  end

  def response
    MCP::Tool::Response.new([ { type: "text", text: } ], structured_content:)
  rescue Mcp::NotFound, Mcp::InvalidArgument => error
    MCP::Tool::Response.new([ { type: "text", text: error.message } ], error: true)
  end

  private
    def payload = @payload ||= build_payload

    def structured_content = captures_data ? { notice: Mcp::UNTRUSTED_NOTICE, **payload } : payload

    def text = Mcp::Text.lines(*(Mcp::UNTRUSTED_NOTICE if captures_data), *text_lines)

    def limit(default) = (arguments[:limit] || default).to_i.clamp(1, LIMIT_MAX)

    def time(value) = Mcp::Text.time(value)
end
