class AddAccountRefToStPurchases < ActiveRecord::Migration
  def change
    add_column :st_purchases, :account_ref, :string
  end
end
