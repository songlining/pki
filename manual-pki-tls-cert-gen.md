# Manual generation description

I am creating demo scenarios for PKI certificate generation with hashicorp Vault.  I want to illustrate how PKI TLS/Server cert has been generated and consumed in the traditional way using mermaid.  

It's a sequence flow chart, with parties: Intermediate CA admin, Web server (that needs a new TLS cert) admin, a ticketing system. It should contain the standard workflows like this:

 - web server admin generates a pair of keys: public and private
 - web server admin runs the certificate signing request command against the public key, which generates the CSR file. 
 - web server admin creates a ticket and attach the CSR file to it.
 - the ticket is sent to the Intermediate CA admin for signing.
 - the Intermediate CA admin runs the command and signs the request
 - the signed certificate is sent back through the ticket to the web server admin
 - 


 The sequence flow chart should contain as much details as possible, we can always cutdown from there.