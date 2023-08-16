defmodule MavuList.Ash do

  if Code.ensure_loaded?(Ash) do

  def get_filterform_module(_listconf) do
    MyAppBe.MavuListAshfilter.FilterForm
  end

def get_ash_filter_form(%MavuList{conf: conf,tweaks: tweaks}=list) do

    if is_nil(conf[:ash_resource]) do
      raise "MavuList config should contain an 'ash_resource' entry"
    end

    if is_nil(conf[:ashfilter_conf]) do
      raise "MavuList config should contain an 'ashfilter_conf' entry"
    end

   get_filterform_module(conf).new(conf[:ash_resource], params: (tweaks[:ash_filterform] || %{}), mavu_list: list )

  end


  def apply_ash_filterform(%Ash.Query{} = query,  list = %MavuList{conf: conf, tweaks: %{ash_filterform: filterform_params}}) do

    filter_form= get_filterform_module(conf).new(conf[:ash_resource], mavu_list: list, params: (filterform_params || %{})  )

    case get_filterform_module(conf).filter(query, filter_form) do
      {:ok, modified_query} ->
        # AshPhoenix.FilterForm.to_filter_expression(filter_form)
        # |> MavuUtils.log(
        #   "mwuits-debug 2023-08-10_17:57 [#{elem(__ENV__.function, 0)}]: clgreen",
        #   :info
        # )

        modified_query


      {:error, _filter_form} ->
        query
    end


  end


end

def apply_ash_filterform(source, _mavu_list) do
  source
end

end
