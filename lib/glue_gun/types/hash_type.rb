module GlueGun
  module Types
    class HashType < ActiveModel::Type::Value
      def cast(value)
        case value
        when String
          JSON.parse(value)
        when Hash
          value
        else
          {}
        end
      end

      def serialize(value)
        value.to_json
      end
    end
  end
end
