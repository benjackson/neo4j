begin
  # make sure that this file is not loaded twice
  @_neo4j_rspec_loaded = true

  #require "bundler/setup"
  #require 'ruby-debug'
  require 'rspec'
  require 'fileutils'
  require 'tmpdir'
  require 'rspec-rails-matchers'
  require 'benchmark'

  $LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")

  require 'neo4j'

  def rm_db_storage
    FileUtils.rm_rf Neo4j::Config[:storage_path]
    raise "Can't delete db" if File.exist?(Neo4j::Config[:storage_path])
  end

  def finish_tx
    return unless @tx
    @tx.success
    @tx.finish
    @tx = nil
  end

  def new_tx
    finish_tx if @tx
    @tx = Neo4j::Transaction.new
  end

  # Requires supporting ruby files with custom matchers and macros, etc,
  # in spec/support/ and its subdirectories.
  Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

  # load all fixture classes
  Dir["#{File.dirname(__FILE__)}/fixture/**/*.rb"].each {|f| require f}

  # set database storage location
  Neo4j::Config[:storage_path] = File.join(Dir.tmpdir, 'neo4j-rspec-tests')

  RSpec.configure do |c|

  #c.filter = { :type => :problem}
    c.before(:each, :type => :transactional) do
      new_tx
    end

    c.after(:each, :type => :transactional) do
      finish_tx
      Neo4j::Transaction.run do
        Neo4j._all_nodes.each { |n| n.del unless n.neo_id == 0 }
      end
    end

    c.after(:each) do
      finish_tx
      Neo4j::Transaction.run do
        Neo4j._all_nodes.each { |n| n.del unless n.neo_id == 0 }
      end
    end

    c.before(:all) do
      Neo4j.start
    end

    c.after(:all) do
      finish_tx
      Neo4j.shutdown
      rm_db_storage
    end

  end


  module TempModel
    @@_counter = 1

    def self.set(klass)
      name       = "Model_#{@@_counter}"
      @@_counter += 1
      klass.class_eval <<-RUBY
	def self.to_s
	  "#{name}"
	end
      RUBY
      Kernel.const_set(name, klass)
      klass
    end
  end

  def model_subclass(base_class = Neo4j::Model, &block)
    klass = block ? Class.new(base_class, &block) : Class.new(base_class)
    TempModel.set(klass)
  end

  def tmp_node_mixin(&block)
    klass = Class.new
    TempModel.set(klass)
    klass.send(:include, Neo4j::NodeMixin)
    klass.class_eval &block
    klass
  end
end unless @_neo4j_rspec_loaded

