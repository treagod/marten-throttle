module MartenThrottle
  # Fixed-window counter. One bucket per `window`, identified by `floor(now / window)`.
  # Allows up to `limit` requests per bucket; a single client can therefore burst up to `2 * limit`
  # at the boundary between two buckets. Cheap: one cache increment per request.
  class FixedWindow < Strategy
    def check(key : String, limit : Int32, window : Time::Span) : Result
      validate_arguments!(limit, window)

      window_seconds = window.total_seconds.to_i
      now = Time.utc.to_unix
      bucket = now // window_seconds
      bucket_key = "#{key}:fw:#{bucket}"

      count = increment_cache(bucket_key, expires_in: window).to_i

      retry_after = window_seconds - (now % window_seconds)
      Result.new(allowed: count <= limit, count: count, limit: limit, retry_after: retry_after.to_i)
    end
  end
end
