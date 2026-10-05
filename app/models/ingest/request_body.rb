# Reads an ingest request body as a UTF-8 string, inflating gzip, and never
# buffering more than Ingest::Limits::BODY_BYTES + 1 bytes (zip-bomb safe).
class Ingest::RequestBody
  MAX = Ingest::Limits::BODY_BYTES
  ENCODINGS = [ "", "identity", "gzip" ].freeze

  def initialize(request)
    @request = request
  end

  # Content-Encoding values other than gzip/identity are not accepted.
  def supported_encoding?
    ENCODINGS.include?(content_encoding)
  end

  def read
    raise Ingest::PayloadTooLarge if @request.content_length.to_i > MAX

    raw = capped_read(@request.body)
    utf8(gzip? ? inflate(raw) : raw)
  end

  private
    def content_encoding
      @request.headers["Content-Encoding"].to_s.strip.downcase
    end

    def gzip? = content_encoding == "gzip"

    def capped_read(io)
      data = +(io&.read(MAX + 1) || "")
      raise Ingest::PayloadTooLarge if data.bytesize > MAX

      data
    end

    def inflate(raw)
      capped_read(Zlib::GzipReader.new(StringIO.new(raw)))
    rescue Zlib::Error
      raise Ingest::InvalidJson, cause: nil
    end

    def utf8(data)
      data.force_encoding(Encoding::UTF_8).tap { raise Ingest::InvalidJson unless it.valid_encoding? }
    end
end
