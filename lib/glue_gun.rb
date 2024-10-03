require "active_model"
require "active_support/concern"

module GlueGun
  require_relative "glue_gun/types/hash_type"
  ActiveModel::Type.register(:hash, GlueGun::Types::HashType)

  require_relative "glue_gun/dsl"
end
