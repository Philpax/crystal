class IPSocket < Socket
  macro sockname(name, method)
    def {{name.id}}
      addr :: LibC::SockAddrIn6
      addrlen = LibC::SocklenT.new(sizeof(LibC::SockAddrIn6))

      if LibC.{{method.id}}(fd, pointerof(addr) as LibC::SockAddr*, pointerof(addrlen)) != 0
        raise Errno.new("{{method.id}}")
      end

      if addrlen == sizeof(LibC::SockAddrIn6)
        family_name = "AF_INET6"
        result_addr = (pointerof(addr) as LibC::SockAddrIn6*).value
      else
        family_name = "AF_INET"
        result_addr = (pointerof(addr) as LibC::SockAddrIn*).value
      end

      Addr.new(family_name, LibC.htons(result_addr.port).to_u16, Socket.inet_ntop(result_addr))
    end
  end

  sockname :addr, :getsockname
  sockname :peeraddr, :getpeername

  class DnsRequestCbArg
    getter value

    def initialize
      @fiber = Fiber.current
    end

    def value= val
      @value = val
      @fiber.resume
    end
  end

  # Yields LibC::Addrinfo to the block while the block returns false and there are more LibC::Addrinfo results.
  #
  # The block must return true if it succeeded using that addressinfo
  # (to connect or bind, for example), and false otherwise. If it returns false and
  # the LibC::Addrinfo has a next LibC::Addrinfo, it is yielded to the block, and so on.
  private def getaddrinfo(host, port, family, socktype, protocol = LibC::IPPROTO_IP, timeout = nil)
    hints = LibC::Addrinfo.new
    hints.family = (family || LibC::AF_UNSPEC).to_i32
    hints.socktype = socktype
    hints.protocol = protocol
    hints.flags = 0

    dns_req = DnsRequestCbArg.new
    dns_base = Scheduler.event_base.dns_base

    # may fire immediately or on the next event loop
    req = LibEvent2.evdns_getaddrinfo(dns_base, host, port.to_s, pointerof(hints), ->(err, addr, data) {
      dreq = data as DnsRequestCbArg

      if err == 0
        dreq.value = addr
      else
        dreq.value = err
      end
    }, dns_req as Void*)

#    assert req != nil

    dns_timeout dns_base, req, timeout

    success = false

    value = dns_req.value
# BUG: not thread safe.  change when threads are implemented
    unless value
      Scheduler.reschedule
      value = dns_req.value
    end

    if value.is_a?(LibC::Addrinfo*)
      begin
        cur_addr = value
        while cur_addr
          success = yield cur_addr.value

          break if success
          cur_addr = cur_addr.value.next
        end
      ensure
        LibEvent2.evutil_freeaddrinfo value
      end
    elsif value.is_a?(Int)
      raise Socket::Error.new("getaddrinfo: #{String.new(LibC.gai_strerror(value))}")
    else
      raise "unknown type #{value.inspect}"
    end

    # shouldn't raise
    raise Socket::Error.new("getaddrinfo: unspecified error") unless success
  end

  private def dns_timeout dns_base, req, timeout
    if timeout && req
      spawn do
        sleep timeout.not_nil!
        LibEvent2.evdns_cancel_request dns_base, req
      end
    end
  end
end

