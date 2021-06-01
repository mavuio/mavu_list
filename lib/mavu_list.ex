defmodule MavuList do
  @moduledoc false

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
    |> handle_columns()
    |> handle_data(source)
  end

  def generate_state(source_id, conf \\ %{}, tweaks \\ %{}) do
    %__MODULE__{
      data: [],
      metadata: %{},
      conf: conf,
      tweaks: tweaks || %{},
      source_id: source_id
    }
  end

  def handle_columns(%__MODULE__{} = state) do
    state
    |> put_in([:metadata, :columns], get_columns_from_conf(state))
  end

  def get_columns_from_conf(%__MODULE__{} = state) do
    state.conf.columns
  end

  def prepare_metadata(state, _source) do
    state
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

  def apply_sort(%Ecto.Query{} = query, conf, [[colname, direction]]) when is_map(conf) do
    db_colname = get_db_colname(conf, colname)

    query
    |> Ecto.Query.exclude(:order_by)
    |> Ecto.Query.order_by([{^direction, ^db_colname}])
  end

  def apply_sort(data, _, _), do: data

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

  def get_db_colname(conf, name) when is_map(conf) and is_atom(name) do
    get_col_conf(conf, name)
    |> case do
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

  def get_length(%Ecto.Query{} = query, %{repo: repo} = _conf),
    do: query |> repo.aggregate(:count)

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
      keyword: "",
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

  def get_label(col, name) when is_atom(name) and is_map(col),
    do: col[:label] || get_label(nil, name)

  def get_label(nil, name) when is_atom(name), do: Phoenix.Naming.humanize(name)

  def get_col(%__MODULE__{} = state, name) when is_atom(name),
    do: state.metadata.columns |> Enum.find(&(&1.name == name))

  def handle_event("toggle_column", msg, source, %__MODULE__{} = state) do
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

  def handle_event("set_page", %{"page" => page}, source, %__MODULE__{} = state) do
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

  def handle_event("set_keyword", %{"keyword" => keyword}, source, %__MODULE__{} = state) do
    state
    |> put_in([:tweaks, :keyword], String.trim(keyword))
    |> put_in([:tweaks, :page], 1)
    |> handle_data(source)
  end

  def handle_event("reprocess", _, source, %__MODULE__{} = state) do
    state
    |> handle_data(source)
  end

  def default_sort(%__MODULE__{} = _state), do: :asc

  def handle_event(event, msg, %__MODULE__{} = state) do
    {event, msg} |> IO.inspect(label: "unknown mavu_list event")

    state
  end
end
