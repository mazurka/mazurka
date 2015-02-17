defmodule Mazurka.Protocols.HTTP.Router do
  @moduledoc """
  A DSL for mazurka resources
  """

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      import Mazurka.Protocols.HTTP.Router
      @before_compile Mazurka.Protocols.HTTP.Router

      use Plug.Builder

      defp match(conn, _opts) do
        {mod, params} = do_match(conn.method, conn.path_info, conn.host)
        Plug.Conn.put_private(conn, :mazurka_route, mod)
         |> Plug.Conn.put_private(:mazurka_params, params) 
      end

      def resolve(mod) do
        resolve(mod, %{})
      end

      def resolve(mod, params) do
        try do
          do_resolve(mod, params)
        rescue
          _ -> {:error, :not_found}
        end
      end

      defp dispatch(%Plug.Conn{assigns: assigns} = conn, _opts) do
        route = Map.get(conn.private, :mazurka_route)
        params = Map.get(conn.private, :mazurka_params)
        Mazurka.Protocols.HTTP.Router.__handle__(route, params, conn)
      end

      defoverridable [match: 2, dispatch: 2]
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      import Mazurka.Protocols.HTTP.Router, only: []
    end
  end

  defmacro match(path, options, contents \\ []) do
    compile(nil, path, options, contents)
  end

  defmacro get(path, options, contents \\ []) do
    compile(:get, path, options, contents)
  end

  defmacro post(path, options, contents \\ []) do
    compile(:post, path, options, contents)
  end

  defmacro put(path, options, contents \\ []) do
    compile(:put, path, options, contents)
  end

  defmacro patch(path, options, contents \\ []) do
    compile(:patch, path, options, contents)
  end

  defmacro delete(path, options, contents \\ []) do
    compile(:delete, path, options, contents)
  end

  defmacro options(path, options, contents \\ []) do
    compile(:options, path, options, contents)
  end

  defmacro head(path, options, contents \\ []) do
    compile(:head, path, options, contents)
  end

  ## TODO use forward macro from Plug.Router.forward

  @doc false
  def __route__(method, path, guards, options) do
    {method, guards} = build_methods(List.wrap(method || options[:via]), guards)
    {vars, match}   = Plug.Router.Utils.build_path_match(path)
    {map_params, list_params} = format_params(vars)
    {method, match, map_params, list_params, Plug.Router.Utils.build_host_match(options[:host]), guards}
  end

  def format_params(vars) do
    map_params = Enum.map(vars, fn(var) ->
      {:erlang.list_to_binary(:erlang.atom_to_list(var)), {var, [], nil}}
    end)
    list_params = Enum.map(vars, fn(var) ->
      {var, [], nil}
    end)
    {{:%{}, [], map_params}, list_params}
  end

  @doc false
  def __resolve__(method, path, _host) do
    {format_method(method),
     format_path(path), []}
  end

  defp format_method({:_, _, _}), do: "GET"
  defp format_method(method), do: method

  defp format_path({:_path, _, _}), do: []
  defp format_path(path), do: path

  def __handle__(mod, _params, conn) do
    ## TODO accept multiple formats
    # accept = Plug.Conn.get_req_header(conn, "accept")
    #handler = choose_mediatype(accept, apply(mod, :supported_actions, []))
    case apply(mod, :hyper_json_action, [&resolve/7, conn]) do
      {:ok, body, conn} ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
        Plug.Conn.send_resp(conn, conn.status || 200, body)
      {:error, :not_found, _} ->
        Plug.Conn.send_resp(conn, 404, "{\"error\": {\"message\": \"not found!\"}}")
    end
  end

  defp resolve(:__internal, :resolve, ["params", param], conn, _, _, _) do
    params = Map.get(conn.private, :mazurka_params)
    val = Map.get(params, param)
    normalized = if val == nil, do: :undefined, else: URI.decode(val)
    {:ok, normalized}
  end
  defp resolve(:__internal, :resolve, ["req", "host"], conn, _, _, _) do
    {:ok, conn.host}
  end
  defp resolve(:__internal, :resolve, ["req", "method"], conn, _, _, _) do
    {:ok, conn.method}
  end
  defp resolve(:__internal, :resolve, ["req", "port"], conn, _, _, _) do
    {:ok, conn.port}
  end
  defp resolve(:__internal, :resolve, ["req", "peer"], conn, _, _, _) do
    {:ok, conn.peer}
  end
  defp resolve(:__internal, :resolve, ["req", "remote_ip"], conn, _, _, _) do
    {:ok, conn.remote_ip}
  end
  defp resolve(:__internal, :resolve, ["req", "headers"], conn, _, _, _) do
    {:ok, conn.headers}
  end
  defp resolve(:__internal, :resolve, ["req", "scheme"], conn, _, _, _) do
    {:ok, conn.scheme}
  end
  defp resolve(:__internal, :resolve, ["req", "query_string"], conn, _, _, _) do
    {:ok, conn.query_string}
  end
  defp resolve(:res, :status, [code], conn, _, _, _) do
    {:ok, :ok, Plug.Conn.put_status(conn, code)}
  end
  defp resolve(:res, :set, [key, value], conn, _, _, _) do
    {:ok, :ok, Plug.Conn.put_resp_header(conn, key, value)}
  end
  defp resolve(:res, :redirect, [%{"href" => url} | rest], conn, _, _, _) do
    code = case rest do
      [] -> 302
      [status] -> status
    end
    conn = Plug.Conn.put_resp_header(conn, "location", url)
           |> Plug.Conn.put_status(code)
    {:ok, :ok, conn}
  end
  defp resolve(:res, :invalidates, [%{"href" => url}], conn, _, _, _) do
    conn = Plug.Conn.put_resp_header(conn, "link", "<" <> url <> ">; rel=\"invalidates\"")
    {:ok, :ok, conn}
  end
  defp resolve(mod, fun, args, conn, sender, ref, attrs) do
    ## TODO pull from config
    Api.Fns.resolve(mod, fun, args, conn, sender, ref, attrs)
  end

  defp compile(method, expr, options, contents) do
    {mod, options} =
      cond do
        is_atom(options) ->
          {options, []}
        is_atom(contents) ->
          {contents, options}
        true ->
          raise ArgumentError, message: "expected module handler to be an atom"
    end

    {path, guards} = extract_path_and_guards(expr)

    quote bind_quoted: [method: method,
                        path: path,
                        options: options,
                        guards: Macro.escape(guards, unquote: true),
                        mod: mod] do
      {method, match, map_params, list_params, host, guards} = Mazurka.Protocols.HTTP.Router.__route__(method, path, guards, options)
      {res_method, res_match, res_host} = Mazurka.Protocols.HTTP.Router.__resolve__(method, match, host)
      defp do_match(unquote(method), unquote(match), unquote(host)) when unquote(guards) do
        {unquote(mod), unquote(map_params)}
      end

      defp do_resolve(unquote(mod), unquote(map_params)) do
        {:ok, unquote(res_method), unquote(res_match)}
      end
      defp do_resolve(unquote(mod), unquote(list_params)) do
        {:ok, unquote(res_method), unquote(res_match)}
      end
    end
  end

  # Convert the verbs given with `:via` into a variable and guard set that can
  # be added to the dispatch clause.
  defp build_methods([], guards) do
    {quote(do: _), guards}
  end

  defp build_methods([method], guards) do
    {Plug.Router.Utils.normalize_method(method), guards}
  end

  defp build_methods(methods, guards) do
    methods = Enum.map methods, &Plug.Router.Utils.normalize_method(&1)
    var     = quote do: method
    guards  = join_guards(quote(do: unquote(var) in unquote(methods)), guards)
    {var, guards}
  end

  defp join_guards(fst, true), do: fst
  defp join_guards(fst, snd),  do: (quote do: unquote(fst) and unquote(snd))

  # Extract the path and guards from the path.
  defp extract_path_and_guards({:when, _, [path, guards]}), do: {extract_path(path), guards}
  defp extract_path_and_guards(path), do: {extract_path(path), true}

  defp extract_path({:_, _, var}) when is_atom(var), do: "/*_path"
  defp extract_path(path), do: path
end