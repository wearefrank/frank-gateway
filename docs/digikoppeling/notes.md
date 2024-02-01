# Notes on Digikoppeling standards in APISIX:
Er zijn 4 soorten koppelvlakken:
WUS (m.n. geschikt voor bevragingen met direct antwoord) -> mogelijk via API gateway

EBMS2 (voor zowel meldingen (transacties) als bevragingen met een uitgesteld antwoord) -> lijkt async (messaging)

REST API (m.n. geschikt voor bevragingen & operaties op data resources met direct antwoord) -> geschikt voor API gateway

Grote Berichten (voor uitwisselen van grote bestanden) -> niet geschikt voor API Gateway

# WUS
WS002 - SOAPAction in header can be "" need to be able to retrieve the SOAP action from WS-Addresing Action
overige WS-* extensions, like WS-security are handled by the FrankFramework!

# eBMS 
uses similar SOAP extensions as WUS and therefore has the similar routing requirements as WUS

# Grote bestanden
API Gateway not suitable for file transfer 

# Rest API's
The Digikoppeling Rest extension of Digikoppeling can be handled by the API Gateway 

# WUS routing plugin
In order to perform the routing based on WS-Addressing a custom plugin with the following functionality is proposed:
- parse SOAP envelope
- extract wsa:Action SOAP envelope property and set SoapAction HTTP header with this value