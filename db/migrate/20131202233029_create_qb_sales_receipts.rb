class CreateQbSalesReceipts < ActiveRecord::Migration
  def change
    create_table :qb_sales_receipts do |t|
      t.string :txn_id
      t.string :txn_date
      t.string :ref_number

      t.timestamps
    end
  end
end
