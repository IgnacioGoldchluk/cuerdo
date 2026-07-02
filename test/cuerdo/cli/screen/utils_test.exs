defmodule Cuerdo.CLI.Screen.UtilsTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.Context.APICalls
  alias Cuerdo.CLI.Screen
  alias Cuerdo.Report.Result

  describe "summary/1" do
    test "returns execution time in seconds when total exceeds 1s" do
      results = [
        %Result{
          status: :passed,
          http_calls: [
            %APICalls{
              path: ["wokflowId", "stepId"],
              time_ms: 1_200,
              request: %Req.Request{},
              response: %Req.Response{}
            }
          ]
        }
      ]

      expected = "1 passed · 0 failed · 1 total · 1.2s"
      assert expected == Screen.Utils.summary(results)
    end

    test "counts failed passed for total" do
      results = [
        %Result{status: :passed, http_calls: []},
        %Result{status: :failed, http_calls: []}
      ]

      expected = "1 passed · 1 failed · 2 total · 0ms"
      assert expected == Screen.Utils.summary(results)
    end
  end
end
