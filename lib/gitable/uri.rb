require 'addressable/uri'

module Gitable
  class URI < Addressable::URI

    ##
    # Parse a git repository URI into a URI object.
    #
    # @param [Addressable::URI, #to_str] uri URI of a git repository.
    #
    # @return [Gitable::URI, nil] the URI object or nil if nil was passed in.
    #
    # @raise [TypeError] The uri must respond to #to_str.
    # @raise [Gitable::URI::InvalidURIError] When the uri is *total* rubbish.
    #
    def self.parse(uri)
      return nil if uri.nil?
      return uri.dup if uri.kind_of?(self)

      # Copied from Addressable to speed up our parsing.
      #
      # If a URI object of the Ruby standard library variety is passed,
      # convert it to a string, then parse the string.
      # We do the check this way because we don't want to accidentally
      # cause a missing constant exception to be thrown.
      if uri.class.name =~ /^URI\b/
        uri = uri.to_s
      end

      # Otherwise, convert to a String
      begin
        uri = uri.to_str
      rescue TypeError, NoMethodError
        raise TypeError, "Can't convert #{uri.class} into String."
      end if not uri.is_a? String

      addr = super(uri)

      # nil host is our sign that it's an scp URI that addressable can't parse
      if uri.match(ScpURI::REGEXP) && addr.normalized_host.nil?
        authority, path = uri.scan(ScpURI::REGEXP).flatten
        Gitable::ScpURI.new(:authority => authority, :path => path)
      else
        addr
      end
    end

    ##
    # Parse a git repository URI into a URI object.
    # Rescue parse errors and return nil if uri is not parseable.
    #
    # @param [Addressable::URI, #to_str] uri URI of a git repository.
    #
    # @return [Gitable::URI, nil] The parsed uri, or nil if not parseable.
    def self.parse_when_valid(uri)
      parse(uri)
    rescue TypeError, Gitable::URI::InvalidURIError
      nil
    end

    ##
    # Attempts to make a copied URL bar into a git repository URI.
    #
    # First line of defense is for URIs without .git as a basename:
    # * Change the scheme from http:// to git://
    # * Add .git to the basename
    #
    # @param [Addressable::URI, #to_str] uri URI of a git repository.
    #
    # @return [Gitable::URI, nil] the URI object or nil if nil was passed in.
    #
    # @raise [TypeError] The uri must respond to #to_str.
    # @raise [Gitable::URI::InvalidURIError] When the uri is *total* rubbish.
    #
    def self.heuristic_parse(uri)
      return uri if uri.nil? || uri.kind_of?(self)

      # Addressable::URI.heuristic_parse _does_ return the correct type :)
      gitable = super # boo inconsistency

      if gitable.github?
        gitable.extname = "git"
      end
      gitable
    end

    # Is this uri a github uri?
    #
    # @return [Boolean] github.com is the host?
    def github?
      !!normalized_host.to_s.match(/\.?github.com$/)
    end

    # Create a web link uri for repositories that follow the github pattern.
    #
    # This probably won't work for all git hosts, so it's a good idea to use
    # this in conjunction with #github? to help ensure correct links.
    #
    # @param [String] Scheme of the web uri (smart defaults)
    # @return [Addressable::URI] https://#{host}/#{path_without_git_extension}
    def to_web_uri(uri_scheme='https')
      return nil if normalized_host.to_s.empty?
      Addressable::URI.new(:scheme => uri_scheme, :host => normalized_host, :port => normalized_port, :path => normalized_path.sub(%r#\.git/?$#, ''))
    end

    # Tries to guess the project name of the repository.
    #
    # @return [String] Project name without .git
    def project_name
      basename.sub(/\.git$/,'')
    end

    # Detect local filesystem URIs.
    #
    # @return [Boolean] Is the URI local
    def local?
      inferred_scheme == 'file'
    end

    # Scheme inferred by the URI (URIs without hosts or schemes are assumed to be 'file')
    #
    # @return [Boolean] Is the URI local
    def inferred_scheme
      if normalized_scheme == 'file' || (normalized_scheme.to_s.empty? && normalized_host.to_s.empty?)
        'file'
      else
        normalized_scheme
      end
    end

    # Detect URIs that connect over ssh
    #
    # @return [Boolean] true if the URI uses ssh?
    def ssh?
      !!normalized_scheme.to_s.match(/ssh/)
    end

    # Is this an scp formatted uri? (No, always)
    #
    # @return [false] always false (overridden by scp formatted uris)
    def scp?
      false
    end

    # Detect URIs that will require some sort of authentication
    #
    # @return [Boolean] true if the URI uses ssh or has a user but no password
    def authenticated?
      ssh? || interactive_authenticated?
    end

    # Detect URIs that will require interactive authentication
    #
    # @return [Boolean] true if the URI has a user, but is not using ssh
    def interactive_authenticated?
      !ssh? && (!normalized_user.nil? && normalized_password.nil?)
    end

    # Detect if two URIs are equivalent versions of the same uri.
    #
    # When both uris are github repositories, uses a more lenient matching
    # system is used that takes github's repository organization into account.
    #
    # For non-github URIs this method requires the two URIs to have the same
    # host, equivalent paths, and either the same user or an absolute path.
    #
    # @return [Boolean] true if the URI probably indicates the same repository.
    def equivalent?(other_uri)
      other = Gitable::URI.parse(other_uri)

      same_host = normalized_host.to_s == other.normalized_host.to_s

      if github? && other.github?
        # github doesn't care about relative vs absolute paths in scp uris (so we can remove leading / for comparison)
        same_path = normalized_path.sub(%r#\.git/?$#, '').sub(%r#^/#,'') == other.normalized_path.sub(%r#\.git/?$#, '').sub(%r#^/#,'')
        same_host && same_path
      else
        same_path = normalized_path.sub(%r#/$#,'').to_s == other.normalized_path.sub(%r#/$#,'').to_s # remove trailing slashes.
        same_user = normalized_user == other.normalized_user

        # if the path is absolute, we can assume it's the same for all users (so the user doesn't have to match).
        same_host && same_path && (path =~ %r#^/# || same_user)
      end
    rescue Gitable::URI::InvalidURIError
      false
    end

    # Dun da dun da dun, Inspector Gadget.
    #
    # @return [String] I'll get you next time Gadget, NEXT TIME!
    def inspect
      "#<#{self.class.to_s} #{to_s}>"
    end

    # Set an extension name, replacing one if it exists.
    #
    # If there is no basename (i.e. no words in the path) this method call will
    # be ignored because it is likely to break the uri.
    #
    # Use the public method #set_git_extname unless you actually need some other ext
    #
    # @param [String] New extension name
    # @return [String] extname result
    def extname=(new_ext)
      return nil if basename.to_s.empty?
      self.basename = "#{basename.sub(%r#\.git/?$#, '')}.#{new_ext.sub(/^\.+/,'')}"
      extname
    end

    # Set the '.git' extension name, replacing one if it exists.
    #
    # If there is no basename (i.e. no words in the path) this method call will
    # be ignored because it is likely to break the uri.
    #
    # @return [String] extname result
    def set_git_extname
      self.extname = "git"
    end

    # Addressable does basename wrong when there's no basename.
    # It returns "/" for something like "http://host.com/"
    def basename
      super == "/" ? "" : super
    end

    # Set the basename, replacing it if it exists.
    #
    # @param [String] New basename
    # @return [String] basename result
    def basename=(new_basename)
      base = basename
      if base.to_s.empty?
        self.path += new_basename
      else
        rpath = normalized_path.reverse
        # replace the last occurrence of the basename with basename.ext
        self.path = rpath.sub(%r|#{Regexp.escape(base.reverse)}|, new_basename.reverse).reverse
      end
      basename
    end
  end
end

require 'gitable/scp_uri'
