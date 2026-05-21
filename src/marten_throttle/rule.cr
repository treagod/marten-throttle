module MartenThrottle
  # A per-route throttle policy. Stored in `Marten.settings.throttle.rules` and matched in
  # declaration order against incoming requests.
  struct Rule
    alias Matcher = PathMatcher::Matcher

    getter matcher : Matcher
    getter limit : Int32
    getter window : Time::Span
    getter strategy : StrategyName
    getter methods : Array(String)?
    getter identifier : Settings::ClientIdentifier?

    def initialize(
      @matcher : Matcher,
      @limit : Int32,
      @window : Time::Span,
      @strategy : StrategyName = Strategy::FixedWindow,
      methods : Array(String)? = nil,
      @identifier : Settings::ClientIdentifier? = nil,
    ) : Nil
      Settings.validate_limit!(@limit)
      Settings.validate_window!(@window)

      @methods = methods.try(&.map(&.upcase))
      @path_matcher = PathMatcher.new(@matcher)
    end

    @path_matcher : PathMatcher

    def matches?(request : Marten::HTTP::Request) : Bool
      return false unless method_matches?(request.method)
      path_matches?(request.path)
    end

    private def method_matches?(method : String) : Bool
      ms = @methods
      return true if ms.nil?
      ms.includes?(method)
    end

    private def path_matches?(path : String) : Bool
      @path_matcher.matches?(path)
    end
  end
end
