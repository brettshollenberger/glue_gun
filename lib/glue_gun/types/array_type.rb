module GlueGun
  module Types
    class ArrayType < ActiveModel::Type::Value
      def cast(value)
        case value
        when String
          parse_string(value)
        when Array
          value
        else
          []
        end
      end

      def serialize(value)
        value.to_json
      end

      private

      def parse_string(value)
        JSON.parse(value)
      rescue JSON::ParserError
        []
      end
    end
  end
end
