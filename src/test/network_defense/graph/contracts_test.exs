defmodule NetworkDefense.Graph.ContractsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.Contracts.Data.{
    AuthenticatesToData,
    CredentialData,
    HasVulnerabilityData,
    NetworkReachabilityData,
    StoresCredentialData
  }

  describe "CredentialData" do
    test "validates credential data" do
      assert {:ok, _} =
               CredentialData.validate(%{"identifier" => "key-1", "credential_type" => "ssh_key"})

      assert {:ok, _} =
               CredentialData.validate(%{
                 "identifier" => "pass-1",
                 "credential_type" => "password"
               })

      assert {:ok, _} =
               CredentialData.validate(%{"identifier" => "tok-1", "credential_type" => "token"})

      assert {:error, _} = CredentialData.validate(%{"identifier" => "key-1"})

      assert {:error, _} =
               CredentialData.validate(%{"identifier" => "key-1", "credential_type" => "invalid"})
    end
  end

  describe "StoresCredentialData" do
    test "validates required_privilege" do
      assert {:ok, _} = StoresCredentialData.validate(%{"required_privilege" => "user"})
      assert {:ok, _} = StoresCredentialData.validate(%{"required_privilege" => "administrator"})
      assert {:error, _} = StoresCredentialData.validate(%{})
      assert {:error, _} = StoresCredentialData.validate(%{"required_privilege" => "none"})
    end
  end

  describe "AuthenticatesToData" do
    test "validates granted_privilege" do
      assert {:ok, _} = AuthenticatesToData.validate(%{"granted_privilege" => "user"})
      assert {:ok, _} = AuthenticatesToData.validate(%{"granted_privilege" => "administrator"})
      assert {:error, _} = AuthenticatesToData.validate(%{})
    end
  end

  describe "HasVulnerabilityData" do
    test "validates privilege fields" do
      assert {:ok, _} =
               HasVulnerabilityData.validate(%{
                 "required_privilege" => "none",
                 "granted_privilege" => "user"
               })

      assert {:ok, _} =
               HasVulnerabilityData.validate(%{
                 "required_privilege" => "user",
                 "granted_privilege" => "administrator"
               })

      assert {:error, _} = HasVulnerabilityData.validate(%{"required_privilege" => "none"})

      assert {:error, _} =
               HasVulnerabilityData.validate(%{
                 "required_privilege" => "admin",
                 "granted_privilege" => "user"
               })
    end
  end

  describe "NetworkReachabilityData" do
    test "validates protocol and optional ports" do
      assert {:ok, _} = NetworkReachabilityData.validate(%{"protocol" => "any"})
      assert {:ok, _} = NetworkReachabilityData.validate(%{"protocol" => "tcp"})
      assert {:ok, _} = NetworkReachabilityData.validate(%{"protocol" => "udp"})

      assert {:ok, _} =
               NetworkReachabilityData.validate(%{
                 "protocol" => "tcp",
                 "port_start" => 80,
                 "port_end" => 443
               })

      assert {:error, _} = NetworkReachabilityData.validate(%{})

      assert {:error, _} =
               NetworkReachabilityData.validate(%{"protocol" => "tcp", "port_start" => 80})

      assert {:error, _} =
               NetworkReachabilityData.validate(%{
                 "protocol" => "tcp",
                 "port_start" => 70_000,
                 "port_end" => 80_000
               })

      assert {:error, _} =
               NetworkReachabilityData.validate(%{
                 "protocol" => "tcp",
                 "port_start" => 443,
                 "port_end" => 80
               })
    end
  end
end
