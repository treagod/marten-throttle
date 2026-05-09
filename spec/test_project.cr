require "./test_project/**"

Marten.configure :test do |config|
  config.installed_apps = [
    MartenThrottle::App,
    TestApp,
  ]
  config.secret_key = "__insecure_#{Random::Secure.random_bytes(32).hexstring}__"
  config.log_level = ::Log::Severity::None
  config.database do |db|
    db.backend = :sqlite
    db.name = ":memory:"
  end
end

Marten.routes.draw do
  path "/ping", PingHandler, name: "ping"
end
