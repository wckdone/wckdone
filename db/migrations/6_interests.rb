Sequel.migration do
  up do
    create_table(:gender_interests) do
      primary_key :id
      Bignum :user_id, null: false
      String :gender
      index [:user_id, :gender], unique: true
      index [:gender, :user_id]
    end
    DB[:users].all.each do |u|
      if u[:into_females]
        DB[:gender_interests].insert(
          user_id: u[:id],
          gender: 'female'
        )
      end
      if u[:into_males]
        DB[:gender_interests].insert(
          user_id: u[:id],
          gender: 'male'
        )
      end
    end
  end
end
