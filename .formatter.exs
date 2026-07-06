# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [
    # Hawk.Model
    model: 2,
    json_api: 1,
    type: 1,
    doc: 1,
    attribute: 1,
    attribute: 2,
    relationship: 1,
    relationship: 2,
    creatable: 1,
    updatable: 1,

    # Hawk.Policy
    read: 1,
    role: 2,
    write: 1,

    # Hawk.Reader.Resource
    filter: 1,
    filter: 2,
    sort: 1,
    preload: 1,
    preload: 2,
    attach: 3,

    # Hawk.JsonApiControllerCase
    authorities: 1,
    pre_sample: 2,
    sample: 4
  ]
]
