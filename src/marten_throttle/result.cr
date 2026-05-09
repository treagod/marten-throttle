module MartenThrottle
  # Outcome of a `Strategy#check` call.
  struct Result
    getter count : Int32
    getter limit : Int32
    getter retry_after : Int32

    def initialize(@allowed : Bool, @count : Int32, @limit : Int32, @retry_after : Int32)
    end

    def allowed? : Bool
      @allowed
    end
  end
end
