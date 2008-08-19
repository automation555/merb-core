module Merb

  module SessionMixin

    # Adds a before and after dispatch hook for setting up the memory session
    # store.
    #
    # ==== Parameters
    # base<Class>:: The class to which the SessionMixin is mixed into.
    def setup_session
      orig_sid = cookies[_session_id_key]
      session = Merb::MemorySession.persist(orig_sid)
      request.session = session
      if session.session_id != orig_sid 
        set_session_id_cookie(session.session_id)
      end
    end

    # Finalizes the session by storing the session ID in a cookie, if the
    # session has changed.
    def finalize_session
      if request.session.needs_new_cookie or @_new_cookie
        set_session_id_cookie(request.session.session_id)
      end
    end

    # ==== Returns
    # String:: The session store type, i.e. "memory".
    def session_store_type
      "memory"
    end
    
  end
  
  # Sessions stored in memory.
  #
  # Set it up by adding the following to your init file:
  #
  #  Merb::Config.use do |c|
  #    c[:session_store]      = :memory
  #    c[:memory_session_ttl] = 3600 # in seconds, one hour
  #  end
  #
  # Sessions will remain in memory until the server is stopped or the time
  # as set in :memory_session_ttl expires.
  class MemorySession < SessionStore
    
    class << self

      # Generates a new session ID and creates a new session.
      #
      # ==== Returns
      # MemorySession:: The new session.
      def generate
        sid = Merb::SessionMixin::rand_uuid
        MemorySessionContainer[sid] = new(sid)
      end

      # ==== Parameters
      # session_id<String:: The ID of the session to retrieve.
      #
      # ==== Returns
      # Array::
      #   A pair consisting of a MemorySession and the session's ID. If no
      #   sessions matched session_id, a new MemorySession will be generated.
      def persist(session_id)
        session_id.blank? ? generate : MemorySessionContainer[session_id] || generate
      end
      
      # ==== Returns
      # String:: The session store type, i.e. "memory".
      def session_store_type
        "memory"
      end

    end
    
    # Regenerate the Session ID
    def regenerate
      new_sid = Merb::SessionMixin::rand_uuid 
      old_sid = @session_id
      MemorySessionContainer[new_sid] = MemorySessionContainer[old_sid]
      @session_id = new_sid
      MemorySessionContainer.delete(old_sid)
      refresh_expiration
    end
    
  end
  
  # Used for handling multiple sessions stored in memory.
  class MemorySessionContainer
    class << self

      # ==== Parameters
      # ttl<Fixnum>:: Session validity time in seconds. Defaults to 1 hour.
      #
      # ==== Returns
      # MemorySessionContainer:: The new session container.
      def setup(ttl=nil)
        @sessions = Hash.new
        @timestamps = Hash.new
        @mutex = Mutex.new
        @session_ttl = ttl || 60*60 # default 1 hour
        start_timer
        self
      end

      # Creates a new session based on the options.
      #
      # ==== Parameters
      # opts<Hash>:: The session options (see below).
      #
      # ==== Options (opts)
      # :session_id<String>:: ID of the session to create in the container.
      # :data<MemorySession>:: The session to create in the container.
      def create(opts={})
        self[opts[:session_id]] = opts[:data]
      end

      # ==== Parameters
      # key<String>:: ID of the session to retrieve.
      #
      # ==== Returns
      # MemorySession:: The session corresponding to the ID.
      def [](key)
        @mutex.synchronize {
          @timestamps[key] = Time.now
          @sessions[key]
        }
      end

      # ==== Parameters
      # key<String>:: ID of the session to set.
      # val<MemorySession>:: The session to set.
      def []=(key, val) 
        @mutex.synchronize {
          @timestamps[key] = Time.now
          @sessions[key] = val
        } 
      end

      # ==== Parameters
      # key<String>:: ID of the session to delete.
      def delete(key)
        @mutex.synchronize {
          @sessions.delete(key)
          @timestamps.delete(key)
        }
      end

      # Deletes any sessions that have reached their maximum validity.
      def reap_old_sessions
        @timestamps.each do |key,stamp|
          if stamp + @session_ttl < Time.now
            delete(key)
          end  
        end
        GC.start
      end

      # Starts the timer that will eventually reap outdated sessions.
      def start_timer
        Thread.new do
          loop {
            sleep @session_ttl
            reap_old_sessions
          } 
        end  
      end

      # ==== Returns
      # Array:: The sessions stored in this container.
      def sessions
        @sessions
      end  
      
    end # end singleton class

  end # end MemorySessionContainer
end

Merb::MemorySessionContainer.setup(Merb::Config[:memory_session_ttl])
