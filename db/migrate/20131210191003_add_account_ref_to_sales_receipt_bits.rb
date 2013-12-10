class AddAccountRefToSalesReceiptBits < ActiveRecord::Migration
  def change
    add_column :sales_receipt_bits, :account_ref, :string
  end
end
