defmodule Beacon.Web.MediaLibraryController do
  @moduledoc false

  use Beacon.Web, :controller

  alias Beacon.MediaLibrary
  alias Beacon.MediaLibrary.Asset

  # ── /__beacon_media__/:file_name — PROXY path ───────────────────────
  #
  # Streams the asset bytes through Phoenix. Works in every env (no
  # external network access from the browser required) at the cost of
  # the bytes flowing through the app pod. Use this for assets that
  # need to be reachable from any client, or when the S3 endpoint
  # isn't browser-reachable (e.g. Kubernetes in-cluster ServiceName
  # like `http://minio:9000`).
  #
  # The router mounts this under the site prefix
  # (`<prefix>/__beacon_media__/:file_name`).
  def show(%{assigns: %{site: site}} = conn, %{"file_name" => file_name}) when is_atom(site) do
    case MediaLibrary.get_asset_by(site, file_name: file_name) do
      %Asset{file_body: file_body} = asset when is_binary(file_body) and file_body != "" ->
        Beacon.Web.Cache.when_stale(conn, asset, fn conn ->
          conn
          |> put_resp_header("content-type", "#{asset.media_type}; charset=utf-8")
          |> Beacon.Web.Cache.asset_cache(:public)
          |> send_resp(200, file_body)
        end)

      %Asset{} = asset ->
        # External provider (S3): no DB bytes. Proxy the object through
        # Phoenix. See module-level note above. Operators who want
        # client-direct S3 fetches (no Phoenix bandwidth) should embed
        # the companion `__beacon_media_presigned__` URL instead.
        case Beacon.MediaLibrary.Provider.S3.read(asset) do
          {:ok, body} ->
            Beacon.Web.Cache.when_stale(conn, asset, fn conn ->
              conn
              |> put_resp_header("content-type", "#{asset.media_type}; charset=utf-8")
              |> Beacon.Web.Cache.asset_cache(:public)
              |> send_resp(200, body)
            end)

          {:error, reason} ->
            raise Beacon.Web.NotFoundError,
                  "S3 asset #{inspect(file_name)} fetch failed: #{inspect(reason)}"
        end

      _ ->
        raise Beacon.Web.NotFoundError, "asset #{inspect(file_name)} not found"
    end
  end

  def show(_conn, %{"file_name" => file_name}) do
    raise Beacon.Web.NotFoundError, "failed to serve asset #{file_name}"
  end

  def show(_conn, _params) do
    raise Beacon.Web.NotFoundError, "failed to serve asset"
  end

  # ── /__beacon_media_presigned__/:file_name — PRESIGNED-URL path ────
  #
  # 302 redirects the browser to a presigned URL that points
  # **directly at the S3 endpoint**. The bytes flow client ↔ S3
  # without ever touching the Phoenix pod — useful for large media or
  # when you'd rather not spend app-server bandwidth on asset serving.
  #
  # Requires `:beacon, :media_library_presigned_url_endpoint` to be
  # set to a host the browser can resolve (e.g. `http://minio.localhost:9000`
  # for Rancher Desktop localhost envs, or your production CDN host).
  # If the asset has no S3 provider mapping the route raises a 404 —
  # operators can switch back to the proxy URL for that asset.
  #
  # DB-backed assets (in-row `file_body`) intentionally fall through
  # to the proxy semantics — there's no presigned URL to redirect to,
  # so we stream the bytes the same way `show/2` does. This keeps the
  # route safe to use unconditionally in templates without having to
  # branch on the asset's storage backend.
  def presigned(%{assigns: %{site: site}} = conn, %{"file_name" => file_name})
      when is_atom(site) do
    case MediaLibrary.get_asset_by(site, file_name: file_name) do
      %Asset{file_body: file_body} = asset when is_binary(file_body) and file_body != "" ->
        Beacon.Web.Cache.when_stale(conn, asset, fn conn ->
          conn
          |> put_resp_header("content-type", "#{asset.media_type}; charset=utf-8")
          |> Beacon.Web.Cache.asset_cache(:public)
          |> send_resp(200, file_body)
        end)

      %Asset{} = asset ->
        case MediaLibrary.presigned_url_for(asset) do
          url when is_binary(url) and url != "" ->
            # Browsers should follow this 302 and fetch directly from
            # the S3 endpoint. We deliberately avoid caching the
            # redirect — the presigned URL embeds an expiry, and a
            # cached 302 from yesterday is worse than a fresh request.
            conn
            |> put_resp_header("cache-control", "no-store")
            |> redirect(external: url)

          _ ->
            raise Beacon.Web.NotFoundError,
                  "asset #{inspect(file_name)} has no presigned URL provider"
        end

      _ ->
        raise Beacon.Web.NotFoundError, "asset #{inspect(file_name)} not found"
    end
  end

  def presigned(_conn, %{"file_name" => file_name}) do
    raise Beacon.Web.NotFoundError, "failed to serve presigned asset #{file_name}"
  end

  def presigned(_conn, _params) do
    raise Beacon.Web.NotFoundError, "failed to serve presigned asset"
  end
end
