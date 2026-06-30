defmodule Cuerdo.CLI.Screen.Basic do
  @moduledoc """
  Basic Screen interface. Prints unbuffered output to stdout with minimal information
  """
  @behaviour Cuerdo.CLI.Screen

  alias Cuerdo.CLI.Screen

  @impl true
  def start do
    IO.puts("Started Cuerdo #{Screen.Utils.version()}")
  end

  @impl true
  def fetched_document do
    IO.puts("Fetched document")
  end

  @impl true
  def started_workflows(workflows) do
    IO.puts("Collected workflows: #{Enum.join(workflows, ", ")}")
  end

  @impl true
  def fetched_specification(url) do
    IO.puts("Fetched OpenAPI spec: #{url}")
  end

  @impl true
  def completed_workflow(workflow_id, status) do
    IO.puts("Workflow #{workflow_id} completed: #{status}")
  end

  @impl true
  def completed_workflow_testcase(_workflow_id) do
    IO.write(".")
  end

  @impl true
  def summary(results, filename) do
    IO.puts(Screen.Utils.summary(results))
    IO.puts("Saving report to #{filename}...")
  end
end
