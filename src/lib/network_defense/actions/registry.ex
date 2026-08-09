defmodule NetworkDefense.Actions.Registry do
  @moduledoc false

  alias NetworkDefense.Actions.{AcquireCredential, ExploitVulnerability, ReuseCredential}
  alias NetworkDefense.Registry

  @types [ExploitVulnerability, AcquireCredential, ReuseCredential]

  def module_for(type), do: Registry.module_for(@types, type)

  def type_for!(module) do
    Registry.type_for(@types, module) || raise ArgumentError, "unknown attempted action module"
  end
end
