require "active_model"
require "active_record"
require "active_support/concern"

module GlueGun
  require_relative "glue_gun/version"
  require_relative "glue_gun/core_ext"
  require_relative "glue_gun/types"
  require_relative "glue_gun/dsl"
  require_relative "glue_gun/model"
end
