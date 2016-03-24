# -*- coding: utf-8 -*-

class TestInstance <  Test::Unit::TestCase
  def api_class(version)
    case version
    when :v1203 then Hijiki::DcmgrResource::V1203::Instance
    end
  end

  include TestBaseMethods

  def test_instance
    [:v1203].each { |api_ver|
      assert_nothing_raised() {
        instance = api_class(api_ver).find(:first).results.first
      }
    }
  end

end
