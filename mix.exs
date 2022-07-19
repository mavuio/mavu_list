defmodule MavuList.MixProject do
  use Mix.Project

  @version "0.1.11"
  def project do
    [
      app: :mavu_list,
      version: @version,
      elixir: "~> 1.0",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "MavuList",
      source_url: "https://github.com/mavuio/mavu_list"
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
      {:phoenix, ">= 1.6.0"},
      {:phoenix_live_view, ">= 0.17.2"},
      {:mavu_form, "~> 0.1.0"},
      {:mavu_utils, "~> 0.1"},
      {:accessible, ">= 0.2.0"},
      {:jason, ">= 1.2.0"},
      {:atomic_map, ">= 0.8.0"},
      {:typed_struct, "~> 0.2.1"},
      {:ecto, ">= 3.0.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "List helpers used in other upcoming packages under mavuio/\*"
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README*),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/mavuio/mavu_list"}
    ]
  end
end
