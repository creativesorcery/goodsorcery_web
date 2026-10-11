require "test_helper"

class EnvironmentChoiceTest < ActiveSupport::TestCase
  setup do
    @project = projects(:storefront) # environments: production, staging
    @project.default_environment = "production"
  end

  test "an env: chip in the query wins over the param, the remembered choice and the default" do
    choice = choose(query: IssueQuery.new("is:unresolved env:staging"), param: "", remembered: "")

    assert_equal "staging", choice.environment
    assert choice.explicit?
  end

  test "the env param comes next; blank means all environments" do
    assert_equal "staging", choose(param: "Staging", remembered: "production").environment
    assert_nil choose(param: "", remembered: "staging").environment
    assert choose(param: "").explicit?
  end

  test "then the remembered choice, all environments included" do
    assert_equal "staging", choose(remembered: "staging").environment
    assert_nil choose(remembered: "").environment
    assert_not choose(remembered: "staging").explicit?
  end

  test "then the project's default, then all environments" do
    assert_equal "production", choose.environment

    @project.default_environment = nil
    assert_nil choose.environment
  end

  test "a remembered value that is not one of the project's environments is ignored" do
    assert_equal "production", choose(remembered: "qa").environment
    assert_equal "production", choose(remembered: { "env" => "staging" }).environment
    assert_equal "production", choose(remembered: nil).environment
  end

  test "a default that lost its key is ignored" do
    @project.default_environment = "qa"

    assert_nil choose.environment
  end

  test "params that are not environment names are not choices" do
    [ "two words", "<b>", [ "staging" ], { "a" => "b" }, nil ].each do |param|
      assert_not choose(param:).explicit?, param.inspect
      assert_equal "production", choose(param:).environment
    end
  end

  test "explicit choices of a known environment or of all are remembered; unknown ones are not" do
    assert choose(param: "staging").remember?
    assert choose(param: "").remember?
    assert choose(query: IssueQuery.new("env:production")).remember?
    assert_not choose(query: IssueQuery.new("env:qa")).remember?
    assert_not choose(remembered: "staging").remember?
    assert_equal "", choose(param: " ").requested
  end

  test "outside production and the way back" do
    assert choose(param: "staging").outside_production?
    assert_not choose(param: "production").outside_production?
    assert_not choose(param: "").outside_production?
    assert_equal "production", choose.production_environment
    assert_nil EnvironmentChoice.new(projects(:billing)).production_environment
  end

  private
    def choose(**options)
      EnvironmentChoice.new(@project, **options)
    end
end
