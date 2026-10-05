require "test_helper"

class Ingest::PathNormalizerTest < ActiveSupport::TestCase
  setup { @normalizer = Ingest::PathNormalizer.new }

  test "normalises gem paths" do
    assert_equal "gems/activerecord-8.0.1/lib/active_record/relation.rb",
                 @normalizer.normalize("/usr/local/bundle/ruby/3.4.0/gems/activerecord-8.0.1/lib/active_record/relation.rb")
    assert_equal "gems/rails-1a2b3c4d5e6f/activerecord/lib/x.rb",
                 @normalizer.normalize("/home/deploy/.bundle/bundler/gems/rails-1a2b3c4d5e6f/activerecord/lib/x.rb")
    assert_equal "gems/rack-3.1.8/lib/rack.rb", @normalizer.normalize("gems/rack-3.1.8/lib/rack.rb")
  end

  test "strips deploy roots to app-relative paths" do
    assert_equal "app/models/order.rb", @normalizer.normalize("/srv/shop/releases/20261004/app/models/order.rb")
    assert_equal "app/models/order.rb", @normalizer.normalize("/var/www/shop/current/app/models/order.rb")
    assert_equal "app/models/order.rb", @normalizer.normalize("/rails/app/models/order.rb")
    assert_equal "lib/tasks/x.rake", @normalizer.normalize("/app/lib/tasks/x.rake")
    assert_equal "app/models/order.rb", @normalizer.normalize("/Users/mara/code/shop/app/models/order.rb")
  end

  test "rewrites ruby stdlib and home directories without personal names" do
    assert_equal "ruby/3.4.0/monitor.rb", @normalizer.normalize("/home/mara/.rbenv/versions/3.4.1/lib/ruby/3.4.0/monitor.rb")
    assert_equal "~/scripts/run.rb", @normalizer.normalize("/home/mara/scripts/run.rb")
    assert_equal "~/run.rb", @normalizer.normalize("/Users/mara/run.rb")
  end

  test "leaves relative and unknown paths alone" do
    assert_equal "app/models/order.rb", @normalizer.normalize("app/models/order.rb")
    assert_equal "/usr/bin/env", @normalizer.normalize("/usr/bin/env")
    assert_equal "", @normalizer.normalize(nil)
  end
end
