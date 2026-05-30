defmodule Beacon.Content.PubsubSnapshotTest do
  use Beacon.DataCase
  use Beacon.Test

  alias Beacon.Content

  describe "create_page_snapshot/2 pubsub baking" do
    test "publish bakes the resolved pubsub set onto the snapshot extra" do
      site = :my_site

      Content.create_component!(%{
        site: site,
        name: "vin_ticker",
        template: "<div>{{ latest_vin }}</div>",
        example: "<div></div>",
        category: :data,
        handlers: %{"info" => ["andon_vin_tick"], "event" => []}
      })

      layout = beacon_published_layout_fixture(site: site)

      page =
        beacon_page_fixture(
          site: site,
          layout_id: layout.id,
          template: "<div><vin_ticker /></div>",
          format: :heex
        )

      {:ok, event} = Content.create_page_event(page, "published")
      {:ok, snapshot} = Content.create_page_snapshot(page, event)

      assert snapshot.extra["pubsub"] == %{"info" => ["andon_vin_tick"], "event" => []}
    end

    test "publish with no live components yields empty pubsub sets" do
      site = :my_site

      layout = beacon_published_layout_fixture(site: site)

      page =
        beacon_page_fixture(
          site: site,
          layout_id: layout.id,
          template: "<div><p>hello</p></div>",
          format: :heex
        )

      {:ok, event} = Content.create_page_event(page, "published")
      {:ok, snapshot} = Content.create_page_snapshot(page, event)

      assert snapshot.extra["pubsub"] == %{"info" => [], "event" => []}
    end
  end
end
