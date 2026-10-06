routes:
  - { id: valid,      uri: /valid,      upstream: { scheme: https, pass_host: node, nodes: { "upstream-valid:8441": 1 },      tls: { verify: true } } }
  - { id: wronghost,  uri: /wronghost,  upstream: { scheme: https, pass_host: node, nodes: { "upstream-wronghost:8442": 1 },  tls: { verify: true } } }
  - { id: selfsigned, uri: /selfsigned, upstream: { scheme: https, pass_host: node, nodes: { "upstream-selfsigned:8443": 1 }, tls: { verify: true } } }
  - { id: untrusted,  uri: /untrusted,  upstream: { scheme: https, pass_host: node, nodes: { "upstream-untrusted:8444": 1 },  tls: { verify: true } } }
  - { id: noverify,   uri: /noverify,   upstream: { scheme: https, pass_host: node, nodes: { "upstream-selfsigned:8443": 1 }, tls: { verify: false } } }
#END