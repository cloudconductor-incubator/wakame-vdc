# -*- coding: utf-8 -*-

require 'securerandom'

module Dcmgr::Models
  class RequestLog < BaseNew

    plugin :serialization
    serialize_attributes :yaml, :params

    def after_initialize
      super
      self[:request_id] ||= SecureRandom.hex(20)
      t = Time.now
      self[:requested_at] = t
      self[:requested_at_usec] = t.usec
    end

    def before_create
      t = Time.now
      self[:responded_at] = t
      self[:responded_at_usec] = t.usec
      super
    end

  end
end
