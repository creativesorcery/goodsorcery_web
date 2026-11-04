require "net/http"

# The Net::HTTP that UptimeProbe connects with. Its socket stops after
# UptimeProbe::MAX_READ_BYTES in total, so a server can't fill memory with an
# endless status line, endless headers or 1xx responses: Net::HTTP reads those
# with no limit of its own, and MAX_BODY_BYTES only bounds the body.
class UptimeProbe::Connection < Net::HTTP
  # Counts every byte taken from the socket: status lines, headers, 1xx
  # responses, chunk-size lines and the body. A read can run one
  # Net::BufferedIO::BUFSIZE past the cap before this raises.
  module ReadCap
    private
      def rbuf_fill
        before = rbuf_size
        super
        @uptime_bytes_read = @uptime_bytes_read.to_i + rbuf_size - before
        raise UptimeProbe::ResponseTooLarge if @uptime_bytes_read > UptimeProbe::MAX_READ_BYTES
      end
  end

  private
    # Net::HTTP#connect calls this once it has built the (plain or TLS) socket.
    def on_connect
      @socket.extend(ReadCap)
    end
end
