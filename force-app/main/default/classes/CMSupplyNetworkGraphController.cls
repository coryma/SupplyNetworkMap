public with sharing class CMSupplyNetworkGraphController {
    private static final Integer DEFAULT_MAX_NODES = 150;
    private static final Integer ABSOLUTE_MAX_NODES = 500;
    private static final Decimal MIN_CONFIDENCE = 0.55;
    private static final String DEMO_ROOT_ACCOUNT_NAME = 'quincy';
    private static final String DEMO_TEMPLATE_NAME = 'DEMO_QUINCY_V1';
    private static final String PROMPT_TEMPLATE_DEVELOPER_NAME = 'CM_Account_Supply_Network_Discovery';
    private static final String PROMPT_APPLICATION_NAME = 'PromptBuilderPreview';
    private static final Set<String> SUPPORTED_DIRECTIONS = new Set<String>{ 'UPSTREAM', 'DOWNSTREAM', 'COMPETITOR' };
    private static final List<String> DEMO_ACCOUNT_NAMES = new List<String>{
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

    @TestVisible private static String testPromptJson;
    @TestVisible private static String testPromptFailureMessage;

    @AuraEnabled(cacheable=false)
    public static GraphResponse getGraph(Id rootAccountId, Integer maxNodes) {
        if (rootAccountId == null) {
            throw new AuraHandledException('rootAccountId is required.');
        }

        validateReadAccess();

        Integer nodeCap = normalizeMaxNodes(maxNodes);
        Account rootAccount = loadRootAccount(rootAccountId);
        if (!isDemoRoot(rootAccount)) {
            return buildNonDemoResponse(rootAccount);
        }
        return buildQuincyDemoResponse(rootAccount, nodeCap);
    }

    private static Boolean isDemoRoot(Account rootAccount) {
        return normalizeName(rootAccount.Name) == DEMO_ROOT_ACCOUNT_NAME;
    }

    private static GraphResponse buildNonDemoResponse(Account rootAccount) {
        GraphResponse response = new GraphResponse();
        response.rootId = String.valueOf(rootAccount.Id);
        response.promptTemplateName = DEMO_TEMPLATE_NAME;
        response.dataSource = 'DEMO_FIXED';
        response.generatedAt = Datetime.now();
        response.coverageNote = '此版本為 Quincy 固定示意圖。請切換到 Quincy Account 查看完整上下游關係。';

        NodeDto rootNode = buildDemoNode(
            rootAccount,
            rootAccount.Name,
            true,
            0,
            0,
            0,
            'ROOT',
            '目前帳戶',
            '僅 Quincy 提供完整 Demo 供應鏈視圖。'
        );
        response.nodes.add(rootNode);
        response.nodeCount = response.nodes.size();
        response.edgeCount = 0;
        return response;
    }

    private static GraphResponse buildQuincyDemoResponse(Account rootAccount, Integer nodeCap) {
        GraphResponse response = new GraphResponse();
        response.rootId = String.valueOf(rootAccount.Id);
        response.promptTemplateName = DEMO_TEMPLATE_NAME;
        response.dataSource = 'DEMO_FIXED';
        response.generatedAt = Datetime.now();

        Map<String, Account> accountByName = new Map<String, Account>();
        for (Account accountRecord : [
            SELECT Id, Name, Type
            FROM Account
            WHERE Name IN :DEMO_ACCOUNT_NAMES
            LIMIT 2000
        ]) {
            accountByName.put(accountRecord.Name, accountRecord);
        }

        List<NodeDto> orderedNodes = new List<NodeDto>();
        Map<String, NodeDto> nodeByNameKey = new Map<String, NodeDto>();

        NodeDto rootNode = buildDemoNode(
            rootAccount,
            rootAccount.Name,
            true,
            0,
            0,
            0,
            'ROOT',
            'IC 設計原廠',
            'Quincy Demo 固定供應鏈主節點。'
        );
        orderedNodes.add(rootNode);
        nodeByNameKey.put(normalizeName(rootNode.label), rootNode);

        List<DemoNodeDefinition> nodeDefinitions = new List<DemoNodeDefinition>{
            new DemoNodeDefinition('TSMC', -2, 2, null, 'UPSTREAM', '晶圓代工 (Foundry)', '提供先進製程晶圓代工服務。'),
            new DemoNodeDefinition('ASE', -1, 1, null, 'UPSTREAM', '封裝與測試 (OSAT)', '提供封裝與測試能力。'),
            new DemoNodeDefinition('Amkor', -1, 1, null, 'UPSTREAM', '封裝與測試 (OSAT)', '支援後段封裝與測試產能。'),
            new DemoNodeDefinition('WPG', 1, null, 1, 'DOWNSTREAM', 'IC 通路代理商', '提供通路供貨與 FAE 支援。'),
            new DemoNodeDefinition('WT Microelectronics', 1, null, 1, 'DOWNSTREAM', 'IC 通路代理商', '提供通路供貨與技術服務。'),
            new DemoNodeDefinition('WNC', 2, null, 2, 'DOWNSTREAM', '網通與車用設備 ODM/JDM', '負責系統整合與最終組裝。'),
            new DemoNodeDefinition('Verizon', 3, null, 3, 'DOWNSTREAM', '電信營運商', '5G FWA 家用路由器導入客戶。'),
            new DemoNodeDefinition('AT&T', 3, null, 3, 'DOWNSTREAM', '電信營運商', '5G FWA 家用路由器導入客戶。'),
            new DemoNodeDefinition('T-Mobile US', 3, null, 3, 'DOWNSTREAM', '電信營運商', '5G FWA 家用路由器導入客戶。'),
            new DemoNodeDefinition('Ford', 3, null, 3, 'DOWNSTREAM', '車廠客戶', '車聯網模組導入客戶。'),
            new DemoNodeDefinition('General Motors', 3, null, 3, 'DOWNSTREAM', '車廠客戶', '車聯網模組導入客戶。')
        };

        for (DemoNodeDefinition nodeDefinition : nodeDefinitions) {
            if (orderedNodes.size() >= nodeCap) {
                response.truncated = true;
                break;
            }

            Account matchedAccount = accountByName.get(nodeDefinition.accountName);
            NodeDto node = buildDemoNode(
                matchedAccount,
                nodeDefinition.accountName,
                false,
                nodeDefinition.signedLevel,
                nodeDefinition.upstreamDepth,
                nodeDefinition.downstreamDepth,
                nodeDefinition.relationshipDirection,
                nodeDefinition.roleLabel,
                nodeDefinition.noteText
            );
            orderedNodes.add(node);
            nodeByNameKey.put(normalizeName(node.label), node);
        }

        List<DemoEdgeDefinition> edgeDefinitions = new List<DemoEdgeDefinition>{
            new DemoEdgeDefinition('TSMC', 'Quincy', 'Foundry', 'UPSTREAM'),
            new DemoEdgeDefinition('ASE', 'Quincy', 'OSAT', 'UPSTREAM'),
            new DemoEdgeDefinition('Amkor', 'Quincy', 'OSAT', 'UPSTREAM'),
            new DemoEdgeDefinition('Quincy', 'WPG', 'Distributor', 'DOWNSTREAM'),
            new DemoEdgeDefinition('Quincy', 'WT Microelectronics', 'Distributor', 'DOWNSTREAM'),
            new DemoEdgeDefinition('WPG', 'WNC', 'Channel Partner', 'DOWNSTREAM'),
            new DemoEdgeDefinition('WT Microelectronics', 'WNC', 'Channel Partner', 'DOWNSTREAM'),
            new DemoEdgeDefinition('WNC', 'Verizon', 'Telecom Operator', 'DOWNSTREAM'),
            new DemoEdgeDefinition('WNC', 'AT&T', 'Telecom Operator', 'DOWNSTREAM'),
            new DemoEdgeDefinition('WNC', 'T-Mobile US', 'Telecom Operator', 'DOWNSTREAM'),
            new DemoEdgeDefinition('WNC', 'Ford', 'Automaker', 'DOWNSTREAM'),
            new DemoEdgeDefinition('WNC', 'General Motors', 'Automaker', 'DOWNSTREAM')
        };

        Integer edgeIndex = 0;
        for (DemoEdgeDefinition edgeDefinition : edgeDefinitions) {
            NodeDto sourceNode = nodeByNameKey.get(normalizeName(edgeDefinition.sourceName));
            NodeDto targetNode = nodeByNameKey.get(normalizeName(edgeDefinition.targetName));
            if (sourceNode == null || targetNode == null) {
                response.truncated = true;
                continue;
            }

            String edgeKey = sourceNode.id + '|' + targetNode.id + '|' + edgeDefinition.relationType + '|' + edgeDefinition.direction;
            EdgeDto edge = new EdgeDto();
            edge.id = buildEdgeId(edgeKey, edgeIndex);
            edge.sourceId = sourceNode.id;
            edge.targetId = targetNode.id;
            edge.relationType = edgeDefinition.relationType;
            edge.relationshipDirection = edgeDefinition.direction;
            response.edges.add(edge);
            edgeIndex++;
        }

        List<String> missingAccounts = new List<String>();
        for (NodeDto node : orderedNodes) {
            if (!node.isRoot && node.accountId == null) {
                missingAccounts.add(node.label);
            }
        }

        response.coverageNote = missingAccounts.isEmpty()
            ? 'Quincy 固定示意圖：上游製造與封測 -> 通路 -> ODM/JDM -> 電信與車廠客戶。'
            : 'Quincy 固定示意圖已載入，但以下節點缺少 Account 無法點擊：' + String.join(missingAccounts, '、');
        response.nodes.addAll(orderedNodes);
        response.nodeCount = response.nodes.size();
        response.edgeCount = response.edges.size();
        return response;
    }

    @TestVisible
    private static GraphResponse buildResponseFromPrompt(String rawPromptJson, Account rootAccount, Integer nodeCap) {
        Map<String, Object> payload = parsePromptPayload(rawPromptJson);
        String payloadError = stringValue(payload.get('error'));
        if (!String.isBlank(payloadError)) {
            String payloadReason = stringValue(payload.get('reason'));
            throw new AuraHandledException(
                'Prompt template returned an error: ' + payloadError + (String.isBlank(payloadReason) ? '' : ' (' + payloadReason + ')')
            );
        }

        List<Object> relationshipObjects = asList(payload.get('relationships'));
        if (relationshipObjects == null) {
            throw new AuraHandledException('Prompt output is missing the relationships array.');
        }

        AccountLookup accountLookup = buildAccountLookup(relationshipObjects);

        GraphResponse response = new GraphResponse();
        response.rootId = String.valueOf(rootAccount.Id);
        response.promptTemplateName = PROMPT_TEMPLATE_DEVELOPER_NAME;
        response.dataSource = 'PROMPT_TEMPLATE';
        response.generatedAt = Datetime.now();

        NodeDto rootNode = new NodeDto();
        rootNode.id = String.valueOf(rootAccount.Id);
        rootNode.accountId = rootAccount.Id;
        rootNode.label = rootAccount.Name;
        rootNode.isRoot = true;
        rootNode.accountType = rootAccount.Type;
        rootNode.upstreamDepth = 0;
        rootNode.downstreamDepth = 0;
        rootNode.signedLevel = 0;
        rootNode.relationshipDirection = 'ROOT';
        rootNode.roleLabel = '核心設計平台';
        rootNode.noteText = String.isBlank(rootAccount.Description)
            ? 'AI 生成供應鏈關係圖（基於 Prompt Template）。'
            : rootAccount.Description;

        Map<String, NodeDto> nodeById = new Map<String, NodeDto>{ rootNode.id => rootNode };
        Set<String> edgeKeys = new Set<String>();

        Integer relationshipIndex = 0;
        for (Object relationshipObject : relationshipObjects) {
            Map<String, Object> relationship = asMap(relationshipObject);
            if (relationship == null) {
                continue;
            }

            Decimal confidence = toDecimal(relationship.get('confidence'));
            if (confidence == null || confidence < MIN_CONFIDENCE) {
                continue;
            }

            String direction = normalizeDirection(stringValue(relationship.get('direction')));
            if (direction == null) {
                continue;
            }

            String companyDomain = normalizeDomain(stringValue(relationship.get('company_domain')));
            if (String.isBlank(companyDomain)) {
                continue;
            }

            String companyName = stringValue(relationship.get('company_name'));
            if (String.isBlank(companyName)) {
                companyName = companyDomain;
            }

            String companyBusinessUnit = stringValue(relationship.get('company_business_unit'));
            String dedupeKey = companyDomain + (String.isBlank(companyBusinessUnit) ? '' : '|' + companyBusinessUnit.toLowerCase());
            String nodeId = buildExternalNodeId(dedupeKey);

            if (!nodeById.containsKey(nodeId)) {
                if (nodeById.size() >= nodeCap) {
                    response.truncated = true;
                    continue;
                }

                Account matchedAccount = resolveAccountForRelationship(relationship, accountLookup);
                NodeDto node = new NodeDto();
                node.id = nodeId;
                node.accountId = matchedAccount == null ? null : matchedAccount.Id;
                node.label = companyName;
                node.isRoot = false;
                node.accountType = String.isBlank(stringValue(relationship.get('role')))
                    ? (matchedAccount == null ? null : matchedAccount.Type)
                    : stringValue(relationship.get('role'));
                node.relationshipDirection = direction;

                if (direction == 'UPSTREAM') {
                    node.signedLevel = -1;
                    node.upstreamDepth = 1;
                    node.downstreamDepth = null;
                } else if (direction == 'COMPETITOR') {
                    node.signedLevel = 1;
                    node.upstreamDepth = null;
                    node.downstreamDepth = 2;
                } else {
                    node.signedLevel = 1;
                    node.upstreamDepth = null;
                    node.downstreamDepth = 1;
                }

                node.roleLabel = String.isBlank(stringValue(relationship.get('role')))
                    ? node.accountType
                    : stringValue(relationship.get('role'));
                node.noteText = buildNoteText(relationship);
                nodeById.put(nodeId, node);
            }

            String relationType = stringValue(relationship.get('relation_type'));
            if (String.isBlank(relationType)) {
                relationType = direction == 'UPSTREAM' ? 'Supplier' : (direction == 'COMPETITOR' ? 'Direct Competitor' : 'Customer');
            }

            String sourceId = direction == 'UPSTREAM' ? nodeId : rootNode.id;
            String targetId = direction == 'UPSTREAM' ? rootNode.id : nodeId;

            if (!nodeById.containsKey(sourceId) || !nodeById.containsKey(targetId)) {
                continue;
            }

            String edgeKey = sourceId + '|' + targetId + '|' + relationType;
            if (edgeKeys.contains(edgeKey)) {
                continue;
            }
            edgeKeys.add(edgeKey);

            EdgeDto edge = new EdgeDto();
            edge.id = buildEdgeId(edgeKey, relationshipIndex);
            edge.sourceId = sourceId;
            edge.targetId = targetId;
            edge.relationType = relationType;
            edge.relationshipDirection = direction;
            response.edges.add(edge);
            relationshipIndex++;
        }

        response.nodes.addAll(nodeById.values());
        response.nodeCount = response.nodes.size();
        response.edgeCount = response.edges.size();

        Map<String, Object> summary = asMap(payload.get('summary'));
        response.coverageNote = summary == null ? null : stringValue(summary.get('coverage_note'));

        return response;
    }

    private static Account resolveAccountForRelationship(Map<String, Object> relationship, AccountLookup accountLookup) {
        String domain = normalizeDomain(stringValue(relationship.get('company_domain')));
        String name = normalizeName(stringValue(relationship.get('company_name')));

        if (!String.isBlank(domain) && accountLookup.byDomain.containsKey(domain)) {
            return accountLookup.byDomain.get(domain);
        }
        if (!String.isBlank(name) && accountLookup.byName.containsKey(name)) {
            return accountLookup.byName.get(name);
        }
        return null;
    }

    private static AccountLookup buildAccountLookup(List<Object> relationshipObjects) {
        Set<String> companyNames = new Set<String>();
        for (Object relationshipObject : relationshipObjects) {
            Map<String, Object> relationship = asMap(relationshipObject);
            if (relationship == null) {
                continue;
            }
            String companyName = stringValue(relationship.get('company_name'));
            if (!String.isBlank(companyName)) {
                companyNames.add(companyName);
            }
        }

        AccountLookup lookup = new AccountLookup();
        if (companyNames.isEmpty()) {
            return lookup;
        }

        for (Account accountRecord : [
            SELECT Id, Name, Type, Website
            FROM Account
            WHERE Name IN :companyNames
            LIMIT 2000
        ]) {
            lookup.byName.put(normalizeName(accountRecord.Name), accountRecord);

            String domain = normalizeDomain(accountRecord.Website);
            if (!String.isBlank(domain) && !lookup.byDomain.containsKey(domain)) {
                lookup.byDomain.put(domain, accountRecord);
            }
        }

        return lookup;
    }

    private static String generatePromptJson(Account rootAccount) {
        if (Test.isRunningTest()) {
            if (!String.isBlank(testPromptFailureMessage)) {
                throw new AuraHandledException(testPromptFailureMessage);
            }
            if (!String.isBlank(testPromptJson)) {
                return testPromptJson;
            }
        }

        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput generationInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            generationInput.inputParams = new Map<String, ConnectApi.WrappedValue>();

            ConnectApi.WrappedValue accountInput = new ConnectApi.WrappedValue();
            accountInput.value = new Map<String, String>{ 'id' => String.valueOf(rootAccount.Id) };
            generationInput.inputParams.put('Input:Account', accountInput);
            generationInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            generationInput.additionalConfig.applicationName = PROMPT_APPLICATION_NAME;
            generationInput.isPreview = false;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationOutput =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    PROMPT_TEMPLATE_DEVELOPER_NAME,
                    generationInput
                );

            if (generationOutput == null || generationOutput.generations == null || generationOutput.generations.isEmpty()) {
                String generationErrorMessage = extractGenerationError(generationOutput);
                if (!String.isBlank(generationErrorMessage)) {
                    throw new AuraHandledException('Prompt template generation error: ' + generationErrorMessage);
                }
                throw new AuraHandledException('Prompt template returned no generations.');
            }

            String responseText = generationOutput.generations[0].text;
            if (String.isBlank(responseText)) {
                throw new AuraHandledException('Prompt template returned empty text.');
            }

            return responseText;
        } catch (ConnectApi.ConnectApiException ex) {
            throw new AuraHandledException('Prompt template invocation failed: ' + ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Prompt template invocation failed: ' + ex.getMessage());
        }
    }

    private static Map<String, Object> parsePromptPayload(String rawPromptJson) {
        if (String.isBlank(rawPromptJson)) {
            throw new AuraHandledException('Prompt template returned empty JSON.');
        }

        try {
            String sanitizedJson = sanitizePromptJson(rawPromptJson);
            Object payloadRaw = JSON.deserializeUntyped(sanitizedJson);
            if (!(payloadRaw instanceof Map<String, Object>)) {
                throw new AuraHandledException('Prompt output is not a JSON object.');
            }
            return (Map<String, Object>)payloadRaw;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Prompt output is not valid JSON: ' + ex.getMessage());
        }
    }

    private static Integer normalizeMaxNodes(Integer requestedMaxNodes) {
        Integer normalized = requestedMaxNodes == null ? DEFAULT_MAX_NODES : requestedMaxNodes;
        if (normalized <= 0) {
            normalized = DEFAULT_MAX_NODES;
        }
        return Math.min(normalized, ABSOLUTE_MAX_NODES);
    }

    private static Account loadRootAccount(Id rootAccountId) {
        List<Account> rootAccounts = [
            SELECT Id, Name, Type, Website, Industry, Description, BillingCountry
            FROM Account
            WHERE Id = :rootAccountId
            LIMIT 1
        ];
        if (rootAccounts.isEmpty()) {
            throw new AuraHandledException('The requested account cannot be found or is not accessible.');
        }
        return rootAccounts[0];
    }

    private static void validateReadAccess() {
        if (!Schema.sObjectType.Account.isAccessible()) {
            throw new AuraHandledException('You do not have access to Account.');
        }

        assertFieldReadable(Account.Name, 'Account.Name');
        assertFieldReadable(Account.Type, 'Account.Type');
        assertFieldReadable(Account.Website, 'Account.Website');
        assertFieldReadable(Account.Industry, 'Account.Industry');
        assertFieldReadable(Account.Description, 'Account.Description');
        assertFieldReadable(Account.BillingCountry, 'Account.BillingCountry');
    }

    private static void assertFieldReadable(Schema.SObjectField fieldToken, String fieldPath) {
        if (!fieldToken.getDescribe().isAccessible()) {
            throw new AuraHandledException('You do not have field access: ' + fieldPath);
        }
    }

    private static List<Object> asList(Object rawValue) {
        return rawValue instanceof List<Object> ? (List<Object>)rawValue : null;
    }

    private static Map<String, Object> asMap(Object rawValue) {
        return rawValue instanceof Map<String, Object> ? (Map<String, Object>)rawValue : null;
    }

    private static Decimal toDecimal(Object rawValue) {
        if (rawValue == null) {
            return null;
        }

        if (rawValue instanceof Decimal) {
            return (Decimal)rawValue;
        }
        if (rawValue instanceof Integer) {
            return Decimal.valueOf(String.valueOf(rawValue));
        }
        if (rawValue instanceof Long) {
            return Decimal.valueOf(String.valueOf(rawValue));
        }
        if (rawValue instanceof Double) {
            return Decimal.valueOf(String.valueOf(rawValue));
        }

        String value = String.valueOf(rawValue);
        return String.isBlank(value) ? null : Decimal.valueOf(value);
    }

    private static String stringValue(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        String value = String.valueOf(rawValue).trim();
        return value == '' ? null : value;
    }

    private static String normalizeDirection(String directionValue) {
        String normalized = String.isBlank(directionValue) ? null : directionValue.trim().toUpperCase();
        return SUPPORTED_DIRECTIONS.contains(normalized) ? normalized : null;
    }

    private static String normalizeDomain(String urlOrDomain) {
        if (String.isBlank(urlOrDomain)) {
            return null;
        }

        String normalized = urlOrDomain.trim().toLowerCase();
        normalized = normalized.replace('https://', '');
        normalized = normalized.replace('http://', '');
        if (normalized.startsWith('www.')) {
            normalized = normalized.substring(4);
        }
        Integer slashIndex = normalized.indexOf('/');
        if (slashIndex > -1) {
            normalized = normalized.substring(0, slashIndex);
        }
        return String.isBlank(normalized) ? null : normalized;
    }

    private static String normalizeName(String companyName) {
        return String.isBlank(companyName) ? null : companyName.trim().toLowerCase();
    }

    private static String buildExternalNodeId(String seed) {
        String digest = EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(seed)));
        return 'ext-' + digest.substring(0, 20);
    }

    private static String buildEdgeId(String seed, Integer indexValue) {
        String digest = EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(seed + '|' + indexValue)));
        return 'edge-' + digest.substring(0, 20);
    }

    private static String buildNoteText(Map<String, Object> relationship) {
        List<Object> evidence = asList(relationship.get('evidence'));
        if (evidence != null && !evidence.isEmpty()) {
            String firstEvidence = stringValue(evidence[0]);
            if (!String.isBlank(firstEvidence)) {
                return firstEvidence;
            }
        }
        return String.isBlank(stringValue(relationship.get('relation_type')))
            ? 'AI 生成的候選供應鏈關係。'
            : '關係類型: ' + stringValue(relationship.get('relation_type'));
    }

    private static NodeDto buildDemoNode(
        Account accountRecord,
        String fallbackLabel,
        Boolean isRoot,
        Integer signedLevel,
        Integer upstreamDepth,
        Integer downstreamDepth,
        String relationshipDirection,
        String roleLabel,
        String noteText
    ) {
        NodeDto node = new NodeDto();
        node.accountId = accountRecord == null ? null : accountRecord.Id;
        node.id = node.accountId == null
            ? buildExternalNodeId('demo|' + fallbackLabel.toLowerCase())
            : String.valueOf(node.accountId);
        node.label = accountRecord == null ? fallbackLabel : accountRecord.Name;
        node.isRoot = isRoot;
        node.signedLevel = signedLevel;
        node.upstreamDepth = upstreamDepth;
        node.downstreamDepth = downstreamDepth;
        node.relationshipDirection = relationshipDirection;
        node.accountType = accountRecord == null ? null : accountRecord.Type;
        node.roleLabel = roleLabel;
        node.noteText = noteText;
        return node;
    }

    private class DemoNodeDefinition {
        String accountName;
        Integer signedLevel;
        Integer upstreamDepth;
        Integer downstreamDepth;
        String relationshipDirection;
        String roleLabel;
        String noteText;

        DemoNodeDefinition(
            String accountNameValue,
            Integer signedLevelValue,
            Integer upstreamDepthValue,
            Integer downstreamDepthValue,
            String relationshipDirectionValue,
            String roleLabelValue,
            String noteTextValue
        ) {
            accountName = accountNameValue;
            signedLevel = signedLevelValue;
            upstreamDepth = upstreamDepthValue;
            downstreamDepth = downstreamDepthValue;
            relationshipDirection = relationshipDirectionValue;
            roleLabel = roleLabelValue;
            noteText = noteTextValue;
        }
    }

    private class DemoEdgeDefinition {
        String sourceName;
        String targetName;
        String relationType;
        String direction;

        DemoEdgeDefinition(String sourceNameValue, String targetNameValue, String relationTypeValue, String directionValue) {
            sourceName = sourceNameValue;
            targetName = targetNameValue;
            relationType = relationTypeValue;
            direction = directionValue;
        }
    }

    private static String sanitizePromptJson(String rawPromptJson) {
        String candidate = rawPromptJson.trim().replace('\r', '');
        if (candidate.startsWith('```')) {
            Integer openingFenceEnd = candidate.indexOf('\n');
            if (openingFenceEnd > -1) {
                candidate = candidate.substring(openingFenceEnd + 1);
            }
            Integer closingFenceStart = candidate.lastIndexOf('```');
            if (closingFenceStart > -1) {
                candidate = candidate.substring(0, closingFenceStart);
            }
            candidate = candidate.trim();
        }

        Integer firstBrace = candidate.indexOf('{');
        Integer lastBrace = candidate.lastIndexOf('}');
        if (firstBrace > -1 && lastBrace > firstBrace) {
            candidate = candidate.substring(firstBrace, lastBrace + 1);
        }
        return candidate;
    }

    private static String extractGenerationError(ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationOutput) {
        if (generationOutput == null || generationOutput.generationErrors == null || generationOutput.generationErrors.isEmpty()) {
            return null;
        }

        Object firstError = generationOutput.generationErrors[0];
        if (firstError == null) {
            return null;
        }

        Map<String, Object> errorMap = (Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(firstError));
        String message = stringValue(errorMap.get('localizedErrorMessage'));
        if (String.isBlank(message)) {
            message = stringValue(errorMap.get('errorMessage'));
        }
        String messageCode = stringValue(errorMap.get('messageCode'));
        if (!String.isBlank(messageCode)) {
            message = String.isBlank(message) ? messageCode : (message + ' [' + messageCode + ']');
        }
        return message;
    }

    private class AccountLookup {
        Map<String, Account> byDomain = new Map<String, Account>();
        Map<String, Account> byName = new Map<String, Account>();
    }

    public class GraphResponse {
        @AuraEnabled public String rootId;
        @AuraEnabled public Boolean truncated;
        @AuraEnabled public Integer nodeCount;
        @AuraEnabled public Integer edgeCount;
        @AuraEnabled public String promptTemplateName;
        @AuraEnabled public String dataSource;
        @AuraEnabled public Datetime generatedAt;
        @AuraEnabled public String coverageNote;
        @AuraEnabled public List<NodeDto> nodes;
        @AuraEnabled public List<EdgeDto> edges;

        public GraphResponse() {
            truncated = false;
            nodeCount = 0;
            edgeCount = 0;
            nodes = new List<NodeDto>();
            edges = new List<EdgeDto>();
        }
    }

    public class NodeDto {
        @AuraEnabled public String id;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isRoot;
        @AuraEnabled public Integer upstreamDepth;
        @AuraEnabled public Integer downstreamDepth;
        @AuraEnabled public Integer signedLevel;
        @AuraEnabled public String accountType;
        @AuraEnabled public String relationshipDirection;
        @AuraEnabled public String roleLabel;
        @AuraEnabled public String noteText;
    }

    public class EdgeDto {
        @AuraEnabled public String id;
        @AuraEnabled public String sourceId;
        @AuraEnabled public String targetId;
        @AuraEnabled public String relationType;
        @AuraEnabled public String relationshipDirection;
    }
}
