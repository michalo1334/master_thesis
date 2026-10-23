defmodule AgentLibElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :agent_lib_elixir,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:igniter, "== 0.8.4", runtime: false}]
    ]
  end
end
