module MartenThrottle
  # Path matcher shared by throttle rules and exclusions.
  struct PathMatcher
    alias Matcher = String | Regex

    getter matcher : Matcher

    def initialize(@matcher : Matcher) : Nil
      @prefix = nil

      case m = @matcher
      in String
        @prefix = m.rchop('*') if m.ends_with?('*')
      in Regex
        # Regex matchers do not need preprocessing.
      end
    end

    @prefix : String?

    def matches?(path : String) : Bool
      case m = @matcher
      in Regex
        m.matches?(path)
      in String
        if pfx = @prefix
          path.starts_with?(pfx)
        else
          path == m
        end
      end
    end
  end
end
