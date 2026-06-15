defmodule Tunnel.MixProject do
  use Mix.Project

  def project do
    [
      app: :tunnel,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Tunnel.Application, []}
    ]
  end

  defp deps do
    []
  end
end
