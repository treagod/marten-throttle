module MartenThrottle
  abstract class Strategy
    abstract def check(key : String, limit : Int32, window : Time::Span) : Result

    class_getter fixed_window : FixedWindow { FixedWindow.new }
    class_getter sliding_window : SlidingWindow { SlidingWindow.new }

    def self.validate_name!(name : Symbol) : Nil
      return if valid_name?(name)

      raise ArgumentError.new("Unknown throttle strategy: #{name.inspect}")
    end

    def self.valid_name?(name : Symbol) : Bool
      case name
      when :fixed_window, :sliding_window
        true
      else
        false
      end
    end

    def self.for(name : Symbol) : Strategy
      case name
      when :fixed_window
        fixed_window
      when :sliding_window
        sliding_window
      else
        raise ArgumentError.new("Unknown throttle strategy: #{name.inspect}")
      end
    end

    private def validate_arguments!(limit : Int32, window : Time::Span) : Nil
      Settings.validate_limit!(limit)
      Settings.validate_window!(window)
    end
  end
end
