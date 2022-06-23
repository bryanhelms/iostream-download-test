# frozen_string_literal: true

class DownloadFileSizeError < StandardError
  attr_reader :file_size, :max_file_size

  def initialize(max_file_size:, file_size: nil)
    @max_file_size = max_file_size
    @file_size = file_size

    if (file_size.nil?)
      super("Attempted to download a file whose size couldn't be determined.")
    else
      super("Attempted to download a file that is larger than the maximum allowed.")
    end
  end
end
