require 'box/api'
require 'box/item'

module Box
  # Represents an enterprise managed group within Box.
  class Group
    include Box::CanUpdateInfo

    # @return [Hash] The hash of info for this item
    attr_accessor :data

    # @return [Api] The {Api} used by this item.
    attr_reader :api

    # Create a new item representing an existing managed group.
    def initialize(api, data = {})
      @api = api
      @data = Hash.new
      self.update_info(data)
    end

    def id
      @data["id"]
    end

    def name
      @data["name"]
    end

    def users(with_access = nil)
      @users ||= begin
        data = user_data.reject { |u| with_access && (u["access_level"] == with_access) }
        data.map { |user_data| Box::User.new(@api, user_data) }
      end
    end

    def add_user(user, access_level = "member")
      @api.query_rest("s_set_user_in_group",
        :action => :set_user_in_group,
        :group_id => id, :user_id => user.id, :access_level => access_level)
    end

    def remove_user(user)
      @api.query_rest("s_remove_user_from_group",
        :action => :remove_user_from_group,
        :group_id => id, :user_id => user.id)
    end

    def folders(with_permission = nil)
      @folders ||= begin
        data = folder_data.reject { |f| with_permission && (f["permission_name"] == with_permission) }
        data.map { |folder_data| account.folder(folder_data["folder_id"]) }
      end
    end

    def self.create(api, name)
      api.query_rest("s_create_group", :action => :create_group, :group_name => name)
      self.new(@api, response)
    end

    def delete
      @api.query_rest("s_delete_group", :action => :delete_group, :group_id => id)
    end

    protected

    def account
      @account ||= Box::Account.new(@api)
    end

    def get_info
      @api.query_rest("s_get_groups",
        :action => :get_groups,
        :params => {:group_id => id},
        :with_unfold => "groups/item").first
    end
    
    def user_data
      @api.query_rest_paged("s_get_group_users",
        :action => :get_group_users,
        :group_id => id,
        :with_unfold => "group_users/item")
    end

    def folder_data
      @api.query_rest_paged("s_get_group_folders",
        :action => :get_group_folders,
        :group_id => id,
        :with_unfold => "group_folders/item")
    end
  end
end
