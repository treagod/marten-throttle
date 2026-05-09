require "../../spec_helper"

describe MartenThrottle::SlidingWindow do
  describe "#check" do
    it "allows up to the limit within a window" do
      strategy = MartenThrottle::SlidingWindow.new

      results = (1..5).map { strategy.check("test:sw:basic", limit: 5, window: 1.minute) }

      results.all?(&.allowed?).should be_true
      results.last.count.should eq(5)
    end

    it "blocks once the effective count exceeds the limit" do
      strategy = MartenThrottle::SlidingWindow.new

      6.times { strategy.check("test:sw:over", limit: 5, window: 1.minute) }
      final = strategy.check("test:sw:over", limit: 5, window: 1.minute)

      final.allowed?.should be_false
      final.count.should be >= 5
    end

    it "tracks separate counters per key" do
      strategy = MartenThrottle::SlidingWindow.new

      3.times { strategy.check("test:sw:a", limit: 5, window: 1.minute) }
      r = strategy.check("test:sw:b", limit: 5, window: 1.minute)

      r.allowed?.should be_true
      r.count.should eq(1)
    end

    it "rounds fractional effective counts up for reporting" do
      strategy = MartenThrottle::SlidingWindow.new
      key = "test:sw:fractional"
      window = 1.hour
      window_seconds = window.total_seconds.to_i
      now = Time.utc.to_unix
      prev_bucket = (now // window_seconds) - 1
      offset = now % window_seconds
      prev_count = 997

      Marten.cache.write("#{key}:sw:#{prev_bucket}", prev_count.to_s, expires_in: window)

      result = strategy.check(key, limit: 10_000, window: window)

      weight = 1.0 - (offset.to_f / window_seconds.to_f)
      expected_count = ((prev_count * weight) + 1).ceil.to_i
      result.count.should be_close(expected_count, 1)
    end

    it "rejects invalid limits and windows" do
      strategy = MartenThrottle::SlidingWindow.new

      expect_raises(ArgumentError, "Throttle limit must be greater than 0") do
        strategy.check("test:sw:invalid-limit", limit: 0, window: 1.minute)
      end

      expect_raises(ArgumentError, "Throttle window must be at least 1 second") do
        strategy.check("test:sw:invalid-window", limit: 1, window: 500.milliseconds)
      end
    end
  end
end
