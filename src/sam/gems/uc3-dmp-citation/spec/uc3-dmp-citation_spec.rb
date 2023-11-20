# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpCitation::Citer' do
  let!(:described_class) { Uc3DmpCitation::Citer }
  let!(citer_error) { Uc3DmpCitation::CiterError }

  describe 'fetch_citation(doi:, work_type: DEFAULT_WORK_TYPE, style: DEFAULT_CITATION_STYLE, logger: nil)' do
  end

  describe '_doi_to_uri(doi:)' do
  end

  describe '_determine_work_type(bibtex:)' do
  end

  describe '_cleanse_bibtex(text:)' do
  end

  describe '_bibtex_to_citation(uri:, work_type: DEFAULT_WORK_TYPE, bibtex:, style: DEFAULT_CITATION_STYLE)' do
  end
end
