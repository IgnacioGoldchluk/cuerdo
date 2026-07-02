defmodule Cuerdo.CLI.ReplayTest do
  use ExUnit.Case

  alias Cuerdo.CLI.Replay

  describe "failures_by_workflow_id/1" do
    test "returns inputs grouped by workflow id" do
      results = [
        %{
          "execution_time_ms" => 3,
          "inputs" => %{"days" => 10, "bookId" => 123},
          "logs" => nil,
          "reason" => nil,
          "status" => "FAILED",
          "workflow_id" => "loanBook"
        },
        %{
          "execution_time_ms" => 3,
          "inputs" => %{
            "book" => %{"author" => "John Doe", "isbn" => "7-578-62137-X", "title" => "Title"}
          },
          "logs" => nil,
          "reason" => nil,
          "status" => "FAILED",
          "workflow_id" => "createAndRetrieveBook"
        },
        %{
          "execution_time_ms" => 3,
          "inputs" => %{
            "book" => %{"author" => "John", "isbn" => "1-578-62137-X", "title" => "Titlee"}
          },
          "logs" => nil,
          "reason" => nil,
          "status" => "FAILED",
          "workflow_id" => "createAndRetrieveBook"
        }
      ]

      grouped = Replay.failures_by_workflow_id(results)
      assert length(grouped["createAndRetrieveBook"]) == 2
      assert length(grouped["loanBook"]) == 1
    end

    test "returns empty map when no workflow failed" do
      results = [
        %{
          "execution_time_ms" => 3,
          "inputs" => %{
            "book" => %{
              "author" => "John Doe",
              "isbn" => "7-578-62137-X",
              "title" => "Title"
            }
          },
          "logs" => nil,
          "reason" => nil,
          "status" => "PASSED",
          "workflow_id" => "createAndRetrieveBook"
        }
      ]

      assert %{} == Replay.failures_by_workflow_id(results)
    end
  end
end
