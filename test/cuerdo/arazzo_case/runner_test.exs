defmodule Cuerdo.ArazzoCase.RunnerTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.Document
  alias Cuerdo.ArazzoCase.Runner

  setup_all do
    document =
      ["tapiz", "arazzo.yml"]
      |> Path.join()
      |> YamlElixir.read_from_file!()
      |> Document.new!()

    %{document: document, ids: Enum.map(document.workflows, & &1.workflowId)}
  end

  describe "workflow_ids/3" do
    test "returns all ids when no options are specified", %{document: document, ids: ids} do
      {:ok, to_run} = Runner.workflow_ids(document, nil, nil)
      assert MapSet.new(to_run) |> MapSet.equal?(MapSet.new(ids))
    end

    test "ignores workflows from excluded ids", %{document: document, ids: ids} do
      [to_ignore | rest] = ids

      {:ok, to_run} = Runner.workflow_ids(document, nil, [to_ignore])
      assert MapSet.new(to_run) |> MapSet.equal?(MapSet.new(rest))
    end

    test "selects ids from only when specified", %{document: document, ids: ids} do
      [id1, id2 | _to_ignore] = Enum.shuffle(ids)

      {:ok, to_run} = Runner.workflow_ids(document, [id1, id2], nil)

      assert MapSet.new(to_run) |> MapSet.equal?(MapSet.new([id1, id2]))
    end

    test "filters when both only and ignore are passed", %{document: document, ids: ids} do
      [id1, id2 | _to_ignore] = Enum.shuffle(ids)
      assert {:ok, [id2]} == Runner.workflow_ids(document, [id1, id2], [id1])
    end

    test "returns error when an id is not in the document", %{document: document} do
      assert {:error, %ArgumentError{message: msg}} =
               Runner.workflow_ids(document, ["invalid_id"], nil)

      assert msg == "invalid workflow ids: invalid_id"
    end
  end
end
