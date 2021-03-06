require 'addressable/uri'
require 'gitable/uri'

module Gitable
  class ScpURI < Gitable::URI

    ##
    # Deprecated: This serves no purpose. You might as well just parse the URI.
    def self.scp?(uri)
      $stderr.puts "DEPRECATED: Gitable::ScpURI.scp?. You're better off parsing the URI and checking #scp?."
      Gitable::URI.parse(uri).scp?
    end

    ##
    # Deprecated: This serves no purpose. Just use Gitable::URI.parse.
    def self.parse(uri)
      $stderr.puts "DEPRECATED: Gitable::ScpURI.parse just runs Gitable::URI.parse. Please use this directly."
      Gitable::URI.parse(uri)
    end


    # Keep URIs like this as they were input:
    #
    #     git@github.com:martinemde/gitable.git
    #
    # Without breaking URIs like these:
    #
    #     git@host.com:/home/martinemde/gitable.git
    #
    # @param [String] new_path The new path to be set.
    # @return [String] The same path passed in.
    def path=(new_path)
      super
      if new_path[0..0] != '/' # addressable adds a / but scp-style uris are altered by this behavior
        @path = path.sub(%r|^/+|,'')
        @normalized_path = nil
        validate
      end
      path
    end

    # Get the URI as a string in the same form it was input.
    #
    # Taken from Addressable::URI.
    #
    # @return [String] The URI as a string.
    def to_s
      @uri_string ||=
        begin
          uri_string = "#{normalized_authority}:#{normalized_path}"
          if uri_string.respond_to?(:force_encoding)
            uri_string.force_encoding(Encoding::UTF_8)
          end
          uri_string
        end
    end
    alias to_str to_s

    # Return the actual scheme even though we don't show it
    #
    # @return [String] always 'ssh' for scp style URIs
    def inferred_scheme
      'ssh'
    end

    # Scp style URIs are always ssh
    #
    # @return [true] always ssh
    def ssh?
      true
    end

    # Is this an scp formatted uri? (Yes, always)
    #
    # @return [true] always scp formatted uri
    def scp?
      true
    end

    protected

    def validate
      return if @validation_deferred

      if host.to_s.empty?
        invalid! "Hostname segment missing"
      end

      if !scheme.to_s.empty?
        invalid! "Scp style URI must not have a scheme"
      end

      if !port.to_s.empty?
        invalid! "Scp style URI cannot have a port"
      end

      if path.to_s.empty?
        invalid! "Absolute URI missing hierarchical segment"
      end

      nil
    end

    def invalid!(reason)
      raise InvalidURIError, "#{reason}: '#{to_s}'"
    end
  end
end
