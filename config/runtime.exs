import Config

if role = System.get_env("TUNNEL_ROLE") do
  config :tunnel, Tunnel, role: String.to_atom(role)
end

if local_app_port = System.get_env("LOCAL_APP_PORT") do
  config :tunnel, Tunnel, public_port: String.to_integer(local_app_port)
end
