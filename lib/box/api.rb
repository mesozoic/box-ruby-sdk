require 'box/api/exceptions'

require 'httmultiparty'

module Box
  # A wrapper and interface to the Box api. Please visit the Box developers
  # site for a full explaination of what each of the Box api methods
  # expect and perform.
  # TODO: Link to the site.

  class Api
    # an extension of HTTParty, adding multi-part upload support
    include HTTMultiParty

    # @return [String] The base url of the box api.
    attr_accessor :base_url

    # @return [String] The upload url of the box api.
    attr_accessor :upload_url

    # Create a new API object using the given parameters.
    #
    # @note Chances are that if the Box api is updated or moves location,
    #       this class will no longer work. However, the option to change
    #       the defaults still remains.
    #
    # @param [String, Api] api_key The api key for your application. You can
    #        request one on the Box developer website at
    #        {http://www.box.net/developers/services}. If an {Api} instance
    #        is passed instead, its key is used.
    #
    # @param [String] url the url of the Box api.
    # @param [String] upload_url the url of the upload host for the Box api.
    # @param [String] version the version of the Box api in use.
    #
    def initialize(key, url = 'https://box.net', upload_url = 'https://upload.box.net', version = '1.0')
      @default_params = { :api_key => key } # add the api_key to every query

      @base_url = "#{ url }/api/#{ version }" # set the base of the request url
      @upload_url = "#{ upload_url }/api/#{ version }" # uploads use a different url than everything else
    end

    # Make a normal REST request.
    #
    # @param [String] expected the normal status expected to be returned.
    #        If the actual status does not match, an exception is thrown.
    # @param [Hash] options The parameters that wish to be passed in the
    #        request. These should correspond to the api specifications,
    #        and will be passed along with the api key and auth token.
    #        Hash can also include the special value :with_unfold, which takes
    #        a path value (e.g. "groups/item") that will be used to unpack
    #        values from the hash returned by the API.
    #
    # @return [Hash] A parsed version of the XML response.
    #
    def query_rest(expected, options = {})
      options = options.dup

      if unfold_path = options.delete(:with_unfold)
        response = query_rest(expected, options) # call w/o :with_unfold
        value = unfold_path.split("/").inject(response) do |current_hash, key|
          (current_hash || {})[key] # same as x["foo"]["bar"] but nil-safe
        end
        # this would be terser as Array[*(value || [])] but that's illegible
        value ||= []
        value = [value] unless value.is_a?(Array)
        value
      else
        query_raw('get', "#{ @base_url }/rest", expected, options)['response']
      end
    end

    # Make one or more REST requests that return paged results. Will continue
    # to iterate until getting an empty page.
    #
    # @param [String] expected the normal status expected to be returned.
    #        If the actual status does not match, an exception is thrown.
    # @param [Hash] options The parameters that wish to be passed in the
    #        request. These should coorespond to the api specifications,
    #        and will be passed along with the api key and auth token.
    #
    # @return [Array] A list of parsed XML responses.
    #
    def query_rest_paged(expected, options = {})
      responses = []
      page_responses = nil

      until page_responses && page_responses.empty?
        options[:params] ||= {}
        options[:params][:page] = responses.count + 1
        begin
          page_responses = query_rest(expected, options)
        rescue Box::Api::Unknown
          page_responses = []
        end
        responses << page_responses
      end
      responses.flatten(1)
    end

    # Make a download request.
    #
    # @param [String] query the operation to be performed ("download").
    # @param [Array] args an array of arguments to put in the url.
    # @param [Hash] options (see #query_rest)
    #
    # @return The raw binary data of the file.
    #
    def query_download(args, options = {})
      # produces: /download/<auth_token>/<arg1>/<arg2>/<etc>
      url = [ "#{ @base_url }/download", @auth_token, args ].flatten.compact.join('/')
      query_raw('get', url, nil, options)
    end

    # Make an upload request.
    #
    # @param [String] query The operation to be performed.
    # @param [Array] args (see #query_download)
    # @param [String] expected (see #query_rest)
    # @param [Hash] options (see #query_rest)
    #
    # @return (see #query_rest)
    #
    def query_upload(query, args, expected, options = {})
      # produces: /upload/<auth_token>/<arg1>/<arg2>/<etc>
      url = [ "#{ @upload_url }/#{ query }", @auth_token, args ].flatten.compact.join('/')
      query_raw('post', url, expected, options)['response']
    end

    # Make a raw request.
    #
    # @note: HTTParty will automatically parse the response from its native
    #        XML to a nested hash/array structure.
    #
    # @param ['get', 'post'] method The HTTP method to use.
    # @param [String] url The url to make the request.
    # @param [String] expected (see #query_rest)
    # @param [Hash] options (see #query_rest)
    #
    # @return (see #query_rest)
    #
    def query_raw(method, url, expected, options = {})
      response = case method
      when 'get'
        self.class.get(url, :query => @default_params.merge(options))
      when 'post'
        self.class.post(url, :query => @default_params.merge(options), :format => :xml) # known bug with api that only occurs with uploads, will be fixed soon
      end

      handle_response(response, expected)
    end

    # Handle the response of the request.
    #
    # @param [Hash] response The parsed representation of the XML response.
    # @param expected (see #query_rest)
    #
    # @return [Hash] The response if no errors were found.
    # @raise [Exception, UnknownResponse] Raises an exception if the
    #        response status does not match the expected. This exception
    #        is determined by {.get_exception}
    def handle_response(response, expected = nil)
      if expected
        begin
          status = response['response']['status']
        rescue
          raise UnknownResponse, "Unknown response: #{ response }"
        end

        unless status == expected # expected is the normal, successful status for this request
          exception = self.class.get_exception(status)
          raise exception, status
        end
      end

      raise ErrorStatus, "HTTP code #{ response.code }" unless response.success? # when the http return code is not normal
      response
    end

    # TODO: Add link to API documentation for all functions below.
    # TODO: Document exceptions that could be thrown.

    # Request a ticket for authorization
    def get_ticket
      query_rest('get_ticket_ok', :action => :get_ticket)
    end

    # Request an auth token given a ticket.
    #
    # @param [String] ticket the ticket to use.
    def get_auth_token(ticket)
      query_rest('get_auth_token_ok', :action => :get_auth_token, :ticket => ticket)
    end

    # Add the auth token to every request.
    #
    # @param [String] auth_token The auth token to add to every request.
    def set_auth_token(auth_token)
      @auth_token = auth_token
      @default_params[:auth_token] = auth_token
    end

    # Request the user be logged out.
    def logout
      query_rest('logout_ok', :action => :logout)
    end

    # Register a new user.
    #
    # @param [String] email The email address to use.
    # @param [String] password The password to use.
    def register_new_user(email, password)
      query_rest('successful_register', :action => :register_new_user, :login => email, :password => password)
    end

    # Verify a registration email.
    #
    # @param [String] email The email address to check.
    def verify_registration_email(email)
      query_rest('email_ok', :action => :verify_registration_email, :login => email)
    end

    # Get the user's account info.
    def get_account_info
      query_rest('get_account_info_ok', :action => :get_account_info)
    end

    # Get the entire tree of a given folder.
    #
    # @param [String] folder_id The id of the folder to use.
    # @param [Array] args The arguments to pass along to get_account_tree.
    #
    # @note This function can take a long time for large folders.
    # @todo Use zip compression to save bandwidth.
    #
    # TODO: document the possible arguments.
    def get_account_tree(folder_id, *args)
      query_rest('listing_ok', :action => :get_account_tree, :folder_id => folder_id, :params => [ 'nozip' ] + args)
    end

    # Create a new folder.
    #
    # @param [String] parent_id The id of the parent folder to use.
    # @param [String] name The name of the newly created folder.
    # @param [Integer] shared The shared state of the new folder.
    def create_folder(parent_id, name, share = 0)
      query_rest('create_ok', :action => :create_folder, :parent_id => parent_id, :name => name, :share => share)
    end

    # Move the item to a new destination.
    #
    # @param ["file", "folder"] target The type of item.
    # @param [String] target_id The id of the item to move.
    # @param [String] destination_id The id of the parent to move to.
    def move(target, target_id, destination_id)
      query_rest('s_move_node', :action => :move, :target => target, :target_id => target_id, :destination_id => destination_id)
    end

    # Copy the the item to a new destination.
    #
    # @note The api currently only supports copying files.
    #
    # @param ["file"] target The type of item.
    # @param [String] target_id The id of the item to copy.
    # @param [String] destination_id The id of the parent to copy to.
    def copy(target, target_id, destination_id)
      query_rest('s_copy_node', :action => :copy, :target => target, :target_id => target_id, :destination_id => destination_id)
    end

    # Rename the item.
    #
    # @param ["file", "folder"] target The type of item.
    # @param [String] target_id The id of the item to rename.
    # @param [String] new_name The new name to be used.
    def rename(target, target_id, new_name)
      query_rest('s_rename_node', :action => :rename, :target => target, :target_id => target_id, :new_name => new_name)
    end

    # Delete the item.
    #
    # @param ["file", "folder"] target The type of item.
    # @param [String] target_id The id of the item to delete.
    def delete(target, target_id)
      query_rest('s_delete_node', :action => :delete, :target => target, :target_id => target_id)
    end

    # Get the file info.
    #
    # @param [String] file_id The file id to get info for.
    def get_file_info(file_id)
      query_rest('s_get_file_info', :action => :get_file_info, :file_id => file_id)
    end

    # Set the item description.
    #
    # @param ["file", "folder"] target The type of item.
    # @param [String] target_id The id of the item to describe.
    # @param [String] description The description to use.
    def set_description(target, target_id, description)
      query_rest('s_set_description', :action => :set_description, :target => target, :target_id => target_id, :description => description)
    end

    # Download the file to the given path.
    #
    # @note You cannot download folders.
    #
    # @param [String] path The path to write the file to.
    # @param [String] file_id The file id to download.
    # @param [Optional, String] version The version of the file to download.
    def download(file_id, version = nil)
      query_download([ file_id, version ])
    end

    # Upload the file to the specified folder.
    #
    # @param [String, File or UploadIO] path Upload the file at the given path, or a File or UploadIO object..
    # @param [String] folder_id The folder id of the parent folder to use.
    # @param [Optional, Boolean] new_copy Upload a new copy instead of overwriting.
    def upload(path, folder_id, new_copy = false)
      path = ::File.new(path) unless path.is_a?(::UploadIO) or path.is_a?(::File)

      # We need to delete new_copy from the args if it is null or false.
      # This is because of a bug with the API that considers any value as 'true'
      options = { :file => path, :new_copy => new_copy }
      options.delete(:new_copy) unless new_copy

      query_upload('upload', folder_id, 'upload_ok', options)
    end

    # Overwrite the given file with a new one.
    #
    # @param [String, File or UploadIO] path (see #upload)
    # @param [String] file_id Replace the file with this id.
    # @param [Optional, String] name Use a new name as well.
    def overwrite(path, file_id, name = nil)
      path = ::File.new(path) unless path.is_a?(::UploadIO) or path.is_a?(::File)
      query_upload('overwrite', file_id, 'upload_ok', :file => path, :file_name => name)
    end

    # Upload a new copy of the given file.
    #
    # @param [String] path (see #upload)
    # @param [String] file_id The id of the file to copy.
    # @param [Optional, String] name Use a new name as well.
    # TODO: Verfiy this does what I think it does
    def new_copy(path, file_id, name = nil)
      query_upload('new_copy', file_id, 'upload_ok', :file => ::File.new(path), :new_file_name => name)
    end

    # Gets the comments posted on the given item.
    #
    # @param ["file"] target The type of item.
    # @param [String] target_id The id of the item to get.
    def get_comments(target, target_id)
      query_rest('get_comments_ok', :action => :get_comments, :target => target, :target_id => target_id)
    end

    # Adds a new comment to the given item.
    #
    # @param ["file"] target The type of item.
    # @param [String] target_id The id of the item to add to.
    # @param [String] message The message to use.
    def add_comment(target, target_id, message)
      query_rest('add_comment_ok', :action => :add_comment, :target => target, :target_id => target_id, :message => message)
    end

    # Deletes a given comment.
    #
    # @param [String] comment_id The id of the comment to delete.
    def delete_comment(comment_id)
      query_rest('delete_comment_ok', :action => :delete_comment, :target_id => comment_id)
    end

    # Request the HTML embed code for a file.
    #
    # @param [String] id The id of the file to use.
    # @param [Hash] options The properties for the generated preview code.
    #        See File#embed_code for a more detailed list of options.
    def file_embed(id, options = Hash.new)
      query_rest('s_create_file_embed', :action => :create_file_embed, :file_id => id, :params => options)
    end

    # Share an item publically, making it accessible via a share link.
    #
    # @param [String] target The type of item.
    # @param [String] target_id The id of the item to share.
    # @param [Hash] options Extra options related to notifications. Please
    #        read the developer documentation for more details.
    def share_public(target, target_id, options = Hash.new)
      query_rest('share_ok', { :action => :public_share, :target => target, :target_id => target_id, :password => "", :message => "", :emails => [ "" ] }.merge(options))
    end

    # Share an item privately, making it accessible only via email.
    #
    # @param [String] target The type of item.
    # @param [String] target_id The id of the item to share.
    # @param [Array] emails The email addresses of the individuals to share with.
    # @param [Hash] options Extra options related to notifications. Please
    #        read the developer documentation for more details.
    #
    def share_private(target, target_id, emails, options = Hash.new)
      query_rest('private_share_ok', { :action => :private_share, :target => target, :target_id => target_id, :emails => emails, :message => "", :notify => "" }.merge(options))
    end

    # Stop sharing an item publically.
    #
    # @param [String] target The type of item.
    # @param [String] target_id The id of the item to unshare.
    def unshare_public(target, target_id)
      query_rest('unshare_ok', :action => :public_unshare, :target => target, :target_id => target_id)
    end
  end
end
