require "spec_helper"

module Rmre
  describe Generator do
    let(:settings) do |sett|
      sett = {:db => {:adapter => 'some_adapter',
          :database => 'db',
          :username => 'user',
          :password => 'pass'},
        :out_path => File.join(Dir.tmpdir, 'gne-test'),
        :include => ['incl1_', 'incl2_'],
        :inflections => [{plural: ["(.*)_des$", '\1_des'], singular: ["(.*)_des$", '\1_des']}]
      }
    end

    let(:generator) do |gen|
      gen = Generator.new(settings[:db], settings[:out_path], settings[:include], settings[:inflections])
      connection = double("db_connection")
      connection.stub(:columns).and_return([])
      gen.stub(:connection).and_return(connection)
      gen
    end

    let(:tables)    { %w(incl1_tbl1 incl1_tbl2 incl2_tbl1 user processes) }

    it "should flag table incl1_tbl1 for processing" do
      generator.process?('incl1_tbl1').should be_true
    end

    it "should not flag table 'processes' for processing" do
      generator.process?('processes').should be_false
    end

    it "should process three tables from the passed array of tables" do
      generator.stub(:create_model)

      generator.should_receive(:create_model).exactly(3).times
      generator.create_models(tables)
    end

    it "should contain set_table_name 'incl1_tbl1' in generated source" do
      generator.stub_chain(:connection, :primary_key).and_return("id")
      generator.send(:generate_model_source, 'incl1_tbl1', []).should match(/self\.table_name = \'incl1_tbl1\'/)
    end

    it "should create three model files" do
      generator.stub_chain(:connection, :primary_key).and_return("id")
      generator.stub(:foreign_keys).and_return([])
      generator.create_models(tables)
      Dir.glob(File.join(generator.output_path, "*.rb")).should have(3).items
    end

    it "should create prettified file names" do
      file = double("model_file")
      file.stub(:write)

      generator.connection.stub(:primary_key).and_return('')

      File.stub(:open).and_yield(file)
      File.should_receive(:open).with(/tbl_user/, "w")
      file.should_receive(:write).with(/class TblUser/)

      generator.create_model("TBL_USERS")
    end

    context 'with non standard keys' do
      before(:each) do
        @file = double('model_file')
        @file.stub(:write)
      end

      it "should set primary key if PK column is not id" do
        generator.connection.stub(:primary_key).and_return('usr_id')

        File.stub(:open).and_yield(@file)
        @file.should_receive(:write).with(/self\.primary_key = :usr_id/)

        generator.create_model('users')
      end

      it "should set relationship foreign key if relationship FK column is not id" do
        generator.connection.stub(:primary_key).and_return('pst_id')
        generator.stub(:foreign_keys).and_return([
          { 'from_table' => 'posts',
            'from_column' => 'pst_id',
            'to_table'=>'user',
            'to_column'=>'user_id'}
            ])

        File.stub(:open).and_yield(@file)
        @file.should_receive(:write).with(/:foreign_key => :pst_id/)

        generator.create_model('posts')
      end

      it "should set relationship primary key if relationship PK column is not id" do
        generator.connection.stub(:primary_key).and_return('usr_id')
        generator.stub(:foreign_keys).and_return([
          { 'from_table' => 'posts',
            'from_column' => 'post_id',
            'to_table'=>'user',
            'to_column'=>'uzer_id'}
            ])

        File.stub(:open).and_yield(@file)
        @file.should_receive(:write).with(/:primary_key => :uzer_id/)

        generator.create_model('posts')
      end

    end

    context 'irregular plural table names' do
      it "should create correct file and class names" do
        file = double("model_file")
        file.stub(:write)

        generator.connection.stub(:primary_key).and_return('')

        File.stub(:open).and_yield(file)
        File.should_receive(:open).with(/status_des/, "w")
        file.should_receive(:write).with(/class StatusDes/)

        generator.create_model("status_des")
      end
    end
  end
end
