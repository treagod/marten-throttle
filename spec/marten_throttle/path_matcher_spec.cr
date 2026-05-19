require "../spec_helper"

describe MartenThrottle::PathMatcher do
  describe "#matches?" do
    it "matches exact string paths" do
      matcher = MartenThrottle::PathMatcher.new("/login")

      matcher.matches?("/login").should be_true
      matcher.matches?("/login/extra").should be_false
    end

    it "matches trailing-star prefixes" do
      matcher = MartenThrottle::PathMatcher.new("/api/*")

      matcher.matches?("/api/users").should be_true
      matcher.matches?("/api/").should be_true
      matcher.matches?("/api").should be_false
    end

    it "does not match near-prefix paths accidentally" do
      matcher = MartenThrottle::PathMatcher.new("/api/*")

      matcher.matches?("/apis/users").should be_false
      matcher.matches?("/api-v2/users").should be_false
    end

    it "matches regexes" do
      matcher = MartenThrottle::PathMatcher.new(/^\/admin/)

      matcher.matches?("/admin/users").should be_true
      matcher.matches?("/public/admin").should be_false
    end
  end
end
