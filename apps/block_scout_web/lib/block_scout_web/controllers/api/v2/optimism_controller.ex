defmodule BlockScoutWeb.API.V2.OptimismController do
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain,
    only: [
      next_page_params: 3,
      paging_options: 1,
      split_list_by_page: 1
    ]

  import BlockScoutWeb.PagingHelper,
    only: [
      delete_parameters_from_next_page_params: 1
    ]

  import Ecto.Query, only: [from: 2]

  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.{Block, Transaction}
  alias Explorer.Chain.Optimism.{Deposit, DisputeGame, FrameSequence, OutputRoot, TxnBatch, Withdrawal}

  action_fallback(BlockScoutWeb.API.V2.FallbackController)

  @doc """
    Function to handle GET requests to `/api/v2/optimism/txn-batches` and
    `/api/v2/optimism/txn-batches/:l2_block_range_start/:l2_block_range_end` endpoints.
  """
  @spec txn_batches(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def txn_batches(conn, params) do
    {batches, next_page} =
      params
      |> paging_options()
      |> Keyword.put(:api?, true)
      |> Keyword.put(:l2_block_range_start, Map.get(params, "l2_block_range_start"))
      |> Keyword.put(:l2_block_range_end, Map.get(params, "l2_block_range_end"))
      |> TxnBatch.list()
      |> split_list_by_page()

    next_page_params = next_page_params(next_page, batches, delete_parameters_from_next_page_params(params))

    conn
    |> put_status(200)
    |> render(:optimism_txn_batches, %{
      batches: batches,
      next_page_params: next_page_params
    })
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/txn-batches/count` endpoint.
  """
  @spec txn_batches_count(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def txn_batches_count(conn, _params) do
    items_count(conn, TxnBatch)
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/batches` endpoint.
  """
  @spec batches(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def batches(conn, params) do
    {batches, next_page} =
      params
      |> paging_options()
      |> Keyword.put(:api?, true)
      |> Keyword.put(:only_view_ready?, true)
      |> FrameSequence.list()
      |> split_list_by_page()

    next_page_params = next_page_params(next_page, batches, params)

    items =
      batches
      |> Enum.map(fn fs ->
        Task.async(fn ->
          l2_block_number_from = batches_edge_l2_block_number(fs.id, :min)
          l2_block_number_to = batches_edge_l2_block_number(fs.id, :max)
          tx_count = batches_tx_count_for_block_range({l2_block_number_from, l2_block_number_to})

          fs
          |> Map.put(:l2_block_range, {l2_block_number_from, l2_block_number_to})
          |> Map.put(:tx_count, tx_count)
        end)
      end)
      |> Task.yield_many(:infinity)
      |> Enum.map(fn {_task, {:ok, item}} -> item end)

    conn
    |> put_status(200)
    |> render(:optimism_batches, %{
      batches: items,
      next_page_params: next_page_params
    })
  end

  defp batches_edge_l2_block_number(id, type) when type == :min do
    Repo.replica().one(
      from(
        tb in TxnBatch,
        select: tb.l2_block_number,
        where: tb.frame_sequence_id == ^id,
        order_by: [asc: tb.l2_block_number],
        limit: 1
      )
    )
  end

  defp batches_edge_l2_block_number(id, type) when type == :max do
    Repo.replica().one(
      from(
        tb in TxnBatch,
        select: tb.l2_block_number,
        where: tb.frame_sequence_id == ^id,
        order_by: [desc: tb.l2_block_number],
        limit: 1
      )
    )
  end

  defp batches_tx_count_for_block_range({l2_block_number_from, l2_block_number_to}) do
    Repo.replica().aggregate(
      from(
        t in Transaction,
        inner_join: b in Block,
        on: b.hash == t.block_hash and b.consensus == true,
        where: t.block_number >= ^l2_block_number_from and t.block_number <= ^l2_block_number_to
      ),
      :count,
      timeout: :infinity
    )
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/batches/count` endpoint.
  """
  @spec batches_count(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def batches_count(conn, _params) do
    items_count(conn, FrameSequence)
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/batches/da/celestia/:height/:commitment` endpoint.
  """
  @spec batch_by_celestia_blob(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def batch_by_celestia_blob(conn, %{"height" => height, "commitment" => commitment}) do
    {height, ""} = Integer.parse(height)

    commitment =
      if String.starts_with?(String.downcase(commitment), "0x") do
        commitment
      else
        "0x" <> commitment
      end

    batch = TxnBatch.batch_by_celestia_blob(commitment, height, api?: true)

    if is_nil(batch) do
      {:error, :not_found}
    else
      conn
      |> put_status(200)
      |> render(:optimism_batch_by_celestia_blob, %{batch: batch})
    end
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/output-roots` endpoint.
  """
  @spec output_roots(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def output_roots(conn, params) do
    {roots, next_page} =
      params
      |> paging_options()
      |> Keyword.put(:api?, true)
      |> OutputRoot.list()
      |> split_list_by_page()

    next_page_params = next_page_params(next_page, roots, params)

    conn
    |> put_status(200)
    |> render(:optimism_output_roots, %{
      roots: roots,
      next_page_params: next_page_params
    })
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/output-roots/count` endpoint.
  """
  @spec output_roots_count(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def output_roots_count(conn, _params) do
    items_count(conn, OutputRoot)
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/games` endpoint.
  """
  @spec games(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def games(conn, params) do
    {games, next_page} =
      params
      |> paging_options()
      |> Keyword.put(:api?, true)
      |> DisputeGame.list()
      |> split_list_by_page()

    next_page_params = next_page_params(next_page, games, params)

    conn
    |> put_status(200)
    |> render(:optimism_games, %{
      games: games,
      next_page_params: next_page_params
    })
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/games/count` endpoint.
  """
  @spec games_count(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def games_count(conn, _params) do
    items_count(conn, DisputeGame)
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/deposits` endpoint.
  """
  @spec deposits(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def deposits(conn, params) do
    {deposits, next_page} =
      params
      |> paging_options()
      |> Keyword.put(:api?, true)
      |> Deposit.list()
      |> split_list_by_page()

    next_page_params = next_page_params(next_page, deposits, params)

    conn
    |> put_status(200)
    |> render(:optimism_deposits, %{
      deposits: deposits,
      next_page_params: next_page_params
    })
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/deposits/count` endpoint.
  """
  @spec deposits_count(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def deposits_count(conn, _params) do
    items_count(conn, Deposit)
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/withdrawals` endpoint.
  """
  @spec withdrawals(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def withdrawals(conn, params) do
    {withdrawals, next_page} =
      params
      |> paging_options()
      |> Keyword.put(:api?, true)
      |> Withdrawal.list()
      |> split_list_by_page()

    next_page_params = next_page_params(next_page, withdrawals, params)

    conn
    |> put_status(200)
    |> render(:optimism_withdrawals, %{
      withdrawals: withdrawals,
      next_page_params: next_page_params
    })
  end

  @doc """
    Function to handle GET requests to `/api/v2/optimism/withdrawals/count` endpoint.
  """
  @spec withdrawals_count(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def withdrawals_count(conn, _params) do
    items_count(conn, Withdrawal)
  end

  defp items_count(conn, module) do
    count = Chain.get_table_rows_total_count(module, api?: true)

    conn
    |> put_status(200)
    |> render(:optimism_items_count, %{count: count})
  end
end
