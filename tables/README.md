
# Change custom tables to analytics tier command. Use in Azure Cloud Shell Bash

```bash
az monitor log-analytics workspace table update --resource-group <Resource Group Name> --workspace-name <Workspace Name> --name SuricataAlert_CL --plan Analytics
```
