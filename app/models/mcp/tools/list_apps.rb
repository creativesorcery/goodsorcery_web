# list_apps: the account's apps with their slugs (the `app` argument of the
# other tools), platform, environments and unresolved issue count. Two
# queries: the apps with their keys' environments, and one grouped count.
class Mcp::Tools::ListApps < Mcp::Tools::Base
  self.tool_name = "list_apps"
  self.title = "List apps"
  self.scope = "read"
  self.annotations = READ_ONLY
  self.description = "List the apps (projects) of this Good Sorcery account: slug, name, platform, environments, " \
                     "issue short-id prefix and unresolved issue count. Use the slug as the app argument of other tools."
  self.input_schema = { properties: {}, additionalProperties: false }

  private
    def build_payload
      { apps: context.projects.map { |project| app(project) } }
    end

    def app(project)
      { slug: project.slug, name: project.name, platform: project.platform, issue_prefix: project.issue_prefix,
        environments: project.environments, unresolved_issues: unresolved_counts.fetch(project.id, 0),
        listening: project.listening?, issues_url: context.issues_url(project) }
    end

    def unresolved_counts
      @unresolved_counts ||= context.issues.unresolved.group(:project_id).count
    end

    def text_lines
      return [ "No apps yet." ] if payload[:apps].empty?

      payload[:apps].map do |app|
        "#{app[:slug]} (#{app[:name]}, #{app[:platform]}, prefix #{app[:issue_prefix]}): " \
          "#{Mcp::Text.count(app[:unresolved_issues])} unresolved · environments #{app[:environments].join(', ')}"
      end
    end
end
