require "test_helper"

class UptimeProbe::AddressGuardTest < ActiveSupport::TestCase
  Guard = UptimeProbe::AddressGuard

  BLOCKED = {
    "this network" => "0.1.2.3", "private 10/8" => "10.20.30.40", "CGNAT" => "100.64.0.1",
    "Alibaba metadata" => "100.100.100.200", "loopback" => "127.0.0.1", "loopback range" => "127.255.0.9",
    "link-local" => "169.254.10.10", "cloud metadata" => "169.254.169.254", "private 172.16/12" => "172.16.0.1",
    "private 172.31" => "172.31.255.254", "IETF protocol" => "192.0.0.8", "TEST-NET-1" => "192.0.2.10",
    "6to4 relay" => "192.88.99.1", "private 192.168/16" => "192.168.1.1", "benchmarking" => "198.19.0.1",
    "TEST-NET-2" => "198.51.100.7", "TEST-NET-3" => "203.0.113.9", "multicast" => "224.0.0.251",
    "multicast top" => "239.255.255.250", "reserved" => "240.0.0.1", "broadcast" => "255.255.255.255",
    "IPv6 unspecified" => "::", "IPv6 loopback" => "::1", "IPv6 ULA" => "fc00::1", "AWS IPv6 metadata" => "fd00:ec2::254",
    "IPv6 link-local" => "fe80::1", "IPv6 site-local" => "fec0::1", "IPv6 multicast" => "ff02::1",
    "IPv6 discard" => "100::1", "IPv6 documentation" => "2001:db8::1",
    "IPv4-mapped loopback" => "::ffff:127.0.0.1", "IPv4-mapped metadata" => "::ffff:169.254.169.254",
    "IPv4-mapped private" => "::ffff:10.0.0.1", "NAT64 private" => "64:ff9b::a00:1", "NAT64 loopback" => "64:ff9b::7f00:1",
    "6to4 loopback" => "2002:7f00:1::1", "6to4 metadata" => "2002:a9fe:a9fe::1", "IPv4-compatible loopback" => "::7f00:1",
    "6to4 private 10/8" => "2002:a00:1::1", "6to4 private 192.168/16" => "2002:c0a8:101:5::1", "6to4 CGNAT" => "2002:6440:1::",
    "local-use NAT64 metadata" => "64:ff9b:1::a9fe:a9fe", "local-use NAT64 public-looking" => "64:ff9b:1:808:8:800::",
    "Teredo" => "2001:0:4136:e378:8000:63bf:3fff:fdd2", "Teredo top" => "2001:0:ffff:ffff:ffff:ffff:ffff:ffff",
    "ORCHIDv2" => "2001:20::1"
  }.freeze

  PUBLIC = %w[
    8.8.8.8 1.1.1.1 93.184.216.34 11.0.0.1 100.63.255.255 100.128.0.1 172.32.0.1 192.169.0.1 223.255.255.255
    2606:4700:4700::1111 2a00:1450:4001::200e ::ffff:8.8.8.8 64:ff9b::808:808 2002:808:808::1
    2001:4860:4860::8888 2001:1::1 64:ff9b:2::1
  ].freeze

  BLOCKED.each do |label, address|
    test "blocks #{label} (#{address})" do
      assert Guard.blocked_address?(IPAddr.new(address))
      assert_raises(UptimeProbe::BlockedAddress) { Guard.new(allow_private: false).vet(address, timeout: 1) }
    end
  end

  test "allows public addresses, including public IPv4 inside IPv6 forms" do
    PUBLIC.each { |address| assert_not Guard.blocked_address?(IPAddr.new(address)), address }
  end

  test "refuses a host when any resolved address is blocked" do
    guard = Guard.new(allow_private: false, resolver: ->(*) { [ IPAddr.new("93.184.216.34"), IPAddr.new("10.0.0.7") ] })

    assert_raises(UptimeProbe::BlockedAddress) { guard.vet("mixed.example", timeout: 1) }
  end

  test "returns the first vetted address for public answers" do
    guard = Guard.new(allow_private: false, resolver: ->(*) { [ IPAddr.new("93.184.216.34"), IPAddr.new("2606:4700::1") ] })

    assert_equal IPAddr.new("93.184.216.34"), guard.vet("site.example", timeout: 1)
  end

  test "refuses localhost names before resolving" do
    guard = Guard.new(allow_private: false, resolver: ->(*) { flunk "must not resolve" })

    %w[localhost LOCALHOST localhost. app.localhost].each do |name|
      assert_raises(UptimeProbe::BlockedAddress) { guard.vet(name, timeout: 1) }
    end
  end

  test "no addresses is a DNS failure" do
    guard = Guard.new(allow_private: false, resolver: ->(*) { [] })

    assert_raises(UptimeProbe::DnsFailure) { guard.vet("nothing.example", timeout: 1) }
  end

  test "IP literals are vetted without resolving, bracketed or not" do
    guard = Guard.new(allow_private: false, resolver: ->(*) { flunk "must not resolve" })

    assert_equal IPAddr.new("8.8.8.8"), guard.vet("8.8.8.8", timeout: 1)
    assert_raises(UptimeProbe::BlockedAddress) { guard.vet("[::1]", timeout: 1) }
  end

  test "passes the remaining budget to the resolver" do
    timeouts = []
    guard = Guard.new(allow_private: false, resolver: ->(_host, timeout) { timeouts << timeout && [ IPAddr.new("8.8.8.8") ] })

    guard.vet("site.example", timeout: 4.5)

    assert_equal [ 4.5 ], timeouts
  end

  test "allowed_ips lets exactly those addresses through" do
    guard = Guard.new(allow_private: false, allowed_ips: [ "127.0.0.1" ])

    assert_equal IPAddr.new("127.0.0.1"), guard.vet("127.0.0.1", timeout: 1)
    assert_raises(UptimeProbe::BlockedAddress) { guard.vet("127.0.0.2", timeout: 1) }
    assert_raises(UptimeProbe::BlockedAddress) { guard.vet("169.254.169.254", timeout: 1) }
  end

  test "the private-address escape hatch is off by default and allows everything when on" do
    assert_not Rails.configuration.x.uptime.allow_private_addresses
    assert_raises(UptimeProbe::BlockedAddress) { Guard.new.vet("10.0.0.1", timeout: 1) }

    assert_equal IPAddr.new("10.0.0.1"), Guard.new(allow_private: true).vet("10.0.0.1", timeout: 1)
  end

  test "refused_literal? covers localhost and blocked literals only" do
    assert Guard.refused_literal?("localhost")
    assert Guard.refused_literal?("169.254.169.254")
    assert Guard.refused_literal?("[fd00:ec2::254]")
    assert_not Guard.refused_literal?("example.com")
    assert_not Guard.refused_literal?("8.8.8.8")
  end

  test "errors never carry the host name" do
    error = assert_raises(UptimeProbe::BlockedAddress) { Guard.new(allow_private: false).vet("10.9.9.9", timeout: 1) }

    assert_not_includes error.message, "10.9.9.9"
  end
end
