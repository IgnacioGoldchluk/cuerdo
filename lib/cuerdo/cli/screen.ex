defmodule Cuerdo.CLI.Screen do
  @moduledoc """
  Renders test execution information
  """
  @type test_result :: :passed | :failed | :error

  alias Cuerdo.CLI.Screen

  @callback start() :: :ok
  @callback fetched_document() :: :ok
  @callback fetched_specification(String.t()) :: :ok
  @callback started_workflows([String.t()]) :: :ok
  @callback completed_workflow_testcase(String.t()) :: :ok
  @callback completed_workflow(String.t(), test_result()) :: :ok
  @callback summary(list(), String.t()) :: :ok

  defp module, do: Application.fetch_env!(:cuerdo, :screen)

  def mode("basic"), do: Screen.Basic
  def mode("rich"), do: Screen.Terminal
  def mode("none"), do: Screen.Dummy

  def start(mode) do
    Application.put_env(:cuerdo, :screen, mode(mode))
    start()
  end

  @doc """
  Starts the screen
  """
  def start, do: module().start()

  @doc """
  Callback when the initial Arazzo document is fetched
  """
  def fetched_document, do: module().fetched_document()

  @doc """
  Callback when the main OpenAPI specification document is fetched
  """
  def fetched_specification(url), do: module().fetched_specification(url)

  @doc """
  Callback when all workflows have been collected
  """
  @spec started_workflows([String.t()]) :: :ok
  def started_workflows(workflow_ids), do: module().started_workflows(workflow_ids)

  @doc """
  Callback each time a workflow testcase is successfully completed (passed or failed)
  """
  @spec completed_workflow_testcase(String.t()) :: :ok
  def completed_workflow_testcase(workflow_id) do
    module().completed_workflow_testcase(workflow_id)
  end

  @doc """
  Callback for a final workflow execution
  """
  @spec completed_workflow(String.t(), test_result()) :: :ok
  def completed_workflow(workflow_id, status) do
    module().completed_workflow(workflow_id, status)
  end

  @doc """
  Renders final summary results. Receives a list of Result and the filename to store
  failing cases
  """
  @spec summary(list(), String.t()) :: :ok
  def summary(results, filename), do: module().summary(results, filename)
end
