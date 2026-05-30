defmodule Beacon.Migrations.V014 do
  @moduledoc false
  use Ecto.Migration

  # Adds a nullable `topic` column to beacon_info_handlers so an
  # InfoHandler can declare which PubSub topic it expects messages
  # from. Sojourner's shared on_mount hook reads these topics and
  # subscribes the LV to each one — the column lets non-engineers
  # bind a page to a topic from the admin without writing Elixir.
  #
  # Nullable + no default → existing handlers continue to work; only
  # handlers that opt into the new topic-driven subscription set it.

  def up do
    alter table(:beacon_info_handlers) do
      add_if_not_exists :topic, :text
    end
  end

  def down do
    alter table(:beacon_info_handlers) do
      remove_if_exists :topic, :text
    end
  end
end
