defmodule Cuerdo.HARTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.Context.APICalls

  alias Cuerdo.HAR

  describe "to_har/1" do
    test "encodes JSON request body to text" do
      req =
        Req.Request.new(
          url: "https://example.com",
          body: JSON.encode!(%{"foo" => "bar"}),
          method: :post
        )
        |> Req.Request.put_header("content-type", "application/json")

      resp = Req.Response.json(%{"id" => 1})

      api_call = APICalls.new!(%{path: ["workflowId", "stepId"], request: req, response: resp})
      %{"entries" => [entry]} = HAR.to_har([api_call])

      request = entry["request"]
      assert request["headers"] == [%{"name" => "content-type", "value" => "application/json"}]
      assert request["postData"]["mimeType"] == "application/json"
      assert request["postData"]["text"] == JSON.encode!(%{"foo" => "bar"})

      assert entry["response"]["content"]["text"] == JSON.encode!(%{"id" => 1})
    end

    test "request with querystring params" do
      req = Req.Request.new(url: "https://example.com?foo=bar")

      resp =
        Req.Response.new()
        |> Req.Response.put_header("date", "Tue, 29 Oct 2024 16:56:32 GMT")

      api_call = APICalls.new!(%{path: ["workflowId", "stepId"], request: req, response: resp})
      %{"entries" => [entry]} = HAR.to_har([api_call])

      refute is_nil(entry["startedDateTime"])
      {:ok, datetime, 0} = DateTime.from_iso8601(entry["startedDateTime"])
      datetime = DateTime.truncate(datetime, :second)
      expected = DateTime.truncate(~U[2024-10-29 16:56:32Z], :second)
      assert :eq == DateTime.compare(datetime, expected)

      assert [%{"name" => "foo", "value" => "bar"}] == entry["request"]["queryString"]
    end

    test "converts JSON request/response to plain text" do
      url = "https://example.com"
      resp_json = %{foo: "bar"}
      req = Req.Request.new(url: url)
      resp = Req.Response.json(resp_json)
      api_call = APICalls.new!(%{path: ["workflowId", "stepId"], request: req, response: resp})

      result = HAR.to_har([api_call])

      assert result["creator"]["name"] == "Cuerdo"
      [entry] = result["entries"]

      assert entry["comment"] == "workflowId.stepId"
      assert entry["request"]["url"] == url

      response = entry["response"]
      assert response["content"]["mimeType"] == "application/json"
      assert response["content"]["text"] == JSON.encode!(resp_json)
      assert %{"name" => "content-type", "value" => "application/json"} in response["headers"]
      assert response["status"] == 200
      assert response["statusText"] == "OK"
    end
  end
end
