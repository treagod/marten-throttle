module MartenThrottle
  # Rate-limiting middleware.
  #
  # Skip requests first, pick the first rule whose matcher accepts the request, then fall back to
  # an explicitly configured default policy. On rejection, returns 429 with `Retry-After` and
  # `X-RateLimit-Limit` headers.
  class Middleware < Marten::Middleware
    GLOBAL_CLIENT = "global"

    def call(
      request : Marten::HTTP::Request,
      get_response : Proc(Marten::HTTP::Response),
    ) : Marten::HTTP::Response
      settings = Marten.settings.throttle
      return get_response.call unless settings.enabled?
      return get_response.call if skipped?(request, settings)

      rule_idx = settings.rules.index(&.matches?(request))
      rule = rule_idx ? settings.rules[rule_idx] : nil
      policy = rule || settings.default_policy
      return get_response.call if policy.nil?

      limit = policy.limit
      window = policy.window
      strategy_name = rule.try(&.strategy) || settings.default_strategy

      client = client_identifier(request, settings)
      scope = rule_idx ? "r#{rule_idx}" : "d"
      key = "#{settings.cache_namespace}:#{scope}:#{client}"

      result = begin
        Strategy.for(strategy_name).check(key, limit, window)
      rescue ex
        raise ex unless settings.fail_open?

        Log.warn(exception: ex) { "Throttle cache unavailable; allowing request" }
        return get_response.call
      end

      return get_response.call if result.allowed?

      response = Marten::HTTP::Response.new(
        content: "Too many requests",
        content_type: "text/plain",
        status: 429,
      )
      response.headers["Retry-After"] = result.retry_after.to_s
      response.headers["X-RateLimit-Limit"] = limit.to_s
      response
    end

    private def skipped?(request : Marten::HTTP::Request, settings) : Bool
      if predicate = settings.skip_if
        return true if predicate.call(request)
      end

      settings.exclusions.any?(&.matches?(request.path))
    end

    # Resolves the client identifier used for the throttle bucket.
    #
    # Applications can provide `client_identifier` to key limits by their own user/session/IP
    # semantics. If no custom identifier is configured, this uses a single global bucket unless
    # `trust_forwarded_headers` is enabled.
    #
    # When `trust_forwarded_headers` is enabled, reads `X-Forwarded-For` (first hop) then
    # `X-Real-IP`. Otherwise — and as a fallback — every request shares one global bucket.
    # The "trust" toggle exists because Marten does not currently expose the peer connection
    # address: trusting these headers without a proxy in front lets clients trivially shard
    # themselves into separate buckets by sending arbitrary values.
    private def client_identifier(request : Marten::HTTP::Request, settings) : String
      if identifier = settings.client_identifier.try(&.call(request))
        return normalize_identifier(identifier)
      end

      return GLOBAL_CLIENT unless settings.trust_forwarded_headers?

      if (xff = request.headers[:"X-Forwarded-For"]?) && !xff.empty?
        return normalize_identifier(xff.split(',', 2).first)
      end
      if (real = request.headers[:"X-Real-IP"]?) && !real.empty?
        return normalize_identifier(real)
      end
      GLOBAL_CLIENT
    end

    private def normalize_identifier(identifier : String) : String
      normalized = identifier.strip
      normalized.empty? ? GLOBAL_CLIENT : normalized
    end
  end
end
