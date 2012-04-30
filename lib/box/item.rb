require 'box/comment'

module Box
  # Mix-in for objects that can update their information from the API.
  module CanUpdateInfo
    module ClassMethods
      def type
        @@type rescue self.name.split("::").last.downcase
      end

      def types
        self.type + "s"
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def type; self.class.type; end
    def types; self.class.types; end

    def reload!
      update_info(get_info)
      self
    end

    protected

    # Fetches this item's info from the api.
    #
    # @return [Hash] The info for the item.
    def get_info
      raise "not implemented"
    end

    # Merges in the given info, making sure the fields are uniform.
    # This is done because the api will occasionally return fields like
    # 'file_id', but we want just 'id'.
    #
    # @param [Hash] info A hash to be merged this item's info
    def update_info(info)
      ninfo = Hash.new

      # some fields are named 'file_id' or 'id' inconsistently, so trim the type off
      info.each do |name, value|
        if name.to_s =~ /^#{ type }_(.+)$/
          ninfo[$1] = value
        else
          ninfo[name.to_s] = value
        end
      end

      @data.merge!(ninfo) # merge in the updated info
    end
  end

  # Represents a folder or file stored on Box. Any attributes or actions
  # typical to a Box item can be accessed through this class. The {Item}
  # class contains only methods shared by {Folder} and {File}, and should
  # not be instanciated directly.

  class Item
    include CanUpdateInfo

    # @return [Hash] The hash of info for this item.
    attr_accessor :data

    # @return [Api] The {Api} used by this item.
    attr_accessor :api

    # @return [Folder] The parent of this item.
    attr_accessor :parent

    # Create a new item representing either a file or folder.
    #
    # @param [Api] api The {Api} instance used to generate requests.
    # @param [Folder] parent The {Folder} parent of this item.
    # @param [Hash] info The hash of initial info for this item.
    def initialize(api, parent, info)
      @api = api
      @parent = parent
      @data = Hash.new

      update_info(info) # merges with the info hash, and renames some fields
    end

    # @return [String] The id of this item.
    def id
      # overloads Object#id
      @data['id']
    end

    # Get the info for this item. Uses a cached copy if avaliable,
    # or else it is fetched from the api.
    #
    # @param [Boolean] refresh Does not use the cached copy if true.
    # @return [Item] self
    def info(refresh = false)
      return self if @cached_info and not refresh

      @cached_info = true
      reload!

      self
    end

    # Move this item to the destination folder.
    #
    # @param [Folder] destination The new parent folder to use.
    # @return [Item] self
    def move(destination)
      @api.move(type, id, destination.id)

      parent.delete_info(self.types)
      destination.delete_info(self.types)

      @parent = destination

      self
    end

    # Copy this item to the destination folder.
    #
    # @note Copying folders is not currently supported.
    #
    # @param [Folder] destination The parent folder to copy the item to.
    # @return [Item] The new copy of this item.
    def copy(destination)
      @api.copy(type, id, destination.id)

      destination.delete_info(self.types)

      self.class.new(api, destination, @data)
    end

    # Rename this item.
    #
    # @param [String] new_name The new name for the item.
    # @return [Item] self
    def rename(new_name)
      @api.rename(type, id, new_name)

      update_info('name' => new_name)

      self
    end

    # Delete this item and all sub-items.
    #
    # @return [Item] self
    # TODO: Return nil instead
    def delete
      @api.delete(type, id)

      parent.delete_info(self.types)
      @parent = nil

      self
    end

    # Set the description of this item.
    #
    # @param [String] message The description message to use.
    # @return [Item] self
    def set_description(message)
      @api.set_description(type, id, message)

      self
    end

    # @return [String] The path of this item. This starts with a '/', unless it is root.
    def path
      "#{ parent.path + '/' if parent }#{ name }"
    end

    # Provides an easy way to access this item's info.
    #
    # @example
    #   item.name # returns @data['name'] or fetches it if not cached
    def method_missing(sym, *args, &block)
      # TODO: Why not symbols?
      # convert to a string
      str = sym.to_s

      # determine whether to refresh the cache
      refresh = args ? args.first : false

      # return the value if it already exists
      return @data[str] if not refresh and @data.key?(str)

      # value didn't exist, so try to update the info
      # TODO: Figure out a good way to work with multiple sources.
      case str
      when 'comments'
        self.get_comments
      when
        self.info(refresh)
      end

      # try returning the value again
      return @data[str] if @data.key?(str)

      # we didn't find a value, so it must be invalid
      # call the normal method_missing function
      super
    end

    # Handles some cases in method_missing, but won't always be accurate.
    def respond_to?(sym)
      @data.key?(sym.to_s) or super
    end

    # Consider the item cached. This prevents an additional api when we
    # know the item is fully fetched.
    def force_cached_info
      @cached_info = true
    end

    # Generates a share link for this item.
    #
    # @param [Hash] options Special options related to notification. See
    #         the developer wiki for details instructions.
    # @return The public name of the item. In order to access this item
    #         on the web, prefix this value with 'http://www.box.net/shared/'.
    #
    # TODO: Document the options.
    def share_public(options = Hash.new)
      @api.share_public(type, id, options)['public_name']
    end

    # Shares this item privately with the given email addresses.
    #
    # @param [Array] emails The Box users to share this item with.
    # @param [Hash] options Special options related to notification. See
    #         the developer wiki for details instructions.
    def share_private(emails, options = Hash.new)
      @api.share_private(type, id, emails, options)

      true
    end

    # Unshares this item.
    def unshare
      @api.unshare(type, id)
    end

    protected

    # Fetches this item's info from the api.
    #
    # @return [Hash] The info for the item.
    def get_info; Hash.new; end

    # Invalidates and deletes the cache for a specific field. This forces
    # the item to lazy-load this field if it is requested.
    #
    # @param [String] field The field to delete.
    def delete_info(field)
      @cached_info = false
      @data.delete(field)
    end

    # Invalidates and deletes the entire cache. This forces all info to be
    # lazy-loaded if requested.
    def clear_info
      @cached_info = false
      @data.clear
    end
  end
end
