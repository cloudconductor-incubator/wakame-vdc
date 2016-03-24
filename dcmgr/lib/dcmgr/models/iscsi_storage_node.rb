# -*- coding: utf-8 -*-

module Dcmgr::Models
  class IscsiStorageNode < StorageNode
    include Dcmgr::Constants::StorageNode

    def_dataset_method(:volumes) do
      # TODO: better SQL....
      Volume.filter(:id=>IscsiVolume.filter(:iscsi_storage_node_id=>self.select(:id)).select(:id))
    end

    def volumes_dataset
      self.class.filter(:id=>self.pk).volumes
    end

    def associate_volume(volume, &blk)
      raise ArgumentError, "Invalid class: #{volume.class}" unless volume.class == Volume
      raise ArgumentError, "#{volume.canonical_uuid} has already been associated." unless volume.volume_type.nil?

      iscsi_vol = IscsiVolume.new(&blk)
      iscsi_vol.id = volume.pk
      iscsi_vol.iscsi_storage_node = self
      iscsi_vol.path = volume.canonical_uuid
      iscsi_vol.save

      volume.volume_type = Dcmgr::Models::IscsiVolume.to_s
      volume.save_changes
      self
    end
  end
end
