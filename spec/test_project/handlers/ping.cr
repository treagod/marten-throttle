class PingHandler < Marten::Handlers::Base
  def dispatch
    Marten::HTTP::Response.new("pong", content_type: "text/plain", status: 200)
  end
end
