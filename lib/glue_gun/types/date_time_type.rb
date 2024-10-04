module GlueGun
  module Types
    class DateTimeType < ActiveModel::Type::Value
      def cast(value)
        case value
        when String
          parse_string(value)
        when Date, DateTime
          value
        end
      end

      def serialize(value)
        value.to_s
      end

      private

      def parse_string(value)
        DateTime.parse(value).utc
      rescue ArgumentError
        nil
      end
    end
  end
end
