import Config

config :tunnel, Tunnel,
  role: :relay,
  tunnel_port: 7000,
  public_port: 8080,
  relay_host: "localhost",
  local_app_port: 4000

if config_env() == :test do
  config :tunnel, Tunnel, role: :none
end
