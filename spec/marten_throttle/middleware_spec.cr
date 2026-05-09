require "../spec_helper"

private class FailingIncrementCacheStore < Marten::Cache::Store::Memory
  def increment(
    key : String,
    amount : Int32 = 1,
    expires_at : Time? = nil,
    expires_in : Time::Span? = nil,
    version : Int32? = nil,
    race_condition_ttl : Time::Span? = nil,
    compress : Bool? = nil,
    compress_threshold : Int32? = nil,
  ) : Int
    raise IO::Error.new("cache unavailable")
  end
end

private def call(middleware, request) : Marten::HTTP::Response
  middleware.call(request, -> : Marten::HTTP::Response { ok_response })
end

describe MartenThrottle::Middleware do
  describe "#call" do
    it "passes through when no rule or default policy matches" do
      middleware = MartenThrottle::Middleware.new

      10.times do
        call(middleware, make_request(path: "/unconfigured")).status.should eq(200)
      end
    end

    it "passes through under the default policy limit" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 5, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      response = call(middleware, make_request(path: "/passthrough"))

      response.status.should eq(200)
      response.content.should eq("ok")
    end

    it "returns 429 with Retry-After once the limit is exceeded" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 3, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      3.times { call(middleware, make_request(path: "/blocked")) }
      response = call(middleware, make_request(path: "/blocked"))

      response.status.should eq(429)
      response.content.should eq("Too many requests")
      response.headers["Retry-After"].should_not be_nil
      response.headers["X-RateLimit-Limit"].should eq("3")
    end

    it "uses one global bucket by default even when forwarded headers are present" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      first = make_request(path: "/global")
      first.headers["X-Forwarded-For"] = "192.0.2.1"
      second = make_request(path: "/global")
      second.headers["X-Forwarded-For"] = "192.0.2.2"

      call(middleware, first).status.should eq(200)
      call(middleware, second).status.should eq(429)
    end

    it "uses a configured client identifier to keep buckets independent" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      Marten.settings.throttle.client_identifier = ->(request : Marten::HTTP::Request) : String {
        request.headers["X-Client"]? || "missing"
      }
      middleware = MartenThrottle::Middleware.new

      first = make_request(path: "/custom-client")
      first.headers["X-Client"] = "client-a"
      second = make_request(path: "/custom-client")
      second.headers["X-Client"] = "client-b"

      call(middleware, first).status.should eq(200)
      call(middleware, second).status.should eq(200)
      call(middleware, first).status.should eq(429)
    end

    it "uses forwarded headers when explicitly trusted" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      Marten.settings.throttle.trust_forwarded_headers = true
      middleware = MartenThrottle::Middleware.new

      first = make_request(path: "/forwarded")
      first.headers["X-Forwarded-For"] = "192.0.2.1"
      second = make_request(path: "/forwarded")
      second.headers["X-Forwarded-For"] = "192.0.2.2"

      call(middleware, first).status.should eq(200)
      call(middleware, second).status.should eq(200)
      call(middleware, first).status.should eq(429)
    end

    it "applies a route-specific rule when its matcher matches" do
      Marten.settings.throttle.draw do
        rule("/login", limit: 2, per: 1.minute, methods: ["POST"])
      end
      middleware = MartenThrottle::Middleware.new

      call(middleware, make_request(method: "POST", path: "/login")).status.should eq(200)
      call(middleware, make_request(method: "POST", path: "/login")).status.should eq(200)
      call(middleware, make_request(method: "POST", path: "/login")).status.should eq(429)
    end

    it "skips a route-specific rule when methods do not match" do
      Marten.settings.throttle.draw do
        rule("/login", limit: 1, per: 1.minute, methods: ["POST"])
      end
      middleware = MartenThrottle::Middleware.new

      # GET is not POST, so the strict rule does not apply.
      5.times do
        call(middleware, make_request(method: "GET", path: "/login")).status.should eq(200)
      end
    end

    it "skips requests when the skip predicate matches" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      Marten.settings.throttle.skip_if = ->(request : Marten::HTTP::Request) : Bool {
        request.path == "/health"
      }
      Marten.settings.throttle.client_identifier = ->(_request : Marten::HTTP::Request) : String {
        raise "client identifier should not be resolved for skipped requests"
      }
      middleware = MartenThrottle::Middleware.new

      3.times do
        call(middleware, make_request(path: "/health")).status.should eq(200)
      end
    end

    it "skips requests when an exclusion matches" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      Marten.settings.throttle.draw do
        exclude("/assets/*")
        rule("/assets/*", limit: 1, per: 1.minute)
      end
      middleware = MartenThrottle::Middleware.new

      3.times do
        call(middleware, make_request(path: "/assets/app.css")).status.should eq(200)
      end
    end

    it "is a no-op when disabled" do
      Marten.settings.throttle.enabled = false
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      10.times do
        call(middleware, make_request(path: "/whatever")).status.should eq(200)
      end
    end

    it "supports the sliding_window strategy" do
      Marten.settings.throttle.default_strategy = :sliding_window
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 3, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      3.times { call(middleware, make_request(path: "/sw")).status.should eq(200) }
      call(middleware, make_request(path: "/sw")).status.should eq(429)
    end

    it "allows requests when the cache fails and fail_open is enabled" do
      Marten.settings.cache_store = FailingIncrementCacheStore.new
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      Log.capture(MartenThrottle::Log.source) do |logs|
        call(middleware, make_request(path: "/cache-down")).status.should eq(200)
        logs.check(:warn, /Throttle cache unavailable/)
      end
    end

    it "raises cache errors when fail_open is disabled" do
      Marten.settings.cache_store = FailingIncrementCacheStore.new
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      Marten.settings.throttle.fail_open = false
      middleware = MartenThrottle::Middleware.new

      expect_raises(IO::Error, "cache unavailable") do
        call(middleware, make_request(path: "/cache-down"))
      end
    end
  end
end
