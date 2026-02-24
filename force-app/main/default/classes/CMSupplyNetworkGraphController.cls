public with sharing class CMSupplyNetworkGraphController {
    private static final Integer DEFAULT_MAX_NODES = 150;
    private static final Integer ABSOLUTE_MAX_NODES = 500;
    private static final String DEMO_TEMPLATE_NAME = 'DEMO_QUINCY_V1';
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
    private static final Set<String> DEMO_ACCOUNT_NAME_KEYS = buildDemoAccountNameKeys();

    @AuraEnabled(cacheable=false)
    public static GraphResponse getGraph(Id rootAccountId, Integer maxNodes) {
        if (rootAccountId == null) {
            throw new AuraHandledException('rootAccountId is required.');
        }

        validateReadAccess();

        Integer nodeCap = normalizeMaxNodes(maxNodes);
        Account rootAccount = loadRootAccount(rootAccountId);
        if (!isDemoAccount(rootAccount)) {
            return buildNonDemoResponse(rootAccount);
        }
        return buildDemoGraphResponse(rootAccount, nodeCap);
    }

    private static Boolean isDemoAccount(Account rootAccount) {
        return DEMO_ACCOUNT_NAME_KEYS.contains(normalizeName(rootAccount.Name));
    }

    private static GraphResponse buildNonDemoResponse(Account rootAccount) {
        GraphResponse response = new GraphResponse();
        response.rootId = String.valueOf(rootAccount.Id);
        response.promptTemplateName = DEMO_TEMPLATE_NAME;
        response.dataSource = 'DEMO_FIXED';
        response.generatedAt = Datetime.now();
        response.coverageNote = '此版本為固定 Demo 供應鏈圖。請切換到 Demo 清單內帳戶查看完整上下游關係。';

        NodeDto rootNode = buildDemoNode(
            rootAccount,
            rootAccount.Name,
            true,
            0,
            0,
            0,
            'ROOT',
            '目前帳戶',
            '此帳戶不在 Demo 清單中。'
        );
        response.nodes.add(rootNode);
        response.nodeCount = response.nodes.size();
        response.edgeCount = 0;
        return response;
    }

    private static GraphResponse buildDemoGraphResponse(Account rootAccount, Integer nodeCap) {
        GraphResponse response = new GraphResponse();
        response.rootId = String.valueOf(rootAccount.Id);
        response.promptTemplateName = DEMO_TEMPLATE_NAME;
        response.dataSource = 'DEMO_FIXED';
        response.generatedAt = Datetime.now();

        Map<String, Account> accountByNameKey = new Map<String, Account>();
        for (Account accountRecord : [
            SELECT Id, Name, Type
            FROM Account
            WHERE Name IN :DEMO_ACCOUNT_NAMES
            LIMIT 2000
        ]) {
            accountByNameKey.put(normalizeName(accountRecord.Name), accountRecord);
        }

        List<DemoNodeDefinition> nodeDefinitions = getDemoNodeDefinitions();
        List<DemoEdgeDefinition> edgeDefinitions = getDemoEdgeDefinitions();
        Map<String, DemoNodeDefinition> nodeDefinitionByNameKey = new Map<String, DemoNodeDefinition>();
        for (DemoNodeDefinition nodeDefinition : nodeDefinitions) {
            nodeDefinitionByNameKey.put(normalizeName(nodeDefinition.accountName), nodeDefinition);
        }

        Map<String, List<String>> outgoingByNode = new Map<String, List<String>>();
        Map<String, List<String>> incomingByNode = new Map<String, List<String>>();
        Set<String> allNodeNameKeys = new Set<String>();
        for (DemoNodeDefinition nodeDefinition : nodeDefinitions) {
            String nameKey = normalizeName(nodeDefinition.accountName);
            allNodeNameKeys.add(nameKey);
            outgoingByNode.put(nameKey, new List<String>());
            incomingByNode.put(nameKey, new List<String>());
        }
        for (DemoEdgeDefinition edgeDefinition : edgeDefinitions) {
            String sourceNameKey = normalizeName(edgeDefinition.sourceName);
            String targetNameKey = normalizeName(edgeDefinition.targetName);
            allNodeNameKeys.add(sourceNameKey);
            allNodeNameKeys.add(targetNameKey);
            if (!outgoingByNode.containsKey(sourceNameKey)) {
                outgoingByNode.put(sourceNameKey, new List<String>());
            }
            if (!incomingByNode.containsKey(targetNameKey)) {
                incomingByNode.put(targetNameKey, new List<String>());
            }
            if (!incomingByNode.containsKey(sourceNameKey)) {
                incomingByNode.put(sourceNameKey, new List<String>());
            }
            if (!outgoingByNode.containsKey(targetNameKey)) {
                outgoingByNode.put(targetNameKey, new List<String>());
            }
            outgoingByNode.get(sourceNameKey).add(targetNameKey);
            incomingByNode.get(targetNameKey).add(sourceNameKey);
        }

        String rootNameKey = normalizeName(rootAccount.Name);
        Map<String, Integer> downstreamDistanceByNode = computeShortestDistance(outgoingByNode, rootNameKey);
        Map<String, Integer> upstreamDistanceByNode = computeShortestDistance(incomingByNode, rootNameKey);

        Set<String> includedNameKeys = new Set<String>{ rootNameKey };
        for (String nameKey : allNodeNameKeys) {
            if (downstreamDistanceByNode.containsKey(nameKey) || upstreamDistanceByNode.containsKey(nameKey)) {
                includedNameKeys.add(nameKey);
            }
        }

        Map<String, Integer> signedLevelByNameKey = new Map<String, Integer>();
        for (String nameKey : includedNameKeys) {
            if (nameKey == rootNameKey) {
                signedLevelByNameKey.put(nameKey, 0);
                continue;
            }
            Integer downstreamDistance = downstreamDistanceByNode.get(nameKey);
            Integer upstreamDistance = upstreamDistanceByNode.get(nameKey);
            if (downstreamDistance == null && upstreamDistance == null) {
                continue;
            }
            if (downstreamDistance != null && upstreamDistance == null) {
                signedLevelByNameKey.put(nameKey, downstreamDistance);
                continue;
            }
            if (upstreamDistance != null && downstreamDistance == null) {
                signedLevelByNameKey.put(nameKey, -upstreamDistance);
                continue;
            }
            signedLevelByNameKey.put(nameKey, downstreamDistance <= upstreamDistance ? downstreamDistance : -upstreamDistance);
        }

        List<String> orderedNodeKeys = new List<String>();
        orderedNodeKeys.addAll(signedLevelByNameKey.keySet());
        orderedNodeKeys.sort(new NodeDistanceComparator(signedLevelByNameKey, nodeDefinitionByNameKey, accountByNameKey));

        Map<String, NodeDto> nodeByNameKey = new Map<String, NodeDto>();
        NodeDto rootNode = buildDemoNode(
            rootAccount,
            rootAccount.Name,
            true,
            0,
            0,
            0,
            'ROOT',
            nodeDefinitionByNameKey.containsKey(rootNameKey) ? nodeDefinitionByNameKey.get(rootNameKey).roleLabel : '核心節點',
            '固定 Demo 供應鏈主節點。'
        );
        nodeByNameKey.put(rootNameKey, rootNode);

        for (String nameKey : orderedNodeKeys) {
            if (nameKey == rootNameKey) {
                continue;
            }
            if (nodeByNameKey.size() >= nodeCap) {
                response.truncated = true;
                break;
            }

            Integer signedLevel = signedLevelByNameKey.get(nameKey);
            if (signedLevel == null) {
                continue;
            }

            DemoNodeDefinition nodeDefinition = nodeDefinitionByNameKey.get(nameKey);
            Account matchedAccount = accountByNameKey.get(nameKey);
            String fallbackLabel = matchedAccount == null
                ? (nodeDefinition == null ? nameKey : nodeDefinition.accountName)
                : matchedAccount.Name;
            Integer upstreamDepth = signedLevel < 0 ? Math.abs(signedLevel) : null;
            Integer downstreamDepth = signedLevel > 0 ? signedLevel : null;
            String relationshipDirection = signedLevel < 0 ? 'UPSTREAM' : 'DOWNSTREAM';
            NodeDto node = buildDemoNode(
                matchedAccount,
                fallbackLabel,
                false,
                signedLevel,
                upstreamDepth,
                downstreamDepth,
                relationshipDirection,
                nodeDefinition == null ? '關聯節點' : nodeDefinition.roleLabel,
                nodeDefinition == null ? '固定 Demo 供應鏈節點。' : nodeDefinition.noteText
            );
            nodeByNameKey.put(nameKey, node);
        }

        Integer edgeIndex = 0;
        for (DemoEdgeDefinition edgeDefinition : edgeDefinitions) {
            String sourceNameKey = normalizeName(edgeDefinition.sourceName);
            String targetNameKey = normalizeName(edgeDefinition.targetName);
            NodeDto sourceNode = nodeByNameKey.get(sourceNameKey);
            NodeDto targetNode = nodeByNameKey.get(targetNameKey);
            if (sourceNode == null || targetNode == null) {
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
        for (NodeDto node : nodeByNameKey.values()) {
            if (!node.isRoot && node.accountId == null) {
                missingAccounts.add(node.label);
            }
        }

        response.coverageNote = missingAccounts.isEmpty()
            ? '固定 Demo 供應鏈圖：以 ' + rootAccount.Name + ' 為核心顯示上下游關係。'
            : '固定 Demo 圖已載入，但以下節點缺少 Account 無法點擊：' + String.join(missingAccounts, '、');
        response.nodes.addAll(nodeByNameKey.values());
        response.nodeCount = response.nodes.size();
        response.edgeCount = response.edges.size();
        return response;
    }

    private static Set<String> buildDemoAccountNameKeys() {
        Set<String> nameKeys = new Set<String>();
        for (String accountName : DEMO_ACCOUNT_NAMES) {
            nameKeys.add(normalizeName(accountName));
        }
        return nameKeys;
    }

    private static List<DemoNodeDefinition> getDemoNodeDefinitions() {
        return new List<DemoNodeDefinition>{
            new DemoNodeDefinition('Quincy', 'IC 設計原廠', '核心設計與平台供應節點。'),
            new DemoNodeDefinition('TSMC', '晶圓代工 (Foundry)', '提供先進製程晶圓代工服務。'),
            new DemoNodeDefinition('ASE', '封裝與測試 (OSAT)', '提供封裝與測試能力。'),
            new DemoNodeDefinition('Amkor', '封裝與測試 (OSAT)', '支援後段封裝與測試產能。'),
            new DemoNodeDefinition('WPG', 'IC 通路代理商', '提供通路供貨與 FAE 支援。'),
            new DemoNodeDefinition('WT Microelectronics', 'IC 通路代理商', '提供通路供貨與技術服務。'),
            new DemoNodeDefinition('WNC', '網通與車用設備 ODM/JDM', '負責系統整合與最終組裝。'),
            new DemoNodeDefinition('Verizon', '電信營運商', '5G FWA 家用路由器導入客戶。'),
            new DemoNodeDefinition('AT&T', '電信營運商', '5G FWA 家用路由器導入客戶。'),
            new DemoNodeDefinition('T-Mobile US', '電信營運商', '5G FWA 家用路由器導入客戶。'),
            new DemoNodeDefinition('Ford', '車廠客戶', '車聯網模組導入客戶。'),
            new DemoNodeDefinition('General Motors', '車廠客戶', '車聯網模組導入客戶。')
        };
    }

    private static List<DemoEdgeDefinition> getDemoEdgeDefinitions() {
        return new List<DemoEdgeDefinition>{
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
    }

    private static Map<String, Integer> computeShortestDistance(Map<String, List<String>> adjacencyByNode, String rootNameKey) {
        Map<String, Integer> distanceByNode = new Map<String, Integer>();
        if (String.isBlank(rootNameKey) || !adjacencyByNode.containsKey(rootNameKey)) {
            return distanceByNode;
        }

        List<String> pendingNodes = new List<String>{ rootNameKey };
        distanceByNode.put(rootNameKey, 0);

        Integer index = 0;
        while (index < pendingNodes.size()) {
            String currentNode = pendingNodes[index];
            Integer currentDistance = distanceByNode.get(currentNode);
            index++;

            List<String> neighborNodes = adjacencyByNode.get(currentNode);
            if (neighborNodes == null) {
                continue;
            }
            for (String neighborNode : neighborNodes) {
                if (distanceByNode.containsKey(neighborNode)) {
                    continue;
                }
                distanceByNode.put(neighborNode, currentDistance + 1);
                pendingNodes.add(neighborNode);
            }
        }
        return distanceByNode;
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
            SELECT Id, Name, Type
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
    }

    private static void assertFieldReadable(Schema.SObjectField fieldToken, String fieldPath) {
        if (!fieldToken.getDescribe().isAccessible()) {
            throw new AuraHandledException('You do not have field access: ' + fieldPath);
        }
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
        String roleLabel;
        String noteText;

        DemoNodeDefinition(
            String accountNameValue,
            String roleLabelValue,
            String noteTextValue
        ) {
            accountName = accountNameValue;
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

    private class NodeDistanceComparator implements System.Comparator<String> {
        private Map<String, Integer> signedLevelByNameKey;
        private Map<String, DemoNodeDefinition> nodeDefinitionByNameKey;
        private Map<String, Account> accountByNameKey;

        NodeDistanceComparator(
            Map<String, Integer> signedLevelByNameKeyValue,
            Map<String, DemoNodeDefinition> nodeDefinitionByNameKeyValue,
            Map<String, Account> accountByNameKeyValue
        ) {
            signedLevelByNameKey = signedLevelByNameKeyValue;
            nodeDefinitionByNameKey = nodeDefinitionByNameKeyValue;
            accountByNameKey = accountByNameKeyValue;
        }

        public Integer compare(String leftNameKey, String rightNameKey) {
            Integer leftLevel = signedLevelByNameKey.get(leftNameKey);
            Integer rightLevel = signedLevelByNameKey.get(rightNameKey);
            Integer leftAbs = leftLevel == null ? 99999 : Math.abs(leftLevel);
            Integer rightAbs = rightLevel == null ? 99999 : Math.abs(rightLevel);
            if (leftAbs != rightAbs) {
                return leftAbs < rightAbs ? -1 : 1;
            }

            String leftLabel = resolveLabel(leftNameKey);
            String rightLabel = resolveLabel(rightNameKey);
            return leftLabel.toLowerCase().compareTo(rightLabel.toLowerCase());
        }

        private String resolveLabel(String nameKey) {
            if (accountByNameKey.containsKey(nameKey)) {
                return accountByNameKey.get(nameKey).Name;
            }
            if (nodeDefinitionByNameKey.containsKey(nameKey)) {
                return nodeDefinitionByNameKey.get(nameKey).accountName;
            }
            return nameKey;
        }
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
