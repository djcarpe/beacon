defmodule Beacon.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Beacon.Registry,
      {Phoenix.PubSub, name: Beacon.PubSub}
    ]

    :ets.new(:beacon_assets, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(:beacon_runtime_poc, [:set, :named_table, :public, read_concurrency: true])
    # Owned by the long-lived application process so the redirect cache outlives
    # transient request/render processes (RedirectCache.init/0 is then a no-op).
    :ets.new(:beacon_redirects, [:set, :named_table, :public, read_concurrency: true])

    Supervisor.start_link(children, strategy: :one_for_one, name: Beacon.Supervisor)
  end
end
