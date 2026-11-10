defmodule Graphyne.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/ChannexIO/graphyne"

  def project do
    [
      app: :graphyne,
      version: @version,
      elixir: "~> 1.18",
      compilers: [:leex, :yecc] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "GraphQL documents as plain text in a ~GQL sigil, with a full syntax check at compile time.",
      package: package(),
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  # Mix compiles the leex and yecc files on the consumer side, so the package
  # ships them and not the generated .erl files.
  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib src/graphyne_lexer.xrl src/graphyne_parser.yrl mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
