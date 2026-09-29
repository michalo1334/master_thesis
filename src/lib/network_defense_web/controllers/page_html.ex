defmodule NetworkDefenseWeb.PageHTML do
  @moduledoc "Renders templates selected by `PageController`."
  use NetworkDefenseWeb, :html

  embed_templates "page_html/*"
end
