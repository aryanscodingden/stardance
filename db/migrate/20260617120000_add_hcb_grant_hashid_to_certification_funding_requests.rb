class AddHCBGrantHashidToCertificationFundingRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :certification_funding_requests, :hcb_grant_hashid, :string
  end
end
