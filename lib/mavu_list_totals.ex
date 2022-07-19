defmodule MavuList.Totals do
  @moduledoc false

  import Ecto.Query

  def total_entries(query, repo, caller) do
    total_entries =
      query
      |> exclude(:preload)
      |> exclude(:order_by)
      |> prepare_select
      |> count
      |> repo.one(caller: caller)

    total_entries || 0
  end

  defp prepare_select(
         %{
           group_bys: [
             %Ecto.Query.QueryExpr{
               expr: [
                 {{:., [], [{:&, [], [source_index]}, field]}, [], []} | _
               ]
             }
             | _
           ]
         } = query
       ) do
    query
    |> exclude(:select)
    |> select([{x, source_index}], struct(x, ^[field]))
  end

  defp prepare_select(query) do
    query
    |> exclude(:select)
  end

  defp count(query) do
    query
    |> subquery
    |> select(count("*"))
  end
end
