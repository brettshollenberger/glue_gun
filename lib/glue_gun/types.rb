module GlueGun
  module Types
    require_relative "types/hash_type"
    ActiveModel::Type.register(:hash, GlueGun::Types::HashType)

    require_relative "types/array_type"
    ActiveModel::Type.register(:array, GlueGun::Types::ArrayType)
  end
end
