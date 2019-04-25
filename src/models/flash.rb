class Flash
  def initialize(token)
    @token = token
    @message = REDIS.with do |conn|
      msg = conn.get("flash:#{@token}")
      conn.del("flash:#{@token}")
      msg
    end
  end

  def message= msg
      REDIS.with do |conn|
        conn.set("flash:#{@token}", msg)
      end
  end

  def message
    @message
  end
end
