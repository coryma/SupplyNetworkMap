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
      new Account(
        Name = 'WT Microelectronics',
        Website = 'https://www.wtmec.com'
      ),
      new Account(Name = 'WNC', Website = 'https://www.wnc.com.tw'),
      new Account(Name = 'Verizon', Website = 'https://www.verizon.com'),
      new Account(Name = 'AT&T', Website = 'https://www.att.com'),
      new Account(Name = 'T-Mobile US', Website = 'https://www.t-mobile.com'),
      new Account(Name = 'Ford', Website = 'https://www.ford.com'),
      new Account(Name = 'General Motors', Website = 'https://www.gm.com'),
      new Account(
        Name = 'Non-Demo Account',
        Website = 'https://www.example.com'
      )
    };
    insert demoAccounts;

    Map<String, Account> accountByName = new Map<String, Account>();
    for (Account accountRecord : [
      SELECT Id, Name
      FROM Account
      WHERE
        Name IN (
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
        )
    ]) {
      accountByName.put(accountRecord.Name, accountRecord);
    }

    insert new List<CM_Supply_Relationship__c>{
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('TSMC').Id,
        Target_Account__c = accountByName.get('Quincy').Id,
        Edge_Category__c = 'DOWNSTREAM',
        Relation_Type__c = 'Foundry',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('ASE').Id,
        Target_Account__c = accountByName.get('Quincy').Id,
        Edge_Category__c = 'DOWNSTREAM',
        Relation_Type__c = 'OSAT',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('Amkor').Id,
        Target_Account__c = accountByName.get('Quincy').Id,
        Edge_Category__c = 'DOWNSTREAM',
        Relation_Type__c = 'OSAT',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('Quincy').Id,
        Target_Account__c = accountByName.get('WPG').Id,
        Edge_Category__c = 'DOWNSTREAM',
        Relation_Type__c = 'Distributor',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('Quincy').Id,
        Target_Account__c = accountByName.get('WT Microelectronics').Id,
        Edge_Category__c = 'DOWNSTREAM',
        Relation_Type__c = 'Distributor',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('WPG').Id,
        Target_Account__c = accountByName.get('WNC').Id,
        Edge_Category__c = 'INDIRECT_PATH',
        Relation_Type__c = 'Channel Partner',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('WT Microelectronics').Id,
        Target_Account__c = accountByName.get('WNC').Id,
        Edge_Category__c = 'INDIRECT_PATH',
        Relation_Type__c = 'Channel Partner',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('WNC').Id,
        Target_Account__c = accountByName.get('Verizon').Id,
        Edge_Category__c = 'INDIRECT_PATH',
        Relation_Type__c = 'Telecom Operator',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('WNC').Id,
        Target_Account__c = accountByName.get('AT&T').Id,
        Edge_Category__c = 'INDIRECT_PATH',
        Relation_Type__c = 'Telecom Operator',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('WNC').Id,
        Target_Account__c = accountByName.get('T-Mobile US').Id,
        Edge_Category__c = 'INDIRECT_PATH',
        Relation_Type__c = 'Telecom Operator',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('WNC').Id,
        Target_Account__c = accountByName.get('Ford').Id,
        Edge_Category__c = 'INDIRECT_PATH',
        Relation_Type__c = 'Automaker',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = accountByName.get('WNC').Id,
        Target_Account__c = accountByName.get('General Motors').Id,
        Edge_Category__c = 'INDIRECT_PATH',
        Relation_Type__c = 'Automaker',
        Is_Active__c = true
      )
    };
  }

  @IsTest
  static void getGraph_quincyReturnsFixedDemoGraph() {
    Account quincy = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Quincy'
      LIMIT 1
    ];

    Test.startTest();
    CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(
      quincy.Id,
      30
    );
    Test.stopTest();

    System.assertEquals('MANUAL_RELATIONSHIP', response.dataSource);
    System.assertEquals(
      'CM_MANUAL_RELATIONSHIP_V1',
      response.promptTemplateName
    );
    System.assertEquals(false, response.truncated);
    System.assertEquals(
      12,
      response.nodeCount,
      'Quincy fixed demo should include 12 nodes.'
    );
    System.assertEquals(
      12,
      response.edgeCount,
      'Quincy fixed demo should include 12 edges.'
    );

    Map<String, CMSupplyNetworkGraphController.NodeDto> nodeByLabel = mapNodesByLabel(
      response.nodes
    );
    System.assertEquals(quincy.Id, nodeByLabel.get('Quincy').accountId);
    System.assertEquals(-1, nodeByLabel.get('TSMC').signedLevel);
    System.assertEquals(2, nodeByLabel.get('WNC').signedLevel);
    System.assertEquals(3, nodeByLabel.get('Verizon').signedLevel);
    System.assertEquals(
      true,
      nodeByLabel.get('WNC').accountId != null,
      'Demo nodes should resolve to Account Id for click-through.'
    );
  }

  @IsTest
  static void getGraph_appliesNodeLimitAndTruncates() {
    Account quincy = [SELECT Id FROM Account WHERE Name = 'Quincy' LIMIT 1];

    Test.startTest();
    CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(
      quincy.Id,
      5
    );
    Test.stopTest();

    System.assertEquals(
      true,
      response.truncated,
      'Response should indicate truncation when maxNodes is reached.'
    );
    System.assertEquals(
      5,
      response.nodeCount,
      'Node count should respect the requested maxNodes value.'
    );
    System.assert(
      response.edgeCount <= 4,
      'Edges should only include retained nodes.'
    );
  }

  @IsTest
  static void getGraph_nonQuincyReturnsRootOnlyDemoHint() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];

    Test.startTest();
    CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(
      nonDemo.Id,
      20,
      false,
      'FWA_5G'
    );
    Test.stopTest();

    System.assertEquals('MANUAL_RELATIONSHIP', response.dataSource);
    System.assertEquals(1, response.nodeCount);
    System.assertEquals(0, response.edgeCount);
    System.assert(response.coverageNote.contains('手動模式'));
  }

  @IsTest
  static void getGraph_demoMemberReturnsRelationshipGraph() {
    Account wnc = [SELECT Id, Name FROM Account WHERE Name = 'WNC' LIMIT 1];

    Test.startTest();
    CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(
      wnc.Id,
      30
    );
    Test.stopTest();

    System.assertEquals('MANUAL_RELATIONSHIP', response.dataSource);
    System.assertEquals(
      12,
      response.nodeCount,
      'Demo member should still see full demo relationship graph.'
    );
    System.assertEquals(12, response.edgeCount);

    Map<String, CMSupplyNetworkGraphController.NodeDto> nodeByLabel = mapNodesByLabel(
      response.nodes
    );
    System.assertEquals(true, nodeByLabel.containsKey('Quincy'));
    System.assertEquals(true, nodeByLabel.containsKey('Verizon'));
    System.assertEquals(true, nodeByLabel.containsKey('TSMC'));
    System.assertEquals(0, nodeByLabel.get('WNC').signedLevel);
    System.assertEquals(
      -2,
      nodeByLabel.get('Quincy').signedLevel,
      'Upstream nodes should become negative levels from current root.'
    );
    System.assertEquals(
      1,
      nodeByLabel.get('Verizon').signedLevel,
      'Direct downstream from current root should be level 1.'
    );
    System.assertEquals(
      -3,
      nodeByLabel.get('TSMC').signedLevel,
      'Farther upstream should have deeper negative levels.'
    );
  }

  @IsTest
  static void getGraph_autoPromptEnabled_buildsGraphFromPromptJson() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    CMSupplyNetworkGraphController.testPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testPromptJson =
      '{' +
      '"schema_version":"3.0",' +
      '"relationships":[' +
      '{"source_company_name":"TSMC","source_company_domain":"tsmc.com","target_company_name":"Non-Demo Account","target_company_domain":"example.com","edge_category":"UPSTREAM","relation_type":"Foundry","role":"晶圓代工合作夥伴","confidence":0.99,"source_type":"PUBLIC_INFO","evidence":["台積電為主要代工夥伴。"],"is_focus_company_path":false},' +
      '{"source_company_name":"Non-Demo Account","source_company_domain":"example.com","target_company_name":"Qualcomm","target_company_domain":"qualcomm.com","edge_category":"DOWNSTREAM","relation_type":"Customer","role":"下游客戶","confidence":0.95,"source_type":"PUBLIC_INFO","evidence":["核心客戶採用晶片。"],"is_focus_company_path":false},' +
      '{"source_company_name":"Qualcomm","source_company_domain":"qualcomm.com","target_company_name":"WNC","target_company_domain":"wnc.com.tw","edge_category":"INDIRECT_PATH","relation_type":"Component Supply","market_risk_note":"WNC 需求波動風險","role":"間接供應鏈路徑","confidence":0.93,"source_type":"INFERRED","evidence":["透過多階供應鏈路徑連結 WNC。"],"is_focus_company_path":true},' +
      '{"source_company_name":"MediaTek","source_company_domain":"mediatek.com","target_company_name":"WNC","target_company_domain":"wnc.com.tw","edge_category":"INDIRECT_PATH","relation_type":"Component Supply","market_risk_note":"替代供應壓力","role":"間接供應鏈路徑","confidence":0.90,"source_type":"INFERRED","evidence":["聯發科亦提供 WNC 晶片方案。"],"is_focus_company_path":true},' +
      '{"source_company_name":"Non-Demo Account","source_company_domain":"example.com","target_company_name":"Amkor","target_company_domain":"amkor.com","edge_category":"COMPETITOR","relation_type":"Direct Competitor","role":"主要競爭對手","confidence":0.98,"source_type":"PUBLIC_INFO","evidence":["在封測服務存在直接競爭。"],"is_focus_company_path":false},' +
      '{"source_company_name":"Non-Demo Account","source_company_domain":"example.com","target_company_name":"Low Confidence","target_company_domain":"low.example","edge_category":"DOWNSTREAM","relation_type":"Customer","role":"低信心測試","confidence":0.12,"source_type":"INFERRED","evidence":["低於門檻應過濾。"],"is_focus_company_path":false}' +
      '],' +
      '"summary":{"coverage_note":"Prompt 測試覆蓋摘要"}' +
      '}';

    Test.startTest();
    CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(
      nonDemo.Id,
      20,
      true,
      'FWA_5G'
    );
    Test.stopTest();

    CMSupplyNetworkGraphController.testPromptJson = null;

    System.assertEquals('MANUAL_RELATIONSHIP', response.dataSource);
    System.assertEquals(
      'CM_MANUAL_RELATIONSHIP_V1',
      response.promptTemplateName
    );
    System.assertEquals(false, response.truncated);
    System.assert(
      response.nodeCount >= 6,
      'Should include prompt-derived nodes in the rendered graph.'
    );
    System.assert(
      response.edgeCount >= 5,
      'Should include prompt-derived edges in the rendered graph.'
    );
    System.assert(
      response.coverageNote != null &&
      response.coverageNote.contains('手動模式')
    );

    Map<String, CMSupplyNetworkGraphController.NodeDto> nodeByLabel = mapNodesByLabel(
      response.nodes
    );
    System.assertEquals(
      nonDemo.Id,
      nodeByLabel.get('Non-Demo Account').accountId
    );
    System.assert(
      nodeByLabel.get('TSMC').signedLevel < 0,
      'TSMC should be classified into upstream tiers.'
    );
    System.assert(
      nodeByLabel.get('Qualcomm').signedLevel > 0,
      'Qualcomm should be classified into downstream tiers.'
    );
    System.assert(
      nodeByLabel.get('WNC').signedLevel != 0,
      'WNC should not collapse into the root level.'
    );
    System.assertEquals(true, nodeByLabel.containsKey('MediaTek'));
    System.assert(
      nodeByLabel.get('MediaTek').signedLevel != 0,
      'MediaTek should be placed into a non-root tier.'
    );
    System.assertEquals(
      'COMPETITOR',
      nodeByLabel.get('Amkor').relationshipDirection
    );
    System.assert(
      nodeByLabel.get('TSMC').accountId != null,
      'TSMC should resolve to Account for click-through.'
    );
    System.assert(
      nodeByLabel.get('WNC').accountId != null,
      'WNC should resolve to Account for click-through.'
    );
    System.assertEquals(false, nodeByLabel.containsKey('Low Confidence'));

    String qualcommNodeId = nodeByLabel.get('Qualcomm').id;
    String wncNodeId = nodeByLabel.get('WNC').id;
    CMSupplyNetworkGraphController.EdgeDto qualcommToWncEdge;
    for (CMSupplyNetworkGraphController.EdgeDto edge : response.edges) {
      if (edge.sourceId == qualcommNodeId && edge.targetId == wncNodeId) {
        qualcommToWncEdge = edge;
        break;
      }
    }
    System.assertNotEquals(
      null,
      qualcommToWncEdge,
      'Expected the Qualcomm -> WNC edge to be present.'
    );
    System.assertEquals('INDIRECT_PATH', qualcommToWncEdge.edgeCategory);

    Account persistedAccount = [
      SELECT CM_Supply_Network_Prompt_JSON__c
      FROM Account
      WHERE Id = :nonDemo.Id
      LIMIT 1
    ];
    System.assert(
      !String.isBlank(persistedAccount.CM_Supply_Network_Prompt_JSON__c),
      'Prompt JSON should be stored on Account.'
    );
    System.assert(
      persistedAccount.CM_Supply_Network_Prompt_JSON__c.contains(
        '"schema_version":"3.0"'
      )
    );
  }

  @IsTest
  static void getGraph_autoPromptEnabled_throwsInvocationFailure() {
    Account nonDemo = [
      SELECT Id
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    CMSupplyNetworkGraphController.testPromptJson = null;
    CMSupplyNetworkGraphController.testPromptFailureMessage = 'Failed to generate Einstein LLM generations response';

    Boolean didThrow = false;
    String errorMessage;

    Test.startTest();
    try {
      CMSupplyNetworkGraphController.getGraph(nonDemo.Id, 20, true, 'FWA_5G');
    } catch (AuraHandledException ex) {
      didThrow = true;
      errorMessage = ex.getMessage();
    }
    Test.stopTest();

    CMSupplyNetworkGraphController.testPromptFailureMessage = null;

    System.assertEquals(
      true,
      didThrow,
      'Prompt invocation errors should surface to UI.'
    );
    System.assertEquals(
      true,
      !String.isBlank(errorMessage),
      'Expected an invocation failure message.'
    );
  }

  @IsTest
  static void getGraph_withoutScenarioReturnsManualResponseWithoutPromptInvocation() {
    Account nonDemo = [
      SELECT Id
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    CMSupplyNetworkGraphController.testPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testPromptJson = '{"schema_version":"3.0","relationships":[{"source_company_name":"TSMC","source_company_domain":"tsmc.com","target_company_name":"Non-Demo Account","target_company_domain":"example.com","edge_category":"UPSTREAM","relation_type":"Foundry","confidence":0.95,"source_type":"PUBLIC_INFO","evidence":["不應被執行"]}]}';

    Test.startTest();
    CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(
      nonDemo.Id,
      20,
      true,
      null
    );
    Test.stopTest();

    CMSupplyNetworkGraphController.testPromptJson = null;

    System.assertEquals('MANUAL_RELATIONSHIP', response.dataSource);
    System.assertEquals(1, response.nodeCount);
    System.assertEquals(0, response.edgeCount);
  }

  @IsTest
  static void getGraph_promptScopeFiltersOutUnrelatedHistoricalEdges() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    Account wnc = [SELECT Id FROM Account WHERE Name = 'WNC' LIMIT 1];

    Account qorvo = new Account(
      Name = 'Qorvo',
      Website = 'https://www.qorvo.com'
    );
    Account skyworks = new Account(
      Name = 'Skyworks',
      Website = 'https://www.skyworksinc.com'
    );
    insert new List<Account>{ qorvo, skyworks };

    insert new List<CM_Supply_Relationship__c>{
      new CM_Supply_Relationship__c(
        Source_Account__c = qorvo.Id,
        Target_Account__c = wnc.Id,
        Edge_Category__c = 'INDIRECT_PATH',
        Relation_Type__c = 'RF Supply',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = skyworks.Id,
        Target_Account__c = wnc.Id,
        Edge_Category__c = 'INDIRECT_PATH',
        Relation_Type__c = 'RF Supply',
        Is_Active__c = true
      )
    };

    CMSupplyNetworkGraphController.testPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testPromptJson =
      '{' +
      '"schema_version":"3.2",' +
      '"relationships":[' +
      '{"source_company_name":"TSMC","source_company_domain":"tsmc.com","target_company_name":"Non-Demo Account","target_company_domain":"example.com","edge_category":"UPSTREAM","relation_type":"Foundry","confidence":0.95,"source_type":"PUBLIC_INFO","evidence":["Prompt scope upstream"]},' +
      '{"source_company_name":"Non-Demo Account","source_company_domain":"example.com","target_company_name":"WNC","target_company_domain":"wnc.com.tw","edge_category":"DOWNSTREAM","relation_type":"Direct Customer","confidence":0.94,"source_type":"PUBLIC_INFO","evidence":["Prompt scope downstream"]},' +
      '{"source_company_name":"WNC","source_company_domain":"wnc.com.tw","target_company_name":"AT&T","target_company_domain":"att.com","edge_category":"INDIRECT_PATH","relation_type":"Telecom Operator","confidence":0.92,"source_type":"PUBLIC_INFO","evidence":["Prompt scope indirect"]}' +
      ']' +
      '}';

    Test.startTest();
    CMSupplyNetworkGraphController.SmartBuildResponse buildResult = CMSupplyNetworkGraphController.smartBuildRelationships(
      nonDemo.Id,
      30,
      'FULL_REBUILD',
      'FWA_5G'
    );
    CMSupplyNetworkGraphController.GraphResponse response = CMSupplyNetworkGraphController.getGraph(
      nonDemo.Id,
      30,
      false,
      'FWA_5G'
    );
    Test.stopTest();

    CMSupplyNetworkGraphController.testPromptJson = null;

    System.assertNotEquals(
      null,
      buildResult.graph,
      'Smart build should return graph payload.'
    );
    System.assertEquals('MANUAL_RELATIONSHIP', response.dataSource);

    Map<String, CMSupplyNetworkGraphController.NodeDto> nodeByLabel = mapNodesByLabel(
      response.nodes
    );
    System.assertEquals(true, nodeByLabel.containsKey('Non-Demo Account'));
    System.assertEquals(true, nodeByLabel.containsKey('TSMC'));
    System.assertEquals(true, nodeByLabel.containsKey('WNC'));
    System.assertEquals(true, nodeByLabel.containsKey('AT&T'));
    System.assertEquals(
      false,
      nodeByLabel.containsKey('Qorvo'),
      'Historical edge node should be excluded when not in prompt scope.'
    );
    System.assertEquals(
      false,
      nodeByLabel.containsKey('Skyworks'),
      'Historical edge node should be excluded when not in prompt scope.'
    );
  }

  @IsTest
  static void smartBuildRelationships_upsertPreservesExistingRelationships() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];

    CMSupplyNetworkGraphController.testPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testPromptJson =
      '{' +
      '"schema_version":"3.0",' +
      '"relationships":[' +
      '{"source_company_name":"TSMC","source_company_domain":"tsmc.com","target_company_name":"Non-Demo Account","target_company_domain":"example.com","edge_category":"UPSTREAM","relation_type":"Foundry","role":"第一次角色","products":["4nm Wafer"],"confidence":0.99,"source_type":"PUBLIC_INFO","evidence":["第一次證據"],"is_focus_company_path":false},' +
      '{"source_company_name":"Non-Demo Account","source_company_domain":"example.com","target_company_name":"ASE","target_company_domain":"aseglobal.com","edge_category":"DOWNSTREAM","relation_type":"Customer","role":"第一次下游","products":["封裝需求"],"confidence":0.91,"source_type":"PUBLIC_INFO","evidence":["第一次下游證據"],"is_focus_company_path":false}' +
      '],' +
      '"summary":{"coverage_note":"智能建立測試"}' +
      '}';

    Test.startTest();
    CMSupplyNetworkGraphController.SmartBuildResponse firstResult = CMSupplyNetworkGraphController.smartBuildRelationships(
      nonDemo.Id,
      30,
      'UPSERT',
      'FWA_5G'
    );

    System.assertEquals(
      'CM_Account_Supply_Network_Discovery',
      firstResult.promptTemplateName
    );
    System.assertEquals(2, firstResult.insertedCount);
    System.assertEquals(0, firstResult.updatedCount);
    System.assertEquals(true, firstResult.graph != null);
    System.assertEquals('MANUAL_RELATIONSHIP', firstResult.graph.dataSource);

    CMSupplyNetworkGraphController.testPromptJson =
      '{' +
      '"schema_version":"3.0",' +
      '"relationships":[' +
      '{"source_company_name":"TSMC","source_company_domain":"tsmc.com","target_company_name":"Non-Demo Account","target_company_domain":"example.com","edge_category":"UPSTREAM","relation_type":"Foundry","role":"更新後角色","products":["3nm Wafer"],"confidence":0.97,"source_type":"INFERRED","evidence":["更新後證據"],"is_focus_company_path":false},' +
      '{"source_company_name":"Non-Demo Account","source_company_domain":"example.com","target_company_name":"ASE","target_company_domain":"aseglobal.com","edge_category":"DOWNSTREAM","relation_type":"Customer","role":"更新後下游","products":["更新封裝需求"],"confidence":0.89,"source_type":"INFERRED","evidence":["更新下游證據"],"is_focus_company_path":false}' +
      '],' +
      '"summary":{"coverage_note":"智能建立測試更新"}' +
      '}';

    CMSupplyNetworkGraphController.SmartBuildResponse secondResult = CMSupplyNetworkGraphController.smartBuildRelationships(
      nonDemo.Id,
      30,
      'UPSERT',
      'FWA_5G'
    );
    Test.stopTest();

    CMSupplyNetworkGraphController.testPromptJson = null;

    System.assertEquals(0, secondResult.insertedCount);
    System.assertEquals(0, secondResult.updatedCount);
    System.assert(
      secondResult.skippedCount >= 2,
      'Upsert mode should preserve existing rows instead of overwriting.'
    );

    List<CM_Supply_Relationship__c> persistedRelationships = [
      SELECT
        Source_Account__r.Name,
        Target_Account__r.Name,
        Relation_Type__c,
        Role__c,
        Source_Type__c
      FROM CM_Supply_Relationship__c
      WHERE
        (Source_Account__r.Name = 'TSMC'
        AND Target_Account__r.Name = 'Non-Demo Account'
        AND Relation_Type__c = 'Foundry')
        OR (Source_Account__r.Name = 'Non-Demo Account'
        AND Target_Account__r.Name = 'ASE'
        AND Relation_Type__c = 'Customer')
    ];
    System.assertEquals(
      2,
      persistedRelationships.size(),
      'Smart build should persist two unique relationship records.'
    );
    for (
      CM_Supply_Relationship__c relationshipRecord : persistedRelationships
    ) {
      System.assertEquals('PUBLIC_INFO', relationshipRecord.Source_Type__c);
      System.assert(
        relationshipRecord.Role__c != null &&
        relationshipRecord.Role__c.startsWith('第一次')
      );
    }

    Account persistedAccount = [
      SELECT CM_Supply_Network_Prompt_JSON__c
      FROM Account
      WHERE Id = :nonDemo.Id
      LIMIT 1
    ];
    System.assert(
      !String.isBlank(persistedAccount.CM_Supply_Network_Prompt_JSON__c)
    );
  }

  @IsTest
  static void smartBuildRelationships_createsPlaceholderAccountsWhenMissing() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];

    CMSupplyNetworkGraphController.testPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testPromptJson =
      '{' +
      '"schema_version":"3.0",' +
      '"relationships":[' +
      '{"source_company_name":"Unknown Foundry Co","source_company_domain":"unknownfoundry.test","target_company_name":"Non-Demo Account","target_company_domain":"example.com","edge_category":"UPSTREAM","relation_type":"Foundry","role":"未知上游","products":["Wafer"],"confidence":0.90,"source_type":"PUBLIC_INFO","evidence":["測試證據"],"is_focus_company_path":false},' +
      '{"source_company_name":"Non-Demo Account","source_company_domain":"example.com","target_company_name":"Ghost ODM","target_company_domain":"ghostodm.test","edge_category":"DOWNSTREAM","relation_type":"ODM","role":"未知下游","products":["模組"],"confidence":0.91,"source_type":"PUBLIC_INFO","evidence":["測試證據"],"is_focus_company_path":false}' +
      '],' +
      '"summary":{"coverage_note":"placeholder測試"}' +
      '}';

    Test.startTest();
    CMSupplyNetworkGraphController.SmartBuildResponse result = CMSupplyNetworkGraphController.smartBuildRelationships(
      nonDemo.Id,
      30,
      'UPSERT',
      'FWA_5G'
    );
    Test.stopTest();
    CMSupplyNetworkGraphController.testPromptJson = null;

    System.assertEquals(
      2,
      result.insertedCount,
      'Two prompt edges should be persisted.'
    );

    List<Account> placeholders = [
      SELECT Id, Name, Website
      FROM Account
      WHERE Website IN ('https://unknownfoundry.test', 'https://ghostodm.test')
    ];
    System.assertEquals(
      2,
      placeholders.size(),
      'Missing companies should be auto-created as placeholder accounts.'
    );

    List<CM_Supply_Relationship__c> relationships = [
      SELECT Id, Source_Account__r.Website, Target_Account__r.Website
      FROM CM_Supply_Relationship__c
      WHERE
        (Source_Account__r.Website = 'https://unknownfoundry.test'
        AND Target_Account__r.Name = 'Non-Demo Account')
        OR (Source_Account__r.Name = 'Non-Demo Account'
        AND Target_Account__r.Website = 'https://ghostodm.test')
    ];
    System.assertEquals(
      2,
      relationships.size(),
      'Placeholder accounts should participate in saved relationship edges.'
    );
  }

  @IsTest
  static void smartBuildRelationships_fullRebuildDeactivatesRootDirectRelationships() {
    Account nonDemo = [
      SELECT Id
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    Account wpg = [SELECT Id FROM Account WHERE Name = 'WPG' LIMIT 1];

    CM_Supply_Relationship__c legacyDirect = new CM_Supply_Relationship__c(
      Source_Account__c = nonDemo.Id,
      Target_Account__c = wpg.Id,
      Edge_Category__c = 'DOWNSTREAM',
      Relation_Type__c = 'Legacy',
      Role__c = '舊資料',
      Source_Type__c = 'PUBLIC_INFO',
      Supply_Scenario__c = 'FWA_5G',
      Is_Active__c = true
    );
    insert legacyDirect;

    CMSupplyNetworkGraphController.testPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testPromptJson =
      '{' +
      '"schema_version":"3.0",' +
      '"relationships":[' +
      '{"source_company_name":"TSMC","source_company_domain":"tsmc.com","target_company_name":"Non-Demo Account","target_company_domain":"example.com","edge_category":"UPSTREAM","relation_type":"Foundry","role":"重繪上游","products":["Wafer"],"confidence":0.95,"source_type":"PUBLIC_INFO","evidence":["重繪測試"],"is_focus_company_path":false}' +
      '],' +
      '"summary":{"coverage_note":"full rebuild測試"}' +
      '}';

    Test.startTest();
    CMSupplyNetworkGraphController.SmartBuildResponse result = CMSupplyNetworkGraphController.smartBuildRelationships(
      nonDemo.Id,
      30,
      'FULL_REBUILD',
      'FWA_5G'
    );
    Test.stopTest();
    CMSupplyNetworkGraphController.testPromptJson = null;

    CM_Supply_Relationship__c refreshedLegacy = [
      SELECT Id, Is_Active__c
      FROM CM_Supply_Relationship__c
      WHERE Id = :legacyDirect.Id
      LIMIT 1
    ];

    System.assertEquals(
      'FULL_REBUILD',
      result.buildMode,
      'Expected full rebuild mode response.'
    );
    System.assert(
      result.deactivatedCount >= 1,
      'Full rebuild should deactivate existing direct relationships.'
    );
    System.assertEquals(
      false,
      refreshedLegacy.Is_Active__c,
      'Legacy direct relationship should be deactivated.'
    );
    System.assert(
      result.insertedCount >= 1,
      'Full rebuild should still insert prompt-derived relationships.'
    );
    System.assertEquals(
      true,
      result.graph != null,
      'Graph response should be returned after rebuild.'
    );
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

    System.assertEquals(
      true,
      didThrow,
      'Method should enforce rootAccountId input.'
    );
  }

  @IsTest
  static void analyzeWncImpact_returnsSummary() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    update new Account(
      Id = nonDemo.Id,
      CM_Supply_Network_Prompt_JSON__c = '{"schema_version":"3.0","analysis_scenario":{"code":"FWA_5G","label":"5G FWA"},"relationships":[{"source_company_name":"TSMC","target_company_name":"Qualcomm"}]}'
    );

    CMSupplyNetworkGraphController.testWncImpactPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testWncImpactPromptJson =
      '{' +
      '"analysis_version":"1.0",' +
      '"root_account":"Non-Demo Account",' +
      '"focus_company":"啟碁科技 WNC",' +
      '"impact_level":"HIGH",' +
      '"overall_assessment":"此供應鏈波動會直接影響 WNC 交期。",' +
      '"summary_for_ui":"WNC 對上游核心晶片供應依賴高，若關鍵代工或封測節點異常，將造成交期與成本壓力。",' +
      '"key_risks":[{"title":"產能排擠","impact":"交期延長","reason":"先進製程產能緊張"}],' +
      '"positive_signals":["有替代供應商可議價"],' +
      '"recommended_actions":["建立 LTA 鎖定產能"]' +
      '}';

    Test.startTest();
    CMSupplyNetworkGraphController.ImpactAnalysisResponse response = CMSupplyNetworkGraphController.analyzeWncImpact(
      nonDemo.Id,
      'FWA_5G'
    );
    Test.stopTest();

    CMSupplyNetworkGraphController.testWncImpactPromptJson = null;

    System.assertEquals('HIGH', response.impactLevel);
    System.assertEquals(true, response.summary.contains('WNC'));
    System.assertEquals(
      'CM_Account_WNC_Impact_Analysis',
      response.promptTemplateName
    );
    System.assertNotEquals(null, response.generatedAt);
    System.assertEquals('1.0', response.analysisVersion);
    System.assertEquals('Non-Demo Account', response.rootAccount);
    System.assertEquals('啟碁科技 WNC', response.focusCompany);
    System.assertEquals(true, response.overallAssessment.contains('WNC'));
    System.assertEquals(1, response.keyRisks.size());
    System.assertEquals(1, response.positiveSignals.size());
    System.assertEquals(1, response.recommendedActions.size());
  }

  @IsTest
  static void analyzeWncImpact_acceptsScenarioAliasesFromCatalog() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    update new Account(
      Id = nonDemo.Id,
      CM_Is_Demo_Target__c = true,
      CM_Supply_Scenario_Catalog__c = '車聯網模組\n5G FWA',
      CM_Supply_Network_Prompt_JSON__c = '{"schema_version":"3.0","analysis_scenario":{"code":"FWA_5G","label":"5G FWA"},"relationships":[{"source_company_name":"TSMC","target_company_name":"Qualcomm"}]}'
    );

    CMSupplyNetworkGraphController.testWncImpactPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testWncImpactPromptJson =
      '{' +
      '"analysis_version":"1.0",' +
      '"analysis_scenario":{"code":"FWA_5G","label":"5G FWA"},' +
      '"root_account":"Non-Demo Account",' +
      '"focus_company":"WT Technology",' +
      '"impact_level":"MEDIUM",' +
      '"overall_assessment":"測試用摘要",' +
      '"summary_for_ui":"測試用 UI 摘要",' +
      '"key_risks":[],' +
      '"positive_signals":[],' +
      '"recommended_actions":[]' +
      '}';

    Test.startTest();
    CMSupplyNetworkGraphController.ImpactAnalysisResponse response = CMSupplyNetworkGraphController.analyzeWncImpact(
      nonDemo.Id,
      '5G_FWA'
    );
    Test.stopTest();

    CMSupplyNetworkGraphController.testWncImpactPromptJson = null;

    System.assertEquals('FWA_5G', response.supplyScenario);
    System.assertEquals(
      'CM_Account_WNC_Impact_Analysis',
      response.promptTemplateName
    );
  }

  @IsTest
  static void analyzeWncImpact_rebuildsScenarioSnapshotFromVisibleRootRelationshipsOnly() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    Account tsmc = [SELECT Id FROM Account WHERE Name = 'TSMC' LIMIT 1];
    Account wpg = [SELECT Id FROM Account WHERE Name = 'WPG' LIMIT 1];

    Account unrelatedRoot = new Account(
      Name = 'Unrelated Root',
      Website = 'https://www.unrelated-root.test'
    );
    Account unrelatedCustomer = new Account(
      Name = 'Unrelated Customer',
      Website = 'https://www.unrelated-customer.test'
    );
    insert new List<Account>{ unrelatedRoot, unrelatedCustomer };

    insert new List<CM_Supply_Relationship__c>{
      new CM_Supply_Relationship__c(
        Source_Account__c = tsmc.Id,
        Target_Account__c = nonDemo.Id,
        Edge_Category__c = 'UPSTREAM',
        Relation_Type__c = 'Foundry',
        Products__c = '5G FWA SoC',
        Evidence__c = 'Root 專屬上游',
        Source_Type__c = 'PUBLIC_INFO',
        Confidence__c = 0.91,
        Supply_Scenario__c = 'FWA_5G',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = unrelatedRoot.Id,
        Target_Account__c = unrelatedCustomer.Id,
        Edge_Category__c = 'DOWNSTREAM',
        Relation_Type__c = 'Customer',
        Products__c = 'Should stay out',
        Evidence__c = '不屬於本次 root',
        Source_Type__c = 'PUBLIC_INFO',
        Confidence__c = 0.92,
        Supply_Scenario__c = 'FWA_5G',
        Is_Active__c = true
      ),
      new CM_Supply_Relationship__c(
        Source_Account__c = nonDemo.Id,
        Target_Account__c = wpg.Id,
        Edge_Category__c = 'DOWNSTREAM',
        Relation_Type__c = 'Distributor',
        Products__c = '車用模組',
        Evidence__c = '其他場景資料',
        Source_Type__c = 'PUBLIC_INFO',
        Confidence__c = 0.88,
        Supply_Scenario__c = 'AUTOMOTIVE_TELEMATICS',
        Is_Active__c = true
      )
    };

    update new Account(
      Id = nonDemo.Id,
      CM_Supply_Network_Prompt_JSON__c = '{"schema_version":"2.1","analysis_scenario":{"code":"ENTERPRISE_WIFI_AP","label":"Enterprise Wi-Fi AP"},"relationships":[]}'
    );

    CMSupplyNetworkGraphController.testWncImpactPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testWncImpactPromptJson =
      '{' +
      '"analysis_version":"1.0",' +
      '"analysis_scenario":{"code":"FWA_5G","label":"5G FWA"},' +
      '"root_account":"Non-Demo Account",' +
      '"focus_company":"啟碁科技 WNC",' +
      '"impact_level":"LOW",' +
      '"overall_assessment":"測試用摘要",' +
      '"key_risks":[],' +
      '"positive_signals":[],' +
      '"recommended_actions":[],' +
      '"summary_for_ui":"測試用 UI 摘要"' +
      '}';

    Test.startTest();
    CMSupplyNetworkGraphController.ImpactAnalysisResponse response = CMSupplyNetworkGraphController.analyzeWncImpact(
      nonDemo.Id,
      'FWA_5G'
    );
    Test.stopTest();

    CMSupplyNetworkGraphController.testWncImpactPromptJson = null;

    Account refreshedAccount = [
      SELECT CM_Supply_Network_Prompt_JSON__c
      FROM Account
      WHERE Id = :nonDemo.Id
      LIMIT 1
    ];

    System.assertEquals('FWA_5G', response.supplyScenario);
    System.assert(
      refreshedAccount.CM_Supply_Network_Prompt_JSON__c.contains('"TSMC"'),
      'Scenario snapshot should include the current root graph relationship.'
    );
    System.assertEquals(
      false,
      refreshedAccount.CM_Supply_Network_Prompt_JSON__c.contains(
        'Unrelated Root'
      ),
      'Scenario snapshot should exclude unrelated same-scenario relationships.'
    );
    System.assertEquals(
      false,
      refreshedAccount.CM_Supply_Network_Prompt_JSON__c.contains('車用模組'),
      'Scenario snapshot should exclude other scenarios.'
    );
  }

  @IsTest
  static void analyzeWncImpact_throwsWhenPromptSnapshotMissing() {
    Account nonDemo = [
      SELECT Id
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];

    Boolean didThrow = false;

    Test.startTest();
    try {
      CMSupplyNetworkGraphController.analyzeWncImpact(nonDemo.Id, 'FWA_5G');
    } catch (AuraHandledException ex) {
      didThrow = true;
    }
    Test.stopTest();

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void manualRelationshipManager_createListAndDeactivate() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    Account tsmc = [SELECT Id, Name FROM Account WHERE Name = 'TSMC' LIMIT 1];

    CMSupplyNetworkGraphController.ManualRelationshipRow createdRow = CMSupplyNetworkGraphController.createManualRelationship(
      nonDemo.Id,
      tsmc.Id,
      'UPSTREAM',
      'Foundry',
      '晶圓代工夥伴',
      '4nm/5nm Wafer',
      '手動建立測試證據',
      0.91,
      'PUBLIC_INFO'
    );

    System.assertNotEquals(null, createdRow);
    System.assertEquals('UPSTREAM', createdRow.mode);
    System.assertEquals(tsmc.Id, createdRow.relatedAccountId);
    System.assertEquals(true, createdRow.isActive);
    System.assertEquals('Foundry', createdRow.relationType);

    List<CMSupplyNetworkGraphController.ManualRelationshipRow> rows = CMSupplyNetworkGraphController.getManualRelationships(
      nonDemo.Id,
      50,
      30
    );
    CMSupplyNetworkGraphController.ManualRelationshipRow createdSnapshot = findRelationshipRowById(
      rows,
      createdRow.id
    );
    System.assertNotEquals(
      null,
      createdSnapshot,
      'Created relationship should be listed.'
    );
    System.assertEquals('UPSTREAM', createdSnapshot.mode);
    System.assertEquals('TSMC', createdSnapshot.relatedAccountName);

    CMSupplyNetworkGraphController.deactivateManualRelationship(
      createdRow.id,
      nonDemo.Id
    );

    List<CMSupplyNetworkGraphController.ManualRelationshipRow> updatedRows = CMSupplyNetworkGraphController.getManualRelationships(
      nonDemo.Id,
      50,
      30
    );
    CMSupplyNetworkGraphController.ManualRelationshipRow deactivatedSnapshot = findRelationshipRowById(
      updatedRows,
      createdRow.id
    );
    System.assertNotEquals(
      null,
      deactivatedSnapshot,
      'Deactivated relationship should still be listed.'
    );
    System.assertEquals(false, deactivatedSnapshot.isActive);

    CMSupplyNetworkGraphController.activateManualRelationship(
      createdRow.id,
      nonDemo.Id
    );
    List<CMSupplyNetworkGraphController.ManualRelationshipRow> reactivatedRows = CMSupplyNetworkGraphController.getManualRelationships(
      nonDemo.Id,
      50,
      30
    );
    CMSupplyNetworkGraphController.ManualRelationshipRow reactivatedSnapshot = findRelationshipRowById(
      reactivatedRows,
      createdRow.id
    );
    System.assertNotEquals(
      null,
      reactivatedSnapshot,
      'Reactivated relationship should be listed.'
    );
    System.assertEquals(true, reactivatedSnapshot.isActive);
  }

  @IsTest
  static void manualRelationshipManager_deleteInactiveRelationship() {
    Account nonDemo = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    Account tsmc = [SELECT Id, Name FROM Account WHERE Name = 'TSMC' LIMIT 1];

    CMSupplyNetworkGraphController.ManualRelationshipRow createdRow = CMSupplyNetworkGraphController.createManualRelationship(
      nonDemo.Id,
      tsmc.Id,
      'UPSTREAM',
      'Foundry',
      '刪除測試',
      null,
      null,
      0.82,
      'PUBLIC_INFO'
    );
    System.assertNotEquals(null, createdRow);

    CMSupplyNetworkGraphController.deactivateManualRelationship(
      createdRow.id,
      nonDemo.Id
    );
    CMSupplyNetworkGraphController.deleteManualRelationship(
      createdRow.id,
      nonDemo.Id
    );

    List<CMSupplyNetworkGraphController.ManualRelationshipRow> rows = CMSupplyNetworkGraphController.getManualRelationships(
      nonDemo.Id,
      50,
      30
    );
    CMSupplyNetworkGraphController.ManualRelationshipRow deletedRow = findRelationshipRowById(
      rows,
      createdRow.id
    );
    System.assertEquals(
      null,
      deletedRow,
      'Deleted relationship should not appear in table rows.'
    );

    Integer remainingCount = [
      SELECT COUNT()
      FROM CM_Supply_Relationship__c
      WHERE Id = :createdRow.id
    ];
    System.assertEquals(
      0,
      remainingCount,
      'Deleted relationship record should no longer exist.'
    );
  }

  @IsTest
  static void manualRelationshipManager_reusesExistingEdgeWhenSameKey() {
    Account nonDemo = [
      SELECT Id
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    Account tsmc = [SELECT Id FROM Account WHERE Name = 'TSMC' LIMIT 1];

    CMSupplyNetworkGraphController.ManualRelationshipRow firstRow = CMSupplyNetworkGraphController.createManualRelationship(
      nonDemo.Id,
      tsmc.Id,
      'UPSTREAM',
      'Foundry',
      '第一次角色',
      null,
      null,
      0.80,
      'PUBLIC_INFO'
    );
    CMSupplyNetworkGraphController.ManualRelationshipRow secondRow = CMSupplyNetworkGraphController.createManualRelationship(
      nonDemo.Id,
      tsmc.Id,
      'UPSTREAM',
      'Foundry',
      '更新後角色',
      null,
      null,
      0.88,
      'INFERRED'
    );

    System.assertEquals(
      firstRow.id,
      secondRow.id,
      'Same relationship key should update existing row.'
    );
    List<CMSupplyNetworkGraphController.ManualRelationshipRow> rows = CMSupplyNetworkGraphController.getManualRelationships(
      nonDemo.Id,
      50,
      30
    );
    CMSupplyNetworkGraphController.ManualRelationshipRow updatedSnapshot = findRelationshipRowById(
      rows,
      firstRow.id
    );
    System.assertNotEquals(
      null,
      updatedSnapshot,
      'Updated relationship should be listed.'
    );
    System.assertEquals('更新後角色', updatedSnapshot.role);
    System.assertEquals('INFERRED', updatedSnapshot.sourceType);
  }

  @IsTest
  static void manualRelationshipManager_allowsSameRelationshipKeyAcrossSupplyScenarios() {
    Account nonDemo = [
      SELECT Id
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    Account tsmc = [SELECT Id FROM Account WHERE Name = 'TSMC' LIMIT 1];

    CMSupplyNetworkGraphController.ManualRelationshipRow fwaRow = CMSupplyNetworkGraphController.createManualRelationship(
      nonDemo.Id,
      tsmc.Id,
      'UPSTREAM',
      'Foundry',
      'FWA 角色',
      '5G FWA 晶圓',
      'FWA 證據',
      0.86,
      'PUBLIC_INFO',
      'FWA_5G'
    );
    CMSupplyNetworkGraphController.ManualRelationshipRow automotiveRow = CMSupplyNetworkGraphController.createManualRelationship(
      nonDemo.Id,
      tsmc.Id,
      'UPSTREAM',
      'Foundry',
      '車用角色',
      '車用 SoC',
      '車用證據',
      0.88,
      'PUBLIC_INFO',
      'AUTOMOTIVE_TELEMATICS'
    );

    System.assertNotEquals(
      fwaRow.id,
      automotiveRow.id,
      'Same natural key should be stored separately per supply scenario.'
    );

    List<CMSupplyNetworkGraphController.ManualRelationshipRow> fwaRows = CMSupplyNetworkGraphController.getManualRelationships(
      nonDemo.Id,
      50,
      30,
      'FWA_5G'
    );
    List<CMSupplyNetworkGraphController.ManualRelationshipRow> automotiveRows = CMSupplyNetworkGraphController.getManualRelationships(
      nonDemo.Id,
      50,
      30,
      'AUTOMOTIVE_TELEMATICS'
    );

    CMSupplyNetworkGraphController.ManualRelationshipRow fwaSnapshot = findRelationshipRowById(
      fwaRows,
      fwaRow.id
    );
    CMSupplyNetworkGraphController.ManualRelationshipRow automotiveSnapshot = findRelationshipRowById(
      automotiveRows,
      automotiveRow.id
    );

    System.assertNotEquals(null, fwaSnapshot);
    System.assertEquals('FWA_5G', fwaSnapshot.supplyScenario);
    System.assertEquals(
      null,
      findRelationshipRowById(fwaRows, automotiveRow.id)
    );
    System.assertNotEquals(null, automotiveSnapshot);
    System.assertEquals(
      'AUTOMOTIVE_TELEMATICS',
      automotiveSnapshot.supplyScenario
    );
  }

  @IsTest
  static void smartBuildRelationships_fullRebuildSkipsUserCuratedRows() {
    Account nonDemo = [
      SELECT Id
      FROM Account
      WHERE Name = 'Non-Demo Account'
      LIMIT 1
    ];
    Account wpg = [SELECT Id FROM Account WHERE Name = 'WPG' LIMIT 1];
    Account tsmc = [SELECT Id FROM Account WHERE Name = 'TSMC' LIMIT 1];

    CM_Supply_Relationship__c machineGenerated = new CM_Supply_Relationship__c(
      Source_Account__c = nonDemo.Id,
      Target_Account__c = wpg.Id,
      Edge_Category__c = 'DOWNSTREAM',
      Relation_Type__c = 'Legacy FWA',
      Source_Type__c = 'PUBLIC_INFO',
      Supply_Scenario__c = 'FWA_5G',
      Is_User_Curated__c = false,
      Is_Active__c = true
    );
    insert machineGenerated;

    CMSupplyNetworkGraphController.ManualRelationshipRow curatedRow = CMSupplyNetworkGraphController.createManualRelationship(
      nonDemo.Id,
      tsmc.Id,
      'UPSTREAM',
      'Foundry',
      '使用者維護',
      null,
      '使用者證據',
      0.91,
      'PUBLIC_INFO',
      'FWA_5G'
    );

    CMSupplyNetworkGraphController.testPromptFailureMessage = null;
    CMSupplyNetworkGraphController.testPromptJson =
      '{' +
      '"schema_version":"3.0",' +
      '"analysis_scenario":{"code":"FWA_5G","label":"5G FWA"},' +
      '"relationships":[' +
      '{"source_company_name":"ASE","source_company_domain":"aseglobal.com","target_company_name":"Non-Demo Account","target_company_domain":"example.com","edge_category":"UPSTREAM","relation_type":"OSAT","role":"新增封測","products":["FWA 封測"],"confidence":0.94,"source_type":"PUBLIC_INFO","evidence":["重建封測路徑"]}' +
      ']' +
      '}';

    Test.startTest();
    CMSupplyNetworkGraphController.SmartBuildResponse result = CMSupplyNetworkGraphController.smartBuildRelationships(
      nonDemo.Id,
      30,
      'FULL_REBUILD',
      'FWA_5G'
    );
    Test.stopTest();
    CMSupplyNetworkGraphController.testPromptJson = null;

    CM_Supply_Relationship__c refreshedMachineGenerated = [
      SELECT Is_Active__c
      FROM CM_Supply_Relationship__c
      WHERE Id = :machineGenerated.Id
      LIMIT 1
    ];
    CM_Supply_Relationship__c refreshedCurated = [
      SELECT Is_Active__c, Is_User_Curated__c
      FROM CM_Supply_Relationship__c
      WHERE Id = :curatedRow.id
      LIMIT 1
    ];

    System.assertEquals(
      false,
      refreshedMachineGenerated.Is_Active__c,
      'Machine-generated direct row should be deactivated.'
    );
    System.assertEquals(
      true,
      refreshedCurated.Is_Active__c,
      'User-curated row should remain active.'
    );
    System.assertEquals(true, refreshedCurated.Is_User_Curated__c);
    System.assert(
      result.insertedCount >= 1,
      'Full rebuild should still insert new prompt-derived relationships.'
    );
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

  private static CMSupplyNetworkGraphController.ManualRelationshipRow findRelationshipRowById(
    List<CMSupplyNetworkGraphController.ManualRelationshipRow> rows,
    Id relationshipId
  ) {
    for (CMSupplyNetworkGraphController.ManualRelationshipRow row : rows) {
      if (row.id == relationshipId) {
        return row;
      }
    }
    return null;
  }
}