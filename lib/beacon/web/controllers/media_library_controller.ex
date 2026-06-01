defmodule Beacon.Web.MediaLibraryController do
  @moduledoc false

  use Beacon.Web, :controller

  alias Beacon.MediaLibrary
  alias Beacon.MediaLibrary.Asset

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
        # Phoenix instead of redirecting the browser to a presigned URL.
        #
        # Redirecting only works when the S3 endpoint host is reachable
        # from the browser — but in the Kubernetes localhost env the
        # endpoint is the in-cluster service name `http://minio:9000`,
        # which a browser running on the user's laptop cannot resolve.
        # Proxying keeps the URL anchored to the Phoenix host
        # (`http://sojourner.localhost/__beacon_media__/...`) and works
        # everywhere — localhost, ephemeral envs, prod with S3 — with
        # no extra ingress / LoadBalancer plumbing per environment.
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
end
