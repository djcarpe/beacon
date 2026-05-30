defmodule Beacon.Content.ComponentHandlersTest do
  use Beacon.DataCase, async: true
  alias Beacon.Content.Component

  test "changeset casts :handlers map" do
    attrs = %{site: :my_site, name: "vin_ticker", template: "<div></div>", example: "<div></div>", category: :data,
              handlers: %{"info" => ["andon_vin_tick"], "event" => []}}
    cs = Component.changeset(%Component{}, attrs)
    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :handlers) == %{"info" => ["andon_vin_tick"], "event" => []}
  end

  test "handlers defaults to empty map" do
    attrs = %{site: :my_site, name: "plain", template: "<div></div>", example: "<div></div>", category: :element}
    cs = Component.changeset(%Component{}, attrs)
    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :handlers) == %{}
  end
end
