defmodule MavuList do
  @moduledoc false

  @derive {Inspect, only: [:conf]}

  defstruct data: [],
            metadata: %{},
            tweaks: %{},
            conf: %{},
            source_id: nil

  use Accessible

  @default_per_page 20
  require(Ecto.Query)

  def process_list(source, source_id, conf, tweaks \\ %{}) do
    generate_state(source_id, conf, tweaks)
    |> handle_data(source)
  end

  def generate_state(source_id, conf \\ %{}, tweaks \\ %{}) do
    %__MODULE__{
      data: [],
      metadata: %{},
      conf: conf,
      tweaks: handle_incoming_tweaks(tweaks),
      source_id: source_id
    }
  end

  def handle_incoming_tweaks(encoded_tweaks) when is_binary(encoded_tweaks) do
    encoded_tweaks
    |> decode_tweaks_from_string()
    |> MavuUtils.log("mwuits-debug 2022-07-19_09:11 TWEAKS IN", :info)
  end

  def handle_incoming_tweaks(tweaks), do: tweaks || %{}

  def get_columns_from_conf(%__MODULE__{} = state) do
    state.conf.columns
    |> handle_hidden_field_in_columns_conf()
  end

  defp handle_hidden_field_in_columns_conf(columns) when is_list(columns) do
    columns
    |> Enum.map(&handle_hidden_field_in_single_column_conf/1)
  end

  defp handle_hidden_field_in_single_column_conf(%{hidden: hidden} = conf) do
    case hidden do
      a when a in ["no", "false", false, :no] -> %{visible: true, editable: true}
      a when a in ["yes", "true", true, :yes] -> %{visible: false, editable: true}
      "never" -> %{visible: true, editable: false}
      "always" -> %{visible: false, editable: false}
    end
    |> Map.merge(conf)
  end

  defp handle_hidden_field_in_single_column_conf(conf) when is_map(conf) do
    %{visible: true, editable: true}
    |> Map.merge(conf)
  end

  def get_columns_with_tweaks_applied(%__MODULE__{} = state) do
    get_columns_from_conf(state)
    |> apply_column_tweaks(get_column_tweaks(state))
  end

  def apply_column_tweaks(columns, column_tweaks)
      when is_list(columns) and is_list(column_tweaks) do
    tweaks_w_index = Enum.with_index(column_tweaks)

    Enum.with_index(columns, 100)
    |> Enum.map(fn {col, col_idx} ->
      Enum.find(tweaks_w_index, fn {i, _tweak_idx} -> i.name == "#{col.name}" end)
      |> case do
        {%{visible: visible_from_tweak}, tweak_idx} ->
          {Map.put(col, :visible, visible_from_tweak), tweak_idx}

        _ ->
          {col, col_idx}
      end
    end)
    |> Enum.sort_by(fn {_, idx} -> idx end)
    |> Enum.map(fn {col, _} -> col end)
  end

  def prepare_metadata(state, _source) do
    state
    |> put_in(
      [:metadata, :columns],
      get_columns_with_tweaks_applied(state) |> Enum.filter(& &1.visible)
    )
    |> put_in(
      [:metadata, :page],
      get_in(state, [:tweaks, :page]) |> MavuUtils.if_nil(1)
    )
    |> put_in(
      [:metadata, :per_page],
      cond do
        is_integer(get_in(state, [:tweaks, :per_page])) -> get_in(state, [:tweaks, :per_page])
        is_integer(get_in(state, [:conf, :per_page])) -> get_in(state, [:conf, :per_page])
        true -> @default_per_page
      end
    )
  end

  def update_metadata(state, source) do
    state
    |> update_in([:metadata], fn metadata ->
      Map.merge(
        metadata,
        %{total_count: get_length(source, state.conf), count: length(state.data)}
      )
    end)
  end

  def handle_data(%__MODULE__{} = state, source) do
    state = state |> prepare_metadata(source)

    filtered_source =
      source
      |> apply_filter(state.conf, state.tweaks)
      |> MavuList.Ash.apply_ash_filterform(state)
      |> apply_sort(state.conf, get_sort_tweaks(state))

    paged_source =
      filtered_source
      |> apply_paging(state.conf, state.metadata.per_page, state.metadata.page)

    state
    |> update_data(source, paged_source)
    |> update_metadata(filtered_source)
  end

  def apply_filter(source, %{filter: filter} = conf, tweaks) do
    apply(filter, [source, conf, tweaks])
  end

  def apply_filter(source, _, _), do: source

  def apply_sort(data, conf, [[colname, direction]]) when is_map(conf) and is_list(data),
    do: Enum.sort_by(data, &get_sortable_colval(&1, conf, colname), direction)

  def apply_sort(%Ecto.Query{} = query, conf, sort_definitions)
      when is_list(sort_definitions) and is_map(conf) do
    sort_definitions_for_query = Enum.map(sort_definitions, &handle_sort_definition(&1, conf))

    query
    |> Ecto.Query.exclude(:order_by)
    |> Ecto.Query.order_by(^sort_definitions_for_query)
  end

  if Code.ensure_loaded?(Ash) do
    def apply_sort(%Ash.Query{} = query, conf, sort_definitions)
        when is_list(sort_definitions) and is_map(conf) do
      sort_definitions_for_query =
        Enum.map(sort_definitions, &handle_sort_definition_for_ash(&1, conf))

      %{
        sort_definitions: sort_definitions,
        sort_definitions_for_query: sort_definitions_for_query
      }

      query
      |> Ash.Query.unset(:sort)
      |> Ash.Query.sort(sort_definitions_for_query)
    end
  end

  def apply_sort(data, _, _), do: data

  def handle_sort_definition([colname, direction], conf) do
    db_colname = get_db_colname(conf, colname)
    {direction, db_colname}
  end

  def handle_sort_definition_for_ash([colname, direction], conf) do
    db_colname = get_db_colname(conf, colname)

    case direction do
      :asc ->
        db_colname

      _ ->
        {db_colname, direction}
    end
  end

  if Code.ensure_loaded?(Ash) do
    def apply_paging(%Ash.Query{} = query, %{api: api} = _conf, per_page, page)
        when is_integer(per_page) and is_integer(page) do
      query
      |> api.read!(page: [limit: per_page, offset: per_page * (page - 1)])
      |> case do
        items when is_list(items) -> items
        %{results: items} -> items
      end
    end
  end

  def apply_paging(%Ecto.Query{} = query, %{repo: repo} = _conf, per_page, page)
      when is_integer(per_page) and is_integer(page) do
    query
    # |> IO.inspect(label: "mwuits-debug 2021-02-26_17:34 ")
    |> Ecto.Query.limit(^per_page)
    |> Ecto.Query.offset(^(per_page * (page - 1)))
    |> repo.all()
  end

  def apply_paging(data, _conf, per_page, page)
      when is_integer(per_page) and is_integer(page) and is_list(data) do
    Enum.slice(data, per_page * (page - 1), per_page)
  end

  def sort_by(data, conf, _) when is_map(conf) do
    data
  end

  def is_user_sortable?(conf, name) when is_map(conf) and is_atom(name) do
    if get_col_conf(conf, name)[:user_sortable] == false do
      false
    else
      case get_db_colname(conf, name) do
        nil -> false
        _valid_colname -> true
      end
    end
  end

  def get_sortable_colval(row, conf, name) when is_map(row) do
    get_colval(row, conf, name)
    |> case do
      str when is_binary(str) -> String.downcase(str)
      val -> val
    end
  end

  def get_colval(row, conf, name) when is_map(row) do
    get_in(
      row,
      get_col_path(conf, name)
    )
  end

  def get_col_path(conf, name) when is_map(conf) and is_atom(name) do
    get_col_conf(conf, name)
    |> case do
      %{path: path} when is_list(path) -> path
      _ -> [name]
    end
  end

  def get_col_path(conf, path) when is_map(conf) and is_list(path), do: path

  def get_db_colname(conf, name) when is_map(conf) and is_atom(name) do
    get_col_conf(conf, name)
    |> case do
      %{order_by_field: order_by_field} when not is_nil(order_by_field) ->
        order_by_field

      %{path: [single_field_name]} when is_atom(single_field_name) ->
        single_field_name

      %{path: multiple_fieldnames} when is_list(multiple_fieldnames) ->
        nil

      _ ->
        name
    end
  end

  def get_col_conf(conf, name) when is_map(conf) and is_atom(name) do
    get_in(conf, [
      :columns,
      Access.filter(&(&1.name == name))
    ])
    |> List.first()
  end

  def update_data(%__MODULE__{} = state, _source, filtered_data) do
    state
    |> put_in([:data], filtered_data)
  end

  def get_length(source, _) when is_list(source), do: length(source)

  if Code.ensure_loaded?(Ash) do
    def get_length(%Ash.Query{} = query, %{api: api} = _conf) do
      api.read!(query, page: [limit: 1, count: true])
      |> Map.get(:count, 0)
    end
  end

  def get_length(%Ecto.Query{} = query, %{repo: repo} = _conf) do
    MavuList.Totals.total_entries(query, repo, [])
    # query |> repo.aggregate(:count)
  end

  def generate_assigns_for_label_component(%__MODULE__{} = state, name) when is_atom(name) do
    col = get_col(state, name)

    %{
      label: get_label(col, name),
      direction: get_sort_direction_of_column(state, name),
      name: name,
      target: get_target(state),
      is_user_sortable: is_user_sortable?(state.conf, name)
    }
  end

  def generate_assigns_for_pagination_component(%__MODULE__{} = state) do
    %{
      items_per_page: state.metadata.per_page,
      page: state.metadata.page,
      pages_total: ceil(state.metadata.total_count / state.metadata.per_page),
      items_total: state.metadata.total_count,
      items_from: state.metadata.per_page * (state.metadata.page - 1) + 1,
      items_to: min(state.metadata.total_count, state.metadata.per_page * state.metadata.page),
      has_next: state.metadata.page < ceil(state.metadata.total_count / state.metadata.per_page),
      has_prev: state.metadata.page > 1,
      target: get_target(state)
    }
  end

  def generate_assigns_for_searchbox_component(%__MODULE__{} = state) do
    %{
      keyword: state.tweaks[:keyword] || "",
      target: get_target(state)
    }
  end

  def get_target(%__MODULE__{} = state), do: "##{state.source_id}"

  def get_sort_direction_of_column(%__MODULE__{} = state, name) when is_atom(name) do
    get_sort_tweaks(state)
    |> Enum.filter(fn [col_name, _dir] -> col_name == name end)
    |> Enum.map(fn [_col_name, dir] -> dir end)
    |> List.first()
    |> case do
      nil -> nil
      dir when is_binary(dir) -> dir |> List.to_existing_atom()
      dir -> dir
    end
  end

  def get_sort_tweaks(%__MODULE__{} = state) do
    case state.tweaks[:sort_by] do
      items when is_list(items) -> items
      _ -> []
    end
  end

  def get_column_tweaks(%__MODULE__{} = state) do
    case state.tweaks[:columns] do
      items when is_list(items) -> items
      _ -> []
    end
  end

  def get_label(col, name) when is_atom(name) and is_map(col),
    do: col[:label] || get_label(nil, name)

  def get_label(nil, name) when is_atom(name), do: Phoenix.Naming.humanize(name)

  def get_col(%__MODULE__{} = state, name) when is_atom(name),
    do: (state.metadata.columns ++ state.conf.columns) |> Enum.find(&(&1.name == name))

  def handle_event(event, msg, source, %__MODULE__{} = state) do
    # version A) handle state only
    handle_event_in_state(event, msg, source, state)
  end

  def handle_event(socket, event, msg, source, fieldname) when is_atom(fieldname) do
    # version B) handle socket
    socket
    |> Phoenix.Component.assign(
      fieldname,
      handle_event_in_state(
        event,
        msg,
        source,
        socket.assigns[fieldname]
      )
    )
    |> update_param_in_url(fieldname)
  end

  def handle_event_in_state("toggle_column", msg, source, %__MODULE__{} = state) do
    name = msg["name"] |> String.to_existing_atom()

    new_direction =
      case get_sort_direction_of_column(state, name) do
        :asc -> :desc
        :desc -> :asc
        _ -> default_sort(state)
      end

    # state.tweaks |> IO.inspect(label: "mwuits-debug 2021-02-07_23:12 TWEAKS")
    state
    |> put_in([:tweaks, :sort_by], [[name, new_direction]])
    |> put_in([:tweaks, :page], 1)
    |> handle_data(source)
  end

  def handle_event_in_state(
        "set_columns",
        %{"fdata" => %{"columns" => incoming_columns, "col_order" => col_order_str}},
        source,
        %__MODULE__{} = state
      ) do
    cols_with_index =
      incoming_columns
      |> Map.to_list()
      |> Enum.map(fn {idx, col} -> {MavuUtils.to_int(idx), col} end)

    cols_with_index =
      if(col_order_str) do
        cols_with_index
        |> apply_order_to_cols_with_index(col_order_str)
      else
        cols_with_index
      end

    columns =
      cols_with_index
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.map(fn {_, col} ->
        %{name: col["name"], visible: MavuUtils.true?(col["visible"])}
      end)

    state
    |> put_in([:tweaks, :columns], columns)
    |> handle_data(source)
  end

  def handle_event_in_state("set_page", %{"page" => page}, source, %__MODULE__{} = state) do
    pagenum =
      MavuUtils.to_int(page)
      |> case do
        0 -> 1
        num -> num
      end

    state
    |> put_in([:tweaks, :page], pagenum)
    |> handle_data(source)
  end

  def handle_event_in_state("set_keyword", %{"keyword" => keyword}, source, %__MODULE__{} = state) do
    state
    |> put_in([:tweaks, :keyword], String.trim(keyword))
    |> put_in([:tweaks, :page], 1)
    |> handle_data(source)
  end

  def handle_event_in_state(
        "set_filter",
        %{"filter_updates" => new_filter_values},
        source,
        %__MODULE__{} = state
      )
      when is_map(new_filter_values) do
    cleaned_new_filter_values =
      new_filter_values
      |> AtomicMap.convert(safe: true, ignore: true)

    state
    |> update_in([:tweaks, :filters], fn old_filter_values ->
      (old_filter_values || %{})
      |> Map.merge(cleaned_new_filter_values)
      |> Map.to_list()
      |> Enum.filter(fn {_key, val} -> MavuUtils.present?(val) end)
      |> Map.new()
    end)
    |> put_in([:tweaks, :page], 1)
    |> handle_data(source)
  end

  def handle_event_in_state(
        "set_ash_filterform",
        %{"filterform_params" => filterform_params},
        source,
        %__MODULE__{} = state
      ) do
    state
    |> put_in([:tweaks, :ash_filterform], filterform_params)
    |> put_in([:tweaks, :page], 1)
    |> handle_data(source)
  end

  def handle_event_in_state("reprocess", _, source, %__MODULE__{} = state) do
    state
    |> handle_data(source)
  end

  def update_param_in_url(
        %{assigns: %{context: %{current_url: current_url}}} = socket,
        fieldname
      )
      when is_atom(fieldname) do
    # version A: use real push-event if @context is given in assigns
    next_url =
      MavuUtils.update_params_in_url(current_url, [
        {get_url_param_name(fieldname),
         encode_tweaks_to_string(socket.assigns[fieldname][:tweaks])}
      ])

    next_path =
      next_url |> URI.parse() |> Map.take(~w(path query)a) |> Map.values() |> Enum.join("?")

    socket
    |> Phoenix.LiveView.push_patch(to: next_path)
  end

  def update_param_in_url(socket, fieldname) when is_atom(fieldname) do
    # version B: update via JS only if no @context is given

    socket
    |> Phoenix.LiveView.push_event("update_param_in_url", %{
      name: get_url_param_name(fieldname),
      value: encode_tweaks_to_string(socket.assigns[fieldname][:tweaks])
    })
  end

  def get_url_param_name(fieldname) when is_atom(fieldname) or is_binary(fieldname) do
    "#{fieldname}_tweaks"
  end

  defp encode_tweaks_to_string(tweaks) when is_map(tweaks) do
    tweaks |> MavuUtils.log("mwuits-debug 2022-07-19_09:13 encode_tweaks_to_string", :info)
    Jason.encode!(tweaks)
  end

  defp decode_tweaks_from_string(tweaks_str) when is_binary(tweaks_str) do
    Jason.decode!(tweaks_str)
    |> decode_sort_tweaks()
    |> decode_page_tweaks()
    |> decode_column_tweaks()
    |> decode_keyword_tweaks()
    |> decode_filter_tweaks()
    |> decode_ash_filterform_tweaks()
    |> MavuUtils.log("mwuits-debug 2022-07-19_09:20 decode_tweaks_from_string", :info)
  end

  defp decode_sort_tweaks(%{"sort_by" => sort_by} = tweaks) do
    tweaks
    |> Map.drop(["sort_by"])
    |> Map.put(
      :sort_by,
      sort_by
      |> Enum.map(fn [col, dir] ->
        [String.to_existing_atom(col), String.to_existing_atom(dir)]
      end)
    )
  end

  defp decode_sort_tweaks(tweaks), do: tweaks

  defp decode_page_tweaks(%{"page" => page} = tweaks) do
    tweaks
    |> Map.drop(["page"])
    |> Map.put(:page, page)
  end

  defp decode_page_tweaks(tweaks), do: tweaks

  defp decode_keyword_tweaks(%{"keyword" => keyword} = tweaks) do
    tweaks
    |> Map.drop(["keyword"])
    |> Map.put(:keyword, keyword)
  end

  defp decode_keyword_tweaks(tweaks), do: tweaks

  defp decode_filter_tweaks(%{"filters" => filters} = tweaks) do
    tweaks
    |> Map.drop(["filters"])
    |> Map.put(:filters, filters |> AtomicMap.convert(safe: true, ignore: true))
  end

  defp decode_filter_tweaks(tweaks), do: tweaks

  defp decode_ash_filterform_tweaks(%{"ash_filterform" => ash_filterform} = tweaks) do
    tweaks
    |> Map.drop(["ash_filterform"])
    |> Map.put(:ash_filterform, ash_filterform)
  end

  defp decode_ash_filterform_tweaks(tweaks), do: tweaks

  defp decode_column_tweaks(%{"columns" => columns} = tweaks) do
    tweaks
    |> Map.drop(["columns"])
    |> Map.put(:columns, columns |> AtomicMap.convert(safe: true, ignore: true))
  end

  defp decode_column_tweaks(tweaks), do: tweaks

  def default_sort(%__MODULE__{} = _state), do: :asc

  def handle_event_in_state(event, msg, %__MODULE__{} = state) do
    {event, msg} |> IO.inspect(label: "unknown mavu_list event")

    state
  end

  defp apply_order_to_cols_with_index(cols_with_index, col_order_str)
       when is_list(cols_with_index) and is_binary(col_order_str) do
    pos_map = col_order_str |> String.split(",")

    cols_with_index
    |> Enum.map(fn {idx, col} ->
      case Enum.find_index(pos_map, &(&1 == col["name"])) do
        nil -> {idx, col}
        new_idx -> {new_idx, col}
      end
    end)
  end

  @builtin_short_names [
    map: "Ash.Type.Map",
    keyword: "Ash.Type.Keyword",
    term: "Ash.Type.Term",
    atom: "Ash.Type.Atom",
    string: "Ash.Type.String",
    integer: "Ash.Type.Integer",
    float: "Ash.Type.Float",
    duration_name: "Ash.Type.DurationName",
    function: "Ash.Type.Function",
    boolean: "Ash.Type.Boolean",
    struct: "Ash.Type.Struct",
    uuid: "Ash.Type.UUID",
    binary: "Ash.Type.Binary",
    date: "Ash.Type.Date",
    time: "Ash.Type.Time",
    decimal: "Ash.Type.Decimal",
    ci_string: "Ash.Type.CiString",
    naive_datetime: "Ash.Type.NaiveDatetime",
    utc_datetime: "Ash.Type.UtcDatetime",
    utc_datetime_usec: "Ash.Type.UtcDatetimeUsec",
    url_encoded_binary: "Ash.Type.UrlEncodedBinary",
    union: "Ash.Type.Union",
    module: "Ash.Type.Module",
    uuid: "AshUUID.UUID"
  ]
  @custom_short_names Application.compile_env(:ash, :custom_types, [])

  @short_names @custom_short_names ++ @builtin_short_names

  def to_ash_shortname({:array, item_type}) do
    "array_of_#{to_ash_shortname(item_type)}"
  end

  def to_ash_shortname(long_type) do
    long_type_str =
      long_type
      |> to_string()
      |> String.replace_prefix("Elixir.", "")

    @short_names
    |> Enum.find_value(fn {shortname, longname} ->
      if longname == long_type_str do
        shortname
      end
    end)
    |> MavuUtils.if_nil(long_type_str |> String.replace(".", "") |> Macro.underscore())
  end

  def get_columns_from_ash_resource(resource_name) when is_atom(resource_name) do
    Ash.Resource.Info.attributes(resource_name)
    |> Enum.map(fn attr -> %{name: attr.name, type: attr.type |> to_ash_shortname()} end)
  end
end
