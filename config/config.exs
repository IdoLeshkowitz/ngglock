import Config

config :tunnel, :env_name, config_env()

config :tunnel, Tunnel,
  role: :relay,
  tunnel_port: 7000,
  public_port: 8080,
  relay_host: "localhost",
  local_app_port: 4000

import_config "#{config_env()}.exs"
