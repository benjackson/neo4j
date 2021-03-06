module Neo4j

  # == Handles Transactional Events
  #
  # You can use this to receive event before the transaction commits.
  # The following events are supported:
  # * <tt>on_neo4j_started</tt>
  # * <tt>on_neo4j_shutdown</tt>
  # * <tt>on_node_created</tt>
  # * <tt>on_node_deleted</tt>
  # * <tt>on_relationship_created</tt>
  # * <tt>on_relationship_deleted</tt>
  # * <tt>on_property_changed</tt>
  # * <tt>on_rel_property_changed</tt>
  #
  # === Usage
  #
  #   class MyListener
  #     def on_node_deleted(node, old_props, tx_data)
  #     end
  #   end
  #
  #   # to add an listener without starting neo4j:
  #   Neo4j.unstarted_db.event_handler.add(MyListener.new)
  #
  # You only need to implement the methods that you need.
  #
  class EventHandler
    include org.neo4j.graphdb.event.TransactionEventHandler

    def initialize
      @listeners = []
    end


    def after_commit(data, state)
    end

    def after_rollback(data, state)
    end

    def before_commit(data)
      data.created_nodes.each{|node| node_created(node)}
      data.assigned_node_properties.each { |tx_data| property_changed(tx_data.entity, tx_data.key, tx_data.previously_commited_value, tx_data.value) }
      data.removed_node_properties.each { |tx_data| property_changed(tx_data.entity, tx_data.key, tx_data.previously_commited_value, nil) unless data.deleted_nodes.include?(tx_data.entity) }
      data.deleted_nodes.each { |node| node_deleted(node, deleted_properties_for(node,data), data)}
      data.created_relationships.each {|rel| relationship_created(rel, data)}
      data.deleted_relationships.each {|rel| relationship_deleted(rel, deleted_rel_properties_for(rel, data), data)}
      data.assigned_relationship_properties.each { |tx_data| rel_property_changed(tx_data.entity, tx_data.key, tx_data.previously_commited_value, tx_data.value) }
      data.removed_relationship_properties.each {|tx_data| rel_property_changed(tx_data.entity, tx_data.key, tx_data.previously_commited_value, nil) unless data.deleted_relationships.include?(tx_data.entity) }
    end

    def deleted_properties_for(node, data)
      data.removed_node_properties.find_all{|tx_data| tx_data.entity == node}.inject({}) do |memo, tx_data|
        memo[tx_data.key] = tx_data.previously_commited_value
        memo
      end
    end

    def deleted_rel_properties_for(rel, data)
      data.removed_relationship_properties.find_all{|tx_data| tx_data.entity == rel}.inject({}) do |memo, tx_data|
        memo[tx_data.key] = tx_data.previously_commited_value
        memo
      end
    end

    def add(listener)
      @listeners << listener unless @listeners.include?(listener)
    end

    def remove(listener)
      @listeners.delete(listener)
    end

    def remove_all
      @listeners = []
    end

    def print
      puts "Listeners #{@listeners.size}"
      @listeners.each {|li| puts "  Listener '#{li}'"}
    end

    def neo4j_started(db)
      @listeners.each { |li| li.on_neo4j_started(db) if li.respond_to?(:on_neo4j_started) }
    end

    def neo4j_shutdown(db)
      @listeners.each { |li| li.on_neo4j_shutdown(db) if li.respond_to?(:on_neo4j_shutdown) }
    end

    def node_created(node)
      @listeners.each {|li| li.on_node_created(node) if li.respond_to?(:on_node_created)}
    end

    def node_deleted(node,old_properties, data)
      @listeners.each {|li| li.on_node_deleted(node,old_properties, data) if li.respond_to?(:on_node_deleted)}
    end

    def relationship_created(relationship, tx_data)
      @listeners.each {|li| li.on_relationship_created(relationship, tx_data) if li.respond_to?(:on_relationship_created)}
    end

    def relationship_deleted(relationship, old_props, data)
      @listeners.each {|li| li.on_relationship_deleted(relationship, old_props, data) if li.respond_to?(:on_relationship_deleted)}
    end

    def property_changed(node, key, old_value, new_value)
      @listeners.each {|li| li.on_property_changed(node, key, old_value, new_value) if li.respond_to?(:on_property_changed)}
    end

    def rel_property_changed(rel, key, old_value, new_value)
      @listeners.each {|li| li.on_rel_property_changed(rel, key, old_value, new_value) if li.respond_to?(:on_rel_property_changed)}
    end
  end
end
