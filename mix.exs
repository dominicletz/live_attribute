defmodule LiveAttribute.MixProject do
  use Mix.Project

  @version "1.1.4"
  @name "LiveAttribute"
  @url "https://github.com/dominicletz/live_attribute"
  @maintainers ["Dominic Letz"]

  def project do
    [
      app: :live_attribute,
      version: @version,
      name: @name,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      homepage_url: @url,
      description: """
        LiveAttributes for Phoenix.LiveView to make subscription and updating
        of changing variables easier.
      """
    ]
  end

  defp aliases() do
    [
      lint: [
        "compile",
        "format --check-formatted",
        "credo"
      ]
    ]
  end

  defp docs do
    [
      main: @name,
      source_ref: "v#{@version}",
      source_url: @url,
      authors: @maintainers
    ]
  end

  defp package do
    [
      maintainers: @maintainers,
      licenses: ["MIT"],
      links: %{github: @url},
      files: ~w(lib LICENSE.md mix.exs README.md)
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:phoenix_live_view, ">= 0.16.0"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false}
    ]
  end
end
