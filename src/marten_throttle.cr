require "digest/sha256"
require "marten"

module MartenThrottle
  Log = ::Log.for(self)
end

require "./marten_throttle/result"
require "./marten_throttle/errors"
require "./marten_throttle/strategy_name"
require "./marten_throttle/strategy/base"
require "./marten_throttle/strategy/fixed_window"
require "./marten_throttle/strategy/sliding_window"
require "./marten_throttle/path_matcher"
require "./marten_throttle/rule"
require "./marten_throttle/policy"
require "./marten_throttle/settings"
require "./marten_throttle/middleware"
require "./marten_throttle/app"

module MartenThrottle
  VERSION = "0.1.0"
end
