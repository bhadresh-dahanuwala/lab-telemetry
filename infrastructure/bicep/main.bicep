@description('The location for all resources.')
param location string = 'eastus'

@description('A unique suffix to append to resource names to ensure global uniqueness.')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The name of the environment (e.g., dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param env string

@description('Location specifically for the Function App to bypass regional quota limits.')
param functionLocation string = 'eastus'

// ==========================================
// 1. ADLS Gen2 (Data Lake)
// ==========================================
var dataLakeName = 'dls${env}${uniqueSuffix}'
var bronzeContainerName = 'telemetry-bronze'

resource dataLake 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: dataLakeName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true // This is what makes it ADLS Gen2
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
  }
}

resource dataLakeBlobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: dataLake
  name: 'default'
}

resource bronzeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: dataLakeBlobServices
  name: bronzeContainerName
}

// ==========================================
// 2. Event Hub
// ==========================================
var eventHubNamespaceName = 'evhns-${env}-${uniqueSuffix}'
var eventHubName = 'telemetry-events'

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: eventHubNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: 7
    partitionCount: 4
    captureDescription: {
      enabled: true
      skipEmptyArchives: true
      encoding: 'Avro'
      intervalInSeconds: 60
      sizeLimitInBytes: 10485760 // 10 MB
      destination: {
        name: 'EventHubArchive.AzureBlockBlob'
        identity: { type: 'SystemAssigned' }
        properties: {
          storageAccountResourceId: dataLake.id
          blobContainer: bronzeContainerName
          archiveNameFormat: '{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}'
        }
      }
    }
  }
}

// ==========================================
// 3. Azure Function App (Compute)
// ==========================================
var funcStorageName = 'stfunc${env}${uniqueSuffix}'
var appServicePlanName = 'asp-func-${env}-${uniqueSuffix}'
var functionAppName = 'func-telemetry-${env}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-telemetry-${env}-${uniqueSuffix}'
var appInsightsName = 'appi-telemetry-${env}-${uniqueSuffix}'

// Functions need their own standard storage account to manage triggers/state
resource functionStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: funcStorageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource functionStorageBlob 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: functionStorage
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: functionStorageBlob
  name: 'deploymentpackage'
}

// Log Analytics & App Insights for Function logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Serverless Consumption Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true // Required for Linux
  }
}

// The Function App itself
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned' // Generates the Managed Identity
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${functionStorage.listKeys().keys[0].value}'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'DATALAKE_ACCOUNT_URL'
          value: dataLake.properties.primaryEndpoints.dfs
        }
        {
          name: 'EVENTHUB_NAMESPACE_FQDN'
          value: '${eventHubNamespace.name}.servicebus.windows.net'
        }
        {
          name: 'EVENTHUB_NAME'
          value: eventHub.name
        }
      ]
      functionAppConfig: {
        deployment: {
          storage: {
            type: 'blobContainer'
            value: '${functionStorage.properties.primaryEndpoints.blob}deploymentpackage'
            authentication: {
              type: 'SystemAssignedIdentity'
            }
          }
        }
        scaleAndConcurrency: {
          maximumInstanceCount: 40
          instanceMemoryMB: 2048
        }
        runtime: {
          name: 'python'
          version: '3.11'
        }
      }
    }
  }
}

// ==========================================
// 4. Role Assignments (RBAC)
// ==========================================



// Grant the Function App permission to read/write its own deployment storage account (required for Flex Consumption)
resource functionStorageAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionStorage.id, functionApp.id, storageBlobDataContributorRoleId)
  scope: functionStorage
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Built-in Role ID for "Storage Blob Data Contributor"
var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

// Built-in Role ID for "Azure Event Hubs Data Sender"
var eventHubsDataSenderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2b629674-e913-4c01-ae53-ef4638d8f975')

// Grant the Function App permission to write to the Data Lake
resource functionDataLakeAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataLake.id, functionApp.id, storageBlobDataContributorRoleId)
  scope: dataLake
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant the Function App permission to write to the Event Hub
resource functionEventHubAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubNamespace.id, functionApp.id, eventHubsDataSenderRoleId)
  scope: eventHubNamespace
  properties: {
    roleDefinitionId: eventHubsDataSenderRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Event Hub permission to write Capture files to the Data Lake
resource eventHubDataLakeAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataLake.id, eventHubNamespace.id, storageBlobDataContributorRoleId)
  scope: dataLake
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: eventHubNamespace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==========================================
// 5. Snowpipe Infrastructure (Queue & Event Grid)
// ==========================================
var snowpipeQueueName = 'snowpipe-queue'

resource storageQueueServices 'Microsoft.Storage/storageAccounts/queueServices@2023-01-01' = {
  parent: dataLake
  name: 'default'
}

resource snowpipeQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  parent: storageQueueServices
  name: snowpipeQueueName
}

// System Topic for the Data Lake
resource dataLakeSystemTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: 'st-telemetry-bronze'
  location: location
  properties: {
    source: dataLake.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// Event Grid Subscription routing to the Queue
resource snowpipeEventSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
  parent: dataLakeSystemTopic
  name: 'snowpipe-sub'
  properties: {
    destination: {
      endpointType: 'StorageQueue'
      properties: {
        resourceId: dataLake.id
        queueName: snowpipeQueueName
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/${bronzeContainerName}/'
    }
  }
}
