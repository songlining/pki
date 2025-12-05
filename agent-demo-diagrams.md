# Vault Agent PKI Demo - Mermaid Diagrams

## Overview: `make agent-demo` Workflow

```mermaid
flowchart TD
    Start([User runs: make agent-demo]) --> CheckCred[Check Agent Credentials]
    CheckCred --> CredExist{Credentials<br/>exist?}
    
    CredExist -->|No| SetupCred[Run setup-agent-credentials.sh]
    CredExist -->|Yes| ValidCred{Valid?}
    
    ValidCred -->|No| SetupCred
    ValidCred -->|Yes| CheckPKI[Check PKI Role]
    
    SetupCred --> CheckPKI
    
    CheckPKI --> RoleExist{example-role<br/>exists?}
    RoleExist -->|No| CreateRole[Create PKI Role<br/>ttl=30s, max_ttl=72h]
    RoleExist -->|Yes| Demo[Run agent-pki-demo.sh]
    
    CreateRole --> Demo
    
    Demo --> Step1[Step 1: Verify Agent Status]
    Step1 --> Step2[Step 2: Show Authentication]
    Step2 --> Step3[Step 3: Display Authorization]
    Step3 --> Step4[Step 4: Verify PKI Infrastructure]
    Step4 --> Step5[Step 5: Show Template Config]
    Step5 --> Step6[Step 6: Analyze Template Files]
    Step6 --> Step7[Step 7: Display Certificate Details]
    Step7 --> Step8[Step 8: Live Rotation Demo]
    
    Step8 --> Monitor{Rotation<br/>detected?}
    Monitor -->|Yes| Success[✅ Demo Complete]
    Monitor -->|No| Timeout[⏰ Suggest watch-rotation.sh]
    
    Timeout --> Success
    Success --> End([Demo Ends])
    
    style Start fill:#e1f5ff
    style End fill:#e1f5ff
    style Success fill:#d4edda
    style SetupCred fill:#fff3cd
    style CreateRole fill:#fff3cd
```

## Container Architecture

```mermaid
graph TB
    subgraph Host["Host Machine (localhost)"]
        Make[make agent-demo command]
        Scripts[Demo Scripts]
        Config[vault-agent-config/]
        Output[vault-agent-output/]
        
        Make --> Scripts
        Scripts --> Config
    end
    
    subgraph Docker["Docker Network: vault-network"]
        subgraph VaultServer["vault-enterprise container"]
            VaultDev[Vault Server<br/>:8200<br/>Dev Mode]
            PKIEngine[PKI Secrets Engine]
            AppRoleAuth[AppRole Auth]
            Policies[PKI Policy]
            
            VaultDev --> PKIEngine
            VaultDev --> AppRoleAuth
            VaultDev --> Policies
        end
        
        subgraph VaultAgent["vault-agent container"]
            AgentProc[Vault Agent Process]
            AgentListener[Agent Listener<br/>:8100]
            Templates[Template Engine]
            AutoAuth[Auto-Auth Method]
            
            AgentProc --> AgentListener
            AgentProc --> Templates
            AgentProc --> AutoAuth
        end
    end
    
    Config -->|Mount| AutoAuth
    Templates -->|Write| Output
    
    AutoAuth -->|AppRole Login| AppRoleAuth
    Templates -->|Request Certs| PKIEngine
    
    Host -->|:8200| VaultDev
    Host -->|:8100| AgentListener
    
    style VaultServer fill:#f0f0ff
    style VaultAgent fill:#fff0f0
    style Host fill:#f0fff0
```

## Credential Setup Flow

```mermaid
sequenceDiagram
    participant User
    participant Script as setup-agent-credentials.sh
    participant Vault as Vault Server :8200
    participant Files as Config Files
    
    User->>Script: Execute setup script
    Script->>Vault: Enable AppRole auth method
    Vault-->>Script: OK (or already enabled)
    
    Script->>Vault: Create PKI policy<br/>(pki/* permissions)
    Vault-->>Script: Policy created
    
    Script->>Vault: Create/update AppRole<br/>(vault-agent-role)
    Note over Script,Vault: Policies: default, pki-policy<br/>TTL: 1h, Max TTL: 4h
    Vault-->>Script: AppRole configured
    
    Script->>Vault: Read role-id
    Vault-->>Script: role-id value
    
    Script->>Vault: Generate secret-id
    Vault-->>Script: secret-id value
    
    Script->>Files: Save role-id
    Script->>Files: Save secret-id
    Script->>Files: chmod 600 (secure permissions)
    
    Script-->>User: ✅ Credentials ready
```

## Vault Agent Auto-Auth and Certificate Lifecycle

```mermaid
sequenceDiagram
    participant Agent as Vault Agent
    participant AuthSink as Token Sink<br/>/tmp/vault-token
    participant VaultAuth as Vault AppRole Auth
    participant Cache as Agent Cache
    participant Template as Template Engine
    participant PKI as Vault PKI Engine
    participant Files as Output Files
    
    Note over Agent: Agent starts with agent.hcl config
    
    Agent->>Agent: Read role-id and secret-id
    Agent->>VaultAuth: Login with AppRole credentials
    VaultAuth-->>Agent: Return Vault token (TTL: 1h)
    Agent->>AuthSink: Write token to file
    Agent->>Cache: Store token for auto-use
    
    Note over Agent,Files: Template Processing Loop
    
    loop For each template (cert, key, ca, env)
        Template->>Cache: Get auto-auth token
        Template->>PKI: Request certificate<br/>pki/issue/example-role<br/>common_name=app.example.com<br/>ttl=30s
        PKI-->>Template: Return certificate + key + CA
        Template->>Files: Render template to file<br/>(app.crt, app.key, ca.crt, app.env)
    end
    
    Note over Agent: Wait until ~15s before cert expiry
    
    loop Auto-Renewal (every ~15s)
        Template->>PKI: Request new certificate
        PKI-->>Template: New cert + key + CA
        Template->>Files: Update files atomically
        Note over Files: Certificate rotated!
    end
    
    Note over Agent: Token renewal (before 1h expiry)
    Agent->>VaultAuth: Renew token
    VaultAuth-->>Agent: Extended token TTL
    Agent->>AuthSink: Update token file
```

## Template Processing Detail

```mermaid
flowchart LR
    subgraph Templates["Template Files"]
        CertTpl[cert.tpl]
        KeyTpl[key.tpl]
        CaTpl[ca.tpl]
        EnvTpl[env.tpl]
    end
    
    subgraph Engine["Vault Agent Template Engine"]
        Parse[Parse Template]
        Execute[Execute Secret Call]
        Render[Render Output]
    end
    
    subgraph PKI["PKI Secret Response"]
        Certificate[certificate]
        PrivateKey[private_key]
        IssuingCA[issuing_ca]
        SerialNum[serial_number]
    end
    
    subgraph Output["Output Files<br/>/vault/agent/"]
        AppCrt[app.crt<br/>perms: 0644]
        AppKey[app.key<br/>perms: 0600]
        CaCrt[ca.crt<br/>perms: 0644]
        AppEnv[app.env<br/>perms: 0644]
    end
    
    CertTpl --> Parse
    KeyTpl --> Parse
    CaTpl --> Parse
    EnvTpl --> Parse
    
    Parse --> Execute
    Execute -->|pki/issue/example-role| PKI
    
    Certificate --> Render
    PrivateKey --> Render
    IssuingCA --> Render
    
    Render -->|cert.tpl| AppCrt
    Render -->|key.tpl| AppKey
    Render -->|ca.tpl| CaCrt
    Render -->|env.tpl| AppEnv
    
    AppEnv -.->|Triggers| RestartCmd[restart-app.sh]
    
    style Templates fill:#ffe6e6
    style Engine fill:#e6f2ff
    style PKI fill:#e6ffe6
    style Output fill:#fff0e6
```

## Certificate Rotation Timeline

```mermaid
gantt
    title Certificate Lifecycle (30-second TTL)
    dateFormat ss
    axisFormat %Ss
    
    section Certificate 1
    Cert Valid          :active, cert1, 00, 30s
    Renewal Window      :crit, renew1, 15, 15s
    
    section Certificate 2
    Cert Valid          :active, cert2, 30, 30s
    Renewal Window      :crit, renew2, 45, 15s
    
    section Certificate 3
    Cert Valid          :active, cert3, 60, 30s
    Renewal Window      :crit, renew3, 75, 15s
```

## Demo Steps Flow

```mermaid
stateDiagram-v2
    [*] --> Step1: Start Demo
    
    Step1: Step 1 - Verify Agent Status
    Step2: Step 2 - Show Authentication
    Step3: Step 3 - Display Authorization
    Step4: Step 4 - Verify PKI Infrastructure
    Step5: Step 5 - Show Template Config
    Step6: Step 6 - Analyze Template Files
    Step7: Step 7 - Display Certificate Details
    Step8: Step 8 - Live Rotation Demo
    
    Step1 --> Step2: curl /v1/sys/health
    Step2 --> Step3: Show agent token
    Step3 --> Step4: Display AppRole config & policies
    Step4 --> Step5: Verify PKI engine, roles, CA
    Step5 --> Step6: Show agent.hcl template blocks
    Step6 --> Step7: Display template file contents
    Step7 --> Step8: Show current certificate details
    Step8 --> Monitor: Wait for rotation (45s max)
    
    Monitor: Monitor Certificate Serial
    Monitor --> Success: Serial number changed
    Monitor --> Timeout: No change after 45s
    
    Success --> [*]: Demo Complete ✅
    Timeout --> [*]: Suggest watch-rotation.sh
    
    note right of Step3
        Shows:
        - AppRole config
        - PKI policy
        - Token info
    end note
    
    note right of Step8
        Monitors serial number
        every 5 seconds
        for up to 45 seconds
    end note
```

## Security and Authorization Model

```mermaid
graph TD
    subgraph Identity["Identity Layer"]
        AppRole[AppRole: vault-agent-role]
        RoleID[role-id file]
        SecretID[secret-id file]
    end
    
    subgraph Auth["Authentication"]
        Login[AppRole Login]
        Token[Vault Token<br/>TTL: 1h, Max: 4h]
    end
    
    subgraph Policy["Authorization"]
        DefaultPol[default policy]
        PKIPol[pki-policy]
    end
    
    subgraph Capabilities["PKI Capabilities"]
        Create[Create certificates]
        Read[Read PKI config]
        Update[Update certificates]
        Delete[Delete certificates]
        List[List roles]
    end
    
    subgraph PKI["PKI Resources"]
        PKIPath[pki/*]
        MountPath[sys/mounts/pki]
        Role[pki/roles/example-role]
    end
    
    RoleID --> Login
    SecretID --> Login
    AppRole --> Login
    
    Login --> Token
    
    Token --> DefaultPol
    Token --> PKIPol
    
    PKIPol --> Create
    PKIPol --> Read
    PKIPol --> Update
    PKIPol --> Delete
    PKIPol --> List
    
    Create --> PKIPath
    Read --> PKIPath
    Update --> PKIPath
    Delete --> PKIPath
    List --> PKIPath
    
    Create --> MountPath
    Read --> MountPath
    Update --> MountPath
    
    PKIPath --> Role
    
    style Identity fill:#ffe6e6
    style Auth fill:#e6ffe6
    style Policy fill:#e6f2ff
    style Capabilities fill:#fff0e6
    style PKI fill:#f0e6ff
```

## Software Component Architecture

```mermaid
graph TB
    Client[Demo Script]
    
    Client -->|HTTP API| VaultServer

    subgraph DockerNetwork[" "]
        subgraph VaultContainer[" "]
            VaultServer[Vault Server]
            VaultServer --> PKIEngine
        end
        
        subgraph AgentContainer[" "]
            AgentProxy[Vault Agent]
            AgentProxy -->|Writes Files| OutputFiles
        end
        
        PKIEngine[PKI Secrets Engine<br/>Role: example-role<br/>TTL: 30s]
        
        OutputFiles[app.crt, app.key, ca.crt]
    end
    
    AgentProxy --> VaultServer
    
    style DockerNetwork fill:#fffacd
    style VaultContainer fill:#e6f3ff
    style AgentContainer fill:#ffe6f0
    style Client fill:#e6e6fa
```

## Data Flow: Certificate Request to File

```mermaid
flowchart TD
    Start([Certificate Needed]) --> Timer{Renewal<br/>Timer}
    
    Timer -->|Time to renew| GetToken[Get Auto-Auth Token<br/>from cache]
    
    GetToken --> APICall[API Call:<br/>POST pki/issue/example-role]
    
    APICall --> Params[Parameters:<br/>common_name=app.example.com<br/>ttl=30s]
    
    Params --> VaultPKI[Vault PKI Engine]
    
    VaultPKI --> Generate[Generate:<br/>- Private Key<br/>- Certificate<br/>- Sign with CA]
    
    Generate --> Response[JSON Response:<br/>.Data.certificate<br/>.Data.private_key<br/>.Data.issuing_ca<br/>.Data.serial_number]
    
    Response --> Parse[Template Parser]
    
    Parse --> Extract1[Extract certificate]
    Parse --> Extract2[Extract private_key]
    Parse --> Extract3[Extract issuing_ca]
    
    Extract1 --> Write1[Write app.crt<br/>chmod 0644]
    Extract2 --> Write2[Write app.key<br/>chmod 0600]
    Extract3 --> Write3[Write ca.crt<br/>chmod 0644]
    
    Write1 --> Schedule[Schedule Next Renewal<br/>~15 seconds]
    Write2 --> Schedule
    Write3 --> Schedule
    
    Schedule --> Wait[Wait...]
    Wait --> Timer
    
    style Start fill:#e1f5ff
    style VaultPKI fill:#d4edda
    style Generate fill:#fff3cd
    style Response fill:#f8d7da
    style Write1 fill:#d1ecf1
    style Write2 fill:#d1ecf1
    style Write3 fill:#d1ecf1
```

## Component Interaction Overview

```mermaid
C4Context
    title Component Interaction - Vault Agent PKI Demo
    
    Person(user, "Demo User", "Runs make agent-demo")
    
    System_Boundary(host, "Host System") {
        Container(makefile, "Makefile", "Build tool", "Orchestrates demo")
        Container(demoscript, "agent-pki-demo.sh", "Bash", "Interactive demo script")
        Container(setupscript, "setup-agent-credentials.sh", "Bash", "Credential setup")
    }
    
    System_Boundary(docker, "Docker Environment") {
        Container(vault, "Vault Server", "Enterprise", "PKI engine, AppRole auth")
        Container(agent, "Vault Agent", "OSS", "Auto-auth, templating, caching")
    }
    
    System_Boundary(storage, "Persistent Storage") {
        ContainerDb(configs, "Config Files", "HCL/Templates", "agent.hcl, *.tpl, credentials")
        ContainerDb(outputs, "Output Files", "PEM Files", "app.crt, app.key, ca.crt")
    }
    
    Rel(user, makefile, "Executes", "make agent-demo")
    Rel(makefile, demoscript, "Runs")
    Rel(demoscript, setupscript, "Calls if needed")
    Rel(setupscript, vault, "Configures", "HTTPS API")
    
    Rel(agent, vault, "Authenticates & requests certs", "HTTP :8200")
    Rel(agent, configs, "Reads")
    Rel(agent, outputs, "Writes")
    
    Rel(demoscript, vault, "Queries status", "HTTP :8200")
    Rel(demoscript, agent, "Queries health", "HTTP :8100")
    Rel(demoscript, outputs, "Displays cert info")
    
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="2")
```

## Error Handling and Recovery

```mermaid
flowchart TD
    Start([make agent-demo]) --> Check1{Agent<br/>container<br/>running?}
    
    Check1 -->|No| Error1[❌ Error: Container not started]
    Check1 -->|Yes| Check2{Credentials<br/>exist?}
    
    Error1 --> Fix1[Run: make start]
    Fix1 --> Retry1[Retry demo]
    
    Check2 -->|No| Auto1[Auto-run setup-agent-credentials.sh]
    Check2 -->|Yes| Check3{Credentials<br/>valid?}
    
    Check3 -->|No| Auto1
    Check3 -->|Yes| Check4{PKI role<br/>exists?}
    
    Auto1 --> CreateCred[Create AppRole & credentials]
    CreateCred --> Check4
    
    Check4 -->|No| Auto2[Auto-create example-role]
    Check4 -->|Yes| CheckInit{Vault<br/>initialized?}
    
    Auto2 --> CheckInit
    
    CheckInit -->|No| Error2[❌ Error: Vault not initialized]
    CheckInit -->|Yes| RunDemo[Run Demo Steps]
    
    Error2 --> Fix2[Run: make init]
    Fix2 --> Retry2[Retry demo]
    
    RunDemo --> Check5{Templates<br/>rendering?}
    
    Check5 -->|No| Wait[Wait a moment...]
    Check5 -->|Yes| Monitor[Monitor rotation]
    
    Wait --> Check5
    
    Monitor --> Success[✅ Success]
    
    style Error1 fill:#f8d7da
    style Error2 fill:#f8d7da
    style Auto1 fill:#fff3cd
    style Auto2 fill:#fff3cd
    style Success fill:#d4edda
```

---

## Summary

The `make agent-demo` command demonstrates HashiCorp Vault Agent's automatic PKI certificate management with the following key features:

1. **Automated Setup**: Checks and creates necessary credentials and PKI roles
2. **AppRole Authentication**: Agent authenticates using role-id and secret-id
3. **Template-Based Cert Management**: Automatically generates and rotates certificates using templates
4. **Short-Lived Certificates**: 30-second TTL for demonstration purposes
5. **Automatic Renewal**: Agent renews certificates ~15 seconds before expiry
6. **Live Monitoring**: Demonstrates rotation detection in real-time

The demo showcases enterprise-grade certificate lifecycle management without manual intervention.
