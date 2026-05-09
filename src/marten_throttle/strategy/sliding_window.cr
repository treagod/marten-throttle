module MartenThrottle
  # Sliding-window counter (two-bucket weighted variant).
  #
  # The window is divided into fixed buckets of length `window`. For each request we increment the
  # current bucket and combine it with a fractional weight of the previous bucket — the fraction
  # of the previous bucket that still falls inside the rolling window ending "now".
  #
  # `effective = (prev_count * weight) + curr_count` where
  # `weight = 1.0 - (now_in_bucket / window_seconds)`.
  #
  # One cache `read` + one `increment` per request. Smooths out the boundary bursts that a strict
  # fixed-window has, at the cost of one extra cache read.
  class SlidingWindow < Strategy
    def check(key : String, limit : Int32, window : Time::Span) : Result
      validate_arguments!(limit, window)

      window_seconds = window.total_seconds.to_i
      now = Time.utc.to_unix
      curr_bucket = now // window_seconds
      prev_bucket = curr_bucket - 1
      offset = now % window_seconds

      prev_key = "#{key}:sw:#{prev_bucket}"
      curr_key = "#{key}:sw:#{curr_bucket}"

      prev_count = (Marten.cache.read(prev_key).try(&.to_i?)) || 0
      curr_count = Marten.cache.increment(curr_key, expires_in: window * 2).to_i

      weight = 1.0 - (offset.to_f / window_seconds.to_f)
      effective = (prev_count * weight) + curr_count

      retry_after = window_seconds - offset
      Result.new(
        allowed: effective <= limit,
        count: effective.ceil.to_i,
        limit: limit,
        retry_after: retry_after.to_i
      )
    end
  end
end
