defmodule Cuerdo.Integration.TapizTest do
  use Cuerdo.ArazzoCase

  @moduletag :integration

  setup_all do
    opts = Application.get_env(:cuerdo, :client_options)

    Application.put_env(:cuerdo, :client_options, [])

    on_exit(fn -> Application.put_env(:cuerdo, :client_options, opts) end)
  end

  # Doesn't work because AshJsonApi generates `"included": {"oneOf": []}`
  # arazzo_document_test num_runs: 20,
  #                      transform_inputs: %{
  #                        "createUserWithCategoryAndYearlyLimit" =>
  #                          {Cuerdo.ArazzoFixtures, :with_unique_email}
  #                      },
  #                      only: [],
  #                      document:
  #                        Path.join(["tapiz", "arazzo.yml"])
  #                        |> YamlElixir.read_from_file!()

  describe "run_workflow/3 local" do
    setup do
      %{document: Path.join(["tapiz", "arazzo.yml"]) |> YamlElixir.read_from_file!()}
    end

    test "recurring payment creation workflow", %{document: document} do
      workflow_id = "createRecurringPayment"

      inputs = %{
        "email" => "user#{System.unique_integer([:positive])}@email.com",
        "recurring_payment" => %{
          "name" => "Subscription #{System.unique_integer([:positive])}",
          "amount" => 40_000,
          "period" => "month"
        }
      }

      {:ok, _new_ctx} = Cuerdo.Arazzo.run_workflow(inputs, workflow_id, document)
    end

    @tag skip: "Broken because AshJsonApi sets 'id' to required"
    test "expense update workflow", %{document: document} do
      workflow_id = "updateExpense"

      inputs = %{
        "email" => "user#{System.unique_integer([:positive])}@email.com",
        "amount" => Enum.random(1..10) * 1_000
      }

      {:ok, _new_ctx} = Cuerdo.Arazzo.run_workflow(inputs, workflow_id, document)
    end

    test "expense deletion workflow", %{document: document} do
      workflow_id = "deleteExpense"

      inputs = %{"email" => "user#{System.unique_integer([:positive])}@email.com"}

      {:ok, _new_ctx} = Cuerdo.Arazzo.run_workflow(inputs, workflow_id, document)
    end

    test "expense creation workflow", %{document: document} do
      workflow_id = "createExpense"

      inputs = %{
        "email" => "user#{System.unique_integer([:positive])}@email.com",
        "expense" => %{
          "name" => "Bus ticket",
          "amount" => 3_000
        }
      }

      {:ok, _new_ctx} = Cuerdo.Arazzo.run_workflow(inputs, workflow_id, document)
    end

    test "category creation + deletion workflow", %{document: document} do
      workflow_id = "deleteEmptyCategory"
      inputs = %{"email" => "user#{System.unique_integer([:positive])}@email.com"}
      {:ok, _new_ctx} = Cuerdo.Arazzo.run_workflow(inputs, workflow_id, document)
    end
  end

  describe "run_workflow/3 remote workflow reference" do
    test "create expense" do
      document = Path.join(["tapiz", "expense", "arazzo.yml"]) |> YamlElixir.read_from_file!()

      workflow_id = "createExpense"

      inputs = %{
        "email" => "user#{System.unique_integer([:positive])}@email.com",
        "expense" => %{
          "name" => "Bus ticket",
          "amount" => 3_000
        }
      }

      {:ok, _new_ctx} = Cuerdo.Arazzo.run_workflow(inputs, workflow_id, document)
    end
  end
end
