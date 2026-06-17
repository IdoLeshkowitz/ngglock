import Config

config :logger, level: :warning

config :tunnel, Tunnel,
  role: :none,
  control_port: 7000,
  proxy_port: 7001,
  heartbeat_interval: 100,
  heartbeat_timeout: 300,
  control_check: 100,
  control_timeout: 300,
  park_timeout: 200,
  register_retry: 50
