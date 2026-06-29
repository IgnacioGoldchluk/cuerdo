defmodule Cuerdo.ArazzoCase.ReplayTest do
  use ExUnit.Case

  alias Cuerdo.ArazzoCase

  import Cuerdo.ArazzoFixtures

  describe "replay/1" do
    test "re-runs all failed inputs" do
      document = people_document(with_self: true)

      failures = [
        %{"min_age" => 1, "name" => "Alice"},
        %{"min_age" => 2, "name" => "Bob"}
      ]

      workflow_id = "getPeople"

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert %{"min_age" => "1", "name" => "Alice"} == conn.params
        Req.Test.json(conn, [%{"age" => 4, "name" => "Alicee"}])
      end)

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert %{"min_age" => "2", "name" => "Bob"} == conn.params
        Req.Test.json(conn, [%{"age" => 3, "name" => "Boberson"}])
      end)

      [r1, r2] = ArazzoCase.Runner.replay(workflow_id, failures, document)

      assert r1.inputs == Enum.at(failures, 0)
      assert r1.workflow_id == workflow_id
      assert r1.status == :passed

      assert r2.inputs == Enum.at(failures, 1)
      assert r2.workflow_id == workflow_id
      assert r2.status == :passed
    end
  end
end
