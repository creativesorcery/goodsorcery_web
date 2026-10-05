# Derives a project's URL slug (unique per account, "-2", "-3" on collision)
# and its default short-ID prefix.
class Project::Slug
  FALLBACK = "app".freeze

  # Initials of the slug words ("marketing-site" => "MS"), or the first three
  # letters when there is one word ("storefront" => "STO").
  def self.prefix_for(slug)
    words = slug.to_s.upcase.split("-").map { |word| word.delete("^A-Z") }.compact_blank
    prefix = words.one? ? words.first.first(3) : words.map(&:first).join
    prefix.first(6).presence || "APP"
  end

  def initialize(account, name)
    @account = account
    @base = name.to_s.parameterize.first(60).delete_suffix("-").presence || FALLBACK
  end

  def unique
    taken = taken_slugs
    return @base unless taken.include?(@base)

    (2..).each { |n| return "#{@base}-#{n}" unless taken.include?("#{@base}-#{n}") }
  end

  private
    def taken_slugs
      pattern = "#{ActiveRecord::Base.sanitize_sql_like(@base)}-%"
      @account.projects.where("slug = :base OR slug LIKE :pattern", base: @base, pattern:).pluck(:slug).to_set
    end
end
