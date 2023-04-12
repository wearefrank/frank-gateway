# APISIX as an NLX/FSC Inway

There are two aspects in order for APISIX (or any other gateway) to function as an NLX Inway:
1) handling traffic conformant to the NLX/FSC specification
2) handle registration of the Inway and it's services in the registry and the NLX management

Note, this would still require the NLX Management API and optionally the NLX Management UI. 


## Traffic handling conformat to NLX/FSC specification

In order for APISIX to handle traffic according to the NLX/FSC specification as an Inway the following features must be implemented in APISIX.

- mTLS connections 
    - verify clients based on their client certificate 
        - PKI Overheid CA??
        - extract and verify NLX organization indentifier from the certificates `serialNumber` as part of the `CN` 
- Add NLX organization identifier to HTTP Header `X-NLX-Request-Organization` 
- perform authorization
    - The Peer ID in the X.509 certificate used by the connecting Outway matches the value of the field grant.data.outway.peer_id.
    - The Public Key Fingerprint of the Public Key used by the connecting Outway matches a value of the field grant.data.outway.public_key_fingerprints.
    - The access token is signed by the same Peer that owns Inway.
    - The access token is used by an Outway that uses the X.509 certificate to which the access token is bound. This is verified by applying the JWT Certificate Thumbprint Confirmation Method specified in Section 3.1 of [RFC8705].
    - The Service specified in the access token is known to the Inway.
- respond with NLX errors https://gitlab.com/commonground/nlx/nlx/-/blob/master/docs/docs/support/common-errors.md 

## NLX registration
`currently it is not known how an NLX inway needs to become part of the group. The below is still part of the NLX reference implementation and documentation. But is not part of the FSC standard.` 

In order for APISIX to become part of the NLX network it needs to register as an NLX Inway. Currently all management capabilities of NLX of which the registration is part of is handled by the `NLX Management UI` and `NLX Management API`. It makes the most sense to use the `NLX Management API`.  
However this is a GRPC API of which documentation is currently sparce. E.g. addition of the required GRPC headers was only discovered by looking at the source code of the Tyk experiment of NLX.

In order to get a functioning NLX Inway the following features must be implemented:
- Register itself to the Management API as an Inway. -> GRPC call `RegisterInway` -> https://gitlab.com/commonground/nlx/nlx/-/blob/master/management-api/api/management.proto#L81
- Retrieve an Inway config and keep up to date from the Management API. -> GRPC call `GetInwayConfig` -> https://gitlab.com/commonground/nlx/nlx/-/blob/master/management-api/api/management.proto#L218
- Validate if an Access Grant exists for the Outway making the call. 
- Register itself and its services to the Directory API. -> GRPC call `RegisterInway` https://gitlab.com/commonground/nlx/nlx/-/blob/master/directory-api/api/directoryapi.proto#L16

this could roughly look like:
![nlx phase 1 integration with APISIX](../diagrams/nlx-phase1v2.png)

A first draft of the technical setup of the NLX/FSC plugin in APISIX can be depicted as follows:
![APISIX NLX/FSX plugin](../diagrams/APISIX_NLX-FSC_Plugin.png)

Open points:
- FSC does not provide a standard mechanism of obtaining the public key from the manager in order to validate the access token
    - Can the GET /certificates endpoint of the manager also be used to retrieve the public key of the manager that can be used for validating access tokens? If so how can this key be obtained from the map?
- the inway needs the grant (ServiceConnectionGrant) from the manager in order to perform additional validation of the access token. However obtaining these grants is awkward at best, three possible solutions can be created for this:
    - "invert" the data structure and store all grants based on peer_id
        - this results in a datatransformation and storage of lot of duplicate data
    - re-calculate the granthash and use this as a key for storing the hash
        - the calculation of the hash is prone to implementation differences (e.g. encoding scheme)
    - the GET /contracts returns per grant the grant hash in the response
        - this is the preferred solution, however this does require the FSC/NLX endpoint to be changed. 