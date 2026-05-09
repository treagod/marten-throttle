# marten-throttle

Rate-limiting middleware for the [Marten](https://martenframework.com) web framework. It plugs into `Marten::Middleware` and stores counters in `Marten.cache`. In multi-process deployments the cache needs to be a shared backend, otherwise counters drift between workers and the limit silently stops working.

Two strategies are included:

- `:fixed_window` performs one cache increment per request. Cheap, accurate to within a window boundary. The downside is that a client can spend its full budget at the end of one window and again at the start of the next, producing short bursts at the seam.
- `:sliding_window` keeps two buckets (current and previous) and weights the previous count by how far into the new window the request falls. Smoother behavior, slightly more cache traffic.

## Installation

Add the dependency to `shard.yml`:

```yaml
dependencies:
  marten_throttle:
    github: treagod/marten-throttle
```

Then run `shards install`.

## Setup

Require the shard in `src/project.cr`:

```crystal
require "marten_throttle"
```

Register the app and add the middleware in `config/settings/base.cr`:

```crystal
config.installed_apps = [
  # ...
  MartenThrottle::App,
]

config.middleware = [
  MartenThrottle::Middleware,
  # Other middlewares...
]
```

Place the throttle middleware early in the chain so blocked requests short-circuit before more expensive middlewares run. If a per-client identifier depends on session or auth state, place it after the middlewares that produce that state.

Per-route rules go into a `draw` block. Rules are checked top to bottom, first match wins. If nothing matches, the request passes through unless you configure an opt-in default policy.

```crystal
Marten.settings.throttle.draw do
  rule "/login", limit: 5, per: 1.minute, strategy: :sliding_window, methods: ["POST"]
  rule "/api/*", limit: 30, per: 1.minute
  rule %r{^/admin}, limit: 10, per: 1.minute
end
```

To throttle otherwise unmatched requests, configure `default_policy`:

```crystal
Marten.settings.throttle.default_policy = MartenThrottle::Policy.new(limit: 100, per: 1.minute)
Marten.settings.throttle.default_strategy = :fixed_window
```

`default_strategy` is also the strategy used by rules that do not pass an explicit `strategy`.

When a request crosses its limit, the middleware short-circuits with a `429 Too Many Requests` response and sets `Retry-After` and `X-RateLimit-Limit` headers.

## The `rule` API

`rule(matcher, limit, per, strategy = default_strategy, methods = nil)`:

- `matcher` is a `String` or `Regex`. Strings match exactly; a trailing `*` makes it a prefix match (`"/api/*"` covers `/api/users/1`, `/api/orders/3`, and so on).
- `limit` is an `Int32` and must be greater than zero.
- `per` is a `Time::Span`. Anything below one second is rejected.
- `strategy` is `:fixed_window` or `:sliding_window`.
- `methods`, if set, restricts the rule to those HTTP methods. Case-insensitive.

A rule defines one bucket, not one bucket per concrete path. `/api/users/1` and `/api/users/42` share the same `/api/*` bucket. To count them separately, write separate rules or fold the path into the client identifier.

## Skipping requests

Skips short-circuit before client identification and cache access. They take precedence over rules and the default policy.

Use `skip_if` for programmatic bypasses:

```crystal
Marten.settings.throttle.skip_if = ->(request : Marten::HTTP::Request) {
  request.path.starts_with?("/internal/") || request.path == "/health"
}
```

Use `exclude` in the `draw` block for simple path patterns. The matcher syntax is the same as `rule`: exact strings, trailing-`*` prefixes, and regexes.

```crystal
Marten.settings.throttle.draw do
  exclude "/assets/*"
  exclude "/health"
  rule "/api/*", limit: 30, per: 1.minute
end
```

## Identifying clients

By default every throttled request lands in the same `"global"` bucket per rule or default policy. That makes the middleware a global limiter rather than a per-client one. It is the safe default because the alternative, trusting a header that any client can set, would let callers shard themselves into their own buckets and trivially defeat the limit.

For per-client throttling, point `client_identifier` at something stable that the application controls:

```crystal
Marten.settings.throttle.client_identifier = ->(request : Marten::HTTP::Request) {
  request.headers["X-Verified-Client-ID"]? || "global"
}
```

Good identifiers are things like an authenticated user ID, an API key ID, a tenant ID, or an IP address that a trusted proxy has written into the header. Anything a public client can set directly is a bad identifier. Empty values fall back to `"global"`.

Marten does not expose the peer connection address on the request, so IP-based identification has to come from a header. With a proxy or load balancer in front of the app that overwrites client-supplied forwarding headers, this can be enabled explicitly:

```crystal
Marten.settings.throttle.trust_forwarded_headers = true
```

Without that flag and without a custom identifier, every throttled request shares the `"global"` bucket per rule or default policy.

## Cache failures

By default `fail_open` is `true`: if `Marten.cache` raises while checking a throttle bucket, the middleware logs a warning and allows the request. This avoids turning a cache outage into an application outage, which is usually the right tradeoff for general traffic.

For sensitive endpoints where bypassing the throttle is worse than rejecting traffic, set:

```crystal
Marten.settings.throttle.fail_open = false
```

With `fail_open = false`, cache exceptions propagate to the application.

## Cache key format

```
{cache_namespace}:{r<rule_index>|d}:{client_id}
```

`r<rule_index>` is used when a per-route rule matched, `d` for the opt-in default policy. The strategy appends its own suffix on top.

## Not yet there

A few things that are planned but not implemented:

- explicit trusted-proxy configuration and IP allowlists
- a token-bucket strategy
- the standard `RateLimit-*` headers alongside the `X-` ones
- customizable 429 responses (templates or callable)
- an opt-in log of blocked requests

Issues and PRs welcome.

## License

MIT.
