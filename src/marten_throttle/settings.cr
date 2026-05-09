module MartenThrottle
  # Configuration namespace for marten-throttle.
  #
  # Accessed via `Marten.settings.throttle`. Per-route rules and path exclusions are declared
  # inside a `#draw` block; unmatched requests are throttled only when `default_policy` is set:
  #
  # ```
  # Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 100, per: 1.minute)
  #
  # Marten.settings.throttle.draw do
  #   exclude "/health"
  #   rule "/login", limit: 5, per: 1.minute, methods: ["POST"]
  # end
  # ```
  class Settings < Marten::Conf::Settings
    alias ClientIdentifier = Proc(Marten::HTTP::Request, String)
    alias SkipPredicate = Proc(Marten::HTTP::Request, Bool)

    namespace(:throttle)

    property? enabled : Bool = true
    property default_policy : Policy? = nil
    getter default_strategy : Symbol = :fixed_window
    property? fail_open : Bool = true
    property cache_namespace : String = "throttle"
    property? trust_forwarded_headers : Bool = false
    property client_identifier : ClientIdentifier? = nil
    property skip_if : SkipPredicate? = nil
    property exclusions : Array(PathMatcher) = Array(PathMatcher).new
    property rules : Array(Rule) = Array(Rule).new

    def default_strategy=(strategy : Symbol) : Symbol
      Strategy.validate_name!(strategy)
      @default_strategy = strategy
    end

    def draw(&) : Nil
      with self yield self
      nil
    end

    def rule(
      matcher : Rule::Matcher,
      limit : Int32,
      per : Time::Span,
      strategy : Symbol = default_strategy,
      methods : Array(String)? = nil,
    ) : Rule
      r = Rule.new(matcher: matcher, limit: limit, window: per, strategy: strategy, methods: methods)
      @rules << r
      r
    end

    def exclude(matcher : PathMatcher::Matcher) : PathMatcher
      exclusion = PathMatcher.new(matcher)
      @exclusions << exclusion
      exclusion
    end

    def self.validate_limit!(limit : Int32) : Nil
      return if limit > 0

      raise ArgumentError.new("Throttle limit must be greater than 0")
    end

    def self.validate_window!(window : Time::Span) : Nil
      return if window.total_seconds >= 1

      raise ArgumentError.new("Throttle window must be at least 1 second")
    end
  end
end
