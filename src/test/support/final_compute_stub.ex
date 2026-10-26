defmodule NetworkDefense.Evaluation.FinalImmediateRetry do
  @moduledoc false
  @behaviour Gust.DAG.TaskDelayer

  @impl true
  def calc_delay(_attempt), do: 0
end

defmodule NetworkDefense.Evaluation.FinalComputeStub do
  @moduledoc """
  Local stand-in for the Python compute service in Final tests.

  The stub serves the three endpoints a Final run uses. Comparison answers come
  from the checked-in Final conformance statistics and correction answers come
  from the checked-in Holm response, so the test suite never implements a
  second statistic.
  """

  import Plug.Conn

  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluation.PilotConformance

  @clients [
    NetworkDefense.Evaluation.Pilot.Client,
    NetworkDefense.Evaluation.Comparison.Client,
    NetworkDefense.Evaluation.Family.Client
  ]

  @doc """
  Start the stub on a free port and point every evaluation client at it.

  Returns the agent that records the observed traffic.
  """
  def start!(opts \\ []) do
    final_fixture = Keyword.get(opts, :final_fixture, FinalConformance.fixture())

    agent =
      ExUnit.Callbacks.start_supervised!(
        {Agent,
         fn ->
           %{
             pilot_requests: [],
             comparison_seeds: [],
             completion_order: [],
             correction_requests: [],
             delays: %{},
             fail_seeds: [],
             correction_failures: [],
             final_fixture: final_fixture
           }
         end}
      )

    server =
      ExUnit.Callbacks.start_supervised!(
        {Bandit, plug: {__MODULE__, agent}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    configure_clients!(port)
    agent
  end

  @doc "Point the Pilot, comparison, and family clients at a local port."
  def configure_clients!(port) do
    originals = Enum.map(@clients, &{&1, Application.fetch_env!(:network_defense, &1)})

    Enum.each(@clients, fn client ->
      Application.put_env(:network_defense, client, base_url: "http://127.0.0.1:#{port}")
    end)

    ExUnit.Callbacks.on_exit(fn ->
      Enum.each(originals, fn {client, config} ->
        Application.put_env(:network_defense, client, config)
      end)
    end)
  end

  @doc "Delay the answer for one comparison seed."
  def slow!(agent, seed, delay_ms) do
    Agent.update(agent, fn state -> Map.update!(state, :delays, &Map.put(&1, seed, delay_ms)) end)
  end

  @doc "Fail the comparison whose resampling seed matches."
  def fail!(agent, seed) do
    Agent.update(agent, fn state -> Map.update!(state, :fail_seeds, &[seed | &1]) end)
  end

  @doc """
  Fail the next correction calls with one HTTP status and one bounded answer.

  The answer is either an error code, which becomes one documented error
  envelope, or a complete response body. A queued failure is used once, so a
  later call in the same test succeeds unless the queue holds another entry.
  Each correction call takes one queue entry, including a call whose request
  does not match the checked-in request; such a call still receives a bounded
  error.
  """
  def fail_correction!(agent, status, code) when is_binary(code),
    do: fail_correction!(agent, status, FinalConformance.error_envelope(code))

  def fail_correction!(agent, status, body) when is_map(body) do
    Agent.update(agent, fn state ->
      Map.update!(state, :correction_failures, &(&1 ++ [{status, body}]))
    end)
  end

  def requests(agent, key), do: Agent.get(agent, &Map.fetch!(&1, key))

  @doc """
  Start the Gust DAG loader and dispatcher and wait for the evaluation DAGs.

  Gust skips these children in the test environment, so every test that runs a
  real Final or Pilot run starts them explicitly.
  """
  def start_gust! do
    ExUnit.Callbacks.start_supervised!(
      {Gust.DAG.Loader.Worker, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}}
    )

    ExUnit.Callbacks.start_supervised!({Gust.Run.DispatcherSupervisor, []})
    immediate_retries!()

    Enum.each(["evaluation_pilot", "evaluation_final"], &wait_for_dag!/1)
    :ok
  end

  @doc "Create and complete one real recommended Pilot run through Gust."
  def recommended_pilot_run! do
    alias NetworkDefense.Evaluation.Pilot.Contracts.PilotResult
    alias NetworkDefense.Evaluation.Pilot.Workflow
    alias NetworkDefense.Evaluation.PilotConformance

    {:ok, snapshot} = PilotConformance.store_snapshot(PilotConformance.snapshot())
    {:ok, run_id} = PilotConformance.submit(PilotConformance.request_params(snapshot.id))
    {:ok, :succeeded} = Workflow.await(run_id, 20_000)
    {:ok, %PilotResult{outcome: "recommended"}} = Workflow.result(run_id)

    run_id
  end

  @doc "Use a zero-delay retry policy so a retry does not outlive the test."
  def immediate_retries! do
    original = Application.get_env(:gust, :dag_task_delayer)

    Application.put_env(:gust, :dag_task_delayer, NetworkDefense.Evaluation.FinalImmediateRetry)

    ExUnit.Callbacks.on_exit(fn ->
      if original do
        Application.put_env(:gust, :dag_task_delayer, original)
      else
        Application.delete_env(:gust, :dag_task_delayer)
      end
    end)
  end

  defp wait_for_dag!(name) do
    Enum.reduce_while(1..200, nil, fn _attempt, _acc ->
      case Gust.Flows.get_dag_by_name(name) do
        nil ->
          Process.sleep(10)
          {:cont, nil}

        dag ->
          {:halt, dag}
      end
    end) || raise "Gust did not load #{name}"
  end

  def init(agent), do: agent

  def call(conn, agent) do
    {:ok, body, conn} = read_body(conn)
    request = if body == "", do: %{}, else: Jason.decode!(body)

    {status, response} =
      case conn.request_path do
        "/v1/pilots/candidate-comparisons" -> pilot(request, agent)
        "/v1/comparisons/corrected-crossed-bootstrap" -> comparison(request, agent)
        "/v1/families/holm" -> correction(request, agent)
        _other -> {404, error_envelope("invalid_json")}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(response))
  end

  defp pilot(request, agent) do
    Agent.update(agent, fn state -> Map.update!(state, :pilot_requests, &[request | &1]) end)

    case PilotConformance.response_for(request) do
      nil -> {422, error_envelope("invalid_json")}
      response -> {200, response}
    end
  end

  defp comparison(request, agent) do
    seed = get_in(request, ["resampling", "seed"])
    state = Agent.get(agent, & &1)

    Agent.update(agent, fn current -> Map.update!(current, :comparison_seeds, &[seed | &1]) end)

    delay = Map.get(state.delays, seed, 0)
    if delay > 0, do: Process.sleep(delay)

    Agent.update(agent, fn current ->
      Map.update!(current, :completion_order, &[seed | &1])
    end)

    case FinalConformance.response_for(request, state.final_fixture) do
      nil ->
        {422, error_envelope("invalid_json")}

      response ->
        if seed in state.fail_seeds do
          {400, error_envelope("invalid_json")}
        else
          {200, response}
        end
    end
  end

  defp correction(request, agent) do
    {failure, fixture} =
      Agent.get_and_update(agent, fn state ->
        {{List.first(state.correction_failures), state.final_fixture},
         %{
           state
           | correction_requests: [request | state.correction_requests],
             correction_failures: Enum.drop(state.correction_failures, 1)
         }}
      end)

    cond do
      request != fixture.correction_request ->
        {422, FinalConformance.error_envelope("validation_failed")}

      failure ->
        failure

      true ->
        {200, fixture.correction_response}
    end
  end

  defp error_envelope(code), do: FinalConformance.error_envelope(code)
end
