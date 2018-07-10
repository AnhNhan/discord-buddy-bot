class MemberMessageCounts < ActiveRecord::Migration[5.2]
  def change
    create_table :member_message_counts do |t|
      t.string :uid
      t.integer :count

      t.timestamps
    end
  end
end
