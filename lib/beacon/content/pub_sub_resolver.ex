defmodule Beacon.Content.PubSubResolver do
  @moduledoc """
  Resolves the set of info/event handler names a page depends on, by walking
  its AST, collecting every component it embeds (transitively), and unioning
  those components' declared `handlers`.

  Used at publish time to bake the resolved set onto `Page.extra["pubsub"]`.
  """

  # Standard HTML tags are never treated as component references, mirroring
  # Beacon.Template.ComponentExpander (which checks this list *before* the
  # registry). Keeping the same precedence guarantees the resolver only counts
  # components the expander will actually inline — otherwise a page could
  # subscribe to a handler whose "component" never renders.
  @html_tags ~w(
    a abbr address area article aside audio b base bdi bdo blockquote body br
    button canvas caption cite code col colgroup data datalist dd del details
    dfn dialog div dl dt em embed fieldset figcaption figure footer form
    h1 h2 h3 h4 h5 h6 head header hgroup hr html i iframe img input ins kbd
    label legend li link main map mark menu meta meter nav noscript object
    ol optgroup option output p param picture pre progress q rp rt ruby s
    samp script search section select slot small source span strong style sub
    summary sup table tbody td template textarea tfoot th thead time title
    tr track u ul var video wbr
  )

  @doc """
  `registry` is `%{component_name => %{ast: [nodes], handlers: map}}`.
  Returns `%{"info" => [names], "event" => [names]}` (deduped, order stable).
  """
  @spec resolve([map()], map()) :: %{String.t() => [String.t()]}
  def resolve(page_ast, registry) when is_list(page_ast) and is_map(registry) do
    names = collect_component_names(page_ast, registry, MapSet.new(), [])

    Enum.reduce(names, %{"info" => [], "event" => []}, fn name, acc ->
      handlers = get_in(registry, [name, :handlers]) || %{}

      acc
      |> merge_list("info", get_handler_list(handlers, "info"))
      |> merge_list("event", get_handler_list(handlers, "event"))
    end)
  end

  defp get_handler_list(handlers, key) do
    handlers[key] || handlers[String.to_atom(key)] || []
  end

  defp merge_list(acc, key, list) do
    Map.update!(acc, key, fn existing -> existing ++ Enum.reject(list, &(&1 in existing)) end)
  end

  # Walk nodes, accumulating component names (transitively into their ASTs).
  defp collect_component_names(nodes, registry, visited, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, &collect_node(&1, registry, visited, &2))
  end

  defp collect_node(%{type: :element, tag: tag} = node, registry, visited, acc) do
    children = Map.get(node, :children, [])

    if tag not in @html_tags and Map.has_key?(registry, tag) and not MapSet.member?(visited, tag) do
      visited = MapSet.put(visited, tag)
      sub_ast = get_in(registry, [tag, :ast]) || []
      acc = acc ++ if(tag in acc, do: [], else: [tag])
      acc = collect_component_names(sub_ast, registry, visited, acc)
      collect_component_names(children, registry, visited, acc)
    else
      collect_component_names(children, registry, visited, acc)
    end
  end

  defp collect_node(%{type: :conditional} = n, registry, visited, acc) do
    acc = collect_component_names(Map.get(n, :then, []), registry, visited, acc)
    collect_component_names(Map.get(n, :else, []), registry, visited, acc)
  end

  defp collect_node(%{type: type} = n, registry, visited, acc) when type in [:loop, :fragment] do
    collect_component_names(Map.get(n, :children, []), registry, visited, acc)
  end

  defp collect_node(_leaf, _registry, _visited, acc), do: acc
end
