# Reads an ingest request body as a UTF-8 string, inflating gzip, and never
# buffering more than max + 1 bytes (zip-bomb safe). The cap applies to both
# the compressed and the decompressed body.
class Ingest::RequestBody
  ENCODINGS = [ "", "identity", "gzip" ].freeze

  def initialize(request, max: Ingest::Limits::BODY_BYTES)
    @request = request
    @max = max
  end

  # Content-Encoding values other than gzip/identity are not accepted.
  def supported_encoding?
    ENCODINGS.include?(content_encoding)
  end

  def read
    raise Ingest::PayloadTooLarge if @request.content_length.to_i > @max

    raw = capped_read(@request.body)
    utf8(gzip? ? inflate(raw) : raw)
  end

  private
    def content_encoding
      @request.headers["Content-Encoding"].to_s.strip.downcase
    end

    def gzip? = content_encoding == "gzip"

    def capped_read(io)
      data = +(io&.read(@max + 1) || "")
      raise Ingest::PayloadTooLarge if data.bytesize > @max

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
