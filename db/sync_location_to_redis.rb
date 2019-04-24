require 'logger'
require 'redis'
require 'sequel'

REDIS = Redis.new(url: ENV['REDIS_URL'])

DB = Sequel.connect("#{ENV['DATABASE_URL']}/wckdone", max_connections: 10,
                    loggers: [Logger.new($stdout)])

DB[:users].all.each do |u|
  if u[:longitude] && u[:latitude]
    puts
    REDIS.geoadd 'locations', u[:longitude], u[:latitude], u[:id]
  end
end

