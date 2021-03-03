defmodule MavuList.MixProject do
  use Mix.Project

  @version "0.1.3"
  def project do
    [
      app: :mavu_list,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:pit, "~> 1.2.0"},
      {:phoenix_html, ">= 2.0.0"},
      {:phoenix, ">= 1.5.0"},
      {:mavu_utils, "~> 0.1"},
      {:accessible, ">= 0.2.0"},
      {:ecto, ">= 3.0.0"}
    ]
  end
end
