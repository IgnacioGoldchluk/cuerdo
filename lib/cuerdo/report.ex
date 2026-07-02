defmodule Cuerdo.Report do
  @moduledoc """
  Generates serializable reports for document executions
  """
  @version Mix.Project.config() |> Keyword.fetch!(:version)

  alias Cuerdo.Arazzo.Context.APICalls
  alias Cuerdo.Arazzo.Document
  alias Cuerdo.Errors.ExecutionError
  alias Cuerdo.Report.Result

  @doc """
  Generates and stores a report for the given Arazzo document and results
  """
  def store(%Document{} = arazzo_document, workflow_results, destination) do
    report = generate(arazzo_document, workflow_results)
    File.write(destination, JSON.encode!(report))
  end

  @doc """
  Generates a report given the Arazzo document and the map of %{workflow_id => results}
  """
  @spec generate(Document.t(), %{String.t() => list()}) :: map()
  def generate(%Document{} = arazzo_document, workflows_results) do
    %{
      "metadata" => metadata(arazzo_document),
      "results" => Enum.map(workflows_results, &result/1)
    }
  end

  def metadata(%Document{} = arazzo_document) do
    %{
      "cuerdo_version" => @version,
      "arazzo_version" => arazzo_document.arazzo,
      "arazzo_name" => arazzo_document.info.title,
      "run_id" => UUIDv7.generate()
      # Add hashes later using ssdeep for the document + each workflow + each step
    }
  end

  defp result(%Result{} = result) do
    %{
      "status" => to_string(result.status) |> String.upcase(),
      "workflow_id" => result.workflow_id,
      "inputs" => result.inputs,
      "error" => error_report(result.error),
      "execution_time_ms" => Enum.sum_by(result.http_calls, & &1.time_ms),
      "http_calls" => Enum.map(result.http_calls, &to_report/1)
    }
  end

  defp error_report(nil), do: nil

  defp error_report(%ExecutionError{error: error, path: path} = _execution_error) do
    %{
      "location" => path_to_comment(path),
      "type" => error.__struct__.error_type(error),
      "value" => Exception.message(error)
    }
  end

  defp error_report(e) when is_binary(e), do: e
  defp error_report(e) when is_exception(e), do: Exception.message(e)

  defp to_report(%APICalls{request: req, response: resp, path: path, time_ms: time_ms}) do
    %{
      "time" => time_ms,
      "executionPath" => path_to_comment(path),
      "request" => to_report(req),
      "response" => to_report(resp)
    }
  end

  defp to_report(%Req.Request{} = request) do
    %{
      "method" => request.method |> to_string() |> String.upcase(),
      "url" => url_minus_fragment(request.url),
      "headers" => headers(request),
      "queryString" => querystring(request.url),
      "postData" => post_data(request)
    }
  end

  defp to_report(%Req.Response{} = response) do
    %{"status" => response.status, "headers" => headers(response), "content" => content(response)}
  end

  defp path_to_comment(path) when is_list(path), do: Enum.join(path, ".")

  defp url_minus_fragment(%URI{} = uri), do: uri |> Map.put(:fragment, nil) |> to_string()
  defp querystring(%URI{query: nil}), do: []

  defp querystring(%URI{query: query}) when is_binary(query) do
    for {name, value} <- URI.decode_query(query), do: %{"name" => name, "value" => value}
  end

  defp headers(req_resp), do: req_resp |> Req.get_headers_list() |> Map.new()

  defp post_data(%Req.Request{} = request) do
    %{"mimeType" => content_type(request), "text" => body(request)}
  end

  defp body(request_response) do
    case request_response.body do
      nil -> ""
      body when is_binary(body) -> body
      body -> JSON.encode!(body)
    end
  end

  defp content_type(%Req.Request{} = request) do
    case Req.Request.get_header(request, "content-type") do
      [] -> "text/plain"
      others -> Enum.join(others, "; ")
    end
  end

  defp content_type(%Req.Response{} = response) do
    case Req.Response.get_header(response, "content-type") do
      [] -> "text/plain"
      others -> Enum.join(others, "; ")
    end
  end

  defp content(response) do
    %{"mimeType" => content_type(response), "text" => body(response)}
  end
end
