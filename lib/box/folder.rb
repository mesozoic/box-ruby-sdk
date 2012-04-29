require 'box/item'
require 'box/file'

module Box
  # Represents a folder stored on Box. Any attributes or actions typical to
  # a Box folder can be accessed through this class.

  class Folder < Item
    # (see Item.type)
    def self.type; 'folder'; end

    # (see Item#info)
    # Files and folders will only be one-level deep, and {#tree} should be
    # used if fetching deeper than that.
    def info(refresh = false)
      return self if @cached_info and not refresh

      create_sub_items(nil, Box::Folder)
      create_sub_items(nil, Box::File)

      super
    end

    # Get the tree for this folder. The tree includes all sub folders and
    # files, including their info. Uses a cached copy if avaliable,
    # or else it is fetched from the api.
    #
    # @note Fetching the tree can take a long time for large folders. There
    #       is a trade-off between one {#tree} call and multiple {#info}
    #       calls, so use the one most relevant for your application.
    #
    # @param [Boolean] refresh Does not use the cached copy if true.
    # @return [Folder] self
    def tree(refresh = false)
      return self if @cached_tree and not refresh

      @cached_info = true # count the info as cached as well
      @cached_tree = true

      update_info(get_tree)
      force_cached_tree

      self
    end

    # Create a new folder using this folder as the parent.
    #
    # @param [String] name The name of the new folder.
    # @param [Integer] share The shared status of the new folder. Defaults
    #        to not being shared.
    # @return [Folder] The new folder.
    def create(name, share = 0)
      info = @api.create_folder(id, name, share)['folder']

      delete_info('folders')

      Box::Folder.new(api, self, info)
    end

    # Upload a new file using this folder as the parent
    #
    # @param [String] path The path of the file on disk to upload.
    # @return [File] The new file.
    def upload(path)
      info = @api.upload(path, id)['files']['file']

      delete_info('files')

      Box::File.new(api, self, info)
    end

    # Search for sub-items using criteria.
    #
    # @param [Hash] criteria The hash of criteria to use. Each key of
    #        the criteria will be called on each sub-item and tested
    #        for equality. This lets you use any method of {Item}, {Folder},
    #        and {File} as the criteria.
    # @return [Array] An array of all sub-items that matched the criteria.
    #
    # @note The recursive option will call {#tree}, which can be slow for
    #       large folders.
    # @note Any item method (as a symbol) can be used as criteria, which
    #       could cause major problems if used improperly.
    #
    # @example Find all sub-items with the name 'README'
    #   folder.search(:name => 'README')
    #
    # @example Recusively find a sub-item with the given path.
    #   folder.search(:path => '/test/file.mp4', :recursive => true)
    #
    # @example Recursively find all files with a given sha1.
    #   folder.search(:type => 'file', :sha1 => 'abcdefg', :recursive => true)
    #
    # TODO: Lookup YARD syntax for options hash.
    def find(criteria)
      recursive = criteria.delete(:recursive)
      recursive = false if recursive == nil # default to false for performance reasons

      tree if recursive # get the full tree

      find!(criteria, recursive)
    end

    # (see Item#force_cached_info)
    def force_cached_info
      create_sub_items(nil, Box::Folder)
      create_sub_items(nil, Box::File)

      super
    end

    # Consider the tree cached. This prevents an additional api
    # when we know the item is fully fetched.
    def force_cached_tree
      @cached_tree = true

      create_sub_items(nil, Box::Folder)
      create_sub_items(nil, Box::File)

      folders.each do |folder|
        folder.force_cached_tree
      end
    end

    # Get the item at the given path.
    #
    # @param [String] The path to search for. This follows the typical unix
    #                 path syntax, in that the root folder is '/'. Supports
    #                 the dot sytax, where '.' is the current folder and
    #                 '..' is the parent folder.
    #
    # @return [Item]  The item that exists at this path, or nil.
    #
    # @example Find a folder based on its absolute path.
    #   folder.at('/box/is/awesome')
    #
    # @example Find a file based on a relative path.
    #   folder.at('awesome/file.pdf')
    #
    # @example Find a folder using the parent.
    #   folder.at('../other/folder')
    def at(target_path)
      # start with this folder
      current = self

      if target_path.start_with?('/')
        # absolute path, find the root folder
        current = current.parent while current.parent != nil
      end

      # split each part of the target path
      target_path.split('/').each do |target_name|
        # update current based on the target name
        current = case target_name
        when "", "."
          # no-op
          current
        when ".."
          # use the parent folder
          parent
        else
          # must be a file/folder name, so make sure this is a folder
          return nil unless current and current.type == 'folder'

          # search for an item with that name
          current.find(:name => target_name, :recursive => false).first
        end
      end

      if current
        # ends with a slash, so it has to be a folder
        if target_path.end_with?('/') and current.type != 'folder'
          # get the folder with the same name (if it exists)
          current = parent.find(:type => 'folder', :name => name, :recursive => false).first
        end
      end

      current
    end

    def get_collaborations
      @api.query_rest("s_get_collaborations",
        :action => :get_collaborations,
        :with_unfold => "collaborations/collaboration",
        :target => "folder",
        :target_id => self.id)
    end
    
    def collaborator?(user)
      get_collaborations.map { |c| c["user_id"] }.member?(user.id)
    end

    def invite_collaborator(user, role)
      invite_collaborators([user], role)
    end
    
    def invite_collaborators(users, role, options = {})
      @api.query_rest("s_invite_collaborators",
        :action => :invite_collaborators,
        :target => 'folder',
        :target_id => self.id,
        :user_ids => users.collect(&:id),
        :emails => users.collect(&:email),
        :item_role_name => role,
        :resend_invite => options.fetch(:resend_invite, false),
        :no_email => options.fetch(:no_email, false))
    end

    def traverse(path_segments, options = {})
      create_missing = options[:create]
      path_segments.inject(self) do |folder, subfolder|
        found = folder.find(:type => "folder", :name => subfolder).first
        found ||= folder.create(subfolder) if create_missing
        raise Box::Api::InvalidFolder unless found
        found
      end
    end

    protected

    attr_accessor :cached_tree

    # (see Item#get_info)
    def get_info
      @api.get_account_tree(id, 'onelevel')['tree']['folder']
    end

    # Fetch the folder tree from the api.
    # @return [Hash] The folder tree.
    def get_tree
      @api.get_account_tree(id, 'simple')['tree']['folder']
    end

    # (see Item#clear_info)
    def clear_info
      @cached_tree = false
      super
    end

    # (see Item#update_info)
    def update_info(info)
      if folders = info.delete('folders')
        create_sub_items(folders, Box::Folder)
      end

      if files = info.delete('files')
        create_sub_items(files, Box::File)
      end

      super
    end

    # Create objects for the sub items.
    #
    # @param [Array] items Array of item info.
    # @param [Item] item_class The class of the items in the Array.
    # @return [Array] Array of {Item}s.
    def create_sub_items(items, item_class)
      @data[item_class.types] ||= Array.new

      return unless items

      temp = items[item_class.type]
      temp = [ temp ] if temp.class == Hash # lone folders need to be packaged into an array

      temp.collect do |item_info|
        item_class.new(api, self, item_info).tap do |item|
          @data[item_class.types] << item
        end
      end
    end

    # (see #find)
    def find!(criteria, recursive)
      matches = (files + folders).collect do |item| # search over our files and folders
        match = criteria.all? do |key, value| # make sure all criteria pass
          value === item.send(key) rescue false
        end

        item if match # use the item if it is a match
      end

      if recursive
        folders.each do |folder| # recursive step
          matches += folder.find!(criteria, recursive) # search each folder
        end
      end

      matches.compact # return the results without nils
    end
  end
end
