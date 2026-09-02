param location string = resourceGroup().location

@description('Name of the storage account for Terraform state')
param storageAccountName string = 'sttfstate${uniqueString(resourceGroup().id)}'

@description('Name of the blob container for Terraform state')
param containerName string = 'tfstate'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: containerName
}

output storageAccountName string = storageAccount.name
output containerName string = container.name
