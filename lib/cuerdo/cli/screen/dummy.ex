defmodule Cuerdo.CLI.Screen.Dummy do
  @moduledoc false
  @behaviour Cuerdo.CLI.Screen

  @impl true
  def completed_workflow_testcase(_), do: :ok

  @impl true
  def start, do: :ok

  @impl true
  def fetched_document, do: :ok

  @impl true
  def fetched_specification(_), do: :ok

  @impl true
  def started_workflows(_), do: :ok

  @impl true
  def completed_workflow(_, _), do: :ok

  @impl true
  def summary(_, _), do: :ok
end
