module Mongoid
  module Validations
    class UniquenessValidator < ActiveModel::EachValidator
      # Scope the criteria to the scope options provided.
      #
      # @api private
      #
      # @example Scope the criteria.
      #   validator.scope(criteria, document)
      #
      # @param [ Criteria ] criteria The criteria to scope.
      # @param [ Document ] document The document being validated.
      #
      # @return [ Criteria ] The scoped criteria.
      #
      # @since 2.3.0
      def scope(criteria, document, attribute)
        Array.wrap(options[:scope]).each do |item|
          name = document.database_field_name(item)
          criteria = criteria.where(item => document.attributes[name])
        end
        criteria = criteria.where(deleted_at: nil) if document.respond_to?(:paranoid)
        criteria
      end
    end
  end
end

module Mongoid
  module Relations
    module Builders
      module NestedAttributes
        class Many < NestedBuilder
          # Destroy the child document, needs to do some checking for embedded
          # relations and delay the destroy in case parent validation fails.
          #
          # @api private
          #
          # @example Destroy the child.
          #   builder.destroy(parent, relation, doc)
          #
          # @param [ Document ] parent The parent document.
          # @param [ Proxy ] relation The relation proxy.
          # @param [ Document ] doc The doc to destroy.
          #
          # @since 3.0.10
          def destroy(parent, relation, doc)
            doc.flagged_for_destroy = true
            if !doc.embedded? || parent.new_record? || doc.respond_to?(:paranoid)
              destroy_document(relation, doc)
            else
              parent.flagged_destroys.push(->{ destroy_document(relation, doc) })
            end
          end
        end
      end
    end
  end
end

module Mongoid
  module Relations
    module Embedded
      # This class handles the behaviour for a document that embeds many other
      # documents within in it as an array.
      class Many < Relations::Many
        # Delete the supplied document from the target. This method is proxied
        # in order to reindex the array after the operation occurs.
        #
        # @example Delete the document from the relation.
        #   person.addresses.delete(address)
        #
        # @param [ Document ] document The document to be deleted.
        #
        # @return [ Document, nil ] The deleted document or nil if nothing deleted.
        #
        # @since 2.0.0.rc.1
        def delete(document)
          execute_callback :before_remove, document
          doc = target.delete_one(document)
          if doc && !_binding?
            _unscoped.delete_one(doc) unless doc.respond_to?(:paranoid)
            if _assigning?
              if doc.respond_to?(:paranoid)
                doc.destroy(suppress: true)
              else
                base.add_atomic_pull(doc)
              end
            else
              doc.delete(suppress: true)
              unbind_one(doc)
            end
          end
          reindex
          execute_callback :after_remove, document
          doc
        end
      end
    end
  end
end