# frozen_string_literal: true

module Uc3DmpId
  module Schemas
    # The JSON schema for creating a new DMP ID
    # rubocop:disable Layout/LineLength, Metrics/MethodLength, Metrics/ClassLength
    class Amend
      class << self
        def load
          JSON.parse({
            '$id': 'https://github.com/CDLUC3/dmp-hub-sam/layer/ruby/config/schemas/amend.json',
            title: 'RDA DMP Common Standard Schema',
            description: 'JSON Schema for the RDA DMP Common Standard',
            type: 'object',
            properties: {
              dmp: {
                '$id': '#/properties/dmp',
                type: 'object',
                title: 'The DMP Schema',
                properties: {
                  dmp_id: {
                    '$id': '#/properties/dmp/properties/dmp_id',
                    type: 'object',
                    title: 'The DMP Identifier Schema',
                    description: 'Identifier for the DMP itself',
                    properties: {
                      identifier: {
                        '$id': '#/properties/dmp/properties/dmp_id/properties/identifier',
                        type: 'string',
                        title: 'The DMP Identifier Value Schema',
                        description: 'Identifier for a DMP',
                        examples: ['https://doi.org/10.1371/journal.pcbi.1006750']
                      },
                      type: {
                        '$id': '#/properties/dmp/properties/dmp_id/properties/type',
                        type: 'string',
                        enum: %w[
                          handle
                          doi
                          ark
                          url
                          other
                        ],
                        title: 'The DMP Identifier Type Schema',
                        description: 'The DMP Identifier Type. Allowed values: handle, doi, ark, url, other',
                        examples: ['doi']
                      }
                    },
                    required: %w[
                      identifier
                      type
                    ]
                  },
                  modified: {
                    '$id': '#/properties/dmp/properties/modified',
                    type: 'string',
                    format: 'date-time',
                    title: 'The DMP Modification Schema',
                    description: 'Must be set each time DMP is modified. Indicates DMP version. Encoded using the relevant ISO 8601 Date and Time compliant string.',
                    examples: ['2020-03-14T10:53:49']
                  },
                  title: {
                    '$id': '#/properties/dmp/properties/title',
                    type: 'string',
                    title: 'The DMP Title Schema',
                    description: 'Title of a DMP',
                    examples: ['DMP for our new project']
                  },
                  anyOf: [
                    {
                      dmproadmap_related_identifiers: {
                        '$id': '#/properties/dmp/properties/dmproadmap_related_identifiers',
                        type: 'array',
                        title: 'Related identifiers for the DMP',
                        description: 'Identifiers for objects related to the DMP (e.g. datasets, publications, etc.)',
                        items: {
                          '$id': '#/properties/dmp/properties/dmproadmap_related_identifiers/items',
                          type: 'object',
                          title: 'A related identifier',
                          properties: {
                            descriptor: {
                              '$id': '#/properties/dmp/properties/dmproadmap_related_identifiers/items/properties/descriptor',
                              type: 'string',
                              enum: %w[
                                is_cited_by
                                cites
                                is_supplement_to
                                is_supplemented_by
                                is_described_by
                                describes
                                has_metadata
                                is_metadata_for
                                is_part_of
                                has_part
                                is_referenced_by
                                references
                                is_documented_by
                                documents
                                is_new_version_of
                                is_previous_version_of
                              ]
                            },
                            identifier: {
                              '$id': '#/properties/dmp/properties/dmproadmap_related_identifiers/items/properties/identifier',
                              type: 'string',
                              title: 'A unique identifier for the item',
                              description: 'Identifier for a DMP',
                              examples: ['https://doi.org/10.1371/journal.pcbi.1006750']
                            },
                            type: {
                              '$id': '#/properties/dmp/properties/dmproadmap_related_identifiers/items/properties/type',
                              type: 'string',
                              enum: %w[
                                handle
                                doi
                                ark
                                url
                                other
                              ]
                            },
                            work_type: {
                              '$id': '#/properties/dmp/properties/dmproadmap_related_identifiers/items/properties/work_type',
                              type: 'string',
                              enum: %w[
                                article
                                book
                                dataset
                                metadata_template
                                other
                                output_management_plan
                                paper
                                preprint
                                preregistration
                                protocol
                                software
                                supplemental_information
                              ]
                            }
                          },
                          required: %w[
                            descriptor
                            identifier
                            type
                            work_type
                          ]
                        }
                      }
                    },
                    {
                      project: {
                        '$id': '#/properties/dmp/properties/project',
                        type: 'array',
                        title: 'The DMP Project Schema',
                        description: 'Project related to a DMP',
                        items: {
                          '$id': '#/properties/dmp/properties/project/items',
                          type: 'object',
                          title: 'The DMP Project Items Schema',
                          properties: {
                            funding: {
                              '$id': '#/properties/dmp/properties/project/items/properties/funding',
                              type: 'array',
                              title: 'The DMP Project Funding Schema',
                              description: 'Funding related with a project',
                              items: {
                                '$id': '#/properties/dmp/properties/project/items/properties/funding/items',
                                type: 'object',
                                title: 'The DMP Project Funding Items Schema',
                                properties: {
                                  dmproadmap_funded_affiliations: {
                                    '$id': '#/properties/dmp/properties/project/items/properties/funding//items/properties/dmproadmap_funded_affiliations',
                                    type: 'array',
                                    title: 'Institutions named on the grant',
                                    description: 'The institutions who received the funding',
                                    items: {
                                      '$id': '#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items',
                                      type: 'object',
                                      title: 'An institution that received funding',
                                      properties: {
                                        affiliation_id: {
                                          '$id': '#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items/properties/affiliation_id',
                                          type: 'object',
                                          title: "The funded affiliation's ID",
                                          description: 'Affiliation ID of the associated project',
                                          properties: {
                                            identifier: {
                                              '$id': '#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items/properties/affiliation_id/properties/identifier',
                                              type: 'string',
                                              title: 'The affiliation ID',
                                              description: 'ROR ID or URL. Recommended to use Research Organization Registry (ROR). See: https://ror.org',
                                              examples: ['https://ror.org/00pjdza24', 'https://cdlib.org']
                                            },
                                            type: {
                                              '$id': '#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items/properties/affiliation_id/properties/type',
                                              type: 'string',
                                              enum: %w[
                                                doi
                                                ror
                                                url
                                              ],
                                              title: 'The affiliation ID Type Schema',
                                              description: 'Identifier type. Allowed values: doi, ror, url',
                                              examples: ['ror']
                                            }
                                          },
                                          required: %w[
                                            identifier
                                            type
                                          ]
                                        },
                                        name: {
                                          '$id': '#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items/properties/name',
                                          type: 'string',
                                          title: 'The name of the instituion / organization',
                                          description: 'Project title',
                                          examples: ['Our New Project']
                                        }
                                      }
                                    }
                                  },
                                  dmproadmap_opportunity_number: {
                                    '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/dmproadmap_opportunity_number',
                                    type: 'string',
                                    title: "The funder's opportunity / award number",
                                    description: "The funder's number used to identify the award or call for submissions",
                                    examples: ['Award-123']
                                  },
                                  dmproadmap_project_number: {
                                    '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/dmproadmap_project_number',
                                    type: 'string',
                                    title: "The funder's identifier for the research project",
                                    description: "The funder's identifier used to identify the research project",
                                    examples: ['prj-XYZ987-UCB']
                                  },
                                  funder_id: {
                                    '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/funder_id',
                                    type: 'object',
                                    title: 'The Funder ID Schema',
                                    description: 'Funder ID of the associated project',
                                    properties: {
                                      identifier: {
                                        '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/funder_id/properties/identifier',
                                        type: 'string',
                                        title: 'The Funder ID Value Schema',
                                        description: 'Funder ID, recommended to use CrossRef Funder Registry. See: https://www.crossref.org/services/funder-registry/',
                                        examples: ['501100002428']
                                      },
                                      type: {
                                        '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/funder_id/properties/type',
                                        type: 'string',
                                        enum: %w[
                                          fundref
                                          ror
                                          url
                                          other
                                        ],
                                        title: 'The Funder ID Type Schema',
                                        description: 'Identifier type. Allowed values: fundref, url, other',
                                        examples: ['fundref']
                                      }
                                    },
                                    required: %w[
                                      identifier
                                      type
                                    ]
                                  },
                                  funding_status: {
                                    '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/funding_status',
                                    type: 'string',
                                    enum: %w[
                                      planned
                                      applied
                                      granted
                                      rejected
                                    ],
                                    title: 'The Funding Status Schema',
                                    description: 'To express different phases of project lifecycle. Allowed values: planned, applied, granted, rejected',
                                    examples: ['granted']
                                  },
                                  grant_id: {
                                    '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/grant_id',
                                    type: 'object',
                                    title: 'The Funding Grant ID Schema',
                                    description: 'Grant ID of the associated project',
                                    properties: {
                                      identifier: {
                                        '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/grant_id/properties/identifier',
                                        type: 'string',
                                        title: 'The Funding Grant ID Value Schema',
                                        description: 'Grant ID',
                                        examples: ['776242']
                                      },
                                      type: {
                                        '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/grant_id/properties/type',
                                        type: 'string',
                                        title: 'The Funding Grant ID Type Schema',
                                        enum: %w[
                                          doi
                                          url
                                          other
                                        ],
                                        description: 'Identifier type. Allowed values: url, other',
                                        examples: ['other']
                                      }
                                    },
                                    required: %w[
                                      identifier
                                      type
                                    ]
                                  },
                                  name: {
                                    '$id': '#/properties/dmp/properties/project/items/properties/funding/properties/name',
                                    type: 'string',
                                    title: 'The name of the funding instituion / organization',
                                    description: 'Name',
                                    examples: ['National Science Foundation']
                                  }
                                },
                                required: %w[
                                  funding_status
                                  name
                                ]
                              }
                            }
                          }
                        }
                      }
                    }
                  ]
                },
                required: %w[
                  dmp_id
                  modified
                  title
                ]
              }
            },
            additionalProperties: false,
            required: ['dmp']
          }.to_json)
        end
      end
    end
    # rubocop:enable Layout/LineLength, Metrics/MethodLength, Metrics/ClassLength
  end
end
