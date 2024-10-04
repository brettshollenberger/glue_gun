module GlueGun
  module Types
    require_relative "types/hash_type"
    ActiveModel::Type.register(:hash, GlueGun::Types::HashType)

    require_relative "types/array_type"
    ActiveModel::Type.register(:array, GlueGun::Types::ArrayType)

    require_relative "types/date_type"
    ActiveModel::Type.register(:date, GlueGun::Types::DateType)

    require_relative "types/date_time_type"
    ActiveModel::Type.register(:datetime, GlueGun::Types::DateTimeType)
  end
end
