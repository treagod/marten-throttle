module MartenThrottle
  # Raised when a throttle strategy cannot read from or write to the configured cache backend.
  class CacheUnavailableError < Exception
  end
end
