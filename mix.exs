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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Tunnel.Application, []}
    ]
  end

  defp deps do
    [
      {:thousand_island, "~> 1.4"}
    ]
  end
end
