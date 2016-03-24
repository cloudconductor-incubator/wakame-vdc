# -*- coding: utf-8 -*-

shared_examples 'dont reassign released addresses' do
  context "when previously assigned addresses have been released" do
    let(:network) do
      Fabricate(:network, ipv4_network: "192.168.0.0").tap do |n|
        set_dhcp_range(n, "192.168.0.1", "192.168.0.15")
      end
    end

    before do
      5.times { incremental.schedule Fabricate(:network_vif, network: network) }

      network_vif_from_ip_lease("192.168.0.3").destroy
    end

    it "assigns the next IP, ignoring the previously released one" do
      expect(subject).to eq "192.168.0.6"
    end
  end
end
