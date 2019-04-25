class User < Sequel::Model
  plugin :validation_helpers

  one_to_many :photos
  one_to_many :gender_interests
  
  attr_accessor :password
  
  @@genders = ['female', 'male', 'non-binary']
  def self.genders
    @@genders
  end

  @@review_statuses = [:pending, :approved, :rejected, :banned]
  def self.review_statuses
    @@review_statuses
  end

  def validate
    super
    validates_presence [:username, :birth_date, :gender]
    validates_unique :username
    validates_min_length 4, :username
    validates_max_length 24, :username
    validates_format /\A[0-9a-zA-Z]+\z/, :username
    if !password.nil? && password.length < 6
      errors.add(:password, 'is shorter than 6 characters')
    end
    unless User.genders.include?(gender)
      errors.add(:gender, 'is not correct') 
    end
    unless birth_date.next_year(18) < Date.today
      errors.add(:birth_date, 'is invalid. You need to be 18+')
    end
  end

  def before_save
    if self.password && self.password.length > 0
      self.password_digest = BCrypt::Password.create(self.password)
    end
    super
  end

  def check_password(password)
    correct = BCrypt::Password.new(self.password_digest)
    correct == password
  end

  def is_approved?
    self.review_status == 'approved'
  end

  def is_pending?
    self.review_status == 'pending'
  end

  def self.all_pending_review
    User.where(review_status: 'pending').reverse(:verified_photo_uploaded_on).
      limit(100)
  end

  def set_verified_photo name
    self.verified_photo = name
    self.review_status = :pending
    self.verified_photo_uploaded_on = Time.now
    self.save_changes
    EmailWorker.perform_async(self.id)
  end

  def delete_verified_photo
    self.verified_photo = nil
    self.review_status = nil
    self.verified_photo_uploaded_on = Time.now
    self.save_changes
  end

  def set_review_status reviewer_id, status, reason = nil
    return unless review_status == 'pending'
    return unless [:approved, :rejected].include?(status.to_sym)
    self.reviewer_id = reviewer_id
    self.review_status = status
    self.review_reason = reason
    self.reviewed_on = DateTime.now
    self.save_changes
  end

  def log_visit ip
    self.last_visit = DateTime.now
    if self.last_ip != ip
      self.last_ip = ip
      LocationWorker.perform_async(self.id, ip)
    end
    self.save_changes
  end

  def set_location(location)
    self.longitude = location['longitude']
    self.latitude = location['latitude']
    self.location = "#{location['city']}, #{location['region_name']}, " +
                    "#{location['country_name']}"
    REDIS.with do |conn|
      conn.geoadd 'locations', self.longitude, self.latitude, self.id
    end
    self.save_changes
  end

  def set_description(description)
    self.description = sanitize(description)
    self.save_changes
  end

  def get_candidates(distance, limit = nil)
    coords = Geo.bounding_box(self.latitude, self.longitude, distance * 1.6)
    genders = gender_interests.each.map{|g| "gender = '#{g.gender}'"}.join(' OR ')
    filter = Sequel.lit("latitude BETWEEN #{coords[0]} AND #{coords[2]} " +
                        "AND longitude BETWEEN #{coords[1]} AND #{coords[3]} AND " +
                        "(#{genders}) AND " +
                        "review_status = 'approved' AND " +
                        "id != #{self.id} AND " +
                        "(id IN (SELECT user_id FROM gender_interests WHERE " +
                        "gender = '#{self.gender}')) AND " +
                        "(id NOT IN (SELECT destination FROM actions " +
                        "WHERE source = #{self.id}))")
    if limit
      User.where(filter).limit(limit)
    else
      User.where(filter).order(:last_visit)
    end
  end

  def next_candidate
    [50, 100, 500, 1000].each do |distance|
      candidates = self.get_candidates(distance, 1)
      first = candidates.first
      return first unless first.nil?
    end
    nil
  end

  def get_matches
    filter = Sequel.lit('id IN ' +
                        '(SELECT destination FROM actions WHERE ' +
                        'source = ? AND action = ?) AND ' +
                        'id IN (SELECT source FROM actions WHERE ' +
                        'destination = ? AND action = ?)',
                        id, 'like', id, 'like')
    User.where(filter)
  end
  
  def age
    ((Date.today - self.birth_date) / 365).floor
  end

  def distance_from u
    km = Geo.distance(self.latitude, self.longitude, u.latitude, u.longitude)
    miles = km / 1.6
    if miles < 10
      return 10
    elsif miles < 25
      return 25
    elsif miles < 100
      return (miles / 25).floor * 25
    elsif miles < 300
      return (miles / 50).floor * 50
    else
      return (miles / 100).floor * 100
    end
  end

  def get_match id
    return nil unless Action.is_a_match?(self.id, id)
    User.find(id: id)
  end

  def sanitize_keywords keywords
    keywords.gsub(/[^0-9a-zA-Z ]/i, '').split(/\W+/).map{|k| "+#{k}"}.join(' ')
  end

  def new_search_do search_id, gender, into, keywords, distance
    return nil unless User.genders.include?(gender)
    return nil unless User.genders.include?(into)
    keywords = sanitize_keywords keywords
    coords = Geo.bounding_box(self.latitude, self.longitude, distance * 1.6)
    
    full_text = if keywords&.length > 0
                  "MATCH(description) AGAINST ('#{keywords}' IN BOOLEAN MODE) AND "
                else
                  ""
                end
    location = if distance > 0
                 "latitude BETWEEN #{coords[0]}  AND #{coords[2]} " +
                   "AND longitude BETWEEN #{coords[1]} AND #{coords[3]} AND "
               else
                 ""
               end
    sql = "SELECT id FROM users WHERE "+
          "#{location} gender = '#{gender}' AND " +
          "#{full_text} review_status = 'approved' AND " +
          "(id IN (SELECT user_id FROM gender_interests "+
          "        WHERE gender = '#{into}')) AND " +
          "id != #{self.id} ORDER BY last_visit"
    results = DB[sql].all.map{|r| r[:id]}
    REDIS.with do |conn|
      conn.set("search:#{self.id}", results.to_json)
    end
  end

  def new_search gender, into, keywords, distance
    new_search_do self.search_id, gender, into, keywords, distance
  end

  def search_results start = 0
    data = REDIS.with do |conn|
      conn.get("search:#{self.id}")
    end
    results = JSON.parse(data)
    count = results.length
    range = (start..[start + 25, count].min)
    next_id = start + 25
    next_id = nil if start + 25 >= count
    [next_id, User.where(id: range.map{|i| results[i]}).all]
  end

  def has_unread
    Message.count_unread_for(self) > 0
  end

  def email_update email, notifications
    email = nil if email == ''
    update_email = email != self.email
    if update_email
      self.email = email
      self.is_email_verified = false
      self.email_verification_token = SecureRandom.hex
    end
    self.email_notifications = notifications
    return unless self.valid?
    self.save_changes
    EmailVerificationWorker.perform_async(self.id) if update_email
  end

  def email_verify token
    return unless token && token == self.email_verification_token
    self.is_email_verified = true
    self.save_changes
  end

  def is_interested_in? gender
    gender_interests.each do |i|
      return true if i.gender == gender
    end
    return false
  end

  def set_gender_interests interests
    interests.each do |i|
      return unless User.genders.include?(i)
      self.add_gender_interest(gender: i) unless is_interested_in? i
    end
    self.gender_interests.each do |i|
      i.delete unless interests.include?(i.gender)
    end
  end

  def password_change args
    unless check_password(args[:old_password])
      return errors.add(:old_password, 'is not correct')
    end
    unless args[:password] == args[:repeat_password]
      return errors.add(:repeat_password, "doesn't match new password")
    end
    # Just change self.password here doesn't work
    self.password_digest = BCrypt::Password.create(args[:password])
    self.save_changes
  end
end
