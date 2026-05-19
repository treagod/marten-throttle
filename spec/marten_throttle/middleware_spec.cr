require "../spec_helper"

private class MiddlewareFailingIncrementCacheStore < Marten::Cache::Store::Memory
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

private class MiddlewareRecordingCacheStore < Marten::Cache::Store::Memory
  getter increment_keys = Array(String).new

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
    @increment_keys << key
    super
  end
end

private def call(middleware, request) : Marten::HTTP::Response
  middleware.call(request, -> : Marten::HTTP::Response { ok_response })
end

private def expect_rate_limit_headers(response, limit : Int32, remaining : Int32) : Nil
  response.headers["RateLimit-Limit"].should eq(limit.to_s)
  response.headers["RateLimit-Remaining"].should eq(remaining.to_s)
  response.headers["RateLimit-Reset"]?.should_not be_nil
  response.headers["X-RateLimit-Limit"].should eq(limit.to_s)
  response.headers["X-RateLimit-Remaining"].should eq(remaining.to_s)
  response.headers["X-RateLimit-Reset"]?.should_not be_nil
end

private def expect_no_rate_limit_headers(response) : Nil
  response.headers["RateLimit-Limit"]?.should be_nil
  response.headers["RateLimit-Remaining"]?.should be_nil
  response.headers["RateLimit-Reset"]?.should be_nil
  response.headers["X-RateLimit-Limit"]?.should be_nil
  response.headers["X-RateLimit-Remaining"]?.should be_nil
  response.headers["X-RateLimit-Reset"]?.should be_nil
end

describe MartenThrottle::Middleware do
  describe "#call" do
    it "passes through when no rule or default policy matches" do
      middleware = MartenThrottle::Middleware.new

      response = call(middleware, make_request(path: "/unconfigured"))

      response.status.should eq(200)
      expect_no_rate_limit_headers(response)
    end

    it "passes through under the default policy limit with rate limit headers" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 5, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      response = call(middleware, make_request(path: "/passthrough"))

      response.status.should eq(200)
      response.content.should eq("ok")
      expect_rate_limit_headers(response, limit: 5, remaining: 4)
      response.headers["Retry-After"]?.should be_nil
    end

    it "returns 429 with Retry-After once the limit is exceeded" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 3, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      3.times { call(middleware, make_request(path: "/blocked")) }
      response = call(middleware, make_request(path: "/blocked"))

      response.status.should eq(429)
      response.content.should eq("Too many requests")
      response.headers["Retry-After"].should_not be_nil
      expect_rate_limit_headers(response, limit: 3, remaining: 0)
    end

    it "hashes the client identifier before using it in a cache key" do
      store = MiddlewareRecordingCacheStore.new
      Marten.settings.cache_store = store
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 5, per: 1.minute)
      raw_client = "user@example.com with spaces / api-key"
      Marten.settings.throttle.client_identifier = ->(_request : Marten::HTTP::Request) : String {
        raw_client
      }
      middleware = MartenThrottle::Middleware.new

      call(middleware, make_request(path: "/hashed-key")).status.should eq(200)

      key = store.increment_keys.first
      digest = Digest::SHA256.hexdigest(raw_client)
      key.includes?("throttle:d:#{digest}:fw:").should be_true
      key.includes?(raw_client).should be_false
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

      response = call(middleware, make_request(path: "/health"))

      response.status.should eq(200)
      expect_no_rate_limit_headers(response)
    end

    it "skips requests when an exclusion matches" do
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      Marten.settings.throttle.draw do
        exclude("/assets/*")
        rule("/assets/*", limit: 1, per: 1.minute)
      end
      middleware = MartenThrottle::Middleware.new

      response = call(middleware, make_request(path: "/assets/app.css"))

      response.status.should eq(200)
      expect_no_rate_limit_headers(response)
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
      Marten.settings.throttle.default_strategy = MartenThrottle::Strategy::SlidingWindow
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 3, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      3.times { call(middleware, make_request(path: "/sw")).status.should eq(200) }
      call(middleware, make_request(path: "/sw")).status.should eq(429)
    end

    it "allows requests when the cache fails and fail_open is enabled" do
      Marten.settings.cache_store = MiddlewareFailingIncrementCacheStore.new
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      middleware = MartenThrottle::Middleware.new

      Log.capture(MartenThrottle::Log.source) do |logs|
        response = call(middleware, make_request(path: "/cache-down"))

        response.status.should eq(200)
        expect_no_rate_limit_headers(response)
        logs.check(:warn, /Throttle cache unavailable/)
      end
    end

    it "raises cache errors when fail_open is disabled" do
      Marten.settings.cache_store = MiddlewareFailingIncrementCacheStore.new
      Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 1, per: 1.minute)
      Marten.settings.throttle.fail_open = false
      middleware = MartenThrottle::Middleware.new

      expect_raises(MartenThrottle::CacheUnavailableError, "Throttle cache unavailable") do
        call(middleware, make_request(path: "/cache-down"))
      end
    end
  end
end
