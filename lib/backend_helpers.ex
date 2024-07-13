defmodule MavuList.BackendHelpers do
  import Phoenix.HTML
  import Phoenix.HTML.Form
  use PhoenixHTMLHelpers

  def tw_class(class_name, opts \\ [])

  def tw_class(:narrow_container, _), do: "max-w-md  mx-auto"
  def tw_class(_, _), do: ""

  def remove_tag_params(html, tags_to_remove) when is_list(tags_to_remove) do
    {:safe,
     Phoenix.HTML.html_escape(html)
     |> Phoenix.HTML.safe_to_string()
     |> Floki.parse_fragment!()
     |> Floki.find_and_update(
       "input",
       fn
         {name, attributes, children} ->
           {name, remove_attributes(attributes, tags_to_remove), children}

         {name, attributes} ->
           {name, remove_attributes(attributes, tags_to_remove)}

         other ->
           other
       end
     )
     |> Floki.raw_html()}
  end

  def remove_attributes(attributes, tags_to_remove) when is_list(tags_to_remove) do
    # {attributes, tags_to_remove} |> MyApp.Error.die(label: "mwuits-debug 2021-01-16_20:06 ")
    attributes
    |> Enum.filter(fn {key, _val} ->
      key not in tags_to_remove
    end)
  end

  def tw_icon(icon_fun, size) when is_integer(size) and is_function(icon_fun, 1) do
    icon_fun.(class: "w-#{size} h-#{size}") |> Phoenix.HTML.raw()
  end

  def tw_icon(icon_fun, class) when is_binary(class) and is_function(icon_fun, 1) do
    icon_fun.(class: class) |> Phoenix.HTML.raw()
  end

  def tw_icon(icon_fun, opts) when is_list(opts) and is_function(icon_fun, 1) do
    icon_fun.(opts) |> Phoenix.HTML.raw()
  end

  defdelegate local_date(utc_date), to: MyAppWeb.MyHelpers

  defdelegate format_date(utc_date), to: MyAppWeb.MyHelpers

  defdelegate trans(lang_or_params, txt_en, txt_de \\ nil), to: MyAppWeb.MyHelpers

  defdelegate lang_from_params(lang_or_params), to: MyAppWeb.MyHelpers

  defdelegate if_empty(val, default_val), to: MavuUtils
  defdelegate if_nil(val, default_val), to: MavuUtils
  defdelegate present?(term), to: MavuUtils
  defdelegate empty?(term), to: MavuUtils
  defdelegate true?(term), to: MavuUtils
  defdelegate false?(term), to: MavuUtils

  # def s(_lang_or_params, _key, default \\ nil, _variables \\ []), do: default

  # defdelegate s(lang_or_params, key, default \\ nil, variables \\ []),
  # to: MyAppWeb.MyHelpers
end
