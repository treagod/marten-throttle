module MartenThrottle
  # Limit/window pair used by the opt-in default throttle policy.
  struct Policy
    getter limit : Int32
    getter window : Time::Span

    def initialize(*, limit : Int32, per : Time::Span) : Nil
      @limit = limit
      @window = per
      validate!
    end

    def initialize(*, limit : Int32, window : Time::Span) : Nil
      @limit = limit
      @window = window
      validate!
    end

    def initialize(@limit : Int32, @window : Time::Span) : Nil
      validate!
    end

    private def validate! : Nil
      Settings.validate_limit!(@limit)
      Settings.validate_window!(@window)
    end
  end
end
