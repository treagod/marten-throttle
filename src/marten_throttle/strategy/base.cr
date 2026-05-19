module MartenThrottle
  abstract class Strategy
    FixedWindow   = StrategyName::FixedWindow
    SlidingWindow = StrategyName::SlidingWindow

    abstract def check(key : String, limit : Int32, window : Time::Span) : Result

    class_getter fixed_window : ::MartenThrottle::FixedWindow { ::MartenThrottle::FixedWindow.new }
    class_getter sliding_window : ::MartenThrottle::SlidingWindow { ::MartenThrottle::SlidingWindow.new }

    def self.for(name : StrategyName) : Strategy
      case name
      when FixedWindow
        fixed_window
      when SlidingWindow
        sliding_window
      else
        raise ArgumentError.new("Unknown throttle strategy: #{name}")
      end
    end

    private def validate_arguments!(limit : Int32, window : Time::Span) : Nil
      Settings.validate_limit!(limit)
      Settings.validate_window!(window)
    end

    private def increment_cache(key : String, expires_in : Time::Span) : Int
      Marten.cache.increment(key, expires_in: expires_in)
    rescue ex
      raise CacheUnavailableError.new("Throttle cache unavailable", cause: ex)
    end

    private def read_cache(key : String) : String?
      Marten.cache.read(key)
    rescue ex
      raise CacheUnavailableError.new("Throttle cache unavailable", cause: ex)
    end
  end
end
