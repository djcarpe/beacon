defmodule Beacon.Plug.Redirect do
  @moduledoc """
  Plug that checks incoming requests against cached redirect rules.

  Inserted in the proxy endpoint pipeline before routing. Uses ETS for
  constant-time exact-match lookups. Regex patterns are checked in
  priority order as a fallback.

  Hit counts are incremented asynchronously to avoid slowing the redirect.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{method: method} = conn, _opts) when method in ["GET", "HEAD"] do
    path = "/" <> Enum.join(conn.path_info, "/")

    case find_redirect(path) do
      {destination, status_code, site} ->
        # Increment hit count asynchronously
        Task.start(fn -> Beacon.Content.increment_redirect_hit(site, path) end)

        # Preserve query string
        destination =
          case conn.query_string do
            "" -> destination
            qs -> "#{destination}?#{qs}"
          end

        conn
        |> Plug.Conn.put_resp_header("location", destination)
        |> Plug.Conn.send_resp(status_code, "")
        |> Plug.Conn.halt()

      nil ->
        conn
    end
  end

  def call(conn, _opts), do: conn

  defp find_redirect(path) do
    Beacon.Registry.running_sites()
    |> Enum.find_value(fn site ->
      with in_path when is_binary(in_path) <- in_site_path(site, path),
           {dest, status} <- Beacon.Content.RedirectCache.lookup(site, in_path) do
        {build_destination(site, dest), status, site}
      else
        _ -> nil
      end
    end)
  end

  # Sojourner fork: when sites are mounted in the host router (`beacon_site "/andon"`)
  # instead of via `Beacon.ProxyEndpoint`, the incoming request path carries the
  # site's mount prefix, but redirect source/destination paths are stored in-site.
  # Strip the prefix before the cache lookup, and re-apply it to the destination so
  # the Location header points at the mounted path. Returns nil when the request
  # path isn't under the site's prefix.
  defp in_site_path(site, full_path) do
    case site_prefix(site) do
      prefix when prefix in [nil, "", "/"] ->
        full_path

      prefix ->
        cond do
          full_path == prefix -> "/"
          String.starts_with?(full_path, prefix <> "/") -> String.replace_prefix(full_path, prefix, "")
          true -> nil
        end
    end
  end

  defp build_destination(site, "/" <> _ = dest) do
    case site_prefix(site) do
      prefix when prefix in [nil, "", "/"] -> dest
      prefix -> Beacon.Router.build_path_with_prefix(prefix, dest)
    end
  end

  defp build_destination(_site, dest), do: dest

  defp site_prefix(site) do
    case Beacon.Config.fetch!(site) do
      %{router: router} when not is_nil(router) -> router.__beacon_scoped_prefix_for_site__(site)
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
