module Neo4j::Mapping
  module ClassMethods
    module InitRel
      def load_wrapper(rel)
        wrapped_rel = self.orig_new
        wrapped_rel.init_on_load(rel)
        wrapped_rel
      end


      # Creates a relationship between given nodes.
      #
      # You can use two callback method to initialize the relationship
      # init_on_load:: this method is called when the relationship is loaded from the database
      # init_on_create:: called when the relationship is created, will be provided with the same argument as the new method
      #
      # ==== Parameters (when creating a new relationship in db)
      # type:: the key and value to be set
      # from_node:: create relationship from this node
      # to_node:: create relationship to this node
      # props:: optional hash of properties to initialize the create relationship with
      #
      def new(*args)
        type, from_node, to_node, props = args
        rel = Neo4j::Relationship.create(type, from_node, to_node)
        wrapped_rel = super()
        wrapped_rel.init_on_load(rel)
        wrapped_rel.init_on_create(*args)
        wrapped_rel
      end

      alias_method :create, :new
    end
  end
end
