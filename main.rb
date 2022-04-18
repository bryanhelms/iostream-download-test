require 'net/http'
require 'open-uri'
require 'memory_profiler'
require 'down'

def save_from_url(url:, to:, ttl: 3, timeout_retries: 5)
  attempt = 1

  begin
    # basic_download(url: url, to: to, ttl: ttl)
    # stream_download(url: url, to: to, ttl: ttl)
    # improved_download(url: url, to: to, ttl: ttl)
    # down_download(url: url, to: to, ttl: ttl)
    down_chunked(url: url, to: to, ttl: ttl)
  rescue Down::TimeoutError, Net::ReadTimeout => e
    attempt += 1
    raise e if attempt > timeout_retries

    sleep(attempt**3)
    retry
  end
end

def basic_download(url:, to:, ttl: 3)
  res = Net::HTTP.get_response(URI(url)) do |response|
    if response.is_a?(Net::HTTPSuccess)
      File.open(to, "wb") do |f|
        response.read_body do |chunk|
          f.write chunk
        end
      end
    end
  end

  case res
  when Net::HTTPSuccess
    [true, res.code]

  when Net::HTTPRedirection
    if ttl.positive?
      save_from_url url: res["Location"], to: to, ttl: ttl - 1
    else
      [false, res.code]
    end

  else
    [false, res.code]
  end
end

def improved_download(url:, to:, ttl: 3)
  uri = URI(url)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")

  request = Net::HTTP::Get.new uri

  http.request request do |response|
    if response.is_a?(Net::HTTPSuccess)
      File.open(to, "wb") do |f|
        response.read_body do |chunk|
          f.write chunk
        end
      end
    end

    case response
    when Net::HTTPSuccess
      [true, response.code]

    when Net::HTTPRedirection
      if ttl.positive?
        save_from_url url: response["Location"], to: to, ttl: ttl - 1
      else
        [false, response.code]
      end

    else
      [false, response.code]
    end
  end
end

def stream_download(url:, to:, ttl: 3)
  url_data = URI.parse(url).open("rb", redirect: false)
  if url_data.status[0] == "200"
    expected_bytes = url_data.meta["content-length"].to_i
    File.open(to, "wb") do |f|
      bytes_copied = IO.copy_stream(url_data, f)

      if expected_bytes != bytes_copied
        # TODO: Need to figure out how we want to handle this error
      end
    end
    [true, "200"]
  else
    [false, url_data.status[0]]
  end
rescue OpenURI::HTTPRedirect => e
  if ttl.positive?
    save_from_url url: e.uri.to_s, to: to, ttl: ttl - 1
  else
    [false, e.io.status[0]]
  end
rescue OpenURI::HTTPError => e
  [false, e.io.status[0]]
end

def down_download(url:, to:, ttl: 3)
  uri = URI.parse(url);
  dl = Down.download(uri, destination: to, max_redirects: 0)

  [true, "200"]
rescue Down::TooManyRedirects
  # We don't have a way to get the response code out of this error type, so we're just going to hard code a value
  [false, "301"]
rescue Down::NotFound, Down::ClientError, Down::ServerError, Down::ResponseError => e
  [false, e.response.code]
end

def down_chunked(url:, to:, ttl: 3)
  uri = URI.parse(url)
  remote_file = Down.open(uri, rewindable: false, max_redirects: ttl)
  File.open(to, "wb") do |f|
    remote_file.each_chunk do |chunk|
      f.write(chunk)
    end
  end

  [true, "200"]
rescue Down::TooManyRedirects
  # We don't have a way to get the response code out of this error type, so we're just going to hard code a value
  [false, "301"]
rescue Down::NotFound, Down::ClientError, Down::ServerError, Down::ResponseError => e
  [false, e.response.code]
end

out_file = "download.bin"

# report = MemoryProfiler.report do
  # Test files used from https://fastest.fish/test-files
  result = save_from_url(url: "https://github.com/yourkin/fileupload-fastapi/raw/a85a697cab2f887780b3278059a0dd52847d80f3/tests/data/test-5mb.bin", to: out_file)
  # result = save_from_url(url: "https://speed.hetzner.de/1GB.bin", to: "download-2.bin")
  # result = save_from_url(url: "https://speed.hetzner.de/10GB.bin", to: "download-3.bin")
  p result
# end

# report.pretty_print(scale_bytes: true, retained_strings: 0, allocated_strings: 0, detailed_report: false)

data = File.read(out_file)
checksum = Digest::SHA256.hexdigest(data)
puts checksum
