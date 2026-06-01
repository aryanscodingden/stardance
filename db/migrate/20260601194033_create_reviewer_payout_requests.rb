class CreateReviewerPayoutRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :reviewer_payout_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount
      t.integer :adjusted_amount
      t.text :adjust_reason
      t.integer :paid_amount
      t.string :aasm_state, null: false, default: "pending"
      t.references :admin, null: true, foreign_key: { to_table: :users }
      t.datetime :paid_at

      t.timestamps
    end
  end
end
