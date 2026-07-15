class AddPayoutBasisVoteIdsToPostShipEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :post_ship_events, :payout_basis_vote_ids, :bigint, array: true, default: [], null: false
  end
end
