@IsTest
private class CMSupplyNetworkGraphControllerTest {
    @TestSetup
    static void setupDemoAccounts() {
        List<Account> demoAccounts = new List<Account>{
            new Account(Name = 'Quincy', Website = 'https://www.quincy.com'),
            new Account(Name = 'TSMC', Website = 'https://www.tsmc.com'),
            new Account(Name = 'ASE', Website = 'https://www.aseglobal.com'),
            new Account(Name = 'Amkor', Website = 'https://www.amkor.com'),
            new Account(Name = 'WPG', Website = 'https://www.wpgholdings.com'),
            new Account(Name = 'WT Microelectronics', Website = 'https://www.wtmec.com'),
            new Account(Name = 'WNC', Website = 'https://www.wnc.com.tw'),
            new Account(Name = 'Verizon', Website = 'https://www.verizon.com'),
            new Account(Name = 'AT&T', Website = 'https://www.att.com'),
            new Account(Name = 'T-Mobile US', Website = 'https://www.t-mobile.com'),
            new Account(Name = 'Ford', Website = 'https://www.ford.com'),
            new Account(Name = 'General Motors', Website = 'https://www.gm.com'),
            new Account(Name = 'Non-Demo Account', Website = 'https://www.example.com')
        };
        insert demoAccounts;
    }

    @IsTest
    static void getGraph_quincyReturnsFixedDemoGraph() {
        Account quincy = [SELECT Id, Name FROM Account WHERE Name = 'Quincy' LIMIT 1];

        Test.startTest();
        CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(quincy.Id, 30);
        Test.stopTest();

        System.assertEquals('DEMO_FIXED', response.dataSource);
        System.assertEquals('DEMO_QUINCY_V1', response.promptTemplateName);
        System.assertEquals(false, response.truncated);
        System.assertEquals(12, response.nodeCount, 'Quincy fixed demo should include 12 nodes.');
        System.assertEquals(12, response.edgeCount, 'Quincy fixed demo should include 12 edges.');

        Map<String, CMSupplyNetworkGraphController.NodeDto> nodeByLabel = mapNodesByLabel(response.nodes);
        System.assertEquals(quincy.Id, nodeByLabel.get('Quincy').accountId);
        System.assertEquals(-1, nodeByLabel.get('TSMC').signedLevel);
        System.assertEquals(2, nodeByLabel.get('WNC').signedLevel);
        System.assertEquals(3, nodeByLabel.get('Verizon').signedLevel);
        System.assertEquals(true, nodeByLabel.get('WNC').accountId != null, 'Demo nodes should resolve to Account Id for click-through.');
    }

    @IsTest
    static void getGraph_appliesNodeLimitAndTruncates() {
        Account quincy = [SELECT Id FROM Account WHERE Name = 'Quincy' LIMIT 1];

        Test.startTest();
        CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(quincy.Id, 5);
        Test.stopTest();

        System.assertEquals(true, response.truncated, 'Response should indicate truncation when maxNodes is reached.');
        System.assertEquals(5, response.nodeCount, 'Node count should respect the requested maxNodes value.');
        System.assert(response.edgeCount <= 4, 'Edges should only include retained nodes.');
    }

    @IsTest
    static void getGraph_nonQuincyReturnsRootOnlyDemoHint() {
        Account nonDemo = [SELECT Id, Name FROM Account WHERE Name = 'Non-Demo Account' LIMIT 1];

        Test.startTest();
        CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(nonDemo.Id, 20);
        Test.stopTest();

        System.assertEquals('DEMO_FIXED', response.dataSource);
        System.assertEquals(1, response.nodeCount);
        System.assertEquals(0, response.edgeCount);
        System.assert(response.coverageNote.contains('Demo'));
    }

    @IsTest
    static void getGraph_demoMemberReturnsRelationshipGraph() {
        Account wnc = [SELECT Id, Name FROM Account WHERE Name = 'WNC' LIMIT 1];

        Test.startTest();
        CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(wnc.Id, 30);
        Test.stopTest();

        System.assertEquals('DEMO_FIXED', response.dataSource);
        System.assertEquals(12, response.nodeCount, 'Demo member should still see full demo relationship graph.');
        System.assertEquals(12, response.edgeCount);

        Map<String, CMSupplyNetworkGraphController.NodeDto> nodeByLabel = mapNodesByLabel(response.nodes);
        System.assertEquals(true, nodeByLabel.containsKey('Quincy'));
        System.assertEquals(true, nodeByLabel.containsKey('Verizon'));
        System.assertEquals(true, nodeByLabel.containsKey('TSMC'));
        System.assertEquals(0, nodeByLabel.get('WNC').signedLevel);
        System.assertEquals(-2, nodeByLabel.get('Quincy').signedLevel, 'Upstream nodes should become negative levels from current root.');
        System.assertEquals(1, nodeByLabel.get('Verizon').signedLevel, 'Direct downstream from current root should be level 1.');
        System.assertEquals(-3, nodeByLabel.get('TSMC').signedLevel, 'Farther upstream should have deeper negative levels.');
    }

    @IsTest
    static void getGraph_throwsWhenRootIsMissing() {
        Boolean didThrow = false;

        Test.startTest();
        try {
            CMSupplyNetworkGraphController.getGraph(null, 10);
        } catch (Exception ex) {
            didThrow = true;
        }
        Test.stopTest();

        System.assertEquals(true, didThrow, 'Method should enforce rootAccountId input.');
    }

    private static Map<String, CMSupplyNetworkGraphController.NodeDto> mapNodesByLabel(
        List<CMSupplyNetworkGraphController.NodeDto> nodes
    ) {
        Map<String, CMSupplyNetworkGraphController.NodeDto> nodeByLabel = new Map<String, CMSupplyNetworkGraphController.NodeDto>();
        for (CMSupplyNetworkGraphController.NodeDto node : nodes) {
            nodeByLabel.put(node.label, node);
        }
        return nodeByLabel;
    }
}
