defmodule Mazurka.Resource.Link do
  @moduledoc """
  Represents a link in a response. This is used by mediatypes to serialize the link in the appropriate
  format. It's broken into its separate parts (method, host, path, etc.) for easy manipulation.
  """

  defstruct mediatype: nil,
            method: nil,
            scheme: nil,
            host: nil,
            port: nil,
            path: nil,
            query: nil,
            fragment: nil

  def compile(_opts, _env) do
    nil
  end

  def format_params(nil) do
    {:%{}, [], []}
  end
  def format_params({:%{}, meta, items}) do
    {:%{}, meta, Enum.map(items, fn({name, value}) ->
      {to_string(name), value}
    end)}
  end
  def format_params(items) when is_list(items) do
    {:%{}, [], Enum.map(items, fn({name, value}) ->
      {to_string(name), value}
    end)}
  end

  def link_to([module, params, query, fragment], _conn, _parent, _ref, _attrs) do
    params = Enum.reduce(params, %{}, fn
      ({key, %{"id" => id}}, acc) ->
        Map.put(acc, to_string(key), to_string(id))
      ({key, %{id: id}}, acc) ->
        Map.put(acc, to_string(key), to_string(id))
      ({key, value}, acc) ->
        Map.put(acc, to_string(key), to_string(value))
    end)

    props = %{params: params, query: query, fragment: fragment}
    ## FOR BACKWARDS COMPATIBILITY
    |> Dict.merge(params)

    {:partial, {module, :affordance_partial, props}}
  end

  def transition_to(args, %{private: private} = conn, parent, ref, attrs) do
    case resolve(args, conn, parent, ref, attrs) do
      {:ok, :undefined} ->
        {:error, :transition_to_unknown_location}
      {:ok, affordance} ->
        location = to_string(affordance)
        {:ok, nil, %{conn | private: Dict.put(private, :mazurka_transition, location)}}
    end
  end

  def invalidates(args, %{private: private} = conn, parent, ref, attrs) do
    case resolve(args, conn, parent, ref, attrs) do
      {:ok, :undefined} ->
        {:error, :invalidates_unknown_location}
      {:ok, affordance} ->
        location = to_string(affordance)
        invalidations = Map.get(private, :mazurka_invalidations, [])
        {:ok, nil, %{conn | private: Map.put(private, :mazurka_invalidations, [location | invalidations])}}
    end
  end

  def encode_qs(params) do
    out = Enum.filter_map(params, fn({_k, v}) ->
      case v do
        nil -> false
        :undefined -> false
        false -> false
        "" -> false
        _ -> true
      end
    end, fn({k, v}) ->
      [k, "=", URI.encode_www_form(v)]
    end)
    |> Enum.join("&")

    if out == "" do
      nil
    else
      out
    end
  end

  def resolve([module, params, query, fragment], %{private: private} = conn, _parent, _ref, _attrs) do
    %{mazurka_router: router, mazurka_mediatype_handler: mediatype_module} = private
    case router.resolve(module, params) do
      {:ok, method, scheme, host, path} ->
        {:ok, %__MODULE__{mediatype: mediatype_module,
                          method: method,
                          scheme: scheme,
                          host: host,
                          port: conn.port,
                          path: request_path(%{conn | path_info: path}),
                          query: query,
                          fragment: fragment}}
      {:ok, method, path} ->
        {:ok, %__MODULE__{mediatype: mediatype_module,
                          method: method,
                          scheme: conn.scheme,
                          host: conn.host,
                          port: conn.port,
                          path: request_path(%{conn | path_info: path}),
                          query: query,
                          fragment: fragment}}
      {:error, :not_found} ->
        {:ok, :undefined}
    end
  end

  def from_conn(%{private: %{mazurka_mediatype_handler: mediatype_module}} = conn) do
    %__MODULE__{mediatype: mediatype_module,
                method: conn.method,
                scheme: conn.scheme,
                host: conn.host,
                port: conn.port,
                path: request_path(conn),
                query: conn.query_string}
  end
  def from_conn(conn, path_info) do
    from_conn(%{conn | path_info: path_info})
  end

  defp request_path(%{script_name: [], path_info: []}) do
    "/"
  end
  defp request_path(%{script_name: script, path_info: path}) do
    "/" <> Enum.join(script ++ path, "/")
  end
end

defimpl String.Chars, for: Mazurka.Resource.Link do
  def to_string(%{fragment: fragment, host: host, path: path, port: port, query: query, scheme: scheme}) do
    %URI{fragment: format_fragment(fragment),
         host: host,
         path: format_path(path),
         port: port,
         query: format_query(query),
         scheme: Kernel.to_string(scheme)}
    |> Kernel.to_string
  end

  defp format_path(nil), do: nil
  defp format_path(""), do: nil
  defp format_path([]), do: nil
  defp format_path("/"), do: nil
  defp format_path(path) when is_list(path), do: "/" <> Enum.join(path, "/")
  defp format_path(path), do: Kernel.to_string(path)

  defp format_query(nil), do: nil
  defp format_query(""), do: nil
  defp format_query(%{__struct__: _} = qs), do: Kernel.to_string(qs)
  defp format_query(qs) when is_map(qs), do: Mazurka.Resource.Link.encode_qs(qs)
  defp format_query(qs), do: Kernel.to_string(qs)

  defp format_fragment(nil), do: nil
  defp format_fragment([]), do: nil
  defp format_fragment(fragment) when is_list(fragment), do: "/" <> Enum.join(fragment, "/")
  defp format_fragment(fragment), do: Kernel.to_string(fragment)
end
