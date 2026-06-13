defmodule Cuerdo.MixProject do
  use Mix.Project

  @source_url "https://github.com/IgnacioGoldchluk/cuerdo"
  @version "0.1.1"

  def project do
    [
      app: :cuerdo,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [
        tool: Mix.Tasks.Test.CoverageWithIndex,
        ignore_modules: [
          Mix.Tasks.Test.CoverageWithIndex
        ]
      ],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:zoi, "~> 0.18"},
      {:yaml_elixir, "~> 2.12"},
      {:rock_solid, "~> 0.0.8"},
      {:json_path, "~> 0.4"},
      {:jsv, "~> 0.19"},
      {:req, "~> 0.5"},
      {:stream_data, "~> 1.0"},
      {:nimble_options, "~> 1.0"},
      {:plug, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # YAML syntax highlighting in exdoc
      {:makeup, "~> 1.0"},
      {:makeup_elixir, "~> 1.0"},
      {:makeup_syntect, "~> 0.1"}
    ]
  end

  defp docs do
    [
      main: "Cuerdo",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      filter_modules: fn module, _meta ->
        module in [
          Cuerdo,
          Cuerdo.Arazzo,
          Cuerdo.ArazzoCase,
          Cuerdo.Arazzo.Context,
          Cuerdo.Errors.ExecutionError
        ]
      end
    ]
  end

  defp groups_for_extras do
    [
      Dev: ~r/.*/
    ]
  end

  defp groups_for_modules do
    [
      Arazzo: [Cuerdo.Arazzo, Cuerdo.Arazzo.Context],
      ArazzoCase: [Cuerdo.ArazzoCase],
      Exceptions: [Cuerdo.Errors.ExecutionError]
    ]
  end

  defp description do
    "Arazzo workflow runner"
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Ignacio Goldchluk"],
      source_ref: "v#{@version}",
      links: %{"GitHub" => @source_url}
    ]
  end
end
