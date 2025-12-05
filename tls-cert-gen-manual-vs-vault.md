# Manual generation description

I am creating demo scenarios for PKI certificate generation with hashicorp Vault.  I want to illustrate how PKI TLS/Server cert has been generated and consumed in the traditional way using mermaid.  

It's a sequence flow chart, with parties: Intermediate CA admin, Web server (that needs a new TLS cert) admin, a ticketing system. It should contain the standard workflows like this:

 - **Preparation**: Web server admin creates an OpenSSL configuration file, ensuring Subject Alternative Names (SANs) are correctly defined.
 - **Key Generation**: Web server admin generates a private key and a Certificate Signing Request (CSR).
 - **Request**: Web server admin creates a support ticket, attaches the CSR, and assigns it to the Security Team.
 - **Verification**: Intermediate CA admin (Security Team) manually verifies the requester's identity and validates the requested SANs.
 - **Signing**: Intermediate CA admin runs the signing command to generate the certificate.
 - **Delivery**: CA admin attaches the signed certificate AND the full CA chain (Intermediate + Root) to the ticket.
 - **Installation**: Web server admin copies files to the server, sets secure permissions (e.g., `chmod 600`), and configures the web server.
 - **Activation**: Web server admin restarts/reloads the web server service.
 - **Lifecycle**: Web server admin sets a calendar reminder to renew the certificate in 1 year.



 The sequence flow chart should contain as much details as possible, we can always cutdown from there.

```mermaid
sequenceDiagram
    autonumber
    actor WebAdmin as Web Server Admin
    participant Server as Web Server
    participant Ticket as Ticketing System
    actor CAAdmin as Intermediate CA Admin<br/>(Security Team)
    participant CA as Intermediate CA

    Note over WebAdmin, Server: Preparation Phase
    WebAdmin->>WebAdmin: Research OpenSSL config<br/>(Ensure SANs are correct)
    WebAdmin->>Server: Generate Private Key
    WebAdmin->>Server: Generate CSR (using config)
    
    Note over WebAdmin, Ticket: Request Phase
    WebAdmin->>Ticket: Create Ticket
    WebAdmin->>Ticket: Attach CSR File
    Ticket-->>CAAdmin: Notify New Request

    Note over CAAdmin, CA: Verification & Signing Phase
    CAAdmin->>Ticket: Review Request
    CAAdmin->>CAAdmin: Verify Identity & SANs<br/>(Manual Check)
    CAAdmin->>CA: Execute Signing Command<br/>(openssl ca ...)
    CA-->>CAAdmin: Output Signed Certificate
    
    Note over CAAdmin, Ticket: Delivery Phase
    CAAdmin->>CAAdmin: Bundle Cert + Intermediate + Root
    CAAdmin->>Ticket: Attach Cert Chain
    CAAdmin->>Ticket: Close Ticket
    Ticket-->>WebAdmin: Notify Resolution

    Note over WebAdmin, Server: Installation Phase
    WebAdmin->>Ticket: Download Cert Chain
    WebAdmin->>Server: Upload Certs (SCP/SFTP)
    WebAdmin->>Server: Set Permissions (chmod 600)
    WebAdmin->>Server: Update Web Server Config
    WebAdmin->>Server: Restart Service
    
    Note over WebAdmin: Lifecycle Management
    WebAdmin->>WebAdmin: Set Calendar Reminder<br/>(Renew in 1 year)
```

# Vault Generation Description (Automated)

In contrast to the manual process, the Vault workflow shifts the responsibility from humans to the **Vault Agent**. Once configured, the entire lifecycle is automated.

- **One-time Setup**: Admin installs Vault Agent and configures it with a role (e.g., AppRole) and a template.
- **Authentication**: Vault Agent automatically authenticates with Vault to obtain a token.
- **Request & Generation**: Vault Agent requests a certificate from the PKI engine. Vault generates the Key, Cert, and Chain instantly.
- **Delivery & Installation**: Vault Agent renders the certificate and private key directly to the file system with secure permissions (0600).
- **Activation**: Vault Agent automatically runs a `reload` command for the web server whenever the certificate changes.
- **Lifecycle**: Vault Agent monitors the certificate's TTL. When it reaches ~85% of its life, it **automatically renews** it. No tickets, no calendar reminders.

```mermaid
sequenceDiagram
    autonumber
    participant Server as Web Server Process
    box "Web Server Host" #f9f9f9
        participant Agent as Vault Agent
        participant Files as Cert Files
    end
    participant Vault as Vault Server

    Note over Agent, Vault: Initialization (One-time)
    Agent->>Vault: Authenticate (AppRole/Cloud Identity)
    Vault-->>Agent: Return Access Token

    Note over Agent, Vault: Automated Lifecycle Loop
    loop Every TTL (e.g., 24h or 30s)
        Agent->>Vault: Request Certificate (pki/issue/web-role)
        Vault-->>Agent: Return Cert (w/ Pub Key) + Private Key + Chain
        
        Agent->>Files: Write app.crt, app.key, ca.crt
        Agent->>Files: Set Permissions (0600)
        
        Agent->>Server: Execute "systemctl reload nginx"
        Server->>Files: Read new Certs
        
        Note right of Agent: Agent sleeps until renewal window
    end
```

# Comparison Summary

| Feature | Manual Workflow | Vault Workflow |
| :--- | :--- | :--- |
| **Speed** | **Days/Hours** (Ticket queues, manual work) | **Milliseconds** (Instant API response) |
| **Human Effort** | **High** (10+ steps, multiple teams) | **Zero** (After initial setup) |
| **Security** | **Low** (Private keys often moved around, permissions errors) | **High** (Private key never leaves the host, generated in memory) |
| **Reliability** | **Low** (Forgot to renew = Outage) | **High** (Automated renewal, no outages) |
| **Scalability** | **Linear Effort** (More servers = More work) | **Infinite** (1000 servers is same effort as 1) |