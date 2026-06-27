defmodule Cuerdo.CLI.Screen do
  @moduledoc """
  Renders test execution information
  """
  @type test_result :: :passed | :failed | :error

  @callback start() :: :ok
  @callback fetched_document() :: :ok
  @callback fetched_specification() :: :ok
  @callback start_workflows([String.t()], pos_integer()) :: :ok
  @callback completed_workflow_testcase(String.t()) :: :ok
  @callback summary(list(), String.t()) :: :ok

  defp module, do: Application.fetch_env!(:cuerdo, :screen)

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
  def fetched_specification, do: module().fetched_specification()

  @doc """
  Callback when all workflows have been collected
  """
  @spec start_workflows([String.t()], pos_integer()) :: :ok
  def start_workflows(workflow_ids, max_runs),
    do: module().start_workflows(workflow_ids, max_runs)

  @doc """
  Callback each time a workflow testcase is successfully completed (passed or failed)
  """
  @spec completed_workflow_testcase(String.t()) :: :ok
  def completed_workflow_testcase(workflow_id) do
    module().completed_workflow_testcase(workflow_id)
  end

  @doc """
  Renders final summary results. Receives a list of Result and the filename to store
  failing cases
  """
  @spec summary(list(), String.t()) :: :ok
  def summary(results, filename), do: module().summary(results, filename)
end
