defmodule Cuerdo.Arazzo.Context.Cache do
  @moduledoc false

  @doc """
  Creates a new cache ETS table for remotely fetched schemas.
  Returns the reference to the ETS table
  """
  @spec create :: reference()
  def create do
    :ets.new(:whatever, [:set, :protected])
  end

  @doc """
  Stores the remote schema or Arazzo document in the cache
  """
  @spec store(reference(), String.t(), map()) :: true
  def store(ets_ref, url, schema) when is_reference(ets_ref) and is_binary(url) do
    :ets.insert(ets_ref, {url, schema})
  end

  @doc """
  Retrieves the OpenAPI schema or Arazzo document from the cache
  """
  @spec get(reference(), String.t()) :: map() | nil
  def get(ets_ref, url) when is_reference(ets_ref) and is_binary(url) do
    case :ets.lookup(ets_ref, url) do
      [{^url, schema}] -> schema
      [] -> nil
    end
  end
end
