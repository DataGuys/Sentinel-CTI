# Central Threat Intelligence V5: Production Inoculation Engine

A production-ready, fully automated threat intelligence platform that protects your entire digital estate by dynamically distributing indicators across your security infrastructure with intelligent risk assessment, automated workflows, and comprehensive monitoring.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FSecurityOrg%2FCTI-V5%2Fmain%2Fazuredeploy.json)

## Enterprise-Grade Features

- **Universal Protection**: Seamlessly protect Microsoft, AWS, GCP, network devices, and EDR/XDR systems
- **Zero-Touch Operations**: Fully automated for high-confidence indicators with approval workflows for medium-confidence
- **Enterprise Resiliency**: Comprehensive error handling, retry logic, and telemetry  
- **Turn-Key Deployment**: Deploy production-ready in minutes with minimal configuration
- **Performance Optimized**: Scalable architecture with enhanced resource efficiency

## Architecture Overview

![CTI-V5 Architecture](https://raw.githubusercontent.com/SecurityOrg/CTI-V5/main/images/architecture-diagram1.svg)

## Enhanced Components

### 1. Unified Indicator Store

Consolidated schema with enriched metadata:

- Integrated confidence scoring
- Enhanced validation
- Support for all STIX/TAXII types
- Enrichment data storage
- Effectiveness tracking
- Full audit trail

### 2. V5 Inoculation Engine

Production-ready core with enterprise capabilities:

- Intelligent indicator routing with multi-tier classification
- Built-in environment health checks
- Comprehensive error handling with retry logic
- Performance monitoring and telemetry
- Auto-scaling configuration
- SLA monitoring for approval workflows

### 3. Advanced Risk Assessment Engine

Context-aware risk scoring with multiple data sources:

- Third-party reputation data integration (VirusTotal, AbuseIPDB, AlienVault)
- Internal telemetry correlation
- Business context assessment
- Machine learning readiness
- Weighted multi-factor scoring

### 4. Enterprise Connectors

Hardened integration with security platforms:

- **Microsoft**: Defender XDR, Sentinel, Exchange Online, Entra ID
- **AWS**: Security Hub, GuardDuty, Network Firewall, WAF
- **GCP**: Security Command Center, Cloud Armor
- **Network**: Palo Alto, Cisco, Fortinet, Check Point
- **Endpoints**: CrowdStrike, SentinelOne, Carbon Black, Microsoft Defender for Endpoint

### 5. Effectiveness Measurement System

Closed-loop feedback for continuous improvement:

- Real-time effectiveness tracking across platforms
- Self-tuning confidence adjustments
- Operational metrics dashboards
- Automated pruning of low-value indicators
- ROI and coverage reporting

## Production-Ready Deployment

### Prerequisites

- Azure subscription with Contributor role
- Global Administrator for app registration permissions
- Optional: AWS/GCP accounts for cross-cloud protection
- Optional: API access to network/EDR systems

### One-Command Deployment

```bash
./deploy.sh -l eastus -p cti -e prod -t Analytics -x Standard
```

### Advanced Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| -l | Azure region | eastus |
| -p | Resource prefix | cti |
| -e | Environment tag | prod |
| -t | Table plan (Analytics/Basic/Standard) | Analytics |
| -c | Enable cross-cloud protection | true |
| -n | Enable network protection | true |
| -d | Enable endpoint protection | true |
| -s | SLA hours for critical alerts | 24 |
| -a | Auto-approve deployment | false |
| -x | Performance tier (Basic/Standard/Premium) | Standard |

### Post-Deployment Configuration

The deployment script handles most configuration automatically:

1. **API Keys**: Securely stored in Key Vault
2. **Connection Details**: Auto-configured based on environment
3. **Email Notifications**: Customizable templates for approval workflows
4. **SLA Monitoring**: Built-in for all critical processes

## V5 Enhanced Dashboards

The solution includes comprehensive operational dashboards:

- Real-time indicator distribution status
- Multi-cloud protection coverage
- Effectiveness metrics with trend analysis
- System health monitoring with alerting
- ROI and value reporting

## Operational Excellence

V5 includes enterprise-grade operational features:

- **Health Monitoring**: Proactive system checks and alerting
- **Performance Optimization**: Auto-scaling and efficient resource utilization
- **Disaster Recovery**: Automated backup and restoration
- **Upgrade Path**: Seamless updates with backward compatibility
- **Documentation**: Comprehensive operational guides

## Security and Compliance

- **Zero Trust**: Fine-grained access controls and authentication
- **Data Protection**: Encryption at rest and in transit for all components
- **Audit Trail**: Comprehensive logging for all operations
- **Compliance**: Designed for regulatory requirements

## Contributing

Enterprise contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
