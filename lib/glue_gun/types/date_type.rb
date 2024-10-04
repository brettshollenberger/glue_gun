module GlueGun
  module Types
    class DateType < ActiveModel::Type::Value
      def cast(value)
        case value
        when String
          parse_string(value).to_date
        when Date, DateTime
          value.to_date
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
