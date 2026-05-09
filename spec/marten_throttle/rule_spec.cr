require "../spec_helper"

describe MartenThrottle::Rule do
  describe "#matches?" do
    it "matches an exact string path" do
      rule = MartenThrottle::Rule.new(matcher: "/login", limit: 5, window: 1.minute)

      rule.matches?(make_request(path: "/login")).should be_true
      rule.matches?(make_request(path: "/login/extra")).should be_false
    end

    it "matches a string prefix matcher with a trailing *" do
      rule = MartenThrottle::Rule.new(matcher: "/api/*", limit: 5, window: 1.minute)

      rule.matches?(make_request(path: "/api/users")).should be_true
      rule.matches?(make_request(path: "/api/")).should be_true
      rule.matches?(make_request(path: "/api")).should be_false
      rule.matches?(make_request(path: "/other")).should be_false
    end

    it "matches a regex" do
      rule = MartenThrottle::Rule.new(matcher: /^\/admin/, limit: 5, window: 1.minute)

      rule.matches?(make_request(path: "/admin/users")).should be_true
      rule.matches?(make_request(path: "/public")).should be_false
    end

    it "filters by HTTP method when methods is set" do
      rule = MartenThrottle::Rule.new(
        matcher: "/login",
        limit: 5,
        window: 1.minute,
        methods: ["POST"]
      )

      rule.matches?(make_request(method: "POST", path: "/login")).should be_true
      rule.matches?(make_request(method: "GET", path: "/login")).should be_false
    end

    it "matches any method when methods is nil" do
      rule = MartenThrottle::Rule.new(matcher: "/login", limit: 5, window: 1.minute)

      rule.matches?(make_request(method: "GET", path: "/login")).should be_true
      rule.matches?(make_request(method: "POST", path: "/login")).should be_true
    end
  end
end
