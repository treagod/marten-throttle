ENV["MARTEN_ENV"] = "test"

require "spec"
require "log/spec"

require "marten"
require "marten/spec"
require "sqlite3"

require "../src/marten_throttle"
require "./test_project"

Spec.before_each do
  Marten.settings.cache_store = Marten::Cache::Store::Memory.new
  Marten.cache.clear
  Marten.settings.throttle.enabled = true
  Marten.settings.throttle.default_policy = nil
  Marten.settings.throttle.default_strategy = :fixed_window
  Marten.settings.throttle.fail_open = true
  Marten.settings.throttle.cache_namespace = "throttle"
  Marten.settings.throttle.trust_forwarded_headers = false
  Marten.settings.throttle.client_identifier = nil
  Marten.settings.throttle.skip_if = nil
  Marten.settings.throttle.exclusions = Array(MartenThrottle::PathMatcher).new
  Marten.settings.throttle.rules = Array(MartenThrottle::Rule).new
end

def make_request(method : String = "GET", path : String = "/ping") : Marten::HTTP::Request
  Marten::HTTP::Request.new(
    ::HTTP::Request.new(
      method: method,
      resource: path,
      headers: HTTP::Headers{"Host" => "example.com"},
    )
  )
end

def ok_response : Marten::HTTP::Response
  Marten::HTTP::Response.new("ok", content_type: "text/plain", status: 200)
end
