ExUnit.start(autorun: false)
Code.require_file("test/network_defense/credo/project_checks_test.exs")

result = ExUnit.run()
if result.failures > 0, do: System.halt(1)
