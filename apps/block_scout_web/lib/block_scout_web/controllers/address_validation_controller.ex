defmodule BlockScoutWeb.AddressValidationController do
  @moduledoc """
  Display all the blocks that this address validates.
  """
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Account.AuthController, only: [current_user: 1]

  import BlockScoutWeb.Chain,
    only: [paging_options: 1, next_page_params: 3, split_list_by_page: 1]

  import BlockScoutWeb.Models.GetAddressTags, only: [get_address_tags: 2]

  alias BlockScoutWeb.{AccessHelper, BlockView, Controller}
  alias Explorer.{Chain, Market}
  alias Indexer.Fetcher.OnDemand.CoinBalance, as: CoinBalanceOnDemand
  alias Phoenix.View

  def index(conn, %{"address_id" => address_hash_string, "type" => "JSON"} = params) do
    with {:ok, address_hash} <- Chain.string_to_address_hash(address_hash_string),
         {:ok, _} <- Chain.find_or_insert_address_from_hash(address_hash, []),
         {:ok, false} <- AccessHelper.restricted_access?(address_hash_string, params) do
      full_options =
        Keyword.merge(
          [
            necessity_by_association: %{
              miner: :required,
              nephews: :optional,
              transactions: :optional,
              rewards: :optional
            }
          ],
          paging_options(params)
        )

      blocks_plus_one = Chain.get_blocks_validated_by_address(full_options, address_hash)
      {blocks, next_page} = split_list_by_page(blocks_plus_one)

      next_page_path =
        case next_page_params(next_page, blocks, params) do
          nil ->
            nil

          next_page_params ->
            address_validation_path(
              conn,
              :index,
              address_hash_string,
              Map.delete(next_page_params, "type")
            )
        end

      items =
        Enum.map(blocks, fn block ->
          View.render_to_string(
            BlockView,
            "_tile.html",
            conn: conn,
            block: block,
            block_type: BlockView.block_type(block)
          )
        end)

      json(conn, %{items: items, next_page_path: next_page_path})
    else
      {:restricted_access, _} ->
        not_found(conn)

      :error ->
        unprocessable_entity(conn)
    end
  end

  def index(conn, %{"address_id" => address_hash_string} = params) do
    ip = AccessHelper.conn_to_ip_string(conn)

    with {:ok, address_hash} <- Chain.string_to_address_hash(address_hash_string),
         {:ok, address} <- Chain.find_or_insert_address_from_hash(address_hash),
         {:ok, false} <- AccessHelper.restricted_access?(address_hash_string, params) do
      render(
        conn,
        "index.html",
        address: address,
        coin_balance_status: CoinBalanceOnDemand.trigger_fetch(ip, address),
        current_path: Controller.current_full_path(conn),
        counters_path: address_path(conn, :address_counters, %{"id" => address_hash_string}),
        exchange_rate: Market.get_coin_exchange_rate(),
        tags: get_address_tags(address_hash, current_user(conn))
      )
    else
      {:restricted_access, _} ->
        not_found(conn)

      :error ->
        unprocessable_entity(conn)
    end
  end
end
