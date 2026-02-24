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
        String relationshipType;

        EdgeDefinition(String fromAccountName, String toAccountName, String typeValue) {
            fromName = fromAccountName;
            toName = toAccountName;
            relationshipType = typeValue;
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
            SELECT Id, Name, IsPartner, IsPersonAccount
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

        List<Account> accountsToPartnerEnable = new List<Account>();
        for (Account accountRecord : [
            SELECT Id, Name, IsPartner, IsPersonAccount
            FROM Account
            WHERE Name IN :requiredAccountNames
        ]) {
            accountByName.put(accountRecord.Name, accountRecord);
            if (accountRecord.IsPersonAccount) {
                personAccountNames.add(accountRecord.Name);
                continue;
            }
            if (accountRecord.IsPartner != true) {
                accountsToPartnerEnable.add(
                    new Account(
                        Id = accountRecord.Id,
                        IsPartner = true
                    )
                );
            }
        }

        if (!personAccountNames.isEmpty()) {
            List<String> uniquePersonAccounts = new List<String>(new Set<String>(personAccountNames));
            throw new AuraHandledException(
                'Seed requires business Account records (not Person Accounts): ' +
                String.join(uniquePersonAccounts, ', ')
            );
        }

        if (!accountsToPartnerEnable.isEmpty()) {
            update accountsToPartnerEnable;
        }

        List<EdgeDefinition> relationshipsToSeed = new List<EdgeDefinition>{
            new EdgeDefinition('TSMC', 'Quincy', 'Supplier'),
            new EdgeDefinition('ASE', 'Quincy', 'Supplier'),
            new EdgeDefinition('Amkor', 'Quincy', 'Supplier'),
            new EdgeDefinition('Quincy', 'WPG', 'Distributor'),
            new EdgeDefinition('Quincy', 'WT Microelectronics', 'Distributor'),
            new EdgeDefinition('WPG', 'WNC', 'Distributor'),
            new EdgeDefinition('WT Microelectronics', 'WNC', 'Distributor'),
            new EdgeDefinition('WNC', 'Verizon', 'Supplier'),
            new EdgeDefinition('WNC', 'AT&T', 'Supplier'),
            new EdgeDefinition('WNC', 'T-Mobile US', 'Supplier'),
            new EdgeDefinition('WNC', 'Ford', 'Supplier'),
            new EdgeDefinition('WNC', 'General Motors', 'Supplier')
        };

        Set<Id> inScopeAccountIds = new Set<Id>();
        for (String accountName : requiredAccountNames) {
            Account accountRecord = accountByName.get(accountName);
            if (accountRecord != null) {
                inScopeAccountIds.add(accountRecord.Id);
            }
        }

        Set<String> existingRelationshipKeys = new Set<String>();
        for (AccountRelationship relationshipRecord : [
            SELECT Id, AccountFromId, AccountToId, Type
            FROM AccountRelationship
            WHERE AccountFromId IN :inScopeAccountIds
            AND AccountToId IN :inScopeAccountIds
        ]) {
            existingRelationshipKeys.add(
                buildRelationshipKey(
                    relationshipRecord.AccountFromId,
                    relationshipRecord.AccountToId,
                    relationshipRecord.Type
                )
            );
        }

        List<AccountRelationship> relationshipInserts = new List<AccountRelationship>();
        for (EdgeDefinition edgeDefinition : relationshipsToSeed) {
            Account fromAccount = accountByName.get(edgeDefinition.fromName);
            Account toAccount = accountByName.get(edgeDefinition.toName);
            if (fromAccount == null || toAccount == null) {
                continue;
            }

            String relationshipKey = buildRelationshipKey(
                fromAccount.Id,
                toAccount.Id,
                edgeDefinition.relationshipType
            );
            if (existingRelationshipKeys.contains(relationshipKey)) {
                continue;
            }

            existingRelationshipKeys.add(relationshipKey);
            relationshipInserts.add(
                new AccountRelationship(
                    Name = buildRelationshipName(
                        edgeDefinition.fromName,
                        edgeDefinition.toName,
                        edgeDefinition.relationshipType
                    ),
                    AccountFromId = fromAccount.Id,
                    AccountToId = toAccount.Id,
                    Type = edgeDefinition.relationshipType
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

    private static String buildRelationshipKey(Id fromId, Id toId, String relationshipType) {
        return String.valueOf(fromId) + '|' + String.valueOf(toId) + '|' + String.valueOf(relationshipType);
    }

    private static String buildRelationshipName(String fromName, String toName, String relationshipType) {
        String rawName = fromName + ' -> ' + toName + ' (' + relationshipType + ')';
        return rawName.length() > 80 ? rawName.substring(0, 80) : rawName;
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
