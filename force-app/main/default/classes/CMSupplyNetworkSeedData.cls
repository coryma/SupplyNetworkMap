public without sharing class CMSupplyNetworkSeedData {
    public class SeedResult {
        @AuraEnabled public Integer createdAccounts;
        @AuraEnabled public Integer createdRelationships;
        @AuraEnabled public Integer totalAccountsInScope;
        @AuraEnabled public Integer totalRelationshipsInScope;
    }

    private class EdgeDefinition {
        String fromName;
        String toName;
        String edgeCategory;
        String relationType;
        String role;
        String evidence;

        EdgeDefinition(
            String fromAccountName,
            String toAccountName,
            String edgeCategoryValue,
            String relationTypeValue,
            String roleValue,
            String evidenceValue
        ) {
            fromName = fromAccountName;
            toName = toAccountName;
            edgeCategory = edgeCategoryValue;
            relationType = relationTypeValue;
            role = roleValue;
            evidence = evidenceValue;
        }
    }

    public static SeedResult seedWncDemo() {
        Id businessAccountRecordTypeId = getBusinessAccountRecordTypeId();
        List<String> requiredAccountNames = new List<String>{
            'Quincy',
            'TSMC',
            'ASE',
            'Amkor',
            'WPG',
            'WT Microelectronics',
            'WNC',
            'Verizon',
            'AT&T',
            'T-Mobile US',
            'Ford',
            'General Motors'
        };

        Map<String, Account> accountByName = new Map<String, Account>();
        List<String> personAccountNames = new List<String>();
        for (Account existingAccount : [
            SELECT Id, Name, IsPersonAccount
            FROM Account
            WHERE Name IN :requiredAccountNames
        ]) {
            accountByName.put(existingAccount.Name, existingAccount);
            if (existingAccount.IsPersonAccount) {
                personAccountNames.add(existingAccount.Name);
            }
        }

        if (!personAccountNames.isEmpty()) {
            throw new AuraHandledException(
                'Seed requires business Account records (not Person Accounts): ' +
                String.join(personAccountNames, ', ')
            );
        }

        List<Account> accountsToInsert = new List<Account>();
        for (String accountName : requiredAccountNames) {
            if (!accountByName.containsKey(accountName)) {
                Account newAccount = new Account(Name = accountName);
                if (businessAccountRecordTypeId != null) {
                    newAccount.RecordTypeId = businessAccountRecordTypeId;
                }
                accountsToInsert.add(newAccount);
            }
        }

        if (!accountsToInsert.isEmpty()) {
            insert accountsToInsert;
            for (Account insertedAccount : accountsToInsert) {
                accountByName.put(insertedAccount.Name, insertedAccount);
            }
        }

        List<EdgeDefinition> relationshipsToSeed = new List<EdgeDefinition>{
            new EdgeDefinition('TSMC', 'Quincy', 'DOWNSTREAM', 'Foundry', '晶圓代工供應商', '提供先進製程晶圓代工。'),
            new EdgeDefinition('ASE', 'Quincy', 'DOWNSTREAM', 'OSAT', '封裝測試供應商', '提供封裝與測試服務。'),
            new EdgeDefinition('Amkor', 'Quincy', 'DOWNSTREAM', 'OSAT', '封裝測試供應商', '支援後段封測產能。'),
            new EdgeDefinition('Quincy', 'WPG', 'DOWNSTREAM', 'Distributor', 'IC 通路代理商', '提供通路供貨與 FAE 支援。'),
            new EdgeDefinition('Quincy', 'WT Microelectronics', 'DOWNSTREAM', 'Distributor', 'IC 通路代理商', '提供通路供貨與技術服務。'),
            new EdgeDefinition('WPG', 'WNC', 'INDIRECT_PATH', 'Channel Partner', '網通設備通路/整合', '通路代理對接網通製造客戶。'),
            new EdgeDefinition('WT Microelectronics', 'WNC', 'INDIRECT_PATH', 'Channel Partner', '網通設備通路/整合', '通路代理對接網通製造客戶。'),
            new EdgeDefinition('WNC', 'Verizon', 'INDIRECT_PATH', 'Telecom Operator', '電信營運商客戶', '5G FWA 家用路由器導入。'),
            new EdgeDefinition('WNC', 'AT&T', 'INDIRECT_PATH', 'Telecom Operator', '電信營運商客戶', '5G FWA 方案導入。'),
            new EdgeDefinition('WNC', 'T-Mobile US', 'INDIRECT_PATH', 'Telecom Operator', '電信營運商客戶', '5G FWA 方案導入。'),
            new EdgeDefinition('WNC', 'Ford', 'INDIRECT_PATH', 'Automaker', '車廠客戶', '車聯網模組整合導入。'),
            new EdgeDefinition('WNC', 'General Motors', 'INDIRECT_PATH', 'Automaker', '車廠客戶', '車聯網模組整合導入。')
        };

        Set<Id> inScopeAccountIds = new Set<Id>();
        for (String accountName : requiredAccountNames) {
            Account accountRecord = accountByName.get(accountName);
            if (accountRecord != null) {
                inScopeAccountIds.add(accountRecord.Id);
            }
        }

        Set<String> existingRelationshipKeys = new Set<String>();
        for (CM_Supply_Relationship__c relationshipRecord : [
            SELECT
                Id,
                Source_Account__c,
                Target_Account__c,
                Relation_Type__c,
                Edge_Category__c
            FROM CM_Supply_Relationship__c
            WHERE Source_Account__c IN :inScopeAccountIds
            AND Target_Account__c IN :inScopeAccountIds
        ]) {
            existingRelationshipKeys.add(
                buildRelationshipKey(
                    relationshipRecord.Source_Account__c,
                    relationshipRecord.Target_Account__c,
                    relationshipRecord.Relation_Type__c,
                    relationshipRecord.Edge_Category__c
                )
            );
        }

        List<CM_Supply_Relationship__c> relationshipInserts = new List<CM_Supply_Relationship__c>();
        for (EdgeDefinition edgeDefinition : relationshipsToSeed) {
            Account fromAccount = accountByName.get(edgeDefinition.fromName);
            Account toAccount = accountByName.get(edgeDefinition.toName);
            if (fromAccount == null || toAccount == null) {
                continue;
            }

            String relationshipKey = buildRelationshipKey(
                fromAccount.Id,
                toAccount.Id,
                edgeDefinition.relationType,
                edgeDefinition.edgeCategory
            );
            if (existingRelationshipKeys.contains(relationshipKey)) {
                continue;
            }

            existingRelationshipKeys.add(relationshipKey);
            relationshipInserts.add(
                new CM_Supply_Relationship__c(
                    Source_Account__c = fromAccount.Id,
                    Target_Account__c = toAccount.Id,
                    Edge_Category__c = edgeDefinition.edgeCategory,
                    Relation_Type__c = edgeDefinition.relationType,
                    Role__c = edgeDefinition.role,
                    Evidence__c = edgeDefinition.evidence,
                    Confidence__c = 0.95,
                    Source_Type__c = 'PUBLIC_INFO',
                    Is_Active__c = true
                )
            );
        }

        if (!relationshipInserts.isEmpty()) {
            insert relationshipInserts;
        }

        SeedResult result = new SeedResult();
        result.createdAccounts = accountsToInsert.size();
        result.createdRelationships = relationshipInserts.size();
        result.totalAccountsInScope = accountByName.size();
        result.totalRelationshipsInScope = existingRelationshipKeys.size();
        return result;
    }

    private static String buildRelationshipKey(Id fromId, Id toId, String relationType, String edgeCategory) {
        return String.valueOf(fromId) + '|' + String.valueOf(toId) + '|' + String.valueOf(relationType) + '|' + String.valueOf(edgeCategory);
    }

    private static Id getBusinessAccountRecordTypeId() {
        List<RecordType> accountRecordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsActive = true
            AND IsPersonType = false
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        if (accountRecordTypes.isEmpty()) {
            return null;
        }
        return accountRecordTypes[0].Id;
    }
}