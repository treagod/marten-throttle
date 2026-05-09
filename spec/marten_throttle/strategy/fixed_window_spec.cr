require "../../spec_helper"

describe MartenThrottle::FixedWindow do
  describe "#check" do
    it "allows up to the limit and blocks beyond it" do
      strategy = MartenThrottle::FixedWindow.new

      results = (1..6).map { strategy.check("test:fw:basic", limit: 5, window: 1.minute) }

      results[0..4].all?(&.allowed?).should be_true
      results[5].allowed?.should be_false
      results[5].count.should eq(6)
      results[5].limit.should eq(5)
    end

    it "tracks counters independently per key" do
      strategy = MartenThrottle::FixedWindow.new

      3.times { strategy.check("test:fw:k1", limit: 5, window: 1.minute) }
      result = strategy.check("test:fw:k2", limit: 5, window: 1.minute)

      result.count.should eq(1)
      result.allowed?.should be_true
    end

    it "returns a positive retry_after under the limit" do
      strategy = MartenThrottle::FixedWindow.new

      result = strategy.check("test:fw:retry", limit: 5, window: 1.minute)

      result.retry_after.should be > 0
      result.retry_after.should be <= 60
    end

    it "rejects invalid limits and windows" do
      strategy = MartenThrottle::FixedWindow.new

      expect_raises(ArgumentError, "Throttle limit must be greater than 0") do
        strategy.check("test:fw:invalid-limit", limit: 0, window: 1.minute)
      end

      expect_raises(ArgumentError, "Throttle window must be at least 1 second") do
        strategy.check("test:fw:invalid-window", limit: 1, window: 500.milliseconds)
      end
    end
  end
end
