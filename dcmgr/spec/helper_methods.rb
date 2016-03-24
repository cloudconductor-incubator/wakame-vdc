# -*- coding: utf-8 -*-

require 'ipaddress'

module NetworkHelper
  def set_dhcp_range(network, r_begin = nil, r_end = nil)
    if r_begin.nil? || r_end.nil?
      nw_ipv4 = IPAddress::IPv4.new("#{network.ipv4_network}/#{network.prefix}")

      r_begin ||= nw_ipv4.first
      r_end ||= nw_ipv4.last
    end

    r_begin = ipv4_to_u32(r_begin) if r_begin.is_a?(String)
    r_end = ipv4_to_u32(r_end) if r_end.is_a?(String)

    Fabricate(:dhcp_range, network: network,
                           range_begin: r_begin,
                           range_end: r_end)
  end

  def destroy_dhcp_range(network, r_begin, r_end)
    range = Dcmgr::Models::DhcpRange.find(network: network,
                                          range_begin: ipv4_to_u32(r_begin),
                                          range_end: ipv4_to_u32(r_end))
    range.destroy
  end

  def ipv4_to_u32(ipv4)
    IPAddress::IPv4.new(ipv4).to_u32
  end

  def network_vif_from_ip_lease(ipv4)
    ipv4 = ipv4_to_u32(ipv4) if ipv4.is_a?(String)

    lease = Dcmgr::Models::NetworkVifIpLease.alives.where(ipv4: ipv4).first

    lease.network_vif
  end
end
