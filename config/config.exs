import Config

config :logger, level: :debug

config :tunnel, :env_name, config_env()

config :tunnel, Tunnel,
  role: :relay,
  control_port: 7000,
  proxy_port: 7001,
  public_port: 8080,
  relay_host: "localhost",
  local_app_port: 4000,
  subdomain: "foo",
  heartbeat_interval: 15_000,
  heartbeat_timeout: 45_000,
  control_check: 15_000,
  control_timeout: 45_000,
  park_timeout: 10_000,
  register_retry: 500,
  connect_backoff: 500,
  control_packet: 4

import_config "#{config_env()}.exs"
