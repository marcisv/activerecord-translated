module ActiveRecordTranslated
  module Translated

    extend ActiveSupport::Concern

    included do
      def self.translates(*args)
        attribute_names = args.select{|arg| arg.is_a? Symbol }
        attribute_names_with_options = args.detect{|arg| arg.is_a? Hash } || {}
        attribute_names += attribute_names_with_options.keys

        has_many :translations, -> { order(locale: :desc) }, {
          class_name: translation_class_name,
          dependent:  :destroy,
          inverse_of: self.name.underscore.to_sym
        }

        accepts_nested_attributes_for :translations, limit: -> { I18n.available_locales.count }

        scope :order_by_translation, -> field_name {
          joined_table_name = "#{I18n.locale}_translations"

          joins(
            <<-SQL
              LEFT JOIN #{translation_class.table_name} AS #{joined_table_name}
              ON #{table_name}.id = #{joined_table_name}.#{self.name.underscore}_id AND #{joined_table_name}.locale='#{I18n.locale}'
            SQL
          ).order("#{joined_table_name}.#{field_name}")
        }

        attribute_names_with_options.each do |attribute_name, options|
          case options[:mandatory]
          when true
            I18n.available_locales.each{|locale| validates :"#{attribute_name}_#{locale}", presence: true }
          when :unless_default
            I18n.available_locales.each do |locale|
              validates :"#{attribute_name}_#{locale}", presence: true, unless: "#{attribute_name}.present?"
            end
          end
        end

        attribute_names.each do |attribute_name|
          I18n.available_locales.each do |locale|
            define_method :"#{attribute_name}_#{locale}" do
              attribute_translation(attribute_name, locale)
            end
          end

          define_method attribute_name do |*args|
            raise ArgumentError if args.count > 1
            locale = args[0] || I18n.locale
            translated_value = attribute_translation(attribute_name, locale)
            if !translated_value.nil?
              translated_value
            elsif has_attribute?(attribute_name)
              super()
            end
          end
        end
      end

      def attribute_translation(attribute_name, locale)
        translation(locale)&.send(attribute_name)
      end

      def self.translation_class_name
        "#{self.name}Translation"
      end

      def self.translation_class
        translation_class_name.constantize
      end

      def translation(locale)
        translations.detect{|t| t.locale.to_sym == locale.to_sym }
      end

      def build_translations
        I18n.available_locales.each{|locale| translations.find_or_initialize_by(locale: locale.to_s) }
        translations
      end
    end
  end
end
