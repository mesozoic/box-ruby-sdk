module Box
  class Api
    class Exception < StandardError; end

    # HTTP exceptions
    class UnknownResponse < Exception; end
    class ErrorStatus < Exception; end

    # Common responses
    class Restricted < Exception; end
    class InvalidInput < Exception; end
    class NotAuthorized < Exception; end
    class Generic < Exception; end
    class Unknown < Exception; end

    # Registration specific responses
    class EmailInvalid < Exception; end
    class EmailTaken < Exception; end

    # Folder/File specific responses
    class InvalidFolder < Exception; end
    class InvalidName < Exception; end
    class NoAccess < Exception; end
    class NoParent < Exception; end
    class NameTaken < Exception; end

    # Upload/Download specific responses
    class UploadFailed < Exception; end
    class AccountExceeded < Exception; end
    class SizeExceeded < Exception; end

    # User specific responses
    class UserNotFound < Exception; end

    # Sharing specific responses
    class NotShared < Exception; end

    # Given a status, returning a cooresponding Exception class.
    #
    # @param [String] status The failing status to look for.
    # @return [Exception] A coorespondng Exception.
    def self.get_exception(status)
      case status
      # Common responses
      when "application_restricted"
        Restricted
      when "wrong_input", "Wrong input params"
        InvalidInput
      when "not_logged_in", "wrong auth token"
        NotAuthorized
      when "e_no_access", "e_access_denied", "access_denied"
        NoAccess
      # Registration specific responses
      when "email_invalid"
        EmailInvalid
      when "email_already_registered"
        EmailTaken
      when "get_auth_token_error", "e_register"
        Generic
      # Folder/File specific responses
      when "wrong_node"
        InvalidItem
      when "e_folder_id"
        InvalidFolder
      when "no_parent"
        NoParent
      when "invalid_folder_name", "e_no_folder_name", "folder_name_too_big", "upload_invalid_file_name"
        InvalidName
      when "e_input_params"
        InvalidInput
      when "e_filename_in_use", "s_folder_exists"
        NameTaken
      when "e_move_node", "e_copy_node", "e_rename_node", "e_set_description"
        Generic
      # Upload/Download specific responses
      when "upload_some_files_failed"
        UploadFailed
      when "not_enough_free_space"
        AccountExceeded
      when "filesize_limit_exceeded"
        SizeExceeded
      # Comment specific responses
      when "get_comments_error", "add_comment_error", "delete_comment_error"
        Generic
      # Sharing specific responses
      when "file_not_shared"
        NotShared
      when "wrong input params"
        InvalidInput
      when "share_error", "unshare_error", "private_share_error"
        Generic
      when "e_get_user_id"
        UserNotFound
      else
        Unknown
      end
    end
  end
end
