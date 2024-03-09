# frozen_string_literal: true

require 'text'

# rubocop:disable Metrics/ClassLength
module Uc3DmpId
  class ComparatorError < StandardError; end

  # Class that compares incoming data from an external source to the DMP
  # It determines if they are likely related and applies a confidence rating
  class Comparator
    MSG_MISSING_DMPS = 'No DMPs were defined. Expected an Array of OpenSearch documents!'

    STOP_WORDS = %w[a an and if of or the then they].freeze

    # See the bottom of this file for a hard-coded crosswalk between Crossref funder ids and ROR ids
    # Some APIs do not support ROR fully for funder ids, so we need to be able to reference both

    attr_accessor :dmps, :logger

    # Expecting an Array of OpenSearch documents as :dmps in the :args
    def initialize(**args)
      @logger = args[:logger]
      @details_hash = {}

      @dmps = args.fetch(:dmps, [])
      raise ComparatorError, MSG_MISSING_DMPS if @dmps.empty?
    end

    # Compare the incoming hash with the DMP details that were gathered during initialization.
    #
    # The Hash should contain:
    #  {
    #    title: "Example research project",
    #    abstract: "Lorem ipsum psuedo abstract",
    #    keywords: ["foo", "bar"],z
    #    people: [
    #      {
    #        id: "https://orcid.org/blah",
    #        last_name: "doe",
    #        affiliation: { id: "https://ror.org/blah", name: "Foo" }
    #      }
    #    ],
    #    fundings: [
    #      { id: "https://doi.org/crossref123", name: "Bar", grant: ["1234", "http://foo.bar/543"] }
    #    ],
    #    repositories: [
    #      { id: ["http://some.repo.org", "https://doi.org/re3data123"], name: "Repo" }
    #    ]
    #  }
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def compare(hash:)
      return [] unless hash.is_a?(Hash) && !hash['title'].nil?

      # Compare the grant ids. If we have a match return the response immediately since that is
      # a very positive match!
      scoring = @dmps.map do |entry|
        dmp = entry.fetch('_source', {})
        response = { dmp_id: dmp['_id'], confidence: 'None', score: 0, notes: [] }
        response = _grants_match?(array: hash['fundings'], dmp:, response:)
        return response if response[:confidence] != 'None'

        response = _opportunities_match?(array: hash['fundings'], dmp:, response:)
        response = _orcids_match?(array: hash['people'], dmp:, response:)
        response = _last_name_and_affiliation_match?(array: hash['people'], dmp:, response:)

        # Only process the following if we had some matching contributors, affiliations or opportuniy nbrs
        response = _repository_match?(array: hash['repositories'], dmp:, response:) if response[:score].positive?
        # response = _keyword_match?(array: hash['keywords'], response:) if response[:score].positive?
        response = _text_match?(type: 'title', text: hash['title'], dmp:, response:) if response[:score].positive?
        response = _text_match?(type: 'abstract', text: hash['abstract'], dmp:, response:) if response[:score].positive?
        # If the score is less than 3 then we have no confidence that it is a match
        return nil if response[:score] <= 2

        # Set the confidence level based on the score
        response[:confidence] = if response[:score] > 10
                                  'High'
                                else
                                  (response[:score] > 5 ? 'Medium' : 'Low')
                                end
        response
      end

      # TODO: introduce a tie-breaker here (maybe the closes to the project_end date)
      scoring.compact.sort { |a, b| b[:score] <=> a[:score] }&.first
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    private

    # Returns whether or not the incoming grant id(s) match the DMPs grant id. Expecting:
    #    [
    #      { id: "https://doi.org/crossref123", name: "Bar", grant: ["1234", "http://foo.bar/543"] }
    #    ]
    # rubocop:disable Metrics/AbcSize
    def _grants_match?(array:, dmp:, response:)
      return response unless array.is_a?(Array) && dmp.is_a?(Hash) && response.is_a?(Hash)
      return response unless dmp['grant_ids'].is_a?(Array) && !dmp['grant_ids'].empty?

      ids = array.select { |funding| funding.is_a?(Hash) && funding['grant'].is_a?(Array) }
                 .map { |funding| funding['grant'].map { |id| id&.downcase&.strip } }
                 .flatten.compact.uniq

      matched = _compare_arrays(array_a: dmp['grant_ids'], array_b: ids)
      return response if matched <= 0

      response[:confidence] = 'Absolute'
      response[:score] = 100
      response[:notes] << 'the grant ID matched'
      response
    end
    # rubocop:enable Metrics/AbcSize

    # Returns whether or not the incoming grant id(s) match the DMPs opportunity id. Expecting:
    #    [
    #      { id: "https://doi.org/crossref123", name: "Bar", grant: ["1234", "http://foo.bar/543"] }
    #    ]
    # rubocop:disable Metrics/AbcSize
    def _opportunities_match?(array:, dmp:, response:)
      return response unless array.is_a?(Array) && dmp.is_a?(Hash) && response.is_a?(Hash)
      return response unless dmp['funder_opportunity_ids'].is_a?(Array) && !dmp['funder_opportunity_ids'].empty?

      ids = array.select { |funding| funding.is_a?(Hash) && funding['grant'].is_a?(Array) }
                 .map { |funding| funding['grant'].map { |id| id&.downcase&.strip } }
                 .flatten.compact.uniq

      matched = _compare_arrays(array_a: dmp['funder_opportunity_ids'], array_b: ids)
      return response if matched <= 0

      response[:score] += 5
      response[:notes] << 'the funding opportunity number matched'
      response
    end
    # rubocop:enable Metrics/AbcSize

    # Returns whether or not the inciming list of creators/contributors match those on the DMP. Expecting:
    #   [
    #      {
    #        id: "https://orcid.org/blah",
    #        last_name: "doe",
    #        affiliation: { id: "https://ror.org/blah", name: "Foo" }
    #      }
    #    ]
    # rubocop:disable Metrics/AbcSize
    def _orcids_match?(array:, dmp:, response:)
      return response unless array.is_a?(Array) && dmp.is_a?(Hash) && response.is_a?(Hash)
      return response unless dmp['people_ids'].is_a?(Array) && !dmp['people_ids'].empty?

      ids = array.select { |repo| repo.is_a?(Hash) }
                 .map { |person| person['id']&.downcase&.strip }
                 .flatten.compact.uniq

      matched = _compare_arrays(array_a: dmp['people_ids'], array_b: ids)
      return response if matched <= 0

      response[:score] += (matched * 2)
      response[:notes] << 'contributor ORCIDs matched'
      response
    end
    # rubocop:enable Metrics/AbcSize

    # Returns whether or not the inciming list of creators/contributors match those on the DMP. Expecting:
    #   [
    #      {
    #        id: "https://orcid.org/blah",
    #        last_name: "doe",
    #        affiliation: { id: "https://ror.org/blah", name: "Foo" }
    #      }
    #    ]
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def _last_name_and_affiliation_match?(array:, dmp:, response:)
      return response unless array.is_a?(Array) && dmp.is_a?(Hash) && response.is_a?(Hash)
      return response unless dmp['people'].is_a?(Array) && !dmp['people'].empty?

      array = array.select { |repo| repo.is_a?(Hash) }
      affiliations = array.map { |person| person['affiliation'] }&.flatten&.compact&.uniq
      last_names = array.map { |person| person['last_name']&.downcase&.strip }&.flatten&.compact&.uniq
      rors = affiliations.map { |affil| affil['id']&.downcase&.strip }&.flatten&.compact&.uniq
      affil_names = affiliations.map { |affil| affil['name']&.downcase&.strip }&.flatten&.compact&.uniq

      # Check the person last names and affiliation name and RORs
      last_names_matched = _compare_arrays(array_a: dmp['people'], array_b: last_names)
      rors_matched = _compare_arrays(array_a: dmp.fetch('affiliation_ids', []), array_b: rors)
      affil_names_matched = _compare_arrays(array_a: dmp.fetch('affiliations', []), array_b: affil_names)
      return response if last_names_matched <= 0 && rors_matched <= 0 && affil_names_matched <= 0

      response[:score] += last_names_matched + rors_matched + affil_names_matched
      response[:notes] << 'contributor names and affiliations matched'
      response
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Returns whether or not the incoming list of repositories match those defined in the DMP. Expecting:
    #    [
    #      { id: ["http://some.repo.org", "https://doi.org/re3data123"], name: "Repo" }
    #    ]
    # rubocop:disable Metrics/AbcSize
    def _repository_match?(array:, dmp:, response:)
      return response unless array.is_a?(Array) && dmp.is_a?(Hash) && response.is_a?(Hash)
      return response unless dmp['repositories'].is_a?(Array) && !dmp['repositories'].empty?

      # We only care about repositories with ids/urls
      ids = array.select { |repo| repo.is_a?(Hash) }
                 .map { |repo| repo['id'].map { |id| id&.downcase&.strip } }
                 .flatten.compact.uniq

      matched = _compare_arrays(array_a: dmp['repositories'], array_b: ids)
      return response if matched <= 0

      response[:score] += matched
      response[:notes] << 'repositories matched'
      response
    end
    # rubocop:enable Metrics/AbcSize

    # Uses an NLP library to determine if the :text matches the DMP/Project :title or :description
    # rubocop:disable Metrics/AbcSize
    def _text_match?(text:, dmp:, response:, type: 'title')
      return response unless response.is_a?(Hash) && text.is_a?(String) && !text.strip.empty? && dmp.is_a?(Hash)

      nlp_processor = Text::WhiteSimilarity.new
      cleansed = _cleanse_text(text:)

      dmp_val = type == 'title' ? dmp['title'] : dmp['description']
      details = {
        "dmp_#{type}": dmp_val,
        "incoming_#{type}": cleansed,
        nlp_score: nlp_processor.similarity(dmp_val, cleansed)
      }
      @logger&.debug(message: 'Text::WhiteSimilarity score', details:)
      return response if details[:nlp_score] < 0.5

      response[:score] += details[:nlp_score] >= 0.75 ? 5 : 2
      response[:notes] << "#{type}s are similar"
      response
    end
    # rubocop:enable Metrics/AbcSize

    # Change the incoming text to lower case, remove spaces and STOP_WORDS
    def _cleanse_text(text:)
      return nil unless text.is_a?(String)

      text.downcase.split.reject { |word| STOP_WORDS.include?(word) }.join(' ').strip
    end

    # Do an introspection of the 2 arrays and return the number of matches
    def _compare_arrays(array_a: [], array_b: [])
      return 0 unless array_a.is_a?(Array) && array_b.is_a?(Array)

      intersection = array_a & array_b
      intersection.nil? || intersection.size <= 0 ? 0 : intersection.size
    end

    # TODO: Remove this hard-coded crosswalk once the community has broader support for using ROR for funder ids
    ROR_FUNDREF_ID_CROSSWALK = {
      # NIH ID Crosswalk
      'https://ror.org/01cwqze88': 'https://doi.org/10.13039/100000002',
      'https://ror.org/04mhx6838': 'https://doi.org/10.13039/100000055',
      'https://ror.org/012pb6c26': 'https://doi.org/10.13039/100000050',
      'https://ror.org/03wkg3b53': 'https://doi.org/10.13039/100000053',
      'https://ror.org/0060t0j89': 'https://doi.org/10.13039/100000092',
      'https://ror.org/00372qc85': 'https://doi.org/10.13039/100000070',
      'https://ror.org/00190t495': 'https://doi.org/10.13039/100008460',
      'https://ror.org/00j4k1h63': 'https://doi.org/10.13039/100000066',
      'https://ror.org/01y3zfr79': 'https://doi.org/10.13039/100000056',
      'https://ror.org/04q48ey07': 'https://doi.org/10.13039/100000057',
      'https://ror.org/0493hgw16': 'https://doi.org/10.13039/100006545',
      'https://ror.org/04vfsmv21': 'https://doi.org/10.13039/100000098',
      'https://ror.org/03jh5a977': 'https://doi.org/10.13039/100000093',
      'https://ror.org/04xeg9z08': 'https://doi.org/10.13039/100000025',
      'https://ror.org/01s5ya894': 'https://doi.org/10.13039/100000065',
      'https://ror.org/02meqm098': 'https://doi.org/10.13039/100000002',
      'https://ror.org/049v75w11': 'https://doi.org/10.13039/100000049',
      'https://ror.org/004a2wv92': 'https://doi.org/10.13039/100000072',
      'https://ror.org/00adh9b73': 'https://doi.org/10.13039/100000062',
      'https://ror.org/043z4tv69': 'https://doi.org/10.13039/100000060',
      'https://ror.org/00x19de83': 'https://doi.org/10.13039/100000002',
      'https://ror.org/02jzrsm59': 'https://doi.org/10.13039/100000027',
      'https://ror.org/006zn3t30': 'https://doi.org/10.13039/100000069',
      'https://ror.org/04byxyr05': 'https://doi.org/10.13039/100000071',
      'https://ror.org/04pw6fb54': 'https://doi.org/10.13039/100006108',
      'https://ror.org/05aq6yn88': 'https://doi.org/10.13039/100006955',
      'https://ror.org/02xey9a22': 'https://doi.org/10.13039/100000061',
      'https://ror.org/00fj8a872': 'https://doi.org/10.13039/100000052',
      'https://ror.org/01wtjyf13': 'https://doi.org/10.13039/100000063',
      'https://ror.org/04r5s4b52': 'https://doi.org/10.13039/100005440',
      'https://ror.org/046zezr58': 'https://doi.org/10.13039/100006085',
      'https://ror.org/02e3wq066': 'https://doi.org/10.13039/100006086',
      'https://ror.org/031gy6182': 'https://doi.org/10.13039/100000002',
      'https://ror.org/054j5yq82': 'https://doi.org/10.13039/100000002',
      'https://ror.org/02yrzyf97': 'https://doi.org/10.13039/100000002',

      # NSF ID Crosswalk
      'https://.org/021nxhr62': 'https://doi.org/10.13039/100000001',
      'https://.org/04aqat463': 'https://doi.org/10.13039/100000001',
      'https://.org/01rcfpa16': 'https://doi.org/10.13039/100005441',
      'https://.org/014eweh95': 'https://doi.org/10.13039/100005445',
      'https://.org/001xhss06': 'https://doi.org/10.13039/100000076',
      'https://.org/04qn9mx93': 'https://doi.org/10.13039/100000153',
      'https://.org/03g87he71': 'https://doi.org/10.13039/100000155',
      'https://.org/01tnvpc68': 'https://doi.org/10.13039/100000156',
      'https://.org/01rvays47': 'https://doi.org/10.13039/100000154',
      'https://.org/002jdaq33': 'https://doi.org/10.13039/100000152',
      'https://.org/025kzpk63': 'https://doi.org/10.13039/100000083',
      'https://.org/04nh1dc89': 'https://doi.org/10.13039/100007523',
      'https://.org/01mng8331': 'https://doi.org/10.13039/100000143',
      'https://.org/02rdzmk74': 'https://doi.org/10.13039/100000144',
      'https://.org/053a2cp42': 'https://doi.org/10.13039/100000145',
      'https://.org/014bj5w56': 'https://doi.org/10.13039/100000081',
      'https://.org/00whkrf32': 'https://doi.org/10.13039/100000082',
      'https://.org/05s7cqk18': 'https://doi.org/10.13039/100000173',
      'https://.org/02kd4km72': 'https://doi.org/10.13039/100000172',
      'https://.org/03mamvh39': 'https://doi.org/10.13039/100000171',
      'https://.org/00b6sbb32': 'https://doi.org/10.13039/100000084',
      'https://.org/0471zv972': 'https://doi.org/10.13039/100000146',
      'https://.org/028yd4c30': 'https://doi.org/10.13039/100000147',
      'https://.org/01krpsy48': 'https://doi.org/10.13039/100000148',
      'https://.org/050rnw378': 'https://doi.org/10.13039/100000149',
      'https://.org/0388pet74': 'https://doi.org/10.13039/100000150',
      'https://.org/03xyg3m20': 'https://doi.org/10.13039/100000151',
      'https://.org/05p847d66': 'https://doi.org/10.13039/100000085',
      'https://.org/037gd6g64': 'https://doi.org/10.13039/100000159',
      'https://.org/05v01mk25': 'https://doi.org/10.13039/100000160',
      'https://.org/05wqqhv83': 'https://doi.org/10.13039/100000141',
      'https://.org/05nwjp114': 'https://doi.org/10.13039/100007352',
      'https://.org/05fnzca26': 'https://doi.org/10.13039/100000162',
      'https://.org/02trddg58': 'https://doi.org/10.13039/100000163',
      'https://.org/029b7h395': 'https://doi.org/10.13039/100000086',
      'https://.org/04mg8wm74': 'https://doi.org/10.13039/100000164',
      'https://.org/01ar8dr59': 'https://doi.org/10.13039/100000165',
      'https://.org/01pc7k308': 'https://doi.org/10.13039/100000078',
      'https://.org/051fftw81': 'https://doi.org/10.13039/100000121',
      'https://.org/04ap5x931': 'https://doi.org/10.13039/100000166',
      'https://.org/00apvva27': 'https://doi.org/10.13039/100005716',
      'https://.org/04nseet23': 'https://doi.org/10.13039/100000179',
      'https://.org/04k9mqs78': 'https://doi.org/10.13039/100000106',
      'https://.org/01k638r21': 'https://doi.org/10.13039/100000089',
      'https://.org/01gmp5538': 'https://doi.org/10.13039/100005447',
      'https://.org/01vnjbg30': 'https://doi.org/10.13039/100005449',
      'https://.org/03h7mcc28': 'https://doi.org/10.13039/100000088',
      'https://.org/05wgkzg12': 'https://doi.org/10.13039/100000169',
      'https://.org/0445wmv88': 'https://doi.org/10.13039/100000170',
      'https://.org/02dz2hb46': 'https://doi.org/10.13039/100000077',
      'https://.org/034m1ez10': 'https://doi.org/10.13039/100000107',
      'https://.org/02a65dj82': 'https://doi.org/10.13039/100005717',
      'https://.org/020fhsn68': 'https://doi.org/10.13039/100000001',
      'https://.org/03z9hh605': 'https://doi.org/10.13039/100000174',
      'https://.org/04ya3kq71': 'https://doi.org/10.13039/100007521',
      'https://.org/04evh7y43': 'https://doi.org/10.13039/100005443',
      'https://.org/04h67aa53': 'https://doi.org/10.13039/100000177',
      'https://.org/025dabr11': 'https://doi.org/10.13039/100005446',
      'https://.org/04vw0kz07': 'https://doi.org/10.13039/100005448',
      'https://.org/054ydxh33': 'https://doi.org/10.13039/100005554',
      'https://.org/01sharn77': 'https://doi.org/10.13039/100006091',
      'https://.org/02ch5q898': 'https://doi.org/10.13039/100000001',

      # NASA ID Crosswalk
      'https://.org/0171mag52': 'https://doi.org/10.13039/100006198',
      'https://.org/027k65916': 'https://doi.org/10.13039/100006196',
      'https://.org/027ka1x80': 'https://doi.org/10.13039/100000104',
      'https://.org/02acart68': 'https://doi.org/10.13039/100006195',
      'https://.org/059fqnc42': 'https://doi.org/10.13039/100006193',
      'https://.org/01cyfxe35': 'https://doi.org/10.13039/100016595',
      'https://.org/04xx4z452': 'https://doi.org/10.13039/100006203',
      'https://.org/0399mhs52': 'https://doi.org/10.13039/100006199',
      'https://.org/02epydz83': 'https://doi.org/10.13039/100006197',
      'https://.org/03j9e2j92': 'https://doi.org/10.13039/100006205',
      'https://.org/02s42x260': 'https://doi.org/10.13039/100000104',
      'https://.org/01p7gwa14': 'https://doi.org/10.13039/100000104',
      'https://.org/01qxmdg18': 'https://doi.org/10.13039/100000104',
      'https://.org/006ndaj41': 'https://doi.org/10.13039/100000104',
      'https://.org/03em45j53': 'https://doi.org/10.13039/100007346',
      'https://.org/045t78n53': 'https://doi.org/10.13039/100000104',
      'https://.org/00r57r863': 'https://doi.org/10.13039/100000104',
      'https://.org/0401vze59': 'https://doi.org/10.13039/100007726',
      'https://.org/04hccab49': 'https://doi.org/10.13039/100000104',
      'https://.org/04437j066': 'https://doi.org/10.13039/100000104',
      'https://.org/028b18z22': 'https://doi.org/10.13039/100000104',
      'https://.org/00ryjtt64': 'https://doi.org/10.13039/100000104',

      # DOE ID Crosswalk
      'https://ror.org/01bj3aw27': 'https://doi.org/10.13039/100000015',
      'https://ror.org/03q1rgc19': 'https://doi.org/10.13039/100006133',
      'https://ror.org/02xznz413': 'https://doi.org/10.13039/100006134',
      'https://ror.org/03sk1we31': 'https://doi.org/10.13039/100006168',
      'https://ror.org/00f93gc02': 'https://doi.org/10.13039/100006177',
      'https://ror.org/05tj7dm33': 'https://doi.org/10.13039/100006147',
      'https://ror.org/0012c7r22': 'https://doi.org/10.13039/100006192',
      'https://ror.org/00mmn6b08': 'https://doi.org/10.13039/100006132',
      'https://ror.org/03ery9d53': 'https://doi.org/10.13039/100006120',
      'https://ror.org/033jmdj81': 'https://doi.org/10.13039/100000015',
      'https://ror.org/03rd4h240': 'https://doi.org/10.13039/100006130',
      'https://ror.org/0054t4769': 'https://doi.org/10.13039/100006200',
      'https://ror.org/03eecgp81': 'https://doi.org/10.13039/100006174',
      'https://ror.org/00heb4d89': 'https://doi.org/10.13039/100006135',
      'https://ror.org/05ek3m339': 'https://doi.org/10.13039/100006150',
      'https://ror.org/00km40770': 'https://doi.org/10.13039/100006138',
      'https://ror.org/02ah1da87': 'https://doi.org/10.13039/100006137',
      'https://ror.org/05hsv7e61': 'https://doi.org/10.13039/100000015',
      'https://ror.org/01c9ay627': 'https://doi.org/10.13039/100006165',
      'https://ror.org/04z2gev20': 'https://doi.org/10.13039/100006183',
      'https://ror.org/02z1qvq09': 'https://doi.org/10.13039/100006144',
      'https://ror.org/03jf3w726': 'https://doi.org/10.13039/100006186',
      'https://ror.org/04848jz84': 'https://doi.org/10.13039/100006142',
      'https://ror.org/04s778r16': 'https://doi.org/10.13039/100006171',
      'https://ror.org/04nnxen11': 'https://doi.org/10.13039/100000015',
      'https://ror.org/05csy5p27': 'https://doi.org/10.13039/100010268',
      'https://ror.org/05efnac71': 'https://doi.org/10.13039/100000015'
    }.freeze
  end
end
# rubocop:enable Metrics/ClassLength
