import json
ca = open("certs/ca.crt").read()
tpl = open("apisix/apisix.yaml.tpl").read()
out = tpl.replace("tls: { verify: true }",
                  "tls: { verify: true, ca_certs: [%s] }" % json.dumps(ca))
open("apisix/apisix.yaml", "w").write(out)
