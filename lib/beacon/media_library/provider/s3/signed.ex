defmodule Beacon.MediaLibrary.Provider.S3.Signed do
  @moduledoc """
  S3 provider variant that hands out time-bounded **presigned URLs**
  to the client instead of streaming the bytes through Phoenix.

  ## When to use

  | Provider              | URL the browser sees                                    | Pros                              | Cons                                              |
  |-----------------------|----------------------------------------------------------|------------------------------------|---------------------------------------------------|
  | `Provider.S3`         | `/__beacon_media__/<file>` (proxy)                       | works in every env, single host    | every byte goes through your Phoenix pod          |
  | `Provider.S3.Signed`  | `https://<s3-host>/<bucket>/<key>?X-Amz-Signature=...`   | bytes go client ↔ S3 directly      | S3 host must be browser-reachable from the client |

  Either provider works for upload — the difference is only in
  `url_for/1`. Both round-trip through the same `Provider.S3.send_to_cdn/2`
  and `Provider.S3.read/1`, so an asset uploaded under one provider can
  be served via the other.

  ## Public-endpoint override

  In clustered envs the application's S3 endpoint is often an
  in-cluster ServiceName (e.g. `http://minio:9000`) that the operator's
  browser cannot resolve. To keep upload going through the in-cluster
  endpoint while emitting **client-reachable** presigned URLs, set:

      config :beacon, :media_library_presigned_url_endpoint,
        "http://minio.localhost:9000"

  When set (and parseable as a URI with a scheme + host), `url_for/1`
  swaps the scheme/host/port on the ExAws config it hands to
  `ExAws.S3.presigned_url/4` so the signed URL points at the public
  endpoint. The SigV4 signature is computed against the new host —
  S3-compatible servers (MinIO, Ceph, real AWS) honor this as long as
  the signature was generated against the same host the client hits.

  An empty string or a malformed URL silently falls back to the
  `:ex_aws, :s3` config — image rendering on every page should never
  break because of a misset env var.
  """
  alias Beacon.MediaLibrary.Provider.S3

  defdelegate send_to_cdn(metadata, config \\ []), to: S3
  defdelegate key_for(metadata), to: S3
  defdelegate bucket(), to: S3
  defdelegate list(), to: S3
  defdelegate provider_key(), to: S3
  defdelegate read(asset, config \\ []), to: S3

  def url_for(asset, config \\ []) do
    key = Map.fetch!(asset.keys, provider_key())
    config = :s3 |> ExAws.Config.new(config) |> apply_public_endpoint()

    {:ok, url} = ExAws.S3.presigned_url(config, :get, config.bucket, key)
    url
  end

  # Rewrites `host` / `port` / `scheme` on the ExAws config from
  # `:beacon, :media_library_presigned_url_endpoint` when set. Bucket,
  # region, credentials are untouched. Bad/blank values fall through.
  defp apply_public_endpoint(config) do
    case Application.get_env(:beacon, :media_library_presigned_url_endpoint) do
      nil ->
        config

      "" ->
        config

      url when is_binary(url) ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
            port = uri.port || default_port(scheme)
            %{config | scheme: scheme <> "://", host: host, port: port}

          _ ->
            config
        end

      _ ->
        config
    end
  end

  defp default_port("https"), do: 443
  defp default_port("http"), do: 80
  defp default_port(_), do: nil
end
