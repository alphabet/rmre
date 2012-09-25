require "rmre/db_utils"
require "rmre/dynamic_db"
require "contrib/progressbar"

# conf = YAML.load_file('rmre_db.yml')
# Rmre::Migrate.prepare(conf[:db_source], conf[:db_target])
# tables = Rmre::Migrate::Source::Db.connection.tables
# tables.each {|tbl| Rmre::Migrate.copy_table(tbl)}
module Rmre
  module Source
    include DynamicDb

    class Db < ActiveRecord::Base
    end
  end

  module Target
    include DynamicDb

    class Db < ActiveRecord::Base
    end
  end

  module Migrate
    @rails_copy_mode = true
    @force_table_create = false # If set to true will call AR create_table with force (table will be dropped if exists)

    def self.prepare(source_db_options, target_db_options, rails_copy_mode = true)
      @rails_copy_mode = rails_copy_mode

      Rmre::Source.connection_options = source_db_options
      Rmre::Target.connection_options = target_db_options
      Rmre::Source::Db.establish_connection(Rmre::Source.connection_options)
      Rmre::Target::Db.establish_connection(Rmre::Target.connection_options)
    end

    def self.copy(force = false)
      tables_count = Rmre::Source::Db.connection.tables.length
      Rmre::Source::Db.connection.tables.sort.each_with_index do |table, idx|
        puts "Copying table #{table} (#{idx + 1}/#{tables_count})..."
        copy_table(table)
      end
    end

    def self.copy_table(table)
      unless Rmre::Target::Db.connection.table_exists?(table)
        create_table(table, Rmre::Source::Db.connection.columns(table))
      end
      copy_data(table)
    end

    def self.create_table(table, source_columns)
      Rmre::Target::Db.connection.create_table(table, :id => @rails_copy_mode, :force => @force_table_create) do |t|
        source_columns.reject {|col| col.name.downcase == 'id' && @rails_copy_mode }.each do |sc|
          options = {
            :null => sc.null,
            :default => sc.default
          }

          col_type = Rmre::DbUtils.convert_column_type(Rmre::Target::Db.connection.adapter_name, sc.type)
          case col_type
          when :decimal
            options.merge!({
                :limit => sc.limit,
                :precision => sc.precision,
                :scale => sc.scale,
              })
          when :string
            options.merge!({
                :limit => sc.limit
              })
          end

          t.column(sc.name, col_type, options)
        end
      end
    end

    def self.table_has_type_column(table)
      Rmre::Source::Db.connection.columns(table).find {|col| col.name == 'type'}
    end

    def self.copy_data(table_name)
      src_model = Rmre::Source.create_model_for(table_name)
      src_model.inheritance_column = 'ruby_type' if table_has_type_column(table_name)
      tgt_model = Rmre::Target.create_model_for(table_name)

      rec_count = src_model.count
      copy_options = {}
      # If we are copying legacy databases and table has column 'type'
      # we must skip protection because ActiveRecord::AttributeAssignment::assign_attributes
      # will skip it and later that value for that column will be set to nil.
      copy_options[:without_protection] = (!@rails_copy_mode && table_has_type_column(table_name))
      progress_bar = Console::ProgressBar.new(table_name, rec_count)
      src_model.all.each do |src_rec|
        tgt_model.create!(src_rec.attributes, copy_options)
        progress_bar.inc
      end
    end
  end
end