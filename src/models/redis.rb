require 'redis'
require 'connection_pool'

REDIS = ConnectionPool.new(size: 10) { Redis.new(url: ENV['REDIS_URL']) }
