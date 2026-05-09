require "../spec_helper"

describe MartenThrottle::Policy do
  describe "#initialize" do
    it "sets the limit and window from a per argument" do
      policy = MartenThrottle::Policy.new(limit: 10, per: 1.minute)

      policy.limit.should eq(10)
      policy.window.should eq(1.minute)
    end

    it "sets the limit and window from a window argument" do
      policy = MartenThrottle::Policy.new(limit: 10, window: 2.minutes)

      policy.limit.should eq(10)
      policy.window.should eq(2.minutes)
    end

    it "rejects non-positive limits" do
      expect_raises(ArgumentError, "Throttle limit must be greater than 0") do
        MartenThrottle::Policy.new(limit: 0, per: 1.minute)
      end
    end

    it "rejects windows shorter than one second" do
      expect_raises(ArgumentError, "Throttle window must be at least 1 second") do
        MartenThrottle::Policy.new(limit: 1, per: 500.milliseconds)
      end
    end
  end
end
