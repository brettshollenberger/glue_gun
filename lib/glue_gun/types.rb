module GlueGun
  module Types
    require_relative "glue_gun/types/hash_type"
    ActiveModel::Type.register(:hash, GlueGun::Types::HashType)

    require_relative "glue_gun/types/array_type"
    ActiveModel::Type.register(:array, GlueGun::Types::ArrayType)
  end
end
