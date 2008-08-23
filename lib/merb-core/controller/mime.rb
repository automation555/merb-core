module Merb
  class << self

    # @return [Hash]
    #   The available mime types.
    def available_mime_types
      ResponderMixin::TYPES
    end

    # Any specific outgoing headers should be included here.  These are not
    # the content-type header but anything in addition to it.
    # +transform_method+ should be set to a symbol of the method used to
    # transform a resource into this mime type.
    # For example for the :xml mime type an object might be transformed by
    # calling :to_xml, or for the :js mime type, :to_json.
    # If there is no transform method, use nil.
    #
    # @note
    # Adding a mime-type adds a render_type method that sets the content
    # type and calls render.
    # 
    # By default this does: def render_all, def render_yaml, def render_text,
    # def render_html, def render_xml, def render_js, and def render_yaml
    #
    # @param key [Symbol]
    #   The name of the mime-type. This is used by the provides API.
    # @param transform_method [~to_s]
    #   The associated method to call on objects to convert them to the
    #   appropriate mime-type. For instance, :json would use :to_json as its
    #   transform_method.
    # @param mimes [Array(String)]
    #   A list of possible values sent in the Accept header, such as text/html,
    #   that should be associated with this content-type.
    # @param new_response_headers [Hash]
    #   The response headers to set for the the mime type. For example: 
    #   'Content-Type' => 'application/json; charset=utf-8'; As a shortcut for
    #   the common charset option, use :charset => 'utf-8', which will be
    #   correctly appended to the mimetype itself.
    # @param block [Proc]
    #   a block which recieves the current controller when the format
    #   is set (in the controller's #content_type method)
    def add_mime_type(key, transform_method, mimes, new_response_headers = {}, default_quality = 1, &block) 
      enforce!(key => Symbol, mimes => Array)
      
      content_type = new_response_headers["Content-Type"] || mimes.first
      
      if charset = new_response_headers.delete(:charset)
        content_type += "; charset=#{charset}"
      end
      
      ResponderMixin::TYPES.update(key => 
        {:accepts           => mimes, 
         :transform_method  => transform_method,
         :content_type      => content_type,
         :response_headers  => new_response_headers,
         :default_quality   => default_quality,
         :response_block    => block })

      mimes.each do |mime|
        ResponderMixin::MIMES.update(mime => key)
      end

      Merb::RenderMixin.class_eval <<-EOS, __FILE__, __LINE__
        def render_#{key}(thing = nil, opts = {})
          self.content_type = :#{key}
          render thing, opts
        end
      EOS
    end

    # Removes a MIME-type from the mime-type list.
    #
    # @param key [Symbol]
    #   The key that represents the mime-type to remove.
    #
    # @note
    # :all is the key for */*; It can't be removed.
    def remove_mime_type(key)
      return false if key == :all
      ResponderMixin::TYPES.delete(key)
    end

    # @param key [Symbol]
    #   The key that represents the mime-type.
    #
    # @return [Symbolc]
    #   The transform method for the mime type, e.g. :to_json.
    #
    # @raise [ArgumentError]
    #   The requested mime type is not valid.
    def mime_transform_method(key)
      raise ArgumentError, ":#{key} is not a valid MIME-type" unless ResponderMixin::TYPES.key?(key)
      ResponderMixin::TYPES[key][:transform_method]
    end

    # The mime-type for a particular inbound Accepts header.
    #
    # @param header [String]
    #   The name of the header to find the mime-type for.
    #
    # @return [Hash]
    #   The mime type information.
    def mime_by_request_header(header)
      available_mime_types.find {|key,info| info[:accepts].include?(header)}.first
    end
    
  end
end
