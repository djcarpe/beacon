defmodule Beacon.Migrations.V015 do
  @moduledoc false
  use Ecto.Migration

  # First-class component-bound pubsub:
  #   * beacon_info_handlers.name — stable key so components reference a
  #     handler and dispatch can filter by it (EventHandler already has name).
  #   * beacon_components.handlers — the info/event handler names a component
  #     declares it needs, shaped %{"info" => [...], "event" => [...]}.
  # Both nullable / defaulted → existing rows keep working; scoping is opt-in.

  def up do
    alter table(:beacon_info_handlers) do
      add_if_not_exists :name, :text
    end

    alter table(:beacon_components) do
      add_if_not_exists :handlers, :map, default: %{}
    end
  end

  def down do
    alter table(:beacon_components) do
      remove_if_exists :handlers, :map
    end

    alter table(:beacon_info_handlers) do
      remove_if_exists :name, :text
    end
  end
end
