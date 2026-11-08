require "test_helper"

class RuntimeListTest < ActiveSupport::TestCase
  test "the list form keeps the client's names and order" do
    list = RuntimeList.new([ { "name" => "Rust", "version" => "1.82.0" }, { "name" => "axum", "version" => "0.8.1" } ])

    assert_equal "Rust 1.82 · axum 0.8", list.label
    assert_equal "Rust 1.82.0 · axum 0.8.1", list.full_label
    assert_equal [ { "name" => "Rust", "version" => "1.82.0" }, { "name" => "axum", "version" => "0.8.1" } ], list.to_a
  end

  test "the older object form labels Rails before Ruby" do
    list = RuntimeList.new({ "ruby" => "3.4.1 (YJIT on)", "rails" => "8.0.1" })

    assert_equal "Rails 8.0 · Ruby 3.4", list.label
    assert_equal [ { "name" => "Rails", "version" => "8.0.1" }, { "name" => "Ruby", "version" => "3.4.1 (YJIT on)" } ], list.to_a
    assert_equal "Ruby 3.4", RuntimeList.new({ "ruby" => "3.4.1" }).label
  end

  test "the older object form skips keys without a version" do
    list = RuntimeList.new({ "ruby" => "3.4.1", "rails" => nil })

    assert_equal "Ruby 3.4.1", list.full_label
    assert_equal "Ruby 3.4", list.label
    assert_equal [ { "name" => "Ruby", "version" => "3.4.1" } ], list.to_a
    assert_equal "Ruby 3.4.1", RuntimeList.new({ "rails" => " ", "ruby" => "3.4.1" }).full_label
  end

  test "an object with other keys reads them as names" do
    assert_equal "Node.js 22.11 · express 4.21", RuntimeList.new({ "Node.js" => "22.11.0", "express" => "4.21.1" }).label
  end

  test "versions need a leading number for the label; a bare major counts" do
    assert_nil RuntimeList.new({ "ruby" => "head" }).label
    assert_equal "Ruby head", RuntimeList.new({ "ruby" => "head" }).full_label
    assert_equal "Go 1.23", RuntimeList.new([ { "name" => "Go", "version" => "1.23.2" }, { "name" => "Go", "version" => "1.22" } ]).label
    assert_equal "Node.js 22", RuntimeList.new([ { "name" => "Node.js", "version" => "v22" } ]).label
    assert_equal "Erlang/OTP 27", RuntimeList.new([ { "name" => "Erlang/OTP", "version" => 27 } ]).label
  end

  test "names outside the short display alphabet are dropped" do
    list = RuntimeList.new([ { "name" => "mara@example.com", "version" => "1.0" }, { "name" => "x" * 33, "version" => "1.0" },
                             { "name" => nil, "version" => "1.0" }, { "name" => "C#", "version" => "12.0" }, "Rust" ])

    assert_equal [ "C#" ], list.entries.map(&:name)
  end

  test "bounds entries, versions and the label" do
    list = RuntimeList.new(Array.new(12) { |i| { "name" => "lib#{i}", "version" => "1.#{i}" } })

    assert_equal 10, list.entries.size
    assert_equal "lib0 1.0 · lib1 1.1 · lib2 1.2", list.label
    assert_equal 64, RuntimeList.new([ { "name" => "Rust", "version" => "1" * 100 } ]).entries.first.version.size
  end

  test "anything else is empty" do
    [ nil, "Rust 1.82", 42, [] ].each do |value|
      assert_predicate RuntimeList.new(value), :empty?
      assert_nil RuntimeList.new(value).label
    end
  end
end
