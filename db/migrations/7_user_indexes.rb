Sequel.migration do
  up do
    drop_column :users, :into_males
    drop_column :users, :into_females
    drop_index :users, [:review_status, :into_females, :gender, :longitude]
    drop_index :users, [:review_status, :into_males, :gender, :longitude]
    drop_index :users, [:review_status, :into_females, :longitude]
    drop_index :users, [:review_status, :into_males, :longitude]
    add_index :users, [:review_status, :gender, :longitude]
  end
end
