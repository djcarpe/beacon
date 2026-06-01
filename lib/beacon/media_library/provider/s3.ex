defmodule Beacon.MediaLibrary.Provider.S3 do
  @moduledoc """
  Store assets in S3 using the `ex_aws` library.

  All files are stored in the same bucket under the same level,
  and the bucket name must be present in the `:ex_aws` config:

      config :ex_aws, s3: [bucket: "my_bucket"]

  And then in your site config, register this provider for each mime type you want to use it:

      assets: [
        {"image/*", [providers: [Beacon.MediaLibrary.Provider.S3]]}
      ]

  """

  alias Beacon.MediaLibrary.Asset
  alias Beacon.MediaLibrary.UploadMetadata

  @provider_key "s3"
  @s3_buffer_size 5 * 1024 * 1024

  @doc false
  def send_to_cdn(metadata, config \\ []) do
    key = key_for(metadata)

    StringIO.open(metadata.output, [], fn pid ->
      IO.binstream(pid, @s3_buffer_size)
      |> ExAws.S3.upload(bucket(), key)
      |> ExAws.request!(config)
    end)

    change = Asset.keys_changeset(metadata.resource, provider_key(), key)
    %{metadata | resource: change}
  end

  @doc """
  Reads the raw bytes for `asset` from S3.

  Used by `Beacon.Web.MediaLibraryController` to proxy S3-backed assets
  through Phoenix instead of redirecting the browser to a presigned
  URL. The redirect path requires the configured S3 endpoint host to
  be reachable from the browser, which is not the case when the
  endpoint is an in-cluster-only DNS name (e.g. `http://minio:9000`
  inside Kubernetes). Proxying keeps the asset URL anchored to the
  application's own host.

  Returns `{:ok, body}` on a successful 200 fetch, `{:error, reason}`
  on any failure (no key on the asset, non-200 status, transport
  error). Never raises — the controller decides how to surface
  failures (404 to the operator).
  """
  @spec read(Asset.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def read(asset, config \\ [])

  def read(%Asset{keys: keys}, config) when is_map(keys) do
    case Map.fetch(keys, provider_key()) do
      {:ok, key} when is_binary(key) and key != "" ->
        case ExAws.S3.get_object(bucket(), key) |> ExAws.request(config) do
          {:ok, %{body: body, status_code: 200}} -> {:ok, body}
          {:ok, %{status_code: code}} -> {:error, {:http_status, code}}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :no_key}
    end
  end

  def read(_, _), do: {:error, :no_asset}

  @doc false
  def key_for(metadata) do
    UploadMetadata.key_for(metadata)
  end

  @doc false
  def bucket do
    case ExAws.Config.new(:s3) do
      %{bucket: bucket} -> bucket
      _ -> raise ArgumentError, message: "Missing :ex_aws, :s3, bucket: \"...\" configuration"
    end
  end

  @doc false
  def list do
    ExAws.S3.list_objects(bucket()) |> ExAws.request!()
  end

  @doc false
  def url_for(asset, config \\ []) do
    key = Map.fetch!(asset.keys, provider_key())
    Path.join(host(config), key)
  end

  @doc false
  defp host([]) do
    host(ExAws.Config.new(:s3))
  end

  @doc false
  defp host(%{bucket: bucket, host: host} = config) do
    scheme = Map.get(config, :scheme, "https://")
    "#{scheme}#{bucket}.#{host}"
  end

  @doc false
  defp host(_) do
    raise(
      ArgumentError,
      message: "Missing :ex_aws, :s3, bucket: \"...\" or host: \" ...\" configuration"
    )
  end

  @doc false
  def provider_key, do: @provider_key

  @doc false
  def soft_delete(_asset) do
    # implement asset removal from S3 bucket
  end
end
