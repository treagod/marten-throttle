require "../spec_helper"

describe MartenThrottle::Settings do
  describe "defaults" do
    it "exposes sensible defaults" do
      s = Marten.settings.throttle

      s.enabled?.should be_true
      s.default_policy.should be_nil
      s.default_strategy.should eq(MartenThrottle::Strategy::FixedWindow)
      s.fail_open?.should be_true
      s.cache_namespace.should eq("throttle")
      s.client_identifier.should be_nil
      s.skip_if.should be_nil
      s.exclusions.should be_empty
      s.rules.should be_empty
    end
  end

  describe "#draw" do
    it "yields self so a block can declare exclusions and rules" do
      Marten.settings.throttle.draw do
        exclude("/health")
        rule("/login", limit: 5, per: 1.minute, methods: ["POST"])
        rule("/api/*", limit: 30, per: 1.minute, strategy: MartenThrottle::Strategy::SlidingWindow)
      end

      s = Marten.settings.throttle
      s.exclusions.size.should eq(1)
      s.exclusions[0].matcher.should eq("/health")
      s.rules.size.should eq(2)
      s.rules[0].matcher.should eq("/login")
      s.rules[0].methods.should eq(["POST"])
      s.rules[1].strategy.should eq(MartenThrottle::Strategy::SlidingWindow)
    end
  end

  describe "#rule" do
    it "uppercases the methods filter" do
      Marten.settings.throttle.rule("/x", limit: 1, per: 1.minute, methods: ["post", "Get"])

      Marten.settings.throttle.rules.last.methods.should eq(["POST", "GET"])
    end

    it "rejects invalid rule limits" do
      expect_raises(ArgumentError, "Throttle limit must be greater than 0") do
        Marten.settings.throttle.rule("/x", limit: 0, per: 1.minute)
      end
    end

    it "rejects invalid rule windows" do
      expect_raises(ArgumentError, "Throttle window must be at least 1 second") do
        Marten.settings.throttle.rule("/x", limit: 1, per: 500.milliseconds)
      end
    end

    it "stores a per-rule identifier when provided" do
      proc = ->(request : Marten::HTTP::Request) : String { request.path }
      Marten.settings.throttle.rule("/x", limit: 1, per: 1.minute, identifier: proc)

      Marten.settings.throttle.rules.last.identifier.should eq(proc)
    end
  end

  describe "#exclude" do
    it "adds a path exclusion" do
      exclusion = Marten.settings.throttle.exclude("/assets/*")

      exclusion.matches?("/assets/app.css").should be_true
      Marten.settings.throttle.exclusions.last.should eq(exclusion)
    end
  end
end
