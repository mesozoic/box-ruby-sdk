require 'box/api'
require 'box/folder'

module Box
  # Represents an account on Box. In order to use the Box api, the user
  # must first grant the application permission to use their account. This
  # is done in the {#authorize} function. Once an account has been
  # authorized, it can access all of the details and information stored
  # on that account.

  class Account
    # @return [String] The auth token if authorization was successful.
    attr_reader :auth_token

    # @return [Api] The {Api} used by this item.
    attr_reader :api

    # Creates an account object using the given Box api key.
    # You can then {#register} a new account or {#authorize} an
    # existing account.
    #
    # @param [String, Api] api the api key to use for the Box api.
    def initialize(api)
      @api = case
        when api.class == Box::Api; api # use the api object as passed in
        else; Box::Api.new(api) # allows user to pass in a string
      end
    end

    # Register a new account on the Box website with the given details.
    #
    # @param [String] email The email address to create the account with
    # @param [String] password The password to create the account with
    # @return [Boolean] Whether registration was successful.
    #
    # @raise [Api::EmailInvalid] The email address was invalid
    # @raise [Api::EmailTaken] The email address was taken
    #
    def register(email, password)
      response = @api.register_new_user(email, password)

      cache_info(response['user']) # cache account_info, saving an extra API call
      authorize_token(response['token'])

      true
    end

    # Authorize the account using the given auth token/ticket, or request
    # permission from the user to let this application use their account.
    #
    # An auth token can be reused from previous authorizations provided the
    # user doesn't log out, and significantly speeds up the process. If the
    # auth token if invalid or not provided, the account tries to log in
    # normally and requires the user to log in and provide access for their
    # account.
    #
    # A ticket can be used for applications that do not block on the user,
    # such as a website, where specifying a redirection url is not possible.
    #
    # In order to maintain backwards compatibility, a ticket can only be
    # specified in the hash syntax, while an auth token can be used in
    # either the hash or string syntax.
    #
    # @param [Optional, String, Hash{:ticket,:auth_token => String}] details
    #        Uses an existing auth token or ticket. If nil, a new ticket
    #        will be generated and used. If a String, it is assumed to be
    #        an auth_token (depreciated). If a Hash, then any values of
    #        the :ticket and :auth_token keys will be used to authenticate.
    # @yield [authorize_url] This block called when the user has not yet
    #        granted this application permission to use their account. You
    #        must have the user navigate to the passed url and authorize
    #        this app before continuing.
    # @return [Boolean] Whether the user is authorized.
    #
    # @example Authorize an account without a saved auth token.
    #   account.authorize do |auth_url|
    #     puts "Please visit #{ auth_url } and enter your account infomation"
    #     puts "Press the enter key once you have done this."
    #     gets # wait for the enter key to be pressed
    #   end
    #
    # @example Authorize an account using an existing auth token.
    #   auth_token = "saved auth token" # load from file ideally
    #   account.authorize(:auth_token => auth_token)
    #
    # @example Combining the above two for the best functionality.
    #   auth_token = "saved auth token" # load from file if possible
    #   account.authorize(:auth_token => auth_token) do |auth_url|
    #     # auth token was invalid or nil, have the user visit auth_url
    #   end
    #
    def authorize(details = nil)
      # for backwards compatibility
      if details.is_a?(Hash)
        auth_token = details[:auth_token]
        ticket = details[:ticket]
      else
        auth_token = details
        ticket = nil
      end

      # use a saved auth token if it is given
      if auth_token
        return true if authorize_token(auth_token)
      end

      # the auth token either failed or was not provided
      # we must try to authorize a ticket, and call the block if that fails
      if not authorize_ticket(ticket) and block_given?
        # the supplied block should instruct the user to visit this url
        yield authorize_url(ticket)

        # try authorizing once more
        authorize_ticket(ticket)
      end

      # return our authorized status
      authorized?
    end

    # Log out of the account and invalidate the auth token.
    #
    # @note The user will have to re-authorize if they wish to use this
    #       application, and the auth token will no longer work.
    #
    # @return [Boolean] Whether logout was successful.
    #
    def logout
      begin
        @api.logout
        cache_token(nil)
      rescue Api::NotAuthorized
        # already logged out, or never logged in
      end

      true
    end

    # Return the account details. A cached copy will be used if avaliable,
    # and requested if it is not.
    #
    # @param [Boolean] refresh Will not use the cached version if true.
    # @return [Hash] A hash containing all of the user's account
    #         details, or nil if they are not authorized. Please see the
    #         Box api documentation for information about each field.
    #
    # TODO: Add url to Box api documentation, and provide the current fields.
    #
    def info(refresh = false)
      return @info if @info and not refresh

      begin
        cache_info(nil) # reset existing info
        info = @api.get_account_info['user']
        cache_info(info)
      rescue Api::NotAuthorized, Api::InvalidInput
        nil
      end
    end

    # Get the root folder of the account. You can use this {Folder} object
    # to access all sub items within the account. This folder is lazy loaded,
    # and a network request will be made if/when the data is requested.
    #
    # @return [Folder] A folder object representing the root folder.
    #
    def root
      return @root if @root
      @root = folder(0)
    end

    # Gets a folder object by id.
    #
    # @param [String] id The id of the folder to fetch.
    #
    # @note This folder will not know its parent because of API
    #       short-comings. If you need the tree above this folder, use
    #       root.find(:type => 'folder', :id => id).first instead.
    #
    # @note This function will return a folder regardless of whether it
    #       actually exists. You will get exceptions if you try to access
    #       any info.
    #
    def folder(id)
      Box::Folder.new(@api, nil, :id => id)
    end

    # Gets a file object by id.
    #
    # @param [String] id The id of the folder to fetch.
    #
    # @note This file will not know its parent because of API
    #       short-comings. If you need the tree above this file, use
    #       root.find(:type => 'file', :id => id).first instead.
    #
    # @note This function will return a file regardless of whether it
    #       actually exists. You will get exceptions if you try to access
    #       any info.
    #
    def file(id)
      Box::File.new(@api, nil, :id => id)
    end

    # Gets a group object by id.
    #
    # @param [String] id The id of the group to fetch.
    def group(id)
      obj = Box::Group.new(@api, :id => id)
      obj.reload!
      obj
    end

    # Gets a list of all groups in the account.
    def groups
      response = @api.query_rest_paged("s_get_groups",
        :action => :get_groups, :with_unfold => "groups/item")
      response.map { |data| Box::Group.new(@api, data) }
    end

    # Gets a group object by its name.
    #
    # @param [String] name The name of the group to fetch.
    def group_with_name(name)
      groups.select { |g| g.name.downcase == name.downcase }.first
    end

    # Creates a new group in the account.
    #
    # @param [String] name The name of the group to create.
    def create_group(name)
      Box::Group.create(@api, name)
    end

    # Gets a user object by id.
    #
    # @param [String] id The id of the user to fetch.
    def user(id)
      obj = Box::User.new(@api, :id => id)
      obj.reload!
    end

    # Gets a user object by its login.
    #
    # @param [String] login The email address of the user to fetch.
    def user_with_login(login)
      obj = Box::User.new(@api, :email => login)
      obj.reload!
    end

    # Returns all managed users in the account.
    def users
      users_data = @api.query_rest("s_get_managed_users",
        :action => :get_managed_users, :with_unfold => "users/item")
      users_data.map { |data| Box::User.new(@api, data) }
    end

    # Gets a user object by its name.
    #
    # @param [String] name The name of the user to fetch.
    def user_with_name(name)
      users.select { |u| u.name.downcase == name.downcase }.first
    end

    # Creates a new managed user in the account.
    #
    # @param [String] name The name of the user.
    # @param [String] email The email address of the user.
    # @param [Hash] options Hash of additional options for the API.
    # @return [Box::User] The newly-created user object.
    def create_user(name, email, options = {})
      Box::User.create(@api, name, email, options)
    end

    # @return [Boolean] Is the account authorized?
    def authorized?
      @info != nil
    end

    # Get the cached ticket or request a new one from the Box api.
    # @return [String] The authorization ticket.
    def ticket
      @ticket ||= @api.get_ticket['ticket']
    end

    # Provides an easy way to access this account's info.
    #
    # @example
    #   account.login # returns @info['login']
    def method_missing(sym, *args, &block)
      super unless authorized?

      # TODO: Use symbols instead of strings
      str = sym.to_s

      return @info[str] if @info.key?(str)

      super
    end

    def respond_to?(sym)
      @info.key?(sym.to_s) or super
    end

    protected

    # The url the user needs to visit in order to grant this application
    # permission to use their account. This requires a ticket, which
    # is either pulled from the cache or requested.
    #
    # @param [String] ticket Use the ticket for the url.
    #         If no ticket is provided, one will be requested and cached.
    # @return [String] the url used for authorizing this account.
    #
    def authorize_url(ticket = nil)
      ticket = self.ticket unless ticket
      "#{ api.base_url }/auth/#{ ticket }"
    end

    # Attempt to authorize this account using the given ticket. This will
    # only succeed if the user has granted this ticket permission, done
    # by visiting and logging into the {#authorize_url}.
    #
    # @param [String] ticket The ticket used for authorization.
    #         If no ticket is provided, one will be requested and cached.
    # @return [String, nil] The auth token if successful otherwise, nil.
    #
    def authorize_ticket(ticket = nil)
      ticket = self.ticket unless ticket

      begin
        response = @api.get_auth_token(ticket)

        cache_info(response['user']) # saves an extra API call
        cache_token(response['auth_token'])
      rescue Api::NotAuthorized
        nil
      end
    end

    # Attempt to authorize this account using the given auth token. This
    # will only succeed if the auth token has been used before, and
    # be done to make login easier.
    #
    # @param [String] auth_token The auth token to attempt to use
    # @return [Boolean] If the attempt was successful.
    #
    def authorize_token(auth_token)
      cache_token(auth_token)
      info(true) # force a refresh

      authorized?
    end

    # Use and cache the given auth token.
    # @param [String] auth_token The auth token to cache.
    # @return [String] The auth token.
    def cache_token(auth_token)
      @api.set_auth_token(auth_token)
      @auth_token = auth_token
    end

    # Cache the account info.
    # @param [Hash] info The account info to cache.
    def cache_info(info)
      @info = info
    end
  end
end
