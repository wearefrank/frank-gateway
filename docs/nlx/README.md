# APISIX as an NLX Inway

There are two aspects in order for APISIX (or any other gateway) to function as an NLX Inway:
1) handling traffic conformant to the NLX specification
2) handle registration of the Inway and it's services in the registry and the NLX management

Note, this would still require the NLX Management API and optionally the NLX Management UI. 


## Traffic handling conformat to NLX specification

In order for APISIX to handle traffic according to the NLX specification as an Inway the following features must be implemented in APISIX.

- mTLS connections 
    - verify clients based on their client certificate 
        - PKI Overheid CA??
        - extract and verify NLX organization indentifier from the certificates `serialNumber` as part of the `CN`
- Add serialNumber to HTTP Header `X-NLX-Request-Organization` 
- verify access grants (list managed by management UI/API)
- respond with NLX errors https://gitlab.com/commonground/nlx/nlx/-/blob/master/docs/docs/support/common-errors.md 

## NLX registration
In order for APISIX to become part of the NLX network it needs to register as an NLX Inway. Currently all management capabilities of NLX of which the registration is part of is handled by the `NLX Management UI` and `NLX Management API`. It makes the most sense to use the `NLX Management API`.  
However this is a GRPC API of which documentation is currently sparce. E.g. addition of the required GRPC headers was only discovered by looking at the source code of the Tyk experiment of NLX.

In order to get a functioning NLX Inway the following features must be implemented:
- Register itself to the Management API as an Inway. -> GRPC call `RegisterInway` -> https://gitlab.com/commonground/nlx/nlx/-/blob/master/management-api/api/management.proto#L81
- Retrieve an Inway config and keep up to date from the Management API. -> GRPC call `GetInwayConfig` -> https://gitlab.com/commonground/nlx/nlx/-/blob/master/management-api/api/management.proto#L218
- Validate if an Access Grant exists for the Outway making the call. 
- Register itself and its services to the Directory API. -> GRPC call `RegisterInway` https://gitlab.com/commonground/nlx/nlx/-/blob/master/directory-api/api/directoryapi.proto#L16

this could roughly look like:
![nlx phase 1 integration with APISIX](../diagrams/nlx-phase1.png)

curl grpc server with grpcurl:
grpcurl -proto=management.proto -import-path=/home/pimg/klanten/we-are-frank/nlx-try-me -key=./pki/internal/certs/internal-cert-key.pem -cert=./pki/internal/certs/internal-cert.pem -cacert=./pki/internal/ca/intermediate_ca.pem -H 'Authorization: Basic YWRtaW5Abmx4LmxvY2FsOmRldmVsb3BtZW50' localhost:9443 nlx.management.ManagementService/ListInways
