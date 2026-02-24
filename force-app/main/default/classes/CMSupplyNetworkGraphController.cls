public with sharing class CMSupplyNetworkGraphController {
    private static final Integer DEFAULT_MAX_NODES = 150;
    private static final Integer ABSOLUTE_MAX_NODES = 500;
    private static final String DEMO_ROOT_ACCOUNT_NAME = 'quincy';
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
