import Config

if role = System.get_env("TUNNEL_ROLE") do
  config :tunnel, Tunnel, role: String.to_atom(role)
end
