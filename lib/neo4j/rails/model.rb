module Neo4j
  module Rails
    class Model
      include Neo4j::NodeMixin
      
      include ActiveModel::Serializers::Xml
      include ActiveModel::Validations
      include ActiveModel::Dirty
      include ActiveModel::MassAssignmentSecurity

      extend ActiveModel::Naming
      extend ActiveModel::Callbacks
      
      include Neo4j::Rails::Validations
      extend 	Neo4j::Rails::Validations::ClassMethods
      
      include Finders						# ActiveRecord style find
      include Mapping::Property	# allows some additional options on the #property class method
      
      extend TxMethods

      class_inheritable_hash :attribute_defaults
      self.attribute_defaults = {}
      
      define_model_callbacks :create, :save, :update, :destroy

      class RecordInvalidError < RuntimeError
        attr_reader :record

        def initialize(record)
          @record = record
          super(@record.errors.full_messages.join(", "))
        end
      end

      # --------------------------------------
      # Initialize
      # --------------------------------------

      def initialize(*)
      end

      def init_on_create(*args) # :nodoc:
        super()
        self.attributes=args[0] if args[0].respond_to?(:each_pair)
      end

      # --------------------------------------
      # Identity
      # --------------------------------------

      def id
        neo_id.nil? ? nil : neo_id.to_s
      end

      def to_param
        persisted? ? neo_id.to_s : nil
      end

      # Returns an Enumerable of all (primary) key attributes
      # or nil if model.persisted? is false
      def to_key
        persisted? ? [:id] : nil
      end

      # enables ActiveModel::Dirty and Validation
      def method_missing(method_id, *args, &block)
        if !self.class.attribute_methods_generated?
          self.class.define_attribute_methods(self.class._decl_props.keys)
          # try again
          send(method_id, *args, &block)
        elsif property?(method_id)
        	send(:[], method_id)
        else
        	super
        end
      end

      def read_attribute_for_validation(key)
        send(key)
      end

      def attributes=(values)
        sanitize_for_mass_assignment(values).each do |k, v|
          if respond_to?("#{k}=")
            send("#{k}=", v)
          else
            self[k] = v
          end
        end
      end

      # Updates this resource with all the attributes from the passed-in Hash and requests that the record be saved.
      # If saving fails because the resource is invalid then false will be returned.
      def update_attributes(attributes)
        self.attributes=attributes
        save
      end

      def update_attributes!(attributes)
        self.attributes=attributes
        save!
      end

      def update_nested_attributes(rel_type, clazz, has_one, attr, options)
        allow_destroy, reject_if = [options[:allow_destroy], options[:reject_if]] if options

        if new?
          # We are updating a node that was created with the 'new' method.
          # The relationship will only be kept in the Value object.
          outgoing(rel_type) << clazz.new(attr) unless reject_if?(reject_if, attr) || (allow_destroy && attr[:_destroy] && attr[:_destroy] != '0')
        else
          # We have a node that was created with the #create method - has real Neo4j relationships
          # does it exist ?
          found = if has_one
            # id == nil that means we have a has_one relationship
                    outgoing(rel_type).first
                  else
                    # do we have an ID ?
                    id = attr[:id]
                    # this is a has_n relationship, find which one we want to update
                    id && outgoing(rel_type).find { |n| n.id == id }
                  end

          # Check if we want to destroy not found nodes (e.g. {..., :_destroy => '1' } ?
          destroy = attr[:_destroy] && attr[:_destroy] != '0'

          if found
            if destroy
              found.destroy if allow_destroy
            else
              found.update_attributes_in_tx(attr) # it already exist, so update that one
            end
          elsif !destroy && !reject_if?(reject_if, attr)
            new_node = clazz.new(attr)
            saved = new_node.save
            outgoing(rel_type) << new_node if saved
          end
        end
      end

      def reject_if?(proc_or_symbol, attr)
        return false if proc_or_symbol.nil?
        if proc_or_symbol.is_a?(Symbol)
          meth = method(proc_or_symbol)
          meth.arity == 0 ? meth.call : meth.call(attr)
        else
          proc_or_symbol.call(attr)
        end
      end

      def save(*args)
        _run_save_callbacks do
          if create_or_update_node(*args)
            true
          else
            # if not valid we should rollback the transaction so that the changes does not take place.
            # no point failing the transaction if we have created a model with 'new'
            Neo4j::Rails::Transaction.fail if Neo4j::Rails::Transaction.running? #&& !_java_node.kind_of?(Neo4j::Rails::Value)
            false
          end
        end
      end

      def create_or_update_node(options = {})
      	options.reverse_merge!({ :validate => true })
      	
      	if options[:validate] == false || valid?(:save)
          if new_record?
            _run_create_callbacks do
              if options[:validate] == false || valid?(:create)
                node = Neo4j::Node.new(props)
                return false unless _java_node.save_nested(node)
                init_on_load(node)
                init_on_create
                self.created_at = DateTime.now if Neo4j::Config[:timestamps] && respond_to?(:created_at)
                clear_changes
                true
              end
            end
          else
            _run_update_callbacks do
              if options[:validate] == false || valid?(:update)
                clear_changes
                self.updated_at = DateTime.now if Neo4j::Config[:timestamps] && respond_to?(:updated_at)
                true
              end
            end
          end
        end
      end

      def clear_changes
        @previously_changed = changes
        @changed_attributes.clear
      end
      
      def reload(options = nil)
				clear_changes
				reload_from_database or set_deleted_properties and return self
      end
      
      def save!(*args)
        raise RecordInvalidError.new(self) unless save(*args)
      end

      # Returns if the record is persisted, i.e. it’s not a new record and it was not destroyed
      def persisted?
        !new_record? && !destroyed?
      end

      def to_model
        self
      end

      def new?
        _java_node.kind_of?(Neo4j::Rails::Value)
      end
      
      alias :new_record? :new?

      def ==(other)
      	new? ? self.__id__ == other.__id__ : @_java_node == (other)
      end

      def del_with_wrapper
        _run_destroy_callbacks do 
        	del_without_wrapper
        	set_deleted_properties
				end
      end
      
      alias_method_chain :del, :wrapper
      alias :destroy :del_with_wrapper

      def destroyed?()
        @_deleted
      end

      # TODO: []= shouldn't need to be in a transaction because it shouldn't update the DB.  Need to refactor the @_java_node handling stuff if we want that to be the case though
      tx_methods :destroy, :create_or_update_node, :[]=, :update_attributes, :update_attributes!, :update_nested_attributes

      # --------------------------------------
      # Class Methods
      # --------------------------------------

      class << self
        extend TxMethods

        # returns a value object instead of creating a new node
        def new(*args)
          wrapped = self.orig_new
          value = Neo4j::Rails::Value.new(wrapped)
          wrapped.init_on_load(value)
          wrapped.attributes = initial_attributes(*args)
          wrapped
        end

        alias_method :_orig_create, :create

        def create(*args)
          new(*args).tap { |o| o.save }
        end

        def create!(*args)
        	new(*args).tap { |o| o.save! }
        end

        def transaction(&block)
          Neo4j::Rails::Transaction.run &block
        end

        def accepts_nested_attributes_for(*attr_names)
          options = attr_names.pop if attr_names[-1].is_a?(Hash)

          attr_names.each do |association_name|
            rel = self._decl_rels[association_name.to_sym]
            raise "No relationship declared with has_n or has_one with type #{association_name}" unless rel
            to_class = rel.to_class
            raise "Can't use accepts_nested_attributes_for(#{association_name}) since it has not defined which class it has a relationship to, use has_n(#{association_name}).to(MyOtherClass)" unless to_class
            type = rel.namespace_type
            has_one = rel.has_one?

            send(:define_method, "#{association_name}_attributes=") do |attributes|
              if has_one
                update_nested_attributes(type, to_class, true, attributes, options)
              else
                if attributes.is_a?(Array)
                  attributes.each do |attr|
                    update_nested_attributes(type, to_class, false, attr, options)
                  end
                else
                  attributes.each_value do |attr|
                    update_nested_attributes(type, to_class, false, attr, options)
                  end
                end
              end
            end
          end
        end
        
        protected
        def initial_attributes(*args)
        	args.first.is_a?(Hash) ? args.first.reverse_merge(attribute_defaults) : attribute_defaults
        end
      end
      
      private
      def reload_from_database
      	if reloaded = self.class.load(self.id.to_s)
					attributes = reloaded.attributes
				end
			end
			
      def set_deleted_properties
      	@_deleted = true
				@_persisted = false
				@_java_node = Neo4j::Rails::Value.new(self)
			end
    end
  end
end
