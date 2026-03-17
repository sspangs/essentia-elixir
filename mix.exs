defmodule EssentiaElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :essentia_elixir,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_env: make_env(),
      make_clean: ["clean"],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Essentia.Application, []}
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.6", runtime: false}
    ]
  end
  
  defp make_env do
    %{
      "ERTS_INCLUDE_DIR" => "#{:code.root_dir()}/erts-#{:erlang.system_info(:version)}/include"
    }
  end
end
