# The staff area's search box (/staff/accounts, /staff/users): a whole number
# finds that id exactly; any other text is a case-insensitive substring of the
# declared columns, with LIKE wildcards (% and _) matched literally.
module StaffSearchable
  extend ActiveSupport::Concern

  # Longer digit strings can't be a bigint id, so they're searched as text.
  ID_PATTERN = /\A\d{1,18}\z/
  MAX_QUERY_LENGTH = 100

  included do
    class_attribute :staff_search_columns, instance_writer: false, default: []
  end

  class_methods do
    def staff_searchable_by(*columns)
      self.staff_search_columns = columns
    end

    def staff_search(query)
      query = query.to_s.strip.first(MAX_QUERY_LENGTH)
      return all if query.empty?
      return where(id: query.to_i) if query.match?(ID_PATTERN)

      pattern = "%#{sanitize_sql_like(query)}%"
      where(staff_search_columns.map { |column| arel_table[column].matches(pattern) }.reduce(:or))
    end
  end
end
