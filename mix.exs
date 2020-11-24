defmodule Kvasir.PubSub.MixProject do
  use Mix.Project

  def project do
    [
      app: :kvasir_pub_sub,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Kvasir.PubSub.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:common_x, ">= 0.0.0"},
      {:jason, ">= 1.2.0"},
      {:ranch, "~> 2.0"}
    ]
  end
end
