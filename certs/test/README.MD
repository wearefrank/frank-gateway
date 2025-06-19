# mTLS Test Certificates for APISIX Standalone

> ⚠️ **Important Notice:**  
> All keys and certificates in this directory are for **testing and development purposes only**.  
> **They should NEVER be used in production environments!**

---

## Overview

This directory contains a set of keys and certificates designed to test **APISIX** with **mTLS** (mutual TLS) in standalone mode, focusing on certificate chains and different Certificate Authorities (CAs).

The scenario covered is:

- **Scenario:**  
    - leaf = bullcert.pem
    - intermediate = Let's Encrypt R11
    - root = ISRG Root X1

    The root ca will be chained with the intermediates like this: 
        root + Intermediate> ca-bundle.pem

    
## Commands
The following commands are for testing the plugin cert-auth.lua

To test the connection use the following curl command:

```shell

openssl s_client -connect localhost:9443 -cert bultcert.pem -key bultcertenc.key -CAfile apisix.pem -servername localhost

``` 


