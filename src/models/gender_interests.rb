class GenderInterest < Sequel::Model
  plugin :validation_helpers

  def validate
    super
    validates_presence [:user_id, :gender]
    unless User.genders.include?(gender)
      errors.add(:gender, 'is not correct')
    end
  end
end
