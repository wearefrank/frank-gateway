# Generate custom keypair
Generate custom keypair singed with NLX root CA of development FSC-NLX cluster. 

This enables Frank API Gateway to act as an FSC-NLX Inway of organization-a in the FSC-NLX local development cluster.

## Prerequisites
The following packages are used to generate the keypair:
- cfssl
- cfssljson

Since the CA keymaterial of the FSC-NLX development cluster is needed to sign the certificates execute the command below in the following directory:
`{FSC-NLX repository}/pki`

## Generate the certificates
In order to generate the certificates execute the following command in the directory mentioned above:
```shell
cfssl gencert \
      -config "external/config.json" \
      -ca "external/ca/intermediate-1.pem" \
      -ca-key "external/ca/intermediate-1-key.pem" \
      -profile peer \
      "external/certs/organization-a/frank-api-gateway.organization-a.nlx.local/csr.json" \
    | cfssljson -bare "external/certs/organization-a/frank-api-gateway.organization-a.nlx.local/cert"
```

The generated key material will be generated in the directory: `{FSC-NLX repo}/pki/external/certs/organization-a/frank-api-gateway.organization-a.nlx.local/cert`

## Use the key material
In order to use the key material:
- copy contents of `cert-key.pem` into the file `apisix.yaml` in `ssls[0]/key`
- copy contents of `cert.pem` into the file `apisix.yaml` in `ssls[0]/cert` at the first entry. Make sure the second certificate ending with `9jBmVZalCQXOpdfR39OmOxJDtzkeaeXJDaXDAtDfibQRp6QbF3M=` remains there as the second certificate in the chain.