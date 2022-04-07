require 'net/http'
require 'open-uri'
require 'memory_profiler'

def save_from_url(url:, to:, ttl: 3, timeout_retries: 5)
  attempt = 1

  begin
    # basic_download(url: url, to: to, ttl: ttl)
    stream_download(url: url, to: to, ttl: ttl)
  rescue Net::ReadTimeout => e
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

def stream_download(url:, to:, ttl: 3)
  File.open(to, "wb") do |f|
    begin
      url_data = URI.open(url, "rb", :redirect => false)
      if (url_data.status[0] == "200")
        expected_bytes = url_data.meta["content-length"].to_i
        bytes_copied = IO.copy_stream(url_data, f)

        if (expected_bytes != bytes_copied)
          puts "Bytes mismatch!!"
          # TODO This should have some other kind of error handling, maybe file delete
        end
      else
        [false, url_data.status[0]]
      end

    rescue OpenURI::HTTPRedirect => redirect
      if ttl.positive?
        save_from_url url: redirect.uri.to_s, to: to, ttl: ttl - 1
      else
        [false, redirect.io.status[0]]
      end
    rescue OpenURI::HTTPError => http_err
      [false, http_err.io.status[0]]
    end

  end
end

report = MemoryProfiler.report do
  save_from_url(url: "https://github.com/yourkin/fileupload-fastapi/raw/a85a697cab2f887780b3278059a0dd52847d80f3/tests/data/test-5mb.bin", to: "download.bin")
  # save_from_url(url: "https://speed.hetzner.de/1GB.bin", to: "download-2.bin")
  # save_from_url(url: "https://speed.hetzner.de/10GB.bin", to: "download-3.bin")
end

report.pretty_print(scale_bytes: true, retained_strings: 0, allocated_strings: 0, detailed_report: false)
