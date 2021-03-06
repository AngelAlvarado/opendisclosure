require_relative 'environment.rb'
require_relative 'socrata_fetcher.rb'
require_relative 'schema.rb' # wipe the database and start anew

class DataFetcher
  URLS = {
    'Schedule A' => 'http://data.oaklandnet.com/resource/3xq4-ermg.json',
    'Form 497' => 'http://data.oaklandnet.com/resource/qact-u8hq.json',
    'Schedule E' => 'http://data.oaklandnet.com/resource/bvfu-nq99.json',
    'Schedule B1' => 'http://data.oaklandnet.com/resource/qaa7-q29f.json',
    'Summary' => 'http://data.oaklandnet.com/resource/rsxe-vvuw.json',
    'IEC Form 465' => 'http://data.oaklandnet.com/resource/jkj3-8yq3.json',
    'IEC Form 496' => 'http://data.oaklandnet.com/resource/6ejr-39gh.json',
  }.freeze

  def self.load_all_data!
    if ENV['LOG'] == "true"
      ActiveRecord::Base.logger = Logger.new(STDOUT)
    end

    # This table maps spellings of employers to a common spelling.
    # It needs to be updated when a new batch of data is available
    # as there is no check on spelling on the forms.
    puts "Loading Employer Map"
    Map.load_mappings('backend/map.csv')

    puts "Loading Lobbyist data"
    Lobbyist.load_from_file('backend/2014_Lobbyist_Directory.csv')

    puts "Fetching Contribution data (Form 497) from Socrata:"
    DataFetcher::LateContribution.fetch_and_parse(URLS['Form 497'])

    puts "Fetching Contribution data (Schedule A) from Socrata:"
    DataFetcher::Contribution.fetch_and_parse(URLS['Schedule A'])

    # Disabled so we can fit under the 10,000 row limit on Heroku
    # puts "Fetching Expense data (Schedule E) from Socrata:"
    # DataFetcher::Payment.fetch_and_parse(URLS['Schedule E'])

    puts 'Fetching Loan data (Schedule B1) from Socrata:'
    DataFetcher::Loan.fetch_and_parse(URLS['Schedule B1'])

    puts "Fetching Summary data from Socrata:"
    DataFetcher::Summary.fetch_and_parse(URLS['Summary'])

    puts "Fetching IEC data from Socrata:"
    DataFetcher::IEC.fetch_and_parse(URLS['IEC Form 496'])
    DataFetcher::IEC.fetch_and_parse(URLS['IEC Form 465'])

    puts "Run analysis"
    DataFetcher::CategoryContributions.run!
    DataFetcher::EmployerContributions.run!
    DataFetcher::Multiples.run!
    DataFetcher::Whales.run!

    Import.create(import_time: Time.now)
  end
  
  def self.get_filer(row)
      filer_id = row['filer_id'];
      if filer_id.nil? then
	filer_id = 0;
      elsif (/^\d*$/ =~ filer_id).nil? then
	puts row.values_at('filer_namf', 'filer_naml').join(' ') + " invalid id:" + filer_id;
	if filer_id =~ /pending/i then
	  filer_id = 0;
	else
	  id = CommitteeMap.maximum(:committee_id);
	  if id.nil? then
	    id = 9000000;
	  end
	  committee = CommitteeMap.where(filer_id: filer_id)
				   .first_or_create(name: row['filer_namel'], committee_id: id + 1);
	  filer_id = committee.committee_id;
	  puts 'filer_id is ' + filer_id.to_s;
	end
      end

      recipient = Party::Committee.where(committee_id: 0, name: row['filer_naml']).take;
      if recipient.nil? then
	recipient = if filer_id == 0    # "pending"
		      puts "Pending " + row['filer_naml'];
		      r = Party::Committee.where(name: row['filer_naml']).take;
		      if r.nil? then
			Party::Committee.where(committee_id: 0, name: row['filer_naml'])
					.first_or_create
		      else
			puts "Found " + r.committee_id;
			r
		      end
		    else
		      Party::Committee.where(committee_id: filer_id)
				      .first_or_create(name: row['filer_naml'])
		    end
      elsif filer_id != 0 then
	puts "Updating " + recipient.name + " " + filer_id.to_s;
	recipient = Party::Committee.where(committee_id: 0, name: row['filer_naml'])
			       .first_or_initialize
			       .tap { |p| p.update_attribute('committee_id', filer_id) };
      end
      return recipient;
  end
end

if __FILE__ == $0
  DataFetcher.load_all_data!
end
