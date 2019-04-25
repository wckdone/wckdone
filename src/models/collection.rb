require 'set'

class Collection
  def self.name= name
    @@name = name
  end
  
  def self.name
    return name
  end

  def self.field *fields
    @@fields ||= Set.new
    @@fields += Set.new fields
  end

  def self.fields
    return @@fields.to_a
  end
end

class Users < Collection
  field :username, :password  
end
