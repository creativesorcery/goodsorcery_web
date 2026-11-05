require "test_helper"

class Apm::LayerSentenceTest < ActiveSupport::TestCase
  Bar = Apm::EndpointReport::Bar

  test "the same layer around p95 and p99, and typical requests waiting elsewhere" do
    bars = [ bar(:average, db: 70, http: 160, view: 62, ruby: 48), bar(95, db: 610, http: 420, view: 120, ruby: 90),
             bar(99, db: 1800, http: 1050, view: 200, ruby: 150) ]
    assert_equal "Around p95 and p99, the database takes the most time (49% and 56%). Typical requests mostly wait on external HTTP.",
      sentence(bars)
  end

  test "different layers, and typical runs in Ruby or the same layer" do
    bars = [ bar(:average, db: 1, http: 1, view: 1, ruby: 9), bar(95, db: 6, http: 4, view: 0, ruby: 0), bar(99, db: 2, http: 8, view: 0, ruby: 0) ]
    assert_equal "Around p95, the database takes the most time (60%); around p99, external HTTP does (80%). " \
      "Typical runs spend most of their time in Ruby.", sentence(bars, noun: "runs")

    same = [ bar(:average, db: 9, http: 1, view: 0, ruby: 0), bar(95, db: 9, http: 1, view: 0, ruby: 0), bar(99, db: 9, http: 1, view: 0, ruby: 0) ]
    assert_match(/Typical requests spend most of their time there too\.\z/, sentence(same))
  end

  test "nothing without the bars" do
    assert_nil sentence([])
  end

  private
    def bar(key, **split) = Bar.new(key:, label: key.to_s, value: split.values.sum.to_f, split: split.transform_values(&:to_f))

    def sentence(bars, noun: "requests") = Apm::LayerSentence.new(bars, noun:).sentence
end
