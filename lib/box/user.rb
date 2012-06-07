require 'box/item'

module Box
  class User
    include Box::CanUpdateInfo

    # @return [Hash] The hash of info for this item
    attr_accessor :data

    # @return [Api] The {Api} used by this item.
    attr_reader :api

    def initialize(api, data = {})
      @api = api
      @data = Hash.new

      update_info(data)
    end

    def first_name
      self.name && self.name.split.first
    end

    def self.create(api, name, email, data = {})
      data.merge!(:name => name, :login => email)
      response = api.query_rest("s_create_managed_user",
        :action => :create_managed_user, :params => data)
      self.new(api, response["new_user"])
    end

    def active?
      @data["status"] == "active"
    end

    def inactive?
      @data["status"] == "inactive"
    end

    protected

    def get_info
      user_id = id || @api.query_rest("s_get_user_id", :action => :get_user_id, :login => email)["id"]
      raise "Box::User requires either :id or :email" unless user_id

      @api.query_rest("s_get_user_info", :action => :get_user_info, :user_id => user_id)
    end
  end
end