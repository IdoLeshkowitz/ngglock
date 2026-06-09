import Config

config :tunnel, Tunnel,
  role: :relay,
  listen_port: 7000

if config_env() == :test do
  config :tunnel, Tunnel, role: :none
end
