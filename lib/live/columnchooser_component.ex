defmodule MavuList.Live.ColumnchooserComponent do
  @moduledoc false
  use MavuListWeb, :live_component

  alias MavuList

  alias Phoenix.LiveView.JS

  @impl true
  def update(%{list: %MavuList{} = list, close_button_id: close_button_id} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       configured_columns: MavuList.get_columns_from_conf(list),
       column_tweaks: MavuList.get_column_tweaks(list),
       columns: MavuList.get_columns_with_tweaks_applied(list),
       target: MavuList.get_target(list),
       close_button_id: close_button_id
     )}
  end
end
