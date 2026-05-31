defmodule Beacon.Content.RedirectCache do
  @moduledoc false

  @table :beacon_redirects

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  def load_redirects(site) do
    redirects = Beacon.Content.list_redirects(site, per_page: :infinity)

    for redirect <- redirects do
      put(redirect)
    end

    :ok
  end

  def lookup(site, path) when is_atom(site) and is_binary(path) do
    if :ets.whereis(@table) == :undefined do
      nil
    else
      case :ets.lookup(@table, {site, path}) do
        [{_, dest, status}] -> {dest, status}
        [] -> lookup_regex(site, path)
      end
    end
  end

  def put(redirect) do
    if :ets.whereis(@table) != :undefined do
      if redirect.is_regex do
        :ets.insert(@table, {{redirect.site, :regex, redirect.source_path, redirect.priority}, redirect.destination_path, redirect.status_code})
      else
        :ets.insert(@table, {{redirect.site, redirect.source_path}, redirect.destination_path, redirect.status_code})
      end
    end

    :ok
  end

  def delete(site, source_path) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table, {site, source_path})
    end

    :ok
  end

  def invalidate(site) do
    # Delete all entries for this site. No-op when the cache table hasn't been
    # created yet: init/0 runs lazily on the runtime render path, so admin
    # writes (create/update/delete redirect) can land before any page render
    # in this runtime. Without this guard :ets.match_delete raises :badarg.
    # The cache is (re)populated by init/load_redirects on the next render.
    if :ets.whereis(@table) != :undefined do
      :ets.match_delete(@table, {{site, :_}, :_, :_})
      :ets.match_delete(@table, {{site, :regex, :_, :_}, :_, :_})
      load_redirects(site)
    end

    :ok
  end

  defp lookup_regex(site, path) do
    # Collect all regex patterns for this site, sorted by priority
    patterns = :ets.match(@table, {{site, :regex, :"$1", :"$2"}, :"$3", :"$4"})

    patterns
    |> Enum.sort_by(fn [_pattern, priority, _dest, _status] -> priority end)
    |> Enum.find_value(fn [pattern, _priority, dest, status] ->
      case Regex.compile(pattern) do
        {:ok, regex} ->
          if Regex.match?(regex, path) do
            resolved_dest = Regex.replace(regex, path, dest)
            {resolved_dest, status}
          end

        _ ->
          nil
      end
    end)
  end
end
