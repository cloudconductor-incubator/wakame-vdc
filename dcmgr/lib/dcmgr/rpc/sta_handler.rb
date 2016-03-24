# -*- coding: utf-8 -*-
require 'isono'
require 'fileutils'

module Dcmgr
  module Rpc

    class StaHandler < EndpointBuilder
      include Dcmgr::Logger
      include Dcmgr::Helpers::CliHelper
      include Dcmgr::Helpers::ByteUnit

      def backing_store
        @backing_store = Dcmgr::Drivers::BackingStore.driver_class(Dcmgr::Configurations.sta.backing_store_driver).new
      end

      def storage_target
        @storage_target = Dcmgr::Drivers::StorageTarget.driver_class(Dcmgr::Configurations.sta.storage_target_driver).new
      end

      def setup_and_export_volume_new
        @sta_ctx = StaContext.new(self)

        rpc.request('sta-collector', 'update_volume', @volume_id, {:state=>:creating})

        if @volume[:backup_object_id]
          @backup_object = rpc.request('sta-collector', 'get_backup_object', @volume[:backup_object_id])
          raise "Invalid backup_object state: #{@backup_object[:state]}" unless @backup_object[:state].to_s == 'available'

          if backing_store.local_backup_object?(@backup_object)
            # the backup data exists on the same storage and also
            # is known how to convert to volume by the backing
            # store driver. e.g. filesystem level snapshot.
            logger.info("Creating new volume #{@volume_id} from #{@backup_object[:uuid]} (#{convert_byte(@volume[:size], MB)} MB)")
            backing_store.create_volume_from_local_backup(@sta_ctx)
          else
            backing_store.create_volume_from_backup(@sta_ctx)
          end
        else
          logger.info("Creating new blank volume #{@volume_id} (#{convert_byte(@volume[:size], MB)} MB)")
          backing_store.create_blank_volume(@sta_ctx)
        end
        logger.info("Finished creating new volume #{@volume_id}.")

        logger.info("Registering to storage target: #{@volume_id}")
        opt = storage_target.create(@sta_ctx)
        rpc.request('sta-collector', 'update_volume', @volume_id, {:state=>:available, :volume_device=>opt})
        logger.info("Finished registering storage target: #{@volume_id}")
      end

      # Setup volume file from snapshot storage and register to
      # sotrage target.
      def setup_and_export_volume
        @sta_ctx = StaContext.new(self)

        rpc.request('sta-collector', 'update_volume', @volume_id, {:state=>:creating})

        if @volume[:backup_object_id]
          @backup_object = rpc.request('sta-collector', 'get_backup_object', @volume[:backup_object_id])
          raise "Invalid backup_object state: #{@backup_object[:state]}" unless @backup_object[:state].to_s == 'available'

          if backing_store.local_backup_object?(@backup_object)
            # the backup data exists on the same storage and also
            # is known how to convert to volume by the backing
            # store driver. e.g. filesystem level snapshot.

            logger.info("Creating new volume #{@volume_id} from #{@backup_object[:uuid]} (#{convert_byte(@volume[:size], MB)} MB)")
            backing_store.create_volume(@sta_ctx, @backup_object[:object_key])
          else
            # download backup data from backup storage. then create
            # volume from the snapshot.
            begin
              snap_tmp_path = File.expand_path("#{@volume[:uuid]}.tmp", Dcmgr::Configurations.sta.tmp_dir)
              begin
                # download backup object to the tmporary place.
                backup_storage = Drivers::BackupStorage.snapshot_storage(@backup_object[:backup_storage])
                logger.info("Downloading to #{@backup_object[:uuid]}: #{snap_tmp_path}")
                backup_storage.download(@backup_object, snap_tmp_path)
                logger.info("Finished downloading #{@backup_object[:uuid]}: #{snap_tmp_path}")
              rescue => e
                logger.error(e)
                raise "Failed to download backup object: #{@backup_object[:uuid]}"
              end
              logger.info("Creating new volume #{@volume_id} from #{@backup_object[:uuid]} (#{convert_byte(@volume[:size], MB)} MB)")

              backing_store.create_volume(@sta_ctx, snap_tmp_path)
            ensure
              File.unlink(snap_tmp_path) rescue nil
            end
          end
        else
          logger.info("Creating new blank volume #{@volume_id} (#{convert_byte(@volume[:size], MB)} MB)")
          backing_store.create_volume(@sta_ctx, nil)
        end
        logger.info("Finished creating new volume #{@volume_id}.")
        logger.info("Registering to storage target: #{@volume_id}")
        opt = storage_target.create(@sta_ctx)
        rpc.request('sta-collector', 'update_volume', @volume_id, {:state=>:available, :volume_device=>opt})
        logger.info("Finished registering storage target: #{@volume_id}")
      end

      job :create_volume, proc {
        @volume_id = request.args[0]
        @volume = rpc.request('sta-collector', 'get_volume', @volume_id)
        raise "Invalid volume state: #{@volume[:state]}" unless @volume[:state].to_s == 'pending'

        if backing_store.kind_of?(Drivers::BackingStore::CreateVolumeInterface)
          setup_and_export_volume_new
        else
          setup_and_export_volume
        end
      }, proc {
        # TODO: need to clear generated temp files or remote files in remote snapshot repository.
        rpc.request('sta-collector', 'update_volume', @volume_id, {:state=>:deleted, :deleted_at=>Time.now.utc})
        logger.error("Failed to run create_volume: #{@volume_id}")
      }

      # create volume and chain to run instance.
      job :create_volume_and_run_instance, proc {
        @volume_id = request.args[0]
        @instance_id = request.args[1]

        @volume = rpc.request('sta-collector', 'get_volume', @volume_id)
        raise "Invalid volume state: #{@volume[:state]}" unless @volume[:state].to_s == 'pending'

        setup_and_export_volume

        @instance = rpc.request('hva-collector', 'get_instance', @instance_id)
        jobreq.submit("hva-handle.#{@instance[:host_node][:node_id]}", 'wait_volumes_available', @instance_id)
      }, proc {
        # TODO: need to clear generated temp files or remote files in remote snapshot repository.
        rpc.request('sta-collector', 'update_volume', @volume_id, {:state=>:deleted, :deleted_at=>Time.now.utc})
        rpc.request('hva-collector', 'update_instance', @instance_id, {:state=>:terminated, :terminated_at=>Time.now.utc})
        logger.error("Failed to run create_volume_and_run_instance: #{@instance_id}, #{@volume_id}")
      }

      job :delete_volume do
        @volume_id = request.args[0]
        @volume = rpc.request('sta-collector', 'get_volume', @volume_id)
        logger.info("#{@volume_id}: start deleting volume.")
        errcount = 0
        if @volume[:state].to_s == 'deleted'
          raise "#{@volume_id}: Invalid volume state: deleted"
        end
        if @volume[:state].to_s != 'deleting'
          logger.warn("#{@volume_id}: Unexpected volume state but try destroy resource: #{@volume[:state]}")
        end

        rpc.request('sta-collector', 'update_volume', @volume_id, {:state=>:deleting})

        # deregister from storage target
        begin
          storage_target.delete(StaContext.new(self))
        rescue => e
          logger.error("#{@volume_id}: Failed to delete storage target entry.")
          logger.error(e)
          errcount += 1
        end

        # delete volume
        begin
          backing_store.delete_volume(StaContext.new(self))
        rescue => e
          logger.error("#{@volume_id}: Failed to delete volume.")
          logger.error(e)
          logger.error(e.backtrace.join("\n"))
          errcount += 1
        end

        rpc.request('sta-collector', 'update_volume', @volume_id, {:state=>:deleted, :deleted_at=>Time.now.utc})
        if errcount > 0
          raise "#{@volume_id}: Encountered one or more errors during deleting."
        else
          logger.info("#{@volume_id}: Deleted volume successfully.")
        end
      end

      class ProgressCallback
        def initialize(&blk)
          @callee = blk
        end

        def setattr(checksum, alloc_size)
          @callee.call(:setattr, checksum, alloc_size)
        end

        def progress(percent)
          if !(0.0 > percent.to_f)
            percent = 0
          elsif 100.0 < percent.to_f
            percent = 100
          end
          @callee.call(:progress, percent)
        end
      end
      
      def backup_single_volume()
        new_object_key = nil
        raise "Missing volume hash object" if @sta_ctx.volume.nil?
        
        rpc.request('sta-collector', 'update_backup_object', @backup_object_id, {:state=>:creating})

        progress_callback = ProgressCallback.new { |cmd, *value|
            case cmd
            when :setattr
              # update checksum & allocation_size of the backup object
              rpc.request('sta-collector', 'update_backup_object', @backup_object_id, {
                            :checksum=>value[0],
                            :allocation_size => value[1],
                          })
            when :progress
              # update upload progress of backup object
              rpc.request('sta-collector', 'update_backup_object', @backup_object_id, {:progress=>value[0]}) do |req|
                req.oneshot = true
              end
            else
              raise "Unknown callback command: #{cmd}"
            end
        }
        
        # backup volume
        if backing_store.kind_of?(Dcmgr::Drivers::BackingStore::ProvideBackupVolume)
          backing_store.backup_volume(@sta_ctx, progress_callback)
          new_object_key = backing_store.backup_object_key_created(@sta_ctx)
        elsif backing_store.kind_of?(Dcmgr::Drivers::BackingStore::ProvidePointInTimeSnapshot)
          # take one generation snapshot -> copy data -> delete snapshot.
          raise NotImplementedError
        else
          raise "None of backup operation types are supported by #{backing_store.class}."
        end

        return new_object_key
      end

      job :backup_volume, proc {
        @volume_id = request.args[0]
        @backup_object_id = request.args[1]

        @volume = rpc.request('sta-collector', 'get_volume', @volume_id)
        @backup_object = rpc.request('sta-collector', 'get_backup_object', @backup_object_id)
        @sta_ctx = StaContext.new(self)

        new_object_key = backup_single_volume

        rpc.request('sta-collector', 'update_backup_object', @backup_object_id,
                    {:state=>:available, :object_key=>new_object_key})
        logger.info("Created new backup from #{@volume_id}: #{@backup_object_id}")
      }, proc {
        rpc.request('sta-collector', 'update_backup_object', @backup_object_id,
                    {:state=>:deleted})
      }

      job :backup_image, proc {
        @volume_id = request.args[0]
        @backup_object_id = request.args[1]
        @image_id = request.args[2]

        @volume = rpc.request('sta-collector', 'get_volume', @volume_id)
        @image = rpc.request('sta-collector', 'get_image', @image_id)
        @backup_object = rpc.request('sta-collector', 'get_backup_object', @backup_object_id) unless @backup_object_id.nil?
        @sta_ctx = StaContext.new(self)

        if @image[:state] == 'deleted'
          raise "Skip to backup volume since the associated image #{@image_id} had been destroyed already: #{@backup_object_id}"
        elsif @image[:state] != 'creating'
          raise "Unexpected image state: #{@image_id}, #{@image[:state]}"
        end

        rpc.request('sta-collector', 'update_backup_object', @backup_object_id, {:state=>:creating})
        rpc.request('hva-collector', 'update_image', @image_id, {:state=>:creating})
        
        new_object_key = backup_single_volume

        rpc.request('sta-collector', 'update_backup_object', @backup_object_id,
                    {:state=>:available, :object_key=>new_object_key})
        logger.info("Created new backup from #{@volume_id} for image #{@image_id}: #{@backup_object_id}")
        rpc.request('sta-collector', 'post_process_backup_image',
                    @image_id)
      }, proc {
        rpc.request('sta-collector', 'update_backup_object', @backup_object_id,
                    {:state=>:deleted, :deleted_at=>Time.now.utc})
        rpc.request('sta-collector', 'update_image', @image_id,
                    {:state=>:deleted, :deleted_at=>Time.now.utc})
      }
      
      job :create_snapshot, proc {
        @volume_id = request.args[0]
        @backup_object_id = request.args[1]
        @backup_object = rpc.request('sta-collector', 'get_backup_object', @backup_object_id) unless @backup_object_id.nil?
        @volume = rpc.request('sta-collector', 'get_volume', @volume_id)
        @sta_ctx = StaContext.new(self)

        logger.info("create new snapshot: #{@backup_object_id}")
        raise "Invalid volume state: #{@volume[:state]}" unless %w(available attached).member?(@volume[:state].to_s)

        begin
          snapshot_storage = Dcmgr::Drivers::BackupStorage.snapshot_storage(@backup_object[:backup_storage])

          logger.info("Taking new snapshot for #{@volume_id}")
          backing_store.create_snapshot(@sta_ctx)
          logger.info("Finish to create snapshot for #{@volume_id}")
          logger.info("Uploading #{@backup_object_id} to #{@backup_object[:backup_storage][:base_uri]}")
          snapshot_storage.upload(backing_store.snapshot_path_created(@sta_ctx), @backup_object)
          logger.info("Finish to upload #{@backup_object_id}")
        rescue => e
          logger.error(e)
          raise "snapshot has not be uploaded"
        ensure
          backing_store.delete_snapshot(@sta_ctx)
        end

        rpc.request('sta-collector', 'update_backup_object', @backup_object_id,
                    {:state=>:available, :path=>backing_store.snapshot_path_created(@sta_ctx)})
        logger.info("created new backup: #{@backup_object_id}")
      }, proc {
        # TODO: need to clear generated temp files or remote files in remote snapshot repository.
        rpc.request('sta-collector', 'update_backup_object', @backup_object_id, {:state=>:deleted, :deleted_at=>Time.now.utc})
        logger.error("Failed to run create_snapshot: #{@backup_object_id}")
      }

      job :delete_snapshot do
        @snapshot_id = request.args[0]
        @snapshot = rpc.request('sta-collector', 'get_snapshot', @snapshot_id)
        @volume = rpc.request('sta-collector', 'get_volume', @snapshot[:origin_volume_id])
        logger.info("deleting snapshot: #{@snapshot_id}")
        raise "Invalid snapshot state: #{@snapshot[:state]}" unless @snapshot[:state].to_s == 'deleting'
        begin
          snapshot_storage = storage_service.snapshot_storage(@destination[:bucket], @destination[:path])
          snapshot_storage.delete(@destination[:filename])
        rescue => e
           logger.error(e)
           raise "snapshot has not be deleted"
        end

        rpc.request('sta-collector', 'update_snapshot', @snapshot_id, {:state=>:deleted, :deleted_at=>Time.now.utc})
        logger.info("deleted snapshot: #{@snapshot_id}")
      end

      def rpc
        @rpc ||= Isono::NodeModules::RpcChannel.new(@node)
      end

      def jobreq
        @jobreq ||= Isono::NodeModules::JobChannel.new(@node)
      end

      def event
        @event ||= Isono::NodeModules::EventChannel.new(@node)
      end
    end

    class StaContext

      def initialize(stahandler)
        raise "Invalid Class: #{stahandler}" unless stahandler.instance_of?(StaHandler)
        @sta = stahandler
      end

      def volume_id
        @sta.instance_variable_get(:@volume_id)
      end

      def backup_object_id
        @sta.instance_variable_get(:@backup_object_id)
      end

      def destination
        @sta.instance_variable_get(:@destination)
      end

      def volume
        @sta.instance_variable_get(:@volume)
      end

      def backup_object
        @sta.instance_variable_get(:@backup_object)
      end

      def node
        @sta.instance_variable_get(:@node)
      end
    end

  end
end
