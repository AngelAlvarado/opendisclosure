class DataFetcher
  class LateContribution
    def self.fetch_and_parse(url)
      SocrataFetcher.new(url).each do |record|
        parse_contributions(record)
      end
    end

    def self.parse_contributions(row)
      if row['amount'].nil? && row['enty_naml'].nil? && row['enty_namf'].nil? then
	puts "Skipping " + row.values_at('filer_naml', 'tran_id').join(':')
	return
      end
      if row['form_type'] == "F497P2" then # this is a payment from this committee.
	return
      end

      recipient = DataFetcher.get_filer(row)
      contributor =
        case row['entity_cd']
        when 'COM', 'SCC'
          # contributor is a Committee and Cmte_ID is set. Same thing as
          # Filer_ID but some names disagree
          Party::Committee.where(committee_id: row['cmte_id'])
                          .first_or_create(name: row['enty_naml'])

        when 'IND', 'OTH'
	  # If there is a first name this may have been chatacterized as other
	  # instead of individual.  This happened with the Firefighters Union Pac
	  if row['entity_cd'] == 'IND' || !row['tran_namf'].nil? then
	    # contributor is an Individual
	    full_name = row.values_at('enty_namf', 'enty_naml', 'enty_nams')
			   .join(' ')
			   .strip
	    Party::Individual.where(name: full_name,
				    city: row['enty_city'],
				    state: row['enty_st'],
				    zip: row['enty_zip4'])
			     .first_or_initialize
			     .tap { |p| p.update_attributes(employer: row['ctrib_emp'], occupation: row['ctrib_occ']) }
	  else
	    # contributor is "Other"
	    Party::Other.where(name: row['enty_naml'])
			.first_or_initialize
			.tap { |p| p.update_attributes(city: row['enty_city'], state: row['enty_st'], zip: row['enty_zip4']) }
	  end
        end

      ::Party.where(committee_id: recipient[:filer_id])
             .update_all(['last_updated_date = GREATEST(?, last_updated_date)', row['rpt_date']])

      ::Contribution.where(recipient: recipient,
                           transaction_id: row['tran_id'],
                           contributor: contributor,
                           amount: row['amount'],
                           date: row['ctrib_date'],
                           type: 'contribution'
                          ).first_or_create()
    end
  end
end
