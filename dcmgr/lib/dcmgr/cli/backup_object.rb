# -*- coding: utf-8 -*-

module Dcmgr::Cli
  class BackupObject < Base
    namespace :backupobject
    M = Dcmgr::Models
    include Dcmgr::Constants::BackupObject

    no_tasks {
      def self.common_options
        method_option :uuid, :type => :string, :desc => "The UUID for the backup storage."
        method_option :account_id, :type => :string, :desc => "The account ID for the backup object."
        method_option :display_name, :type => :string, :desc => "The display name for the backup object."
        method_option :storage_id, :type => :string, :desc => "The backup storage ID to store the backup object."
        method_option :object_key, :type => :string, :desc => "The object key of the backup object."
        method_option :state, :type => :string, :desc => "The state of the backup object."
        method_option :size, :type => :numeric, :desc => "The original file size of the backup object."
        method_option :allocation_size, :type => :numeric, :desc => "The allcated file size of the backup object."
        method_option :checksum, :type => :string, :desc => "The checksum of the backup object."
        method_option :description, :type => :string, :desc => "Description of the backup storage"
        method_option :service_type, :type => :string, :desc => "Service type of the backup object. (#{Dcmgr::Configurations.dcmgr.service_types.keys.sort.join(', ')})"
        method_option :container_format, :type => :string, :desc => "The container format of the backup object.(#{CONTAINER_FORMAT.keys.join(', ')})"
        method_option :progress, :type => :numeric, :desc => "Progress of the backup object. (0.0 - 100.0)"
      end
    }
    
    desc "add [options]", "Register a backup object"
    common_options
    method_options[:account_id].default = 'a-shpoolxx'
    method_options[:state].default = :available
    method_options[:container_format].default = 'none'
    method_options[:storage_id].required = true
    method_options[:object_key].required = true
    method_options[:size].required = true
    method_options[:checksum].required = true
    method_options[:service_type].default = Dcmgr::Configurations.dcmgr.default_service_type
    def add
      bkst = M::BackupStorage[options[:storage_id]] || UnknownUUIDError.raise("Backup Storage UUID: #{options[:storage_id]}")

      fields = options.dup
      fields[:allocation_size] ||= options[:size]

      fields.delete(:storage_id)
      fields[:backup_storage_id] = bkst.id
      puts super(M::BackupObject, fields)
    end

    desc "modify UUID [options]", "Modify the backup object"
    common_options
    def modify(uuid)
      bo = M::BackupObject[uuid] || UnknownUUIDError.raise(uuid)
      fields = options.dup
      fields.delete(:storage_id)

      if options[:storage_id]
        bkst = M::BackupStorage[options[:storage_id]]
        Error.raise("Backup storage '#{options[:storage_id]}' does not exist.",100) if bkst.nil?
        fields[:backup_storage_id] = bkst.id
      end

      super(M::BackupObject, bo.canonical_uuid, fields)
    end

    desc "del UUID", "Deregister the backup object"
    def del(uuid)
      super(M::BackupObject,uuid)
    end

    desc "show [UUID]", "Show the backup object details"
    def show(uuid=nil)
      if uuid
        bo = M::BackupObject[uuid] || UnknownUUIDError.raise(uuid)
        puts ERB.new(<<__END, nil, '-').result(binding)
UUID: <%= bo.canonical_uuid %>
Name: <%= bo.display_name %>
Account ID: <%= bo.account_id %>
Backup Storage UUID: <%= bo.backup_storage.canonical_uuid %>
Object Key: <%= bo.object_key %>
Size: <%= bo.size %> (Alloc Size: <%= bo.allocation_size %>)
Checksum: <%= bo.checksum %>
Progress: <%= bo.progress %>
Container Format: <%= bo.container_format %>
Create: <%= bo.created_at %>
Update: <%= bo.updated_at %>
Delete: <%= bo.deleted_at %>
Purge: <%= bo.purged_at %>
<%- if bo.description -%>
Description:
<%= bo.description %>
<%- end -%>
__END
      else
        ds = M::BackupObject.dataset
        table = [['UUID', 'Account ID', 'Size', 'Checksum', 'Service Type', 'Name']]
        ds.each { |r|
          table << [r.canonical_uuid, r.account_id, r.size, r.checksum[0,10], r.service_type, r.display_name]
        }

        shell.print_table(table)
      end
    end

  end
end
