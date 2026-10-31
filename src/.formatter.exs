[
  import_deps: [:oban, :ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,scripts,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"],
  locals_without_parens: [
    plug: 1,
    plug: 2,
    has_one: 2,
    task_action: 2,
    task_action: 3,
    task_action: 4
  ]
]
