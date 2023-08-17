# frozen_string_literal: true

module Uc3DmpId
  module Schemas
    # The JSON schema for creating a new DMP ID
    class Author
      class << self
        def load
          JSON.parse({
            "$id": "https://github.com/CDLUC3/dmp-hub-sam/layer/ruby/config/schemas/author.json",
            "title": "Data Management Plan (DMP)",
            "description": "JSON Schema for a Data Management Plan (DMP)",
            "type": "object",
            "properties": {
              "dmp": {
                "$id": "#/properties/dmp",
                "type": "object",
                "title": "The DMP Schema",
                "properties": {
                  "contact": {
                    "$id": "#/properties/dmp/properties/contact",
                    "type": "object",
                    "title": "The DMP Contact Schema",
                    "properties": {
                      "contact_id": {
                        "$id": "#/properties/dmp/properties/contact/properties/contact_id",
                        "type": "object",
                        "title": "The Contact ID Schema",
                        "properties": {
                          "identifier": {
                            "$id": "#/properties/dmp/properties/contact/properties/contact_id/properties/identifier",
                            "type": "string",
                            "title": "The DMP Contact Identifier Schema",
                            "examples": ["https://orcid.org/0000-0000-0000-0000"]
                          },
                          "type": {
                            "$id": "#/properties/dmp/properties/contact/properties/contact_id/properties/type",
                            "type": "string",
                            "enum": [
                              "orcid",
                              "isni",
                              "openid",
                              "other"
                            ],
                            "title": "The DMP Contact Identifier Type Schema",
                            "description": "Identifier type. Allowed values: orcid, isni, openid, other",
                            "examples": ["orcid"]
                          }
                        },
                        "required": [
                          "identifier",
                          "type"
                        ]
                      },
                      "dmproadmap_affiliation": {
                        "$id": "#/properties/dmp/properties/contact/properties/dmproadmap_affiliation",
                        "type": "object",
                        "title": "The contact's affiliation",
                        "properties": {
                          "affiliation_id": {
                            "$id": "#/properties/dmp/properties/contact/properties/dmproadmap_affiliation/properties/affiliation_id",
                            "type": "object",
                            "title": "The unique ID of the affiliation",
                            "description": "The affiliation's ROR, Crossref funder ID or URL",
                            "properties": {
                              "identifier": {
                                "$id": "#/properties/dmp/properties/contact/properties/dmproadmap_affiliation/properties/affiliation_id/properties/identifier",
                                "type": "string",
                                "title": "The affiliation ID",
                                "description": "ROR ID, Crossref funder ID or URL. Recommended to use Research Organization Registry (ROR). See: https://ror.org",
                                "examples": ["https://ror.org/03yrm5c26", "http://dx.doi.org/10.13039/100005595", "http://www.cdlib.org/"]
                              },
                              "type": {
                                "$id": "#/properties/dmp/properties/contact/properties/dmproadmap_affiliation/properties/affiliation_id/properties/type",
                                "type": "string",
                                "enum": [
                                  "doi",
                                  "ror",
                                  "url"
                                ],
                                "title": "The affiliation ID type schema",
                                "description": "Identifier type. Allowed values: doi, ror, url",
                                "examples": ["ror"]
                              }
                            },
                            "required": [
                              "identifier",
                              "type"
                            ]
                          },
                          "name": {
                            "$id": "#/properties/dmp/properties/contact/properties/dmproadmap_affiliation/properties/name",
                            "type": "string",
                            "title": "Name of the instituion/organization",
                            "description": "Official institution/organization name",
                            "examples": ["Example University"]
                          }
                        }
                      },
                      "mbox": {
                        "$id": "#/properties/dmp/properties/contact/properties/mbox",
                        "type": "string",
                        "format": "email",
                        "title": "The Mailbox Schema",
                        "description": "Contact Person's E-mail address",
                        "examples": ["cc@example.com"]
                      },
                      "name": {
                        "$id": "#/properties/dmp/properties/contact/properties/name",
                        "type": "string",
                        "title": "The Name Schema",
                        "description": "Name of the contact person as Last, First (e.g. 'Doe PhD., Jane A.' or 'Doe, Jane')",
                        "examples": ["Doe, Jane"]
                      }
                    },
                    "required": [
                      "contact_id",
                      "mbox",
                      "name"
                    ]
                  },
                  "contributor": {
                    "$id": "#/properties/dmp/properties/contributor",
                    "type": "array",
                    "title": "The Contributor Schema",
                    "items": {
                      "$id": "#/properties/dmp/properties/contributor/items",
                      "type": "object",
                      "title": "The Contributor Items Schema",
                      "properties": {
                        "contributor_id": {
                          "$id": "#/properties/dmp/properties/contributor/items/properties/contributor_id",
                          "type": "object",
                          "title": "The Contributor_id Schema",
                          "properties": {
                            "identifier": {
                              "$id": "#/properties/dmp/properties/contributor/items/properties/contributor_id/properties/identifier",
                              "type": "string",
                              "title": "The Contributor Identifier Schema",
                              "description": "Identifier for a contact person",
                              "examples": ["http://orcid.org/0000-0000-0000-0000"]
                            },
                            "type": {
                              "$id": "#/properties/dmp/properties/contributor/items/properties/contributor_id/properties/type",
                              "type": "string",
                              "enum": [
                                "orcid",
                                "isni",
                                "openid",
                                "other"
                              ],
                              "title": "The Contributor Identifier Type Schema",
                              "description": "Identifier type. Allowed values: orcid, isni, openid, other",
                              "examples": ["orcid"]
                            }
                          },
                          "required": [
                            "identifier",
                            "type"
                          ]
                        },
                        "dmproadmap_affiliation": {
                          "$id": "#/properties/dmp/properties/contributor/items/properties/dmproadmap_affiliation",
                          "type": "object",
                          "title": "The contributor's affiliation",
                          "properties": {
                            "affiliation_id": {
                              "$id": "#/properties/dmp/properties/contributor/items/properties/dmproadmap_affiliation/properties/affiliation_id",
                              "type": "object",
                              "title": "The unique ID of the affiliation",
                              "description": "The affiliation's ROR, Crossref funder ID or URL",
                              "properties": {
                                "identifier": {
                                  "$id": "#/properties/dmp/properties/contributor/items/properties/dmproadmap_affiliation/properties/affiliation_id/properties/identifier",
                                  "type": "string",
                                  "title": "The affiliation ID",
                                  "description": "ROR ID, Crossref funder ID or URL. Recommended to use Research Organization Registry (ROR). See: https://ror.org",
                                  "examples": ["https://ror.org/03yrm5c26", "http://dx.doi.org/10.13039/100005595", "http://www.cdlib.org/"]
                                },
                                "type": {
                                  "$id": "#/properties/dmp/properties/contributor/items/properties/dmproadmap_affiliation/properties/affiliation_id/properties/type",
                                  "type": "string",
                                  "enum": [
                                    "doi",
                                    "ror",
                                    "url"
                                  ],
                                  "title": "The affiliation ID type schema",
                                  "description": "Identifier type. Allowed values: doi, ror, url",
                                  "examples": ["ror"]
                                }
                              },
                              "required": [
                                "identifier",
                                "type"
                              ]
                            },
                            "name": {
                              "$id": "#/properties/dmp/properties/contributor/items/properties/dmproadmap_affiliation/properties/name",
                              "type": "string",
                              "title": "Name of the instituion/organization",
                              "description": "Official institution/organization name",
                              "examples": ["Example University"]
                            }
                          }
                        },
                        "mbox": {
                          "$id": "#/properties/dmp/properties/contributor/items/properties/mbox",
                          "type": "string",
                          "title": "The Contributor Mailbox Schema",
                          "description": "Contributor Mail address",
                          "examples": ["john@smith.com"],
                          "format": "email"
                        },
                        "name": {
                          "$id": "#/properties/dmp/properties/contributor/items/properties/name",
                          "type": "string",
                          "title": "The Name Schema",
                          "description": "Name of the contributor as Last, First (e.g. 'Doe PhD., Jane A.' or 'Doe, Jane')",
                          "examples": ["Smith, John"]
                        },
                        "role": {
                          "$id": "#/properties/dmp/properties/contributor/items/properties/role",
                          "type": "array",
                          "title": "The Role Schema",
                          "description": "Type of contributor",
                          "items": {
                            "$id": "#/properties/dmp/properties/contributor/items/properties/role/items",
                            "type": "string",
                            "title": "The Contributor Role(s) Items Schema",
                            "examples": ["Data Steward"]
                          },
                          "uniqueItems": true
                        }
                      },
                      "required": [
                        "name",
                        "role"
                      ]
                    }
                  },
                  "cost": {
                    "$id": "#/properties/dmp/properties/cost",
                    "type": "array",
                    "title": "The Cost Schema",
                    "items": {
                      "$id": "#/properties/dmp/properties/cost/items",
                      "type": "object",
                      "title": "The Cost Items Schema",
                      "properties": {
                        "currency_code": {
                          "$id": "#/properties/dmp/properties/cost/items/properties/currency_code",
                          "type": "string",
                          "enum": [
                            "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN",
                            "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BRL",
                            "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHF", "CLP", "CNY",
                            "COP", "CRC", "CUC", "CUP", "CVE", "CZK", "DJF", "DKK", "DOP", "DZD",
                            "EGP", "ERN", "ETB", "EUR", "FJD", "FKP", "GBP", "GEL", "GGP", "GHS",
                            "GIP", "GMD", "GNF", "GTQ", "GYD", "HKD", "HNL", "HRK", "HTG", "HUF",
                            "IDR", "ILS", "IMP", "INR", "IQD", "IRR", "ISK", "JEP", "JMD", "JOD",
                            "JPY", "KES", "KGS", "KHR", "KMF", "KPW", "KRW", "KWD", "KYD", "KZT",
                            "LAK", "LBP", "LKR", "LRD", "LSL", "LYD", "MAD", "MDL", "MGA", "MKD",
                            "MMK", "MNT", "MOP", "MRU", "MUR", "MVR", "MWK", "MXN", "MYR", "MZN",
                            "NAD", "NGN", "NIO", "NOK", "NPR", "NZD", "OMR", "PAB", "PEN", "PGK",
                            "PHP", "PKR", "PLN", "PYG", "QAR", "RON", "RSD", "RUB", "RWF", "SAR",
                            "SBD", "SCR", "SDG", "SEK", "SGD", "SHP", "SLL", "SOS", "SPL*","SRD",
                            "STN", "SVC", "SYP", "SZL", "THB", "TJS", "TMT", "TND",	"TOP", "TRY",
                            "TTD", "TVD", "TWD", "TZS", "UAH", "UGX", "USD", "UYU", "UZS", "VEF",
                            "VND", "VUV", "WST", "XAF", "XCD", "XDR", "XOF", "XPF", "YER", "ZAR",
                            "ZMW", "ZWD"
                          ],
                          "title": "The Cost Currency Code Schema",
                          "description": "Allowed values defined by ISO 4217",
                          "examples": ["EUR"]
                        },
                        "description": {
                          "$id": "#/properties/dmp/properties/cost/items/properties/description",
                          "type": "string",
                          "title": "The Cost Description Schema",
                          "description": "Cost(s) Description",
                          "examples": ["Costs for maintaining..."]
                        },
                        "title": {
                          "$id": "#/properties/dmp/properties/cost/items/properties/title",
                          "type": "string",
                          "title": "The Cost Title Schema",
                          "description": "Title",
                          "examples": ["Storage and Backup"]
                        },
                        "value": {
                          "$id": "#/properties/dmp/properties/cost/items/properties/value",
                          "type": "number",
                          "title": "The Cost Value Schema",
                          "description": "Value",
                          "examples": [1000]
                        }
                      },
                      "required": ["title"]
                    }
                  },
                  "created": {
                    "$id": "#/properties/dmp/properties/created",
                    "type": "string",
                    "format": "date-time",
                    "title": "The DMP Creation Schema",
                    "description": "Date and time of the first version of a DMP. Must not be changed in subsequent DMPs. Encoded using the relevant ISO 8601 Date and Time compliant string",
                    "examples": ["2019-03-13T13:13:00+00:00"]
                  },
                  "dataset": {
                    "$id": "#/properties/dmp/properties/dataset",
                    "type": "array",
                    "title": "The Dataset Schema",
                    "items": {
                      "$id": "#/properties/dmp/properties/dataset/items",
                      "type": "object",
                      "title": "The Dataset Items Schema",
                      "properties": {
                        "data_quality_assurance": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/data_quality_assurance",
                          "type": "array",
                          "title": "The Data Quality Assurance Schema",
                          "description": "Data Quality Assurance",
                          "items": {
                            "$id": "#/properties/dmp/properties/dataset/items/properties/data_quality_assurance/items",
                            "type": "string",
                            "title": "The Data Quality Assurance Schema",
                            "examples": ["We use file naming convention..."]
                          }
                        },
                        "dataset_id": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/dataset_id",
                          "type": "object",
                          "title": "The Dataset ID Schema",
                          "description": "Dataset ID",
                          "properties": {
                            "identifier": {
                              "$id": "#/properties/dmp/properties/dataset/items/properties/dataset_id/properties/identifier",
                              "type": "string",
                              "title": "The Dataset Identifier Schema",
                              "description": "Identifier for a dataset",
                              "examples": ["https://hdl.handle.net/11353/10.923628"]
                            },
                            "type": {
                              "$id": "#/properties/dmp/properties/dataset/items/properties/dataset_id/properties/type",
                              "type": "string",
                              "enum": [
                                "handle",
                                "doi",
                                "ark",
                                "url",
                                "other"
                              ],
                              "title": "The Dataset Identifier Type Schema",
                              "description": "Dataset identifier type. Allowed values: handle, doi, ark, url, other",
                              "examples": ["handle"]
                            }
                          },
                          "required": [
                            "identifier",
                            "type"
                          ]
                        },
                        "description": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/description",
                          "type": "string",
                          "title": "The Dataset Description Schema",
                          "description": "Description is a property in both Dataset and Distribution, in compliance with W3C DCAT. In some cases these might be identical, but in most cases the Dataset represents a more abstract concept, while the distribution can point to a specific file.",
                          "examples": ["Field observation"]
                        },
                        "distribution": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/distribution",
                          "type": "array",
                          "title": "The Dataset Distribution Schema",
                          "description": "To provide technical information on a specific instance of data.",
                          "items": {
                            "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items",
                            "type": "object",
                            "title": "The Dataset Distribution Items Schema",
                            "properties": {
                              "access_url": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/access_url",
                                "type": "string",
                                "title": "The Dataset Distribution Access URL Schema",
                                "description": "A URL of the resource that gives access to a distribution of the dataset. e.g. landing page.",
                                "examples": ["http://some.repo"]
                              },
                              "available_until": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/available_until",
                                "type": "string",
                                "format": "date",
                                "title": "The Dataset Distribution Available Until Schema",
                                "description": "Indicates how long this distribution will be/ should be available. Encoded using the relevant ISO 8601 Date and Time compliant string.",
                                "examples": ["2030-06-30"]
                              },
                              "byte_size": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/byte_size",
                                "type": "integer",
                                "title": "The Dataset Distribution Byte Size Schema",
                                "description": "Size in bytes.",
                                "examples": [690000]
                              },
                              "data_access": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/data_access",
                                "type": "string",
                                "enum": [
                                  "open",
                                  "shared",
                                  "closed"
                                ],
                                "title": "The Dataset Distribution Data Access Schema",
                                "description": "Indicates access mode for data. Allowed values: open, shared, closed",
                                "examples": ["open"]
                              },
                              "description": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/description",
                                "type": "string",
                                "title": "The Dataset Distribution Description Schema",
                                "description": "Description is a property in both Dataset and Distribution, in compliance with W3C DCAT. In some cases these might be identical, but in most cases the Dataset represents a more abstract concept, while the distribution can point to a specific file.",
                                "examples": ["Best quality data before resizing"]
                              },
                              "download_url": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/download_url",
                                "type": "string",
                                "format": "uri",
                                "title": "The Dataset Distribution Download URL Schema",
                                "description": "The URL of the downloadable file in a given format. E.g. CSV file or RDF file.",
                                "examples": ["http://example.com/download/abc123/download"]
                              },
                              "format": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/format",
                                "type": "array",
                                "title": "The Dataset Distribution Format Schema",
                                "description": "Format according to: https://www.iana.org/assignments/media-types/media-types.xhtml if appropriate, otherwise use the common name for this format.",
                                "items": {
                                  "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/format/items",
                                  "type": "string",
                                  "title": "The Dataset Distribution Format Items Schema",
                                  "examples": ["image/tiff"]
                                }
                              },
                              "host": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host",
                                "type": "object",
                                "title": "The Dataset Distribution Host Schema",
                                "description": "To provide information on quality of service provided by infrastructure (e.g. repository) where data is stored.",
                                "properties": {
                                  "availability": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/availability",
                                    "type": "string",
                                    "title": "The Dataset Distribution Host Availability Schema",
                                    "description": "Availability",
                                    "examples": ["99,5"]
                                  },
                                  "backup_frequency": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/backup_frequency",
                                    "type": "string",
                                    "title": "The Dataset Distribution Host Backup Frequency Schema",
                                    "description": "Backup Frequency",
                                    "examples": ["weekly"]
                                  },
                                  "backup_type": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/backup_type",
                                    "type": "string",
                                    "title": "The Dataset Distribution Host Backup Type Schema",
                                    "description": "Backup Type",
                                    "examples": ["tapes"]
                                  },
                                  "certified_with": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/certified_with",
                                    "type": "string",
                                    "enum": [
                                      "din31644",
                                      "dini-zertifikat",
                                      "dsa",
                                      "iso16363",
                                      "iso16919",
                                      "trac",
                                      "wds",
                                      "coretrustseal"
                                    ],
                                    "title": "The Dataset Distribution Host Certification Type Schema",
                                    "description": "Repository certified to a recognised standard. Allowed values: din31644, dini-zertifikat, dsa, iso16363, iso16919, trac, wds, coretrustseal",
                                    "examples": ["coretrustseal"]
                                  },
                                  "description": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/description",
                                    "type": "string",
                                    "title": "The Dataset Distribution Host Description Schema",
                                    "description": "Description",
                                    "examples": ["Repository hosted by..."]
                                  },
                                  "dmproadmap_host_id": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/host_id",
                                    "type": "object",
                                    "title": "The Host ID",
                                    "description": "The unique identifier or URL for the host",
                                    "properties": {
                                      "identifier": {
                                        "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/host_id/properties/identifier",
                                        "type": "string",
                                        "title": "The Host Identifier",
                                        "description": "The Host URL or identifier",
                                        "examples": ["https://www.re3data.org/repository/r3d100000044", "https://example.host.org"]
                                      },
                                      "type": {
                                        "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/host_id/properties/type",
                                        "type": "string",
                                        "enum": [
                                          "handle",
                                          "doi",
                                          "ark",
                                          "url"
                                        ],
                                        "title": "The Host Identifier Type Schema",
                                        "description": "Host identifier type. Allowed values: handle, doi, ark, url",
                                        "examples": ["url"]
                                      }
                                    },
                                    "required": [
                                      "identifier",
                                      "type"
                                    ]
                                  },
                                  "geo_location": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/geo_location",
                                    "type": "string",
                                    "enum": [
                                      "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AS", "AT", "AU", "AW", "AX", "AZ", "BA",
                                      "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS", "BT", "BV",
                                      "BW", "BY", "BZ", "CA", "CC", "CD", "CF", "CG", "CH", "CI", "CK", "CL", "CM", "CN", "CO", "CR", "CU",
                                      "CV", "CW", "CX", "CY", "CZ", "DE", "DJ", "DK", "DM", "DO", "DZ", "EC", "EE", "EG", "EH", "ER", "ES",
                                      "ET", "FI", "FJ", "FK", "FM", "FO", "FR", "GA", "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL", "GM",
                                      "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY", "HK", "HM", "HN", "HR", "HT", "HU", "ID", "IE",
                                      "IL", "IM", "IN", "IO", "IQ", "IR", "IS", "IT", "JE", "JM", "JO", "JP", "KE", "KG", "KH", "KI", "KM",
                                      "KN", "KP", "KR", "KW", "KY", "KZ", "LA", "LB", "LC", "LI", "LK", "LR", "LS", "LT", "LU", "LV", "LY",
                                      "MA", "MC", "MD", "ME", "MF", "MG", "MH", "MK", "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT",
                                      "MU", "MV", "MW", "MX", "MY", "MZ", "NA", "NC", "NE", "NF", "NG", "NI", "NL", "NO", "NP", "NR", "NU",
                                      "NZ", "OM", "PA", "PE", "PF", "PG", "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY", "QA",
                                      "RE", "RO", "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SI", "SJ", "SK", "SL", "SM",
                                      "SN", "SO", "SR", "SS", "ST", "SV", "SX", "SY", "SZ", "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL",
                                      "TM", "TN", "TO", "TR", "TT", "TV", "TW", "TZ", "UA", "UG", "UM", "US", "UY", "UZ", "VA", "VC", "VE",
                                      "VG", "VI", "VN", "VU", "WF", "WS", "YE", "YT", "ZA", "ZM", "ZW"
                                    ],
                                    "title": "The Dataset Distribution Host Geographical Location Schema",
                                    "description": "Physical location of the data expressed using ISO 3166-1 country code.",
                                    "examples": ["AT"]
                                  },
                                  "pid_system": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/pid_system",
                                    "type": "array",
                                    "title": "The Dataset Distribution Host PID System Schema",
                                    "description": "PID system(s). Allowed values: ark, arxiv, bibcode, doi, ean13, eissn, handle, igsn, isbn, issn, istc, lissn, lsid, pmid, purl, upc, url, urn, other",
                                    "items": {
                                      "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/pid_system/items",
                                      "type": "string",
                                      "title": "The Dataset Distribution Host PID System Items Schema",
                                      "enum": [
                                        "ark",
                                        "arxiv",
                                        "bibcode",
                                        "doi",
                                        "ean13",
                                        "eissn",
                                        "handle",
                                        "igsn",
                                        "isbn",
                                        "issn",
                                        "istc",
                                        "lissn",
                                        "lsid",
                                        "pmid",
                                        "purl",
                                        "upc",
                                        "url",
                                        "urn",
                                        "other"
                                      ],
                                      "examples": ["doi"]
                                    }
                                  },
                                  "storage_type": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/storage_type",
                                    "type": "string",
                                    "title": "The Dataset Distribution Host Storage Type Schema",
                                    "description": "The type of storage required",
                                    "examples": ["External Hard Drive"]
                                  },
                                  "support_versioning": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/support_versioning",
                                    "type": "string",
                                    "enum": [
                                      "yes",
                                      "no",
                                      "unknown"
                                    ],
                                    "title": "The Dataset Distribution Host Support Versioning Schema",
                                    "description": "If host supports versioning. Allowed values: yes, no, unknown",
                                    "examples": ["yes"]
                                  },
                                  "title": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/title",
                                    "type": "string",
                                    "title": "The Dataset Distribution Host Title Schema",
                                    "description": "Title",
                                    "examples": ["Super Repository"]
                                  },
                                  "url": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/host/properties/url",
                                    "type": "string",
                                    "format": "uri",
                                    "title": "The Dataset Distribution Host Title Schema",
                                    "description": "The URL of the system hosting a distribution of a dataset",
                                    "examples": ["https://zenodo.org"]
                                  }
                                },
                                "required": [
                                  "title",
                                  "url"
                                ]
                              },
                              "license": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/license",
                                "type": "array",
                                "title": "The Dataset Distribution License(s) Schema",
                                "description": "To list all licenses applied to a specific distribution of data.",
                                "items": {
                                  "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/license/items",
                                  "type": "object",
                                  "title": "The Dataset Distribution License Items",
                                  "properties": {
                                    "license_ref": {
                                      "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/license/items/properties/license_ref",
                                      "type": "string",
                                      "format": "uri",
                                      "title": "The Dataset Distribution License Reference Schema",
                                      "description": "Link to license document.",
                                      "examples": ["https://creativecommons.org/licenses/by/4.0/"]
                                    },
                                    "start_date": {
                                      "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/license/items/properties/start_date",
                                      "type": "string",
                                      "format": "date-time",
                                      "title": "The Dataset Distribution License Start Date Schema",
                                      "description": "If date is set in the future, it indicates embargo period. Encoded using the relevant ISO 8601 Date and Time compliant string.",
                                      "examples": ["2019-06-30"]
                                    }
                                  },
                                  "required": [
                                    "license_ref",
                                    "start_date"
                                  ]
                                }
                              },
                              "title": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/distribution/items/properties/title",
                                "type": "string",
                                "title": "The Dataset Distribution Title Schema",
                                "description": "Title is a property in both Dataset and Distribution, in compliance with W3C DCAT. In some cases these might be identical, but in most cases the Dataset represents a more abstract concept, while the distribution can point to a specific file.",
                                "examples": ["Full resolution images"]
                              }
                            },
                            "required": [
                              "data_access",
                              "title"
                            ]
                          }
                        },
                        "issued": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/issued",
                          "type": "string",
                          "format": "date-time",
                          "title": "The Dataset Date of Issue Schema",
                          "description": "Issued. Encoded using the relevant ISO 8601 Date and Time compliant string.",
                          "examples": ["2019-06-30"]
                        },
                        "keyword": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/keyword",
                          "type": "array",
                          "title": "The Dataset Keyword(s) Schema",
                          "description": "Keywords",
                          "items": {
                            "$id": "#/properties/dmp/properties/dataset/items/properties/keyword/items",
                            "type": "string",
                            "title": "The Dataset Keyword Items Schema",
                            "examples": ["keyword 1, keyword 2"]
                          }
                        },
                        "language": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/language",
                          "type": "string",
                          "enum": [
                            "aar", "abk", "afr", "aka", "amh", "ara", "arg", "asm", "ava", "ave", "aym", "aze", "bak", "bam", "bel", "ben", "bih", "bis", "bod", "bos",
                            "bre", "bul", "cat", "ces", "cha", "che", "chu", "chv", "cor", "cos", "cre", "cym", "dan", "deu", "div", "dzo", "ell", "eng", "epo", "est",
                            "eus", "ewe", "fao", "fas", "fij", "fin", "fra", "fry", "ful", "gla", "gle", "glg", "glv", "grn", "guj", "hat", "hau", "hbs", "heb", "her",
                            "hin", "hmo", "hrv", "hun", "hye", "ibo", "ido", "iii", "iku", "ile", "ina", "ind", "ipk", "isl", "ita", "jav", "jpn", "kal", "kan", "kas",
                            "kat", "kau", "kaz", "khm", "kik", "kin", "kir", "kom", "kon", "kor", "kua", "kur", "lao", "lat", "lav", "lim", "lin", "lit", "ltz", "lub",
                            "lug", "mah", "mal", "mar", "mkd", "mlg", "mlt", "mon", "mri", "msa", "mya", "nau", "nav", "nbl", "nde", "ndo", "nep", "nld", "nno", "nob",
                            "nor", "nya", "oci", "oji", "ori", "orm", "oss", "pan", "pli", "pol", "por", "pus", "que", "roh", "ron", "run", "rus", "sag", "san", "sin",
                            "slk", "slv", "sme", "smo", "sna", "snd", "som", "sot", "spa", "sqi", "srd", "srp", "ssw", "sun", "swa", "swe", "tah", "tam", "tat", "tel",
                            "tgk", "tgl", "tha", "tir", "ton", "tsn", "tso", "tuk", "tur", "twi", "uig", "ukr", "urd", "uzb", "ven", "vie", "vol", "wln", "wol", "xho",
                            "yid", "yor", "zha", "zho", "zul"
                          ],
                          "title": "The Dataset Language Schema",
                          "description": "Language of the dataset expressed using ISO 639-3.",
                          "examples": ["eng"]
                        },
                        "metadata": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/metadata",
                          "type": "array",
                          "title": "The Dataset Metadata Schema",
                          "description": "To describe metadata standards used.",
                          "items": {
                            "$id": "#/properties/dmp/properties/dataset/items/properties/metadata/items",
                            "type": "object",
                            "title": "The Dataset Metadata Items Schema",
                            "properties": {
                              "description": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/metadata/items/properties/description",
                                "type": "string",
                                "title": "The Dataset Metadata Description Schema",
                                "description": "Description",
                                "examples": ["Provides taxonomy for..."]
                              },
                              "language": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/metadata/items/properties/language",
                                "type": "string",
                                "enum": [
                                  "aar", "abk", "afr", "aka", "amh", "ara", "arg", "asm", "ava", "ave", "aym", "aze", "bak", "bam", "bel", "ben", "bih", "bis", "bod", "bos",
                                  "bre", "bul", "cat", "ces", "cha", "che", "chu", "chv", "cor", "cos", "cre", "cym", "dan", "deu", "div", "dzo", "ell", "eng", "epo", "est",
                                  "eus", "ewe", "fao", "fas", "fij", "fin", "fra", "fry", "ful", "gla", "gle", "glg", "glv", "grn", "guj", "hat", "hau", "hbs", "heb", "her",
                                  "hin", "hmo", "hrv", "hun", "hye", "ibo", "ido", "iii", "iku", "ile", "ina", "ind", "ipk", "isl", "ita", "jav", "jpn", "kal", "kan", "kas",
                                  "kat", "kau", "kaz", "khm", "kik", "kin", "kir", "kom", "kon", "kor", "kua", "kur", "lao", "lat", "lav", "lim", "lin", "lit", "ltz", "lub",
                                  "lug", "mah", "mal", "mar", "mkd", "mlg", "mlt", "mon", "mri", "msa", "mya", "nau", "nav", "nbl", "nde", "ndo", "nep", "nld", "nno", "nob",
                                  "nor", "nya", "oci", "oji", "ori", "orm", "oss", "pan", "pli", "pol", "por", "pus", "que", "roh", "ron", "run", "rus", "sag", "san", "sin",
                                  "slk", "slv", "sme", "smo", "sna", "snd", "som", "sot", "spa", "sqi", "srd", "srp", "ssw", "sun", "swa", "swe", "tah", "tam", "tat", "tel",
                                  "tgk", "tgl", "tha", "tir", "ton", "tsn", "tso", "tuk", "tur", "twi", "uig", "ukr", "urd", "uzb", "ven", "vie", "vol", "wln", "wol", "xho",
                                  "yid", "yor", "zha", "zho", "zul"
                                ],
                                "title": "The Dataset Metadata Language Schema",
                                "description": "Language of the metadata expressed using ISO 639-3.",
                                "examples": ["eng"]
                              },
                              "metadata_standard_id": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/metadata/items/properties/metadata_standard_id",
                                "type": "object",
                                "title": "The Dataset Metadata Standard ID Schema",
                                "properties": {
                                  "identifier": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/metadata/items/properties/metadata_standard_id/identifier",
                                    "type": "string",
                                    "title": "The Dataset Metadata Standard Identifier Value Schema",
                                    "description": "Identifier for the metadata standard used.",
                                    "examples": ["http://www.dublincore.org/specifications/dublin-core/dcmi-terms/"]
                                  },
                                  "type": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/metadata/items/properties/metadata_standard_id/type",
                                    "type": "string",
                                    "enum": [
                                      "url",
                                      "other"
                                    ],
                                    "title": "The Dataset Metadata Standard Identifier Type Schema",
                                    "description": "Identifier type. Allowed values: url, other",
                                    "examples": ["url"]
                                  }
                                },
                                "required": [
                                  "identifier",
                                  "type"
                                ]
                              }
                            },
                            "required": [
                              "metadata_standard_id"
                            ]
                          }
                        },
                        "personal_data": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/personal_data",
                          "type": "string",
                          "enum": [
                            "yes",
                            "no",
                            "unknown"
                          ],
                          "title": "The Dataset Personal Data Schema",
                          "description": "If any personal data is contained. Allowed values: yes, no, unknown",
                          "examples": ["unknown"]
                        },
                        "preservation_statement": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/preservation_statement",
                          "type": "string",
                          "title": "The Dataset Preservation Statement Schema",
                          "description": "Preservation Statement",
                          "examples": ["Must be preserved to enable..."]
                        },
                        "security_and_privacy": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/security_and_privacy",
                          "type": "array",
                          "title": "The Dataset Security and Policy Schema",
                          "description": "To list all issues and requirements related to security and privacy",
                          "items": {
                            "$id": "#/properties/dmp/properties/dataset/items/properties/security_and_privacy/items",
                            "type": "object",
                            "title": "The Dataset Security & Policy Items Schema",
                            "properties": {
                              "description": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/security_and_privacy/items/properties/description",
                                "type": "string",
                                "title": "The Dataset Security & Policy Description Schema",
                                "description": "Description",
                                "examples": ["Server with data must be kept in a locked room"]
                              },
                              "title": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/security_and_privacy/items/properties/title",
                                "type": "string",
                                "title": "The Dataset Security & Policy Title Schema",
                                "description": "Title",
                                "examples": ["Physical access control"]
                              }
                            },
                            "required": ["title"]
                          }
                        },
                        "sensitive_data": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/sensitive_data",
                          "type": "string",
                          "enum": [
                            "yes",
                            "no",
                            "unknown"
                          ],
                          "title": "The Dataset Sensitive Data Schema",
                          "description": "If any sensitive data is contained. Allowed values: yes, no, unknown",
                          "examples": ["unknown"]
                        },
                        "technical_resource": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/technical_resource",
                          "type": "array",
                          "title": "The Dataset Technical Resource Schema",
                          "description": "To list all technical resources needed to implement a DMP",
                          "items": {
                            "$id": "#/properties/dmp/properties/dataset/items/properties/technical_resource/items",
                            "type": "object",
                            "title": "The Dataset Technical Resource Items Schema",
                            "properties": {
                              "description": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/technical_resource/items/description",
                                "type": "string",
                                "title": "The Dataset Technical Resource Description Schema",
                                "description": "Description of the technical resource",
                                "examples": ["Device needed to collect field data..."]
                              },
                              "dmproadmap_technical_resource_id": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/technical_resource/items/dmproadmap_technical_resource_id",
                                "type": "object",
                                "title": "The Dataset Metadata Standard ID Schema",
                                "properties": {
                                  "identifier": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/technical_resource/items/dmproadmap_technical_resource_id/identifier",
                                    "type": "string",
                                    "title": "The Technical Resource Identifier Value Schema",
                                    "description": "Identifier for the metadata standard used.",
                                    "examples": ["http://www.dublincore.org/specifications/dublin-core/dcmi-terms/"]
                                  },
                                  "type": {
                                    "$id": "#/properties/dmp/properties/dataset/items/properties/technical_resource/items/dmproadmap_technical_resource_id/type",
                                    "type": "string",
                                    "enum": [
                                      "ark",
                                      "doi",
                                      "handle",
                                      "rrid",
                                      "url",
                                      "other"
                                    ],
                                    "title": "The Technical Resource Identifier Type Schema",
                                    "description": "Identifier type. Allowed values: url, other",
                                    "examples": ["url"]
                                  }
                                }
                              },
                              "name": {
                                "$id": "#/properties/dmp/properties/dataset/items/properties/technical_resource/items/name",
                                "type": "string",
                                "title": "The Dataset Technical Resource Name Schema",
                                "description": "Name of the technical resource",
                                "examples": ["123/45/43/AT"]
                              }
                            },
                            "required": ["name"]
                          }
                        },
                        "title": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/title",
                          "type": "string",
                          "title": "The Dataset Title Schema",
                          "description": "Title is a property in both Dataset and Distribution, in compliance with W3C DCAT. In some cases these might be identical, but in most cases the Dataset represents a more abstract concept, while the distribution can point to a specific file.",
                          "examples": ["Fast car images"]
                        },
                        "type": {
                          "$id": "#/properties/dmp/properties/dataset/items/properties/type",
                          "type": "string",
                          "title": "The Dataset Type Schema",
                          "description": "If appropriate, type according to: DataCite and/or COAR dictionary. Otherwise use the common name for the type, e.g. raw data, software, survey, etc. https://schema.datacite.org/meta/kernel-4.1/doc/DataCite-MetadataKernel_v4.1.pdf http://vocabularies.coar-repositories.org/pubby/resource_type.html",
                          "examples": ["image"]
                        }
                      },
                      "required": [
                        "title"
                      ]
                    }
                  },
                  "description": {
                    "$id": "#/properties/dmp/properties/description",
                    "type": "string",
                    "title": "The DMP Description Schema",
                    "description": "To provide any free-form text information on a DMP",
                    "examples": ["This DMP is for our new project"]
                  },
                  "dmp_id": {
                    "$id": "#/properties/dmp/properties/dmp_id",
                    "type": "object",
                    "title": "The DMP Identifier Schema",
                    "description": "Identifier for the DMP itself",
                    "properties": {
                      "identifier": {
                        "$id": "#/properties/dmp/properties/dmp_id/properties/identifier",
                        "type": "string",
                        "title": "The DMP Identifier Value Schema",
                        "description": "Identifier for a DMP",
                        "examples": ["https://doi.org/10.1371/journal.pcbi.1006750"]
                      },
                      "type": {
                        "$id": "#/properties/dmp/properties/dmp_id/properties/type",
                        "type": "string",
                        "enum": [
                          "handle",
                          "doi",
                          "ark",
                          "url",
                          "other",
                          "file"
                        ],
                        "title": "The DMP Identifier Type Schema",
                        "description": "The DMP Identifier Type. Allowed values: handle, doi, ark, url, other, file (note: file is used by DMPHub to handle new PDF uploads)",
                        "examples": ["doi"]
                      }
                    },
                    "required": [
                      "identifier",
                      "type"
                    ]
                  },
                  "dmphub_modifications": {
                    "$id": "#/properties/dmp/properties/dmphub_modifications",
                    "type": "array",
                    "title": "External modifications",
                    "description": "Modifications made by an external system that does not own the DMP ID",
                    "items": {
                      "$id": "#/properties/dmp/properties/dmphub_modifications/items",
                      "type": "object",
                      "title": "An external modification",
                      "properties": {
                        "id": {
                          "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/id",
                          "type": "string",
                          "title": "Modification identifier",
                          "examples": ["12345ABCD"]
                        },
                        "provenance": {
                          "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/provenance",
                          "type": "string",
                          "title": "Modifier",
                          "examples": ["datacite"]
                        },
                        "timestamp": {
                          "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/timestamp",
                          "type": "string",
                          "format": "date-time",
                          "title": "The modification date and time",
                          "examples": ["2023-07-27T15:08:32Z"]
                        },
                        "note": {
                          "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/note",
                          "type": "string",
                          "title": "Descriptive note",
                          "examples": ["data received from event data"]
                        },
                        "status": {
                          "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/status",
                          "type": "string",
                          "title": "Modification status",
                          "enum": [
                            "accepted",
                            "pending",
                            "rejected"
                          ]
                        },
                        "dmproadmap_related_identifier": {
                          "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/dmproadmap_related_identifier",
                          "type": "object",
                          "title": "A related identifier",
                          "properties": {
                            "descriptor": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/dmproadmap_related_identifier/properties/descriptor",
                              "type": "string",
                              "enum": [
                                "is_cited_by",
                                "cites",
                                "is_supplement_to",
                                "is_supplemented_by",
                                "is_described_by",
                                "describes",
                                "has_metadata",
                                "is_metadata_for",
                                "is_part_of",
                                "has_part",
                                "is_referenced_by",
                                "references",
                                "is_documented_by",
                                "documents",
                                "is_new_version_of",
                                "is_previous_version_of"
                              ]
                            },
                            "identifier": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/dmproadmap_related_identifier/properties/identifier",
                              "type": "string",
                              "title": "A unique identifier for the item",
                              "description": "Identifier for a DMP",
                              "examples": ["https://doi.org/10.1371/journal.pcbi.1006750"]
                            },
                            "type": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/dmproadmap_related_identifier/properties/type",
                              "type": "string",
                              "enum": [
                                "handle",
                                "doi",
                                "ark",
                                "url",
                                "other"
                              ]
                            },
                            "work_type": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/dmproadmap_related_identifier/properties/work_type",
                              "type": "string"
                            }
                          },
                          "required": [
                            "descriptor",
                            "identifier",
                            "type",
                            "work_type"
                          ]
                        },
                        "funding": {
                          "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/funding",
                          "type": "object",
                          "title": "A modification to Funding",
                          "properties": {
                            "dmproadmap_project_number": {
                              "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/dmproadmap_project_number",
                              "type": "string",
                              "title": "The funder's identifier for the research project",
                              "description": "The funder's identifier used to identify the research project",
                              "examples": ["prj-XYZ987-UCB"]
                            },
                            "funder_id": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/funding/properties/funder_id",
                              "type": "object",
                              "title": "The Funder ID Schema",
                              "description": "Funder ID of the associated project",
                              "properties": {
                                "identifier": {
                                  "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/funding/properties/funder_id/properties/identifier",
                                  "type": "string",
                                  "title": "The Funder ID Value Schema",
                                  "description": "Funder ID, recommended to use CrossRef Funder Registry. See: https://www.crossref.org/services/funder-registry/",
                                  "examples": ["501100002428"]
                                },
                                "type": {
                                  "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/funding/properties/funder_id/properties/type",
                                  "type": "string",
                                  "enum": [
                                    "fundref",
                                    "ror",
                                    "url",
                                    "other"
                                  ],
                                  "title": "The Funder ID Type Schema",
                                  "description": "Identifier type. Allowed values: fundref, url, other",
                                  "examples": ["fundref"]
                                }
                              },
                              "required": [
                                "identifier",
                                "type"
                              ]
                            },
                            "funding_status": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/funding/properties/funding_status",
                              "type": "string",
                              "enum": [
                                "planned",
                                "applied",
                                "granted",
                                "rejected"
                              ],
                              "title": "The Funding Status Schema",
                              "description": "To express different phases of project lifecycle. Allowed values: planned, applied, granted, rejected",
                              "examples": ["granted"]
                            },
                            "grant_id": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/funding/properties/grant_id",
                              "type": "object",
                              "title": "The Funding Grant ID Schema",
                              "description": "Grant ID of the associated project",
                              "properties": {
                                "identifier": {
                                  "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/funding/properties/grant_id/properties/identifier",
                                  "type": "string",
                                  "title": "The Funding Grant ID Value Schema",
                                  "description": "Grant ID",
                                  "examples": ["776242"]
                                },
                                "type": {
                                  "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/funding/properties/grant_id/properties/type",
                                  "type": "string",
                                  "title": "The Funding Grant ID Type Schema",
                                  "enum": [
                                    "doi",
                                    "url",
                                    "other"
                                  ],
                                  "description": "Identifier type. Allowed values: url, other",
                                  "examples": ["other"]
                                }
                              },
                              "required": [
                                "identifier",
                                "type"
                              ]
                            },
                            "name": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/items/properties/funding/properties/name",
                              "type": "string",
                              "title": "The name of the funding instituion / organization",
                              "description": "Name",
                              "examples": ["National Science Foundation"]
                            }
                          },
                          "required": [
                            "funding_status",
                            "name"
                          ]
                        },
                        "project": {
                          "$id": "#/properties/dmp/properties/dmphub_modifications/project",
                          "type": "object",
                          "title": "The DMP Project Items Schema",
                          "properties": {
                            "description": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/project/properties/description",
                              "type": "string",
                              "title": "The DMP Project Description Schema",
                              "description": "Project description",
                              "examples": ["Project develops novel..."]
                            },
                            "end": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/project/properties/end",
                              "type": "string",
                              "format": "date-time",
                              "title": "The DMP Project End Date Schema",
                              "description": "Project end date. Encoded using the relevant ISO 8601 Date and Time compliant string.",
                              "examples": ["2020-03-31T00:00:00Z"]
                            },
                            "start": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/project/properties/start",
                              "type": "string",
                              "format": "date-time",
                              "title": "The DMP Project Start Date Schema",
                              "description": "Project start date. Encoded using the relevant ISO 8601 Date and Time compliant string.",
                              "examples": ["2019-04-01T00:00:00Z"]
                            },
                            "title": {
                              "$id": "#/properties/dmp/properties/dmphub_modifications/project/properties/title",
                              "type": "string",
                              "title": "The DMP Project Title Schema",
                              "description": "Project title",
                              "examples": ["Our New Project"]
                            }
                          },
                          "required": [
                            "title"
                          ]
                        }
                      }
                    },
                    "required": [
                      "id",
                      "provenance",
                      "status",
                      "timestamp"
                    ]
                  },
                  "dmphub_versions": {
                    "$id": "#/properties/dmp/properties/dmphub_versions",
                    "type": "array",
                    "title": "DMP ID versions",
                    "description": "Links to all of the DMPs versions",
                    "items": {
                      "$id": "#/properties/dmp/properties/dmphub_versions/items",
                      "type": "object",
                      "title": "DMP version",
                      "properties": {
                        "timestamp": {
                          "$id": "#/properties/dmp/properties/dmphub_versions/items/properties/timestamp",
                          "type": "string",
                          "format": "date-time",
                          "title": "The version date and time",
                          "examples": ["2023-08-17T16:14:39Z"]
                        },
                        "url": {
                          "$id": "#/properties/dmp/properties/dmphub_versions/items/properties/url",
                          "type": "string",
                          "format": "uri",
                          "title": "The URL to retrieve the specified version",
                          "examples": ["https://somesite.org/dmps/doi.org/10.1234/A1B2C3D4?version=2023-08-17T16:14:39Z"]
                        }
                      }
                    },
                    "required": [
                      "timestamp",
                      "url"
                    ]
                  },
                  "dmproadmap_related_identifiers": {
                    "$id": "#/properties/dmp/properties/dmproadmap_related_identifiers",
                    "type": "array",
                    "title": "Related identifiers for the DMP",
                    "description": "Identifiers for objects related to the DMP (e.g. datasets, publications, etc.)",
                    "items": {
                      "$id": "#/properties/dmp/properties/dmproadmap_related_identifiers/items",
                      "type": "object",
                      "title": "A related identifier",
                      "properties": {
                        "descriptor": {
                          "$id": "#/properties/dmp/properties/dmproadmap_related_identifiers/items/properties/descriptor",
                          "type": "string",
                          "enum": [
                            "is_cited_by",
                            "cites",
                            "is_supplement_to",
                            "is_supplemented_by",
                            "is_described_by",
                            "describes",
                            "has_metadata",
                            "is_metadata_for",
                            "is_part_of",
                            "has_part",
                            "is_referenced_by",
                            "references",
                            "is_documented_by",
                            "documents",
                            "is_new_version_of",
                            "is_previous_version_of"
                          ]
                        },
                        "identifier": {
                          "$id": "#/properties/dmp/properties/dmproadmap_related_identifiers/items/properties/identifier",
                          "type": "string",
                          "title": "A unique identifier for the item",
                          "description": "Identifier for a DMP",
                          "examples": ["https://doi.org/10.1371/journal.pcbi.1006750"]
                        },
                        "type": {
                          "$id": "#/properties/dmp/properties/dmproadmap_related_identifiers/items/properties/type",
                          "type": "string",
                          "enum": [
                            "handle",
                            "doi",
                            "ark",
                            "url",
                            "other"
                          ]
                        },
                        "work_type": {
                          "$id": "#/properties/dmp/properties/dmproadmap_related_identifiers/items/properties/work_type",
                          "type": "string"
                        }
                      },
                      "required": [
                        "descriptor",
                        "identifier",
                        "type",
                        "work_type"
                      ]
                    }
                  },
                  "dmproadmap_research_facilities": {
                    "$id": "#/properties/dmp/properties/dmproadmap_research_facilities",
                    "type": "array",
                    "title": "Facilities",
                    "description": "Facilities (e.g. labs and research stations) that will be used to collect/process research data",
                    "items": {
                      "$id": "#/properties/dmp/properties/dmproadmap_research_facilities/items",
                      "type": "object",
                      "title": "A research facility",
                      "properties": {
                        "facility_id": {
                          "$id": "#/properties/dmp/properties/dmproadmap_research_facilities/items/properties/facility_id",
                          "type": "object",
                          "title": "The unique ID of the facility",
                          "description": "The facility's ROR, DOI or URL",
                          "properties": {
                            "identifier": {
                              "$id": "#/properties/dmp/properties/dmproadmap_research_facilities/items/properties/facility_id/properties/identifier",
                              "type": "string",
                              "title": "The facility ID",
                              "description": "ROR ID, DOI or URL. Recommended to use Research Organization Registry (ROR) or DOI when available. See: https://ror.org",
                              "examples": ["https://ror.org/03yrm5c26", "http://doi.org/10.13039/100005595", "http://www.cdlib.org/"]
                            },
                            "type": {
                              "$id": "#/properties/dmp/properties/dmproadmap_research_facilities/items/properties/facility_id/properties/type",
                              "type": "string",
                              "enum": [
                                "doi",
                                "ror",
                                "url"
                              ],
                              "title": "The facility ID type schema",
                              "description": "Identifier type. Allowed values: doi, ror, url",
                              "examples": ["ror"]
                            }
                          },
                          "required": [
                            "identifier",
                            "type"
                          ]
                        },
                        "name": {
                          "$id": "#/properties/dmp/properties/dmproadmap_research_facilities/items/properties/name",
                          "type": "string",
                          "title": "Name of the facility",
                          "description": "Official facility name",
                          "examples": ["Example Research Lab"]
                        },
                        "type": {
                          "$id": "#/properties/dmp/properties/dmproadmap_research_facilities/items/properties/type",
                          "type": "string",
                          "enum": [
                            "field_station",
                            "laboratory"
                          ],
                          "title": "The type of facility",
                          "examples": ["field_station"]
                        }
                      },
                      "required": [
                        "name",
                        "type"
                      ]
                    }
                  },
                  "ethical_issues_description": {
                    "$id": "#/properties/dmp/properties/ethical_issues_description",
                    "type": "string",
                    "title": "The DMP Ethical Issues Description Schema",
                    "description": "To describe ethical issues directly in a DMP",
                    "examples": ["There are ethical issues, because..."]
                  },
                  "ethical_issues_exist": {
                    "$id": "#/properties/dmp/properties/ethical_issues_exist",
                    "type": "string",
                    "enum": [
                      "yes",
                      "no",
                      "unknown"
                    ],
                    "title": "The DMP Ethical Issues Exist Schema",
                    "description": "To indicate whether there are ethical issues related to data that this DMP describes. Allowed values: yes, no, unknown",
                    "examples": ["yes"]
                  },
                  "ethical_issues_report": {
                    "$id": "#/properties/dmp/properties/ethical_issues_report",
                    "type": "string",
                    "format": "uri",
                    "title": "The DMP Ethical Issues Report Schema",
                    "description": "To indicate where a protocol from a meeting with an ethical commitee can be found",
                    "examples": ["http://report.location"]
                  },
                  "language": {
                    "$id": "#/properties/dmp/properties/language",
                    "type": "string",
                    "enum": [
                      "aar", "abk", "afr", "aka", "amh", "ara", "arg", "asm", "ava", "ave", "aym", "aze", "bak", "bam", "bel", "ben", "bih", "bis", "bod", "bos",
                      "bre", "bul", "cat", "ces", "cha", "che", "chu", "chv", "cor", "cos", "cre", "cym", "dan", "deu", "div", "dzo", "ell", "eng", "epo", "est",
                      "eus", "ewe", "fao", "fas", "fij", "fin", "fra", "fry", "ful", "gla", "gle", "glg", "glv", "grn", "guj", "hat", "hau", "hbs", "heb", "her",
                      "hin", "hmo", "hrv", "hun", "hye", "ibo", "ido", "iii", "iku", "ile", "ina", "ind", "ipk", "isl", "ita", "jav", "jpn", "kal", "kan", "kas",
                      "kat", "kau", "kaz", "khm", "kik", "kin", "kir", "kom", "kon", "kor", "kua", "kur", "lao", "lat", "lav", "lim", "lin", "lit", "ltz", "lub",
                      "lug", "mah", "mal", "mar", "mkd", "mlg", "mlt", "mon", "mri", "msa", "mya", "nau", "nav", "nbl", "nde", "ndo", "nep", "nld", "nno", "nob",
                      "nor", "nya", "oci", "oji", "ori", "orm", "oss", "pan", "pli", "pol", "por", "pus", "que", "roh", "ron", "run", "rus", "sag", "san", "sin",
                      "slk", "slv", "sme", "smo", "sna", "snd", "som", "sot", "spa", "sqi", "srd", "srp", "ssw", "sun", "swa", "swe", "tah", "tam", "tat", "tel",
                      "tgk", "tgl", "tha", "tir", "ton", "tsn", "tso", "tuk", "tur", "twi", "uig", "ukr", "urd", "uzb", "ven", "vie", "vol", "wln", "wol", "xho",
                      "yid", "yor", "zha", "zho", "zul"
                    ],
                    "title": "The DMP Language Schema",
                    "description": "Language of the DMP expressed using ISO 639-3.",
                    "examples": ["eng"]
                  },
                  "modified": {
                    "$id": "#/properties/dmp/properties/modified",
                    "type": "string",
                    "format": "date-time",
                    "title": "The DMP Modification Schema",
                    "description": "Must be set each time DMP is modified. Indicates DMP version. Encoded using the relevant ISO 8601 Date and Time compliant string.",
                    "examples": ["2020-03-14T10:53:49+00:00"]
                  },
                  "project": {
                    "$id": "#/properties/dmp/properties/project",
                    "type": "array",
                    "title": "The DMP Project Schema",
                    "description": "Project related to a DMP",
                    "items": {
                      "$id": "#/properties/dmp/properties/project/items",
                      "type": "object",
                      "title": "The DMP Project Items Schema",
                      "properties": {
                        "description": {
                          "$id": "#/properties/dmp/properties/project/items/properties/description",
                          "type": "string",
                          "title": "The DMP Project Description Schema",
                          "description": "Project description",
                          "examples": ["Project develops novel..."]
                        },
                        "end": {
                          "$id": "#/properties/dmp/properties/project/items/properties/end",
                          "type": "string",
                          "format": "date-time",
                          "title": "The DMP Project End Date Schema",
                          "description": "Project end date. Encoded using the relevant ISO 8601 Date and Time compliant string.",
                          "examples": ["2020-03-31"]
                        },
                        "funding": {
                          "$id": "#/properties/dmp/properties/project/items/properties/funding",
                          "type": "array",
                          "title": "The DMP Project Funding Schema",
                          "description": "Funding related with a project",
                          "items": {
                            "$id": "#/properties/dmp/properties/project/items/properties/funding/items",
                            "type": "object",
                            "title": "The DMP Project Funding Items Schema",
                            "properties": {
                              "dmproadmap_funded_affiliations": {
                                "$id": "#/properties/dmp/properties/project/items/properties/funding//items/properties/dmproadmap_funded_affiliations",
                                "type": "array",
                                "title": "Institutions named on the grant",
                                "description": "The institutions who received the funding",
                                "items": {
                                  "$id": "#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items",
                                  "type": "object",
                                  "title": "An institution that received funding",
                                  "properties": {
                                    "affiliation_id": {
                                      "$id": "#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items/properties/affiliation_id",
                                      "type": "object",
                                      "title": "The funded affiliation's ID",
                                      "description": "Affiliation ID of the associated project",
                                      "properties": {
                                        "identifier": {
                                          "$id": "#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items/properties/affiliation_id/properties/identifier",
                                          "type": "string",
                                          "title": "The affiliation ID",
                                          "description": "ROR ID or URL. Recommended to use Research Organization Registry (ROR). See: https://ror.org",
                                          "examples": ["https://ror.org/00pjdza24", "https://cdlib.org"]
                                        },
                                        "type": {
                                          "$id": "#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items/properties/affiliation_id/properties/type",
                                          "type": "string",
                                          "enum": [
                                            "doi",
                                            "ror",
                                            "url"
                                          ],
                                          "title": "The affiliation ID Type Schema",
                                          "description": "Identifier type. Allowed values: doi, ror, url",
                                          "examples": ["ror"]
                                        }
                                      },
                                      "required": [
                                        "identifier",
                                        "type"
                                      ]
                                    },
                                    "name": {
                                      "$id": "#/properties/dmp/properties/project/items/properties/funding/items/properties/dmproadmap_funded_affiliations/items/properties/name",
                                      "type": "string",
                                      "title": "The name of the instituion / organization",
                                      "description": "Project title",
                                      "examples": ["Our New Project"]
                                    }
                                  }
                                }
                              },
                              "dmproadmap_opportunity_number": {
                                "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/dmproadmap_opportunity_number",
                                "type": "string",
                                "title": "The funder's opportunity / award number",
                                "description": "The funder's number used to identify the award or call for submissions",
                                "examples": ["Award-123"]
                              },
                              "dmproadmap_project_number": {
                                "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/dmproadmap_project_number",
                                "type": "string",
                                "title": "The funder's identifier for the research project",
                                "description": "The funder's identifier used to identify the research project",
                                "examples": ["prj-XYZ987-UCB"]
                              },
                              "funder_id": {
                                "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/funder_id",
                                "type": "object",
                                "title": "The Funder ID Schema",
                                "description": "Funder ID of the associated project",
                                "properties": {
                                  "identifier": {
                                    "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/funder_id/properties/identifier",
                                    "type": "string",
                                    "title": "The Funder ID Value Schema",
                                    "description": "Funder ID, recommended to use CrossRef Funder Registry. See: https://www.crossref.org/services/funder-registry/",
                                    "examples": ["501100002428"]
                                  },
                                  "type": {
                                    "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/funder_id/properties/type",
                                    "type": "string",
                                    "enum": [
                                      "fundref",
                                      "ror",
                                      "url",
                                      "other"
                                    ],
                                    "title": "The Funder ID Type Schema",
                                    "description": "Identifier type. Allowed values: fundref, url, other",
                                    "examples": ["fundref"]
                                  }
                                },
                                "required": [
                                  "identifier",
                                  "type"
                                ]
                              },
                              "funding_status": {
                                "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/funding_status",
                                "type": "string",
                                "enum": [
                                  "planned",
                                  "applied",
                                  "granted",
                                  "rejected"
                                ],
                                "title": "The Funding Status Schema",
                                "description": "To express different phases of project lifecycle. Allowed values: planned, applied, granted, rejected",
                                "examples": ["granted"]
                              },
                              "grant_id": {
                                "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/grant_id",
                                "type": "object",
                                "title": "The Funding Grant ID Schema",
                                "description": "Grant ID of the associated project",
                                "properties": {
                                  "identifier": {
                                    "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/grant_id/properties/identifier",
                                    "type": "string",
                                    "title": "The Funding Grant ID Value Schema",
                                    "description": "Grant ID",
                                    "examples": ["776242"]
                                  },
                                  "type": {
                                    "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/grant_id/properties/type",
                                    "type": "string",
                                    "title": "The Funding Grant ID Type Schema",
                                    "enum": [
                                      "doi",
                                      "url",
                                      "other"
                                    ],
                                    "description": "Identifier type. Allowed values: url, other",
                                    "examples": ["other"]
                                  }
                                },
                                "required": [
                                  "identifier",
                                  "type"
                                ]
                              },
                              "name": {
                                "$id": "#/properties/dmp/properties/project/items/properties/funding/properties/name",
                                "type": "string",
                                "title": "The name of the funding instituion / organization",
                                "description": "Name",
                                "examples": ["National Science Foundation"]
                              }
                            },
                            "required": [
                              "funding_status",
                              "name"
                            ]
                          }
                        },
                        "start": {
                          "$id": "#/properties/dmp/properties/project/items/properties/start",
                          "type": "string",
                          "format": "date-time",
                          "title": "The DMP Project Start Date Schema",
                          "description": "Project start date. Encoded using the relevant ISO 8601 Date and Time compliant string.",
                          "examples": ["2019-04-01"]
                        },
                        "title": {
                          "$id": "#/properties/dmp/properties/project/items/properties/title",
                          "type": "string",
                          "title": "The DMP Project Title Schema",
                          "description": "Project title",
                          "examples": ["Our New Project"]
                        }
                      },
                      "required": [
                        "title"
                      ]
                    }
                  },
                  "title": {
                    "$id": "#/properties/dmp/properties/title",
                    "type": "string",
                    "title": "The DMP Title Schema",
                    "description": "Title of a DMP",
                    "examples": ["DMP for our new project"]
                  }
                },
                "required": [
                  "contact",
                  "created",
                  "dataset",
                  "dmp_id",
                  "modified",
                  "project",
                  "title"
                ]
              }
            },
            "additionalProperties": false,
            "required": ["dmp"]
          }.to_json)
        end
      end
    end
  end
end
