public with sharing class CMSupplyNetworkGraphController {
  private static final Integer DEFAULT_MAX_NODES = 150;
  private static final Integer ABSOLUTE_MAX_NODES = 500;
  private static final Integer DIRECT_UPSTREAM_NODE_LIMIT = 7;
  private static final Integer DIRECT_DOWNSTREAM_NODE_LIMIT = 7;
  private static final Integer MANUAL_RELATIONSHIP_QUERY_LIMIT = 5000;
  private static final Integer MANUAL_RELATIONSHIP_PANEL_DEFAULT_LIMIT = 200;
  private static final Integer ACCOUNT_PROMPT_JSON_MAX_LENGTH = 131072;
  private static final Decimal MIN_CONFIDENCE = 0.55;
  private static final String DEMO_TEMPLATE_NAME = 'DEMO_QUINCY_V1';
  private static final String MANUAL_TEMPLATE_NAME = 'CM_MANUAL_RELATIONSHIP_V1';
  private static final String PROMPT_TEMPLATE_DEVELOPER_NAME = 'CM_Account_Supply_Network_Discovery';
  private static final String WNC_IMPACT_PROMPT_TEMPLATE_DEVELOPER_NAME = 'CM_Account_WNC_Impact_Analysis';
  private static final String PROMPT_APPLICATION_NAME = 'PromptBuilderPreview';
  private static final String SMART_BUILD_MODE_UPSERT = 'UPSERT';
  private static final String SMART_BUILD_MODE_FULL_REBUILD = 'FULL_REBUILD';
  private static final Set<String> SUPPORTED_DIRECTIONS = new Set<String>{
    'UPSTREAM',
    'DOWNSTREAM',
    'COMPETITOR'
  };
  private static final Set<String> SUPPORTED_EDGE_CATEGORIES = new Set<String>{
    'UPSTREAM',
    'DOWNSTREAM',
    'COMPETITOR',
    'INDIRECT_PATH'
  };
  private static final Set<String> SUPPORTED_MANUAL_MODES = new Set<String>{
    'UPSTREAM',
    'DOWNSTREAM',
    'COMPETITOR'
  };
  private static final Set<String> SUPPORTED_SOURCE_TYPES = new Set<String>{
    'PUBLIC_INFO',
    'INFERRED'
  };
  private static final String SUPPLY_SCENARIO_FWA_5G = 'FWA_5G';
  private static final String SUPPLY_SCENARIO_ENTERPRISE_WIFI_AP = 'ENTERPRISE_WIFI_AP';
  private static final String SUPPLY_SCENARIO_AUTOMOTIVE_TELEMATICS = 'AUTOMOTIVE_TELEMATICS';
  private static final String SUPPLY_SCENARIO_LEGACY_UNSCOPED = 'LEGACY_UNSCOPED';
  private static final Map<String, String> SUPPLY_SCENARIO_ALIAS_TO_CANONICAL = buildSupplyScenarioAliasMap();
  private static final Set<String> DEFAULT_SUPPORTED_SUPPLY_SCENARIOS = new Set<String>{
    SUPPLY_SCENARIO_FWA_5G,
    SUPPLY_SCENARIO_ENTERPRISE_WIFI_AP,
    SUPPLY_SCENARIO_AUTOMOTIVE_TELEMATICS,
    SUPPLY_SCENARIO_LEGACY_UNSCOPED
  };
  private static final Set<String> DEFAULT_AI_SUPPLY_SCENARIOS = new Set<String>{
    SUPPLY_SCENARIO_FWA_5G,
    SUPPLY_SCENARIO_ENTERPRISE_WIFI_AP,
    SUPPLY_SCENARIO_AUTOMOTIVE_TELEMATICS
  };
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

  @TestVisible
  private static String testPromptJson;
  @TestVisible
  private static String testPromptFailureMessage;
  @TestVisible
  private static String testWncImpactPromptJson;
  @TestVisible
  private static String testWncImpactPromptFailureMessage;
  @TestVisible
  private static SupplyNetworkRuntimeConfig testRuntimeConfig;
  private static SupplyNetworkRuntimeConfig runtimeConfigCache;

  @AuraEnabled(cacheable=true)
  public static SupplyNetworkRuntimeConfigResponse getRuntimeConfig() {
    SupplyNetworkRuntimeConfig runtimeConfig = getSupplyNetworkRuntimeConfig();
    SupplyNetworkRuntimeConfigResponse response = new SupplyNetworkRuntimeConfigResponse();
    response.focusCompanyName = runtimeConfig.focusCompanyName;
    response.focusCompanyDomain = runtimeConfig.focusCompanyDomain;
    response.supplyScenarios = new List<SupplyScenarioOption>();
    for (SupplyScenarioDefinition scenarioDefinition : runtimeConfig.scenarioDefinitions) {
      SupplyScenarioOption option = new SupplyScenarioOption();
      option.code = scenarioDefinition.code;
      option.label = scenarioDefinition.label;
      option.aiSupported = scenarioDefinition.aiSupported;
      response.supplyScenarios.add(option);
    }
    return response;
  }

  @AuraEnabled(cacheable=false)
  public static GraphResponse getGraph(
    Id rootAccountId,
    Integer maxNodes,
    Boolean enableAutoPrompt,
    String supplyScenario
  ) {
    if (rootAccountId == null) {
      throw new AuraHandledException('rootAccountId is required.');
    }

    validateReadAccess(false);

    Integer nodeCap = normalizeMaxNodes(maxNodes);
    Account rootAccount = loadRootAccount(rootAccountId);
    String normalizedSupplyScenario = normalizeSupplyScenario(
      supplyScenario,
      true
    );
    GraphResponse manualResponse = buildManualGraphResponse(
      rootAccount,
      nodeCap,
      null,
      normalizedSupplyScenario
    );
    populateDebugPromptJson(
      manualResponse,
      resolveGraphPromptDebugJson(rootAccount, normalizedSupplyScenario)
    );
    if (manualResponse.edgeCount > 0) {
      return manualResponse;
    }

    if (
      String.isBlank(normalizedSupplyScenario) ||
      normalizedSupplyScenario == SUPPLY_SCENARIO_LEGACY_UNSCOPED
    ) {
      return manualResponse;
    }

    // Prevent unintended prompt invocation in unit tests unless a prompt stub is explicitly provided.
    if (
      Test.isRunningTest() &&
      String.isBlank(testPromptJson) &&
      String.isBlank(testPromptFailureMessage)
    ) {
      return manualResponse;
    }

    SmartBuildResponse smartBuildResult = smartBuildRelationships(
      rootAccountId,
      nodeCap,
      SMART_BUILD_MODE_UPSERT,
      normalizedSupplyScenario
    );
    if (smartBuildResult != null && smartBuildResult.graph != null) {
      if (String.isBlank(smartBuildResult.graph.promptRawJson)) {
        populateDebugPromptJson(
          smartBuildResult.graph,
          resolveGraphPromptDebugJson(rootAccount, normalizedSupplyScenario)
        );
      }
      return smartBuildResult.graph;
    }
    return manualResponse;
  }

  @AuraEnabled(cacheable=false)
  public static ImpactAnalysisResponse analyzeWncImpact(
    Id rootAccountId,
    String supplyScenario
  ) {
    if (rootAccountId == null) {
      throw new AuraHandledException('rootAccountId is required.');
    }

    validateReadAccess(true);
    String normalizedSupplyScenario = normalizeAiSupplyScenario(supplyScenario);
    Account rootAccount = ensureScenarioPromptSnapshot(
      rootAccountId,
      normalizedSupplyScenario
    );
    String impactJson = generateWncImpactJson(
      rootAccount,
      normalizedSupplyScenario
    );
    return buildWncImpactAnalysisResponse(impactJson);
  }

  @AuraEnabled(cacheable=false)
  public static SmartBuildResponse smartBuildRelationships(
    Id rootAccountId,
    Integer maxNodes,
    String buildMode,
    String supplyScenario
  ) {
    if (rootAccountId == null) {
      throw new AuraHandledException('rootAccountId is required.');
    }

    validateReadAccess(true);
    Integer nodeCap = normalizeMaxNodes(maxNodes);
    Account rootAccount = loadRootAccount(rootAccountId);
    String normalizedBuildMode = normalizeSmartBuildMode(buildMode);
    String normalizedSupplyScenario = normalizeAiSupplyScenario(supplyScenario);

    Integer deactivatedCount = 0;
    if (normalizedBuildMode == SMART_BUILD_MODE_FULL_REBUILD) {
      deactivatedCount = deactivateRootDirectRelationships(
        rootAccount.Id,
        normalizedSupplyScenario
      );
    }

    String promptJson = generatePromptJson(
      rootAccount,
      normalizedSupplyScenario
    );
    Map<String, Object> payload = parsePromptPayload(promptJson);
    String payloadError = stringValue(payload.get('error'));
    if (!String.isBlank(payloadError)) {
      String payloadReason = stringValue(payload.get('reason'));
      throw new AuraHandledException(
        'Prompt template returned an error: ' +
          payloadError +
          (String.isBlank(payloadReason) ? '' : ' (' + payloadReason + ')')
      );
    }

    List<Object> relationshipObjects = asList(payload.get('relationships'));
    if (relationshipObjects == null) {
      throw new AuraHandledException(
        'Prompt output is missing the relationships array.'
      );
    }

    AccountLookup accountLookup = buildAccountLookup(relationshipObjects);
    ensurePlaceholderAccountsForPromptRelationships(
      relationshipObjects,
      rootAccount,
      accountLookup
    );
    Boolean preserveExistingRelationships =
      normalizedBuildMode == SMART_BUILD_MODE_UPSERT;
    SmartBuildStats stats = upsertPromptRelationships(
      relationshipObjects,
      rootAccount,
      accountLookup,
      preserveExistingRelationships,
      normalizedSupplyScenario
    );
    persistPromptJsonOnAccount(rootAccount.Id, promptJson);

    SmartBuildResponse response = new SmartBuildResponse();
    response.promptTemplateName = PROMPT_TEMPLATE_DEVELOPER_NAME;
    response.buildMode = normalizedBuildMode;
    response.generatedAt = Datetime.now();
    response.supplyScenario = normalizedSupplyScenario;
    response.supplyScenarioLabel = getSupplyScenarioLabel(
      normalizedSupplyScenario
    );
    response.insertedCount = stats.insertedCount;
    response.updatedCount = stats.updatedCount;
    response.skippedCount = stats.skippedCount;
    response.totalCandidateCount = stats.totalCandidateCount;
    response.deactivatedCount = deactivatedCount;
    response.graph = buildManualGraphResponse(
      rootAccount,
      nodeCap,
      promptJson,
      normalizedSupplyScenario
    );
    populateDebugPromptJson(response.graph, promptJson);
    return response;
  }

  public static SmartBuildResponse smartBuildRelationships(
    Id rootAccountId,
    Integer maxNodes
  ) {
    return smartBuildRelationships(
      rootAccountId,
      maxNodes,
      SMART_BUILD_MODE_UPSERT,
      null
    );
  }

  public static GraphResponse getGraph(
    Id rootAccountId,
    Integer maxNodes,
    Boolean enableAutoPrompt
  ) {
    return getGraph(rootAccountId, maxNodes, enableAutoPrompt, null);
  }

  public static GraphResponse getGraph(Id rootAccountId, Integer maxNodes) {
    return getGraph(rootAccountId, maxNodes, false, null);
  }

  @AuraEnabled(cacheable=false)
  public static List<ManualRelationshipRow> getManualRelationships(
    Id rootAccountId,
    Integer limitRows,
    Integer maxNodes,
    String supplyScenario
  ) {
    if (rootAccountId == null) {
      throw new AuraHandledException('rootAccountId is required.');
    }

    Integer queryLimit = normalizeManualRelationshipLimit(limitRows);
    Integer nodeCap = normalizeMaxNodes(maxNodes);
    Account rootAccount = loadRootAccount(rootAccountId);
    String rootId = String.valueOf(rootAccountId);
    String normalizedSupplyScenario = normalizeSupplyScenario(
      supplyScenario,
      true
    );

    GraphResponse graphSnapshot = buildManualGraphResponse(
      rootAccount,
      nodeCap,
      null,
      normalizedSupplyScenario
    );
    Set<Id> includedAccountIds = new Set<Id>();
    for (NodeDto graphNode : graphSnapshot.nodes) {
      if (graphNode == null || graphNode.accountId == null) {
        continue;
      }
      includedAccountIds.add(graphNode.accountId);
    }

    Set<String> visibleEdgeKeys = new Set<String>();
    for (EdgeDto graphEdge : graphSnapshot.edges) {
      if (graphEdge == null) {
        continue;
      }
      visibleEdgeKeys.add(
        buildVisibleEdgeKey(
          graphEdge.sourceId,
          graphEdge.targetId,
          graphEdge.relationType,
          graphEdge.relationshipDirection
        )
      );
    }

    List<ManualRelationshipRow> rows = new List<ManualRelationshipRow>();
    Set<Id> includedRelationshipIds = new Set<Id>();
    Set<String> includedVisibleEdgeKeys = new Set<String>();
    if (!includedAccountIds.isEmpty() && !visibleEdgeKeys.isEmpty()) {
      for (CM_Supply_Relationship__c relationshipRecord : [
        SELECT
          Id,
          Source_Account__c,
          Source_Account__r.Name,
          Target_Account__c,
          Target_Account__r.Name,
          Edge_Category__c,
          Relation_Type__c,
          Role__c,
          Products__c,
          Supply_Scenario__c,
          Supply_Scenario_Code__c,
          Evidence__c,
          Confidence__c,
          Source_Type__c,
          Is_User_Curated__c,
          Is_Active__c,
          LastModifiedDate
        FROM CM_Supply_Relationship__c
        WHERE
          Is_Active__c = TRUE
          AND Source_Account__c IN :includedAccountIds
          AND Target_Account__c IN :includedAccountIds
        ORDER BY LastModifiedDate DESC
        LIMIT :MANUAL_RELATIONSHIP_QUERY_LIMIT
      ]) {
        if (
          !matchesSupplyScenario(
            extractRelationshipSupplyScenario(relationshipRecord),
            normalizedSupplyScenario
          )
        ) {
          continue;
        }
        String sourceId = String.valueOf(relationshipRecord.Source_Account__c);
        String targetId = String.valueOf(relationshipRecord.Target_Account__c);
        NormalizedEdgeOrientation orientation = normalizeEdgeOrientation(
          relationshipRecord.Edge_Category__c,
          sourceId,
          targetId,
          rootId
        );
        sourceId = orientation.sourceId;
        targetId = orientation.targetId;
        String edgeCategory = orientation.edgeCategory;

        String relationType = relationshipRecord.Relation_Type__c;
        if (String.isBlank(relationType)) {
          relationType = defaultRelationTypeByCategory(edgeCategory);
        }

        String direction = inferRelationshipDirection(
          edgeCategory,
          sourceId,
          targetId,
          rootId
        );
        String visibleEdgeKey = buildVisibleEdgeKey(
          sourceId,
          targetId,
          relationType,
          direction
        );
        if (!visibleEdgeKeys.contains(visibleEdgeKey)) {
          continue;
        }
        if (includedVisibleEdgeKeys.contains(visibleEdgeKey)) {
          continue;
        }
        includedVisibleEdgeKeys.add(visibleEdgeKey);

        rows.add(buildManualRelationshipRow(relationshipRecord, rootAccountId));
        includedRelationshipIds.add(relationshipRecord.Id);
      }
    }

    // Keep direct inactive rows available so users can reactivate quickly.
    for (CM_Supply_Relationship__c relationshipRecord : [
      SELECT
        Id,
        Source_Account__c,
        Source_Account__r.Name,
        Target_Account__c,
        Target_Account__r.Name,
        Edge_Category__c,
        Relation_Type__c,
        Role__c,
        Products__c,
        Supply_Scenario__c,
        Supply_Scenario_Code__c,
        Evidence__c,
        Confidence__c,
        Source_Type__c,
        Is_User_Curated__c,
        Is_Active__c,
        LastModifiedDate
      FROM CM_Supply_Relationship__c
      WHERE
        Is_Active__c = FALSE
        AND (Source_Account__c = :rootAccountId
        OR Target_Account__c = :rootAccountId)
      ORDER BY LastModifiedDate DESC
      LIMIT :queryLimit
    ]) {
      if (
        !matchesSupplyScenario(
          extractRelationshipSupplyScenario(relationshipRecord),
          normalizedSupplyScenario
        )
      ) {
        continue;
      }
      if (includedRelationshipIds.contains(relationshipRecord.Id)) {
        continue;
      }
      rows.add(buildManualRelationshipRow(relationshipRecord, rootAccountId));
    }

    if (rows.size() > queryLimit) {
      while (rows.size() > queryLimit) {
        rows.remove(rows.size() - 1);
      }
    }
    return rows;
  }

  @AuraEnabled
  public static ManualRelationshipRow createManualRelationship(
    Id rootAccountId,
    Id relatedAccountId,
    String mode,
    String relationType,
    String role,
    String products,
    String evidence,
    Decimal confidence,
    String sourceType,
    String supplyScenario
  ) {
    if (rootAccountId == null) {
      throw new AuraHandledException('rootAccountId is required.');
    }
    if (relatedAccountId == null) {
      throw new AuraHandledException('relatedAccountId is required.');
    }
    if (rootAccountId == relatedAccountId) {
      throw new AuraHandledException('Root account cannot relate to itself.');
    }

    Account rootAccount = loadRootAccount(rootAccountId);
    Account relatedAccount = loadAccountById(relatedAccountId);

    String normalizedMode = normalizeManualMode(mode);
    if (normalizedMode == null) {
      throw new AuraHandledException(
        'mode must be UPSTREAM, DOWNSTREAM, or COMPETITOR.'
      );
    }

    Id sourceAccountId = normalizedMode == 'UPSTREAM'
      ? relatedAccount.Id
      : rootAccount.Id;
    Id targetAccountId = normalizedMode == 'UPSTREAM'
      ? rootAccount.Id
      : relatedAccount.Id;
    String edgeCategory = normalizedMode;
    String normalizedRelationType = String.isBlank(relationType)
      ? defaultRelationTypeByCategory(edgeCategory)
      : relationType.trim();
    String normalizedSourceType = normalizeSourceType(sourceType);
    Decimal normalizedConfidence = normalizeConfidence(confidence);
    String normalizedSupplyScenario = normalizeSupplyScenario(
      supplyScenario,
      false
    );

    List<CM_Supply_Relationship__c> existingRelationships = [
      SELECT
        Id,
        Source_Account__c,
        Source_Account__r.Name,
        Target_Account__c,
        Target_Account__r.Name,
        Edge_Category__c,
        Relation_Type__c,
        Role__c,
        Products__c,
        Supply_Scenario__c,
        Supply_Scenario_Code__c,
        Evidence__c,
        Confidence__c,
        Source_Type__c,
        Is_User_Curated__c,
        Is_Active__c,
        LastModifiedDate
      FROM CM_Supply_Relationship__c
      WHERE
        Source_Account__c = :sourceAccountId
        AND Target_Account__c = :targetAccountId
        AND Edge_Category__c = :edgeCategory
        AND Relation_Type__c = :normalizedRelationType
      LIMIT :MANUAL_RELATIONSHIP_QUERY_LIMIT
    ];

    CM_Supply_Relationship__c relationshipRecord;
    for (CM_Supply_Relationship__c candidateRecord : existingRelationships) {
      if (
        matchesSupplyScenario(
          extractRelationshipSupplyScenario(candidateRecord),
          normalizedSupplyScenario
        )
      ) {
        relationshipRecord = candidateRecord;
        break;
      }
    }
    if (relationshipRecord == null) {
      relationshipRecord = new CM_Supply_Relationship__c(
        Source_Account__c = sourceAccountId,
        Target_Account__c = targetAccountId,
        Edge_Category__c = edgeCategory,
        Relation_Type__c = normalizedRelationType,
        Role__c = normalizeText(role),
        Products__c = normalizeLongText(products),
        Evidence__c = normalizeLongText(evidence),
        Confidence__c = normalizedConfidence,
        Source_Type__c = normalizedSourceType,
        Is_User_Curated__c = true,
        Is_Active__c = true
      );
      applyRelationshipSupplyScenario(
        relationshipRecord,
        normalizedSupplyScenario
      );
      insert relationshipRecord;
    } else {
      relationshipRecord.Role__c = normalizeText(role);
      relationshipRecord.Products__c = normalizeLongText(products);
      applyRelationshipSupplyScenario(
        relationshipRecord,
        normalizedSupplyScenario
      );
      relationshipRecord.Evidence__c = normalizeLongText(evidence);
      relationshipRecord.Confidence__c = normalizedConfidence;
      relationshipRecord.Source_Type__c = normalizedSourceType;
      relationshipRecord.Is_User_Curated__c = true;
      relationshipRecord.Is_Active__c = true;
      update relationshipRecord;
    }

    return buildManualRelationshipRowById(relationshipRecord.Id, rootAccountId);
  }

  public static ImpactAnalysisResponse analyzeWncImpact(Id rootAccountId) {
    return analyzeWncImpact(rootAccountId, null);
  }

  public static SmartBuildResponse smartBuildRelationships(
    Id rootAccountId,
    Integer maxNodes,
    String buildMode
  ) {
    return smartBuildRelationships(rootAccountId, maxNodes, buildMode, null);
  }

  public static List<ManualRelationshipRow> getManualRelationships(
    Id rootAccountId,
    Integer limitRows,
    Integer maxNodes
  ) {
    return getManualRelationships(rootAccountId, limitRows, maxNodes, null);
  }

  public static ManualRelationshipRow createManualRelationship(
    Id rootAccountId,
    Id relatedAccountId,
    String mode,
    String relationType,
    String role,
    String products,
    String evidence,
    Decimal confidence,
    String sourceType
  ) {
    return createManualRelationship(
      rootAccountId,
      relatedAccountId,
      mode,
      relationType,
      role,
      products,
      evidence,
      confidence,
      sourceType,
      SUPPLY_SCENARIO_LEGACY_UNSCOPED
    );
  }

  @AuraEnabled
  public static void deactivateManualRelationship(
    Id relationshipId,
    Id rootAccountId
  ) {
    if (relationshipId == null) {
      throw new AuraHandledException('relationshipId is required.');
    }
    if (rootAccountId == null) {
      throw new AuraHandledException('rootAccountId is required.');
    }

    List<CM_Supply_Relationship__c> relationships = [
      SELECT Id, Is_Active__c
      FROM CM_Supply_Relationship__c
      WHERE Id = :relationshipId
      LIMIT 1
    ];
    if (relationships.isEmpty()) {
      throw new AuraHandledException('Relationship not found.');
    }

    CM_Supply_Relationship__c relationshipRecord = relationships[0];
    if (!relationshipRecord.Is_Active__c) {
      return;
    }
    relationshipRecord.Is_Active__c = false;
    update relationshipRecord;
  }

  @AuraEnabled
  public static void activateManualRelationship(
    Id relationshipId,
    Id rootAccountId
  ) {
    if (relationshipId == null) {
      throw new AuraHandledException('relationshipId is required.');
    }
    if (rootAccountId == null) {
      throw new AuraHandledException('rootAccountId is required.');
    }

    List<CM_Supply_Relationship__c> relationships = [
      SELECT Id, Is_Active__c
      FROM CM_Supply_Relationship__c
      WHERE Id = :relationshipId
      LIMIT 1
    ];
    if (relationships.isEmpty()) {
      throw new AuraHandledException('Relationship not found.');
    }

    CM_Supply_Relationship__c relationshipRecord = relationships[0];
    if (relationshipRecord.Is_Active__c) {
      return;
    }
    relationshipRecord.Is_Active__c = true;
    update relationshipRecord;
  }

  @AuraEnabled
  public static void deleteManualRelationship(
    Id relationshipId,
    Id rootAccountId
  ) {
    if (relationshipId == null) {
      throw new AuraHandledException('relationshipId is required.');
    }
    if (rootAccountId == null) {
      throw new AuraHandledException('rootAccountId is required.');
    }

    List<CM_Supply_Relationship__c> relationships = [
      SELECT Id, Source_Account__c, Target_Account__c, Is_Active__c
      FROM CM_Supply_Relationship__c
      WHERE Id = :relationshipId
      LIMIT 1
    ];
    if (relationships.isEmpty()) {
      throw new AuraHandledException('Relationship not found.');
    }

    CM_Supply_Relationship__c relationshipRecord = relationships[0];
    Boolean isRootDirectRelationship =
      relationshipRecord.Source_Account__c == rootAccountId ||
      relationshipRecord.Target_Account__c == rootAccountId;
    if (!isRootDirectRelationship) {
      throw new AuraHandledException(
        'Only direct root relationships can be deleted.'
      );
    }
    if (relationshipRecord.Is_Active__c) {
      throw new AuraHandledException(
        'Only inactive relationships can be deleted.'
      );
    }

    delete relationshipRecord;
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
    response.coverageNote = '此版本為固定 Demo 供應鏈圖。非 Demo 帳戶會優先使用 CM Supply Relationship 資料。';

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

  private static GraphResponse buildManualGraphResponse(
    Account rootAccount,
    Integer nodeCap
  ) {
    return buildManualGraphResponse(rootAccount, nodeCap, null, null);
  }

  private static GraphResponse buildManualGraphResponse(
    Account rootAccount,
    Integer nodeCap,
    String promptScopeJsonOverride
  ) {
    return buildManualGraphResponse(
      rootAccount,
      nodeCap,
      promptScopeJsonOverride,
      null
    );
  }

  private static GraphResponse buildManualGraphResponse(
    Account rootAccount,
    Integer nodeCap,
    String promptScopeJsonOverride,
    String supplyScenario
  ) {
    GraphResponse response = new GraphResponse();
    response.rootId = String.valueOf(rootAccount.Id);
    response.promptTemplateName = MANUAL_TEMPLATE_NAME;
    response.dataSource = 'MANUAL_RELATIONSHIP';
    response.generatedAt = Datetime.now();
    response.supplyScenario = normalizeSupplyScenario(supplyScenario, true);
    response.supplyScenarioLabel = getSupplyScenarioLabel(
      response.supplyScenario
    );

    NodeDto rootNode = buildPromptRootNode(rootAccount);
    String rootId = rootNode.id;
    Map<String, NodeDto> nodeById = new Map<String, NodeDto>{
      rootId => rootNode
    };
    Map<String, List<String>> outgoingByNode = new Map<String, List<String>>{
      rootId => new List<String>()
    };
    Map<String, List<String>> incomingByNode = new Map<String, List<String>>{
      rootId => new List<String>()
    };
    Set<String> dedupeKeys = new Set<String>();
    PromptScopeFilter promptScopeFilter = String.isBlank(
        response.supplyScenario
      )
      ? buildPromptScopeFilter(rootAccount, promptScopeJsonOverride)
      : null;

    Integer relationshipIndex = 0;
    for (CM_Supply_Relationship__c relationshipRecord : [
      SELECT
        Id,
        Source_Account__c,
        Source_Account__r.Id,
        Source_Account__r.Name,
        Source_Account__r.Type,
        Target_Account__c,
        Target_Account__r.Id,
        Target_Account__r.Name,
        Target_Account__r.Type,
        Edge_Category__c,
        Relation_Type__c,
        Role__c,
        Products__c,
        Supply_Scenario__c,
        Supply_Scenario_Code__c,
        Evidence__c,
        Confidence__c
      FROM CM_Supply_Relationship__c
      WHERE
        Is_Active__c = TRUE
        AND Source_Account__c != NULL
        AND Target_Account__c != NULL
      ORDER BY LastModifiedDate DESC
      LIMIT :MANUAL_RELATIONSHIP_QUERY_LIMIT
    ]) {
      if (
        relationshipRecord.Confidence__c != null &&
        relationshipRecord.Confidence__c < MIN_CONFIDENCE
      ) {
        continue;
      }
      if (
        !matchesSupplyScenario(
          extractRelationshipSupplyScenario(relationshipRecord),
          response.supplyScenario
        )
      ) {
        continue;
      }

      String sourceId = String.valueOf(relationshipRecord.Source_Account__c);
      String targetId = String.valueOf(relationshipRecord.Target_Account__c);
      if (sourceId == targetId) {
        continue;
      }

      NormalizedEdgeOrientation orientation = normalizeEdgeOrientation(
        relationshipRecord.Edge_Category__c,
        sourceId,
        targetId,
        rootId
      );
      sourceId = orientation.sourceId;
      targetId = orientation.targetId;
      String edgeCategory = orientation.edgeCategory;

      String relationType = relationshipRecord.Relation_Type__c;
      if (String.isBlank(relationType)) {
        relationType = defaultRelationTypeByCategory(edgeCategory);
      }

      if (
        !isManualRelationshipInPromptScope(
          promptScopeFilter,
          sourceId,
          targetId,
          edgeCategory,
          relationType
        )
      ) {
        continue;
      }

      String direction = inferRelationshipDirection(
        edgeCategory,
        sourceId,
        targetId,
        rootId
      );
      String dedupeKey =
        sourceId +
        '|' +
        targetId +
        '|' +
        relationType +
        '|' +
        direction;
      if (dedupeKeys.contains(dedupeKey)) {
        continue;
      }
      dedupeKeys.add(dedupeKey);

      if (!nodeById.containsKey(sourceId)) {
        nodeById.put(
          sourceId,
          buildManualNode(sourceId, relationshipRecord.Source_Account__r)
        );
      }
      if (!nodeById.containsKey(targetId)) {
        nodeById.put(
          targetId,
          buildManualNode(targetId, relationshipRecord.Target_Account__r)
        );
      }

      updateManualNodeMetadata(nodeById.get(sourceId), relationshipRecord);
      updateManualNodeMetadata(nodeById.get(targetId), relationshipRecord);

      ensureAdjacency(outgoingByNode, sourceId);
      ensureAdjacency(outgoingByNode, targetId);
      ensureAdjacency(incomingByNode, sourceId);
      ensureAdjacency(incomingByNode, targetId);
      outgoingByNode.get(sourceId).add(targetId);
      incomingByNode.get(targetId).add(sourceId);

      EdgeDto edge = new EdgeDto();
      String edgeSeed =
        sourceId +
        '|' +
        targetId +
        '|' +
        relationType +
        '|' +
        edgeCategory;
      edge.id = buildEdgeId(edgeSeed, relationshipIndex);
      edge.sourceId = sourceId;
      edge.targetId = targetId;
      edge.relationType = relationType;
      edge.edgeCategory = edgeCategory;
      edge.relationshipDirection = direction;
      response.edges.add(edge);
      relationshipIndex++;
    }

    if (response.edges.isEmpty()) {
      response.nodes.add(rootNode);
      response.nodeCount = 1;
      response.edgeCount = 0;
      response.coverageNote = buildManualCoverageNote(
        response.supplyScenario,
        '手動模式：此帳戶目前尚未建立可視化關係。請先新增 CM Supply Relationship 資料。'
      );
      return response;
    }

    Map<String, Integer> downstreamDistanceByNode = computeShortestDistance(
      outgoingByNode,
      rootId
    );
    Map<String, Integer> upstreamDistanceByNode = computeShortestDistance(
      incomingByNode,
      rootId
    );
    Map<String, Integer> weakDistanceByNode = computeWeaklyConnectedDistance(
      outgoingByNode,
      incomingByNode,
      rootId
    );
    Set<String> connectedNodeIds = new Set<String>{ rootId };
    connectedNodeIds.addAll(weakDistanceByNode.keySet());

    Set<String> competitorNodeIds = new Set<String>();
    for (EdgeDto edge : response.edges) {
      if (edge.relationshipDirection != 'COMPETITOR') {
        continue;
      }
      if (edge.sourceId == rootId && connectedNodeIds.contains(edge.targetId)) {
        competitorNodeIds.add(edge.targetId);
      } else if (
        edge.targetId == rootId && connectedNodeIds.contains(edge.sourceId)
      ) {
        competitorNodeIds.add(edge.sourceId);
      }
    }

    Map<String, Integer> signedLevelByNodeId = new Map<String, Integer>();
    for (String nodeId : connectedNodeIds) {
      if (nodeId == rootId) {
        continue;
      }
      NodeDto node = nodeById.get(nodeId);
      if (node == null) {
        continue;
      }

      Integer downstreamDistance = downstreamDistanceByNode.get(nodeId);
      Integer upstreamDistance = upstreamDistanceByNode.get(nodeId);
      Integer weakDistance = weakDistanceByNode.get(nodeId);

      if (competitorNodeIds.contains(nodeId)) {
        Integer competitorDepth = downstreamDistance == null
          ? 2
          : Math.max(2, downstreamDistance);
        node.signedLevel = competitorDepth;
        node.upstreamDepth = null;
        node.downstreamDepth = competitorDepth;
        node.relationshipDirection = 'COMPETITOR';
        signedLevelByNodeId.put(nodeId, competitorDepth);
        continue;
      }

      Integer signedLevel;
      if (downstreamDistance != null && upstreamDistance == null) {
        signedLevel = downstreamDistance;
      } else if (upstreamDistance != null && downstreamDistance == null) {
        signedLevel = -upstreamDistance;
      } else if (upstreamDistance != null && downstreamDistance != null) {
        signedLevel = downstreamDistance <= upstreamDistance
          ? downstreamDistance
          : -upstreamDistance;
      } else {
        signedLevel = resolveWeaklyConnectedSignedLevel(
          nodeId,
          weakDistance,
          outgoingByNode,
          incomingByNode,
          connectedNodeIds
        );
      }

      node.signedLevel = signedLevel;
      node.upstreamDepth = signedLevel < 0 ? Math.abs(signedLevel) : null;
      node.downstreamDepth = signedLevel > 0 ? signedLevel : null;
      node.relationshipDirection = signedLevel < 0 ? 'UPSTREAM' : 'DOWNSTREAM';
      signedLevelByNodeId.put(nodeId, signedLevel);
    }

    List<String> orderedNodeIds = new List<String>();
    orderedNodeIds.addAll(signedLevelByNodeId.keySet());
    orderedNodeIds.sort(
      new PromptNodeComparator(signedLevelByNodeId, nodeById)
    );
    Set<String> pinnedNodeIds = resolvePinnedNodeIds(
      rootAccount,
      nodeById,
      rootId
    );

    NodeSelectionResult selectionResult = selectIncludedNodeIds(
      rootId,
      orderedNodeIds,
      signedLevelByNodeId,
      nodeCap,
      pinnedNodeIds
    );
    Set<String> includedNodeIds = selectionResult.includedNodeIds;
    response.truncated = selectionResult.truncated;

    List<EdgeDto> retainedEdges = new List<EdgeDto>();
    for (EdgeDto edge : response.edges) {
      if (
        !includedNodeIds.contains(edge.sourceId) ||
        !includedNodeIds.contains(edge.targetId)
      ) {
        continue;
      }
      retainedEdges.add(edge);
    }
    response.edges = retainedEdges;

    response.nodes.add(rootNode);
    for (String nodeId : orderedNodeIds) {
      if (!includedNodeIds.contains(nodeId)) {
        continue;
      }
      response.nodes.add(nodeById.get(nodeId));
    }
    response.nodeCount = response.nodes.size();
    response.edgeCount = response.edges.size();
    response.coverageNote = buildManualCoverageNote(
      response.supplyScenario,
      response.edgeCount == 0
        ? '手動模式：此帳戶目前尚未建立可視化關係。請先新增 CM Supply Relationship 資料。'
        : '手動模式：使用 CM Supply Relationship 資料繪製。'
    );
    return response;
  }

  private static GraphResponse buildDemoGraphResponse(
    Account rootAccount,
    Integer nodeCap
  ) {
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
      nodeDefinitionByNameKey.put(
        normalizeName(nodeDefinition.accountName),
        nodeDefinition
      );
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
    Map<String, Integer> downstreamDistanceByNode = computeShortestDistance(
      outgoingByNode,
      rootNameKey
    );
    Map<String, Integer> upstreamDistanceByNode = computeShortestDistance(
      incomingByNode,
      rootNameKey
    );

    Set<String> includedNameKeys = new Set<String>{ rootNameKey };
    for (String nameKey : allNodeNameKeys) {
      if (
        downstreamDistanceByNode.containsKey(nameKey) ||
        upstreamDistanceByNode.containsKey(nameKey)
      ) {
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
      signedLevelByNameKey.put(
        nameKey,
        downstreamDistance <= upstreamDistance
          ? downstreamDistance
          : -upstreamDistance
      );
    }

    List<String> orderedNodeKeys = new List<String>();
    orderedNodeKeys.addAll(signedLevelByNameKey.keySet());
    orderedNodeKeys.sort(
      new NodeDistanceComparator(
        signedLevelByNameKey,
        nodeDefinitionByNameKey,
        accountByNameKey
      )
    );

    Map<String, NodeDto> nodeByNameKey = new Map<String, NodeDto>();
    NodeDto rootNode = buildDemoNode(
      rootAccount,
      rootAccount.Name,
      true,
      0,
      0,
      0,
      'ROOT',
      nodeDefinitionByNameKey.containsKey(rootNameKey)
        ? nodeDefinitionByNameKey.get(rootNameKey).roleLabel
        : '核心節點',
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
      String relationshipDirection = signedLevel < 0
        ? 'UPSTREAM'
        : 'DOWNSTREAM';
      NodeDto node = buildDemoNode(
        matchedAccount,
        fallbackLabel,
        false,
        signedLevel,
        upstreamDepth,
        downstreamDepth,
        relationshipDirection,
        nodeDefinition == null ? '關聯節點' : nodeDefinition.roleLabel,
        nodeDefinition == null
          ? '固定 Demo 供應鏈節點。'
          : nodeDefinition.noteText
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

      String edgeKey =
        sourceNode.id +
        '|' +
        targetNode.id +
        '|' +
        edgeDefinition.relationType +
        '|' +
        edgeDefinition.direction;
      EdgeDto edge = new EdgeDto();
      edge.id = buildEdgeId(edgeKey, edgeIndex);
      edge.sourceId = sourceNode.id;
      edge.targetId = targetNode.id;
      edge.relationType = edgeDefinition.relationType;
      edge.edgeCategory = edgeDefinition.direction;
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
      : '固定 Demo 圖已載入，但以下節點缺少 Account 無法點擊：' +
        String.join(missingAccounts, '、');
    response.nodes.addAll(nodeByNameKey.values());
    response.nodeCount = response.nodes.size();
    response.edgeCount = response.edges.size();
    return response;
  }

  @TestVisible
  private static GraphResponse buildResponseFromPrompt(
    String rawPromptJson,
    Account rootAccount,
    Integer nodeCap
  ) {
    Map<String, Object> payload = parsePromptPayload(rawPromptJson);
    String payloadError = stringValue(payload.get('error'));
    if (!String.isBlank(payloadError)) {
      String payloadReason = stringValue(payload.get('reason'));
      throw new AuraHandledException(
        'Prompt template returned an error: ' +
          payloadError +
          (String.isBlank(payloadReason) ? '' : ' (' + payloadReason + ')')
      );
    }

    List<Object> relationshipObjects = asList(payload.get('relationships'));
    if (relationshipObjects == null) {
      throw new AuraHandledException(
        'Prompt output is missing the relationships array.'
      );
    }

    AccountLookup accountLookup = buildAccountLookup(relationshipObjects);
    if (isEdgeBasedPrompt(relationshipObjects)) {
      return buildResponseFromPromptEdges(
        relationshipObjects,
        payload,
        rootAccount,
        nodeCap,
        accountLookup
      );
    }
    return buildResponseFromPromptLegacy(
      relationshipObjects,
      payload,
      rootAccount,
      nodeCap,
      accountLookup
    );
  }

  private static GraphResponse buildResponseFromPromptLegacy(
    List<Object> relationshipObjects,
    Map<String, Object> payload,
    Account rootAccount,
    Integer nodeCap,
    AccountLookup accountLookup
  ) {
    GraphResponse response = new GraphResponse();
    response.rootId = String.valueOf(rootAccount.Id);
    response.promptTemplateName = PROMPT_TEMPLATE_DEVELOPER_NAME;
    response.dataSource = 'PROMPT_TEMPLATE';
    response.generatedAt = Datetime.now();

    NodeDto rootNode = buildPromptRootNode(rootAccount);

    String rootNameKey = normalizeName(rootAccount.Name);
    String rootDomain = normalizeDomain(rootAccount.Website);

    Map<String, NodeDto> nodeById = new Map<String, NodeDto>{
      rootNode.id => rootNode
    };
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

      String direction = normalizeDirection(
        stringValue(relationship.get('direction'))
      );
      if (direction == null) {
        continue;
      }

      String companyDomain = normalizeDomain(
        stringValue(relationship.get('company_domain'))
      );
      if (String.isBlank(companyDomain)) {
        continue;
      }

      String companyName = stringValue(relationship.get('company_name'));
      if (String.isBlank(companyName)) {
        companyName = companyDomain;
      }

      if (
        (!String.isBlank(rootDomain) && companyDomain == rootDomain) ||
        (!String.isBlank(rootNameKey) &&
        normalizeName(companyName) == rootNameKey)
      ) {
        continue;
      }

      String companyBusinessUnit = stringValue(
        relationship.get('company_business_unit')
      );
      String dedupeKey =
        companyDomain +
        (String.isBlank(companyBusinessUnit)
          ? ''
          : '|' + companyBusinessUnit.toLowerCase());
      String nodeId = buildExternalNodeId(dedupeKey);

      if (!nodeById.containsKey(nodeId)) {
        if (nodeById.size() >= nodeCap) {
          response.truncated = true;
          continue;
        }

        Account matchedAccount = resolveAccountForRelationship(
          relationship,
          accountLookup
        );
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
          node.signedLevel = 2;
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
        relationType = direction == 'UPSTREAM'
          ? 'Supplier'
          : (direction == 'COMPETITOR' ? 'Direct Competitor' : 'Customer');
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
      edge.edgeCategory = direction;
      edge.relationshipDirection = direction;
      edge.marketRiskNote = truncateText(
        stringValue(relationship.get('market_risk_note')),
        255
      );
      response.edges.add(edge);
      relationshipIndex++;
    }

    response.nodes.addAll(nodeById.values());
    response.nodeCount = response.nodes.size();
    response.edgeCount = response.edges.size();

    Map<String, Object> summary = asMap(payload.get('summary'));
    response.coverageNote = summary == null
      ? null
      : stringValue(summary.get('coverage_note'));
    if (String.isBlank(response.coverageNote)) {
      response.coverageNote = '已啟用 Auto Prompt 並完成關係圖生成。';
    }

    return response;
  }

  private static GraphResponse buildResponseFromPromptEdges(
    List<Object> relationshipObjects,
    Map<String, Object> payload,
    Account rootAccount,
    Integer nodeCap,
    AccountLookup accountLookup
  ) {
    GraphResponse response = new GraphResponse();
    response.rootId = String.valueOf(rootAccount.Id);
    response.promptTemplateName = PROMPT_TEMPLATE_DEVELOPER_NAME;
    response.dataSource = 'PROMPT_TEMPLATE';
    response.generatedAt = Datetime.now();

    NodeDto rootNode = buildPromptRootNode(rootAccount);
    String rootId = rootNode.id;
    String rootDomain = normalizeDomain(rootAccount.Website);
    String rootNameKey = normalizeName(rootAccount.Name);

    Map<String, NodeDto> nodeById = new Map<String, NodeDto>{
      rootId => rootNode
    };
    Map<String, List<String>> outgoingByNode = new Map<String, List<String>>{
      rootId => new List<String>()
    };
    Map<String, List<String>> incomingByNode = new Map<String, List<String>>{
      rootId => new List<String>()
    };
    Set<String> dedupeKeys = new Set<String>();

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

      String sourceDomain = normalizeDomain(
        stringValue(relationship.get('source_company_domain'))
      );
      String targetDomain = normalizeDomain(
        stringValue(relationship.get('target_company_domain'))
      );
      if (String.isBlank(sourceDomain) || String.isBlank(targetDomain)) {
        continue;
      }

      String sourceName = stringValue(relationship.get('source_company_name'));
      String targetName = stringValue(relationship.get('target_company_name'));
      if (String.isBlank(sourceName)) {
        sourceName = sourceDomain;
      }
      if (String.isBlank(targetName)) {
        targetName = targetDomain;
      }

      String sourceNameKey = normalizeName(sourceName);
      String targetNameKey = normalizeName(targetName);
      Boolean sourceIsRoot = isRootCompany(
        sourceDomain,
        sourceNameKey,
        rootDomain,
        rootNameKey
      );
      Boolean targetIsRoot = isRootCompany(
        targetDomain,
        targetNameKey,
        rootDomain,
        rootNameKey
      );
      String sourceId = sourceIsRoot
        ? rootId
        : buildExternalNodeId(sourceDomain);
      String targetId = targetIsRoot
        ? rootId
        : buildExternalNodeId(targetDomain);
      if (sourceId == targetId) {
        continue;
      }

      String edgeCategory = normalizeEdgeCategory(
        stringValue(relationship.get('edge_category'))
      );
      if (edgeCategory == null) {
        if (targetIsRoot) {
          edgeCategory = 'UPSTREAM';
        } else if (sourceIsRoot) {
          edgeCategory = 'DOWNSTREAM';
        } else {
          edgeCategory = 'INDIRECT_PATH';
        }
      }

      String dedupeKey = sourceDomain + '|' + targetDomain;
      if (dedupeKeys.contains(dedupeKey)) {
        continue;
      }
      dedupeKeys.add(dedupeKey);

      if (!nodeById.containsKey(sourceId)) {
        NodeDto sourceNode = buildPromptNode(
          sourceId,
          sourceName,
          sourceDomain,
          accountLookup
        );
        nodeById.put(sourceId, sourceNode);
      }
      if (!nodeById.containsKey(targetId)) {
        NodeDto targetNode = buildPromptNode(
          targetId,
          targetName,
          targetDomain,
          accountLookup
        );
        nodeById.put(targetId, targetNode);
      }

      updatePromptNodeMetadata(nodeById.get(sourceId), relationship);
      updatePromptNodeMetadata(nodeById.get(targetId), relationship);

      ensureAdjacency(outgoingByNode, sourceId);
      ensureAdjacency(outgoingByNode, targetId);
      ensureAdjacency(incomingByNode, sourceId);
      ensureAdjacency(incomingByNode, targetId);
      outgoingByNode.get(sourceId).add(targetId);
      incomingByNode.get(targetId).add(sourceId);

      String relationType = stringValue(relationship.get('relation_type'));
      if (String.isBlank(relationType)) {
        relationType = defaultRelationTypeByCategory(edgeCategory);
      }

      EdgeDto edge = new EdgeDto();
      String edgeSeed =
        sourceId +
        '|' +
        targetId +
        '|' +
        relationType +
        '|' +
        edgeCategory;
      edge.id = buildEdgeId(edgeSeed, relationshipIndex);
      edge.sourceId = sourceId;
      edge.targetId = targetId;
      edge.relationType = relationType;
      edge.edgeCategory = edgeCategory;
      edge.relationshipDirection = inferRelationshipDirection(
        edgeCategory,
        sourceId,
        targetId,
        rootId
      );
      edge.marketRiskNote = truncateText(
        stringValue(relationship.get('market_risk_note')),
        255
      );
      response.edges.add(edge);
      relationshipIndex++;
    }

    Map<String, Integer> downstreamDistanceByNode = computeShortestDistance(
      outgoingByNode,
      rootId
    );
    Map<String, Integer> upstreamDistanceByNode = computeShortestDistance(
      incomingByNode,
      rootId
    );
    Map<String, Integer> weakDistanceByNode = computeWeaklyConnectedDistance(
      outgoingByNode,
      incomingByNode,
      rootId
    );
    Set<String> connectedNodeIds = new Set<String>{ rootId };
    connectedNodeIds.addAll(weakDistanceByNode.keySet());

    Set<String> competitorNodeIds = new Set<String>();
    for (EdgeDto edge : response.edges) {
      if (edge.relationshipDirection != 'COMPETITOR') {
        continue;
      }
      if (edge.sourceId == rootId && connectedNodeIds.contains(edge.targetId)) {
        competitorNodeIds.add(edge.targetId);
      } else if (
        edge.targetId == rootId && connectedNodeIds.contains(edge.sourceId)
      ) {
        competitorNodeIds.add(edge.sourceId);
      }
    }

    Map<String, Integer> signedLevelByNodeId = new Map<String, Integer>();
    for (String nodeId : connectedNodeIds) {
      if (nodeId == rootId) {
        continue;
      }
      NodeDto node = nodeById.get(nodeId);
      if (node == null) {
        continue;
      }

      Integer downstreamDistance = downstreamDistanceByNode.get(nodeId);
      Integer upstreamDistance = upstreamDistanceByNode.get(nodeId);
      Integer weakDistance = weakDistanceByNode.get(nodeId);

      if (competitorNodeIds.contains(nodeId)) {
        Integer competitorDepth = downstreamDistance == null
          ? 2
          : Math.max(2, downstreamDistance);
        node.signedLevel = competitorDepth;
        node.upstreamDepth = null;
        node.downstreamDepth = competitorDepth;
        node.relationshipDirection = 'COMPETITOR';
        signedLevelByNodeId.put(nodeId, competitorDepth);
        continue;
      }

      Integer signedLevel;
      if (downstreamDistance != null && upstreamDistance == null) {
        signedLevel = downstreamDistance;
      } else if (upstreamDistance != null && downstreamDistance == null) {
        signedLevel = -upstreamDistance;
      } else if (upstreamDistance != null && downstreamDistance != null) {
        signedLevel = downstreamDistance <= upstreamDistance
          ? downstreamDistance
          : -upstreamDistance;
      } else {
        signedLevel = resolveWeaklyConnectedSignedLevel(
          nodeId,
          weakDistance,
          outgoingByNode,
          incomingByNode,
          connectedNodeIds
        );
      }

      node.signedLevel = signedLevel;
      node.upstreamDepth = signedLevel < 0 ? Math.abs(signedLevel) : null;
      node.downstreamDepth = signedLevel > 0 ? signedLevel : null;
      node.relationshipDirection = signedLevel < 0 ? 'UPSTREAM' : 'DOWNSTREAM';
      signedLevelByNodeId.put(nodeId, signedLevel);
    }

    List<String> orderedNodeIds = new List<String>();
    orderedNodeIds.addAll(signedLevelByNodeId.keySet());
    orderedNodeIds.sort(
      new PromptNodeComparator(signedLevelByNodeId, nodeById)
    );
    Set<String> pinnedNodeIds = resolvePinnedNodeIds(
      rootAccount,
      nodeById,
      rootId
    );

    NodeSelectionResult selectionResult = selectIncludedNodeIds(
      rootId,
      orderedNodeIds,
      signedLevelByNodeId,
      nodeCap,
      pinnedNodeIds
    );
    Set<String> includedNodeIds = selectionResult.includedNodeIds;
    response.truncated = selectionResult.truncated;

    List<EdgeDto> retainedEdges = new List<EdgeDto>();
    for (EdgeDto edge : response.edges) {
      if (
        !includedNodeIds.contains(edge.sourceId) ||
        !includedNodeIds.contains(edge.targetId)
      ) {
        response.truncated = true;
        continue;
      }
      retainedEdges.add(edge);
    }
    response.edges = retainedEdges;

    response.nodes.add(rootNode);
    for (String nodeId : orderedNodeIds) {
      if (!includedNodeIds.contains(nodeId)) {
        continue;
      }
      response.nodes.add(nodeById.get(nodeId));
    }
    response.nodeCount = response.nodes.size();
    response.edgeCount = response.edges.size();

    Map<String, Object> summary = asMap(payload.get('summary'));
    response.coverageNote = summary == null
      ? null
      : stringValue(summary.get('coverage_note'));
    if (String.isBlank(response.coverageNote)) {
      response.coverageNote = '已啟用 Auto Prompt 並完成多層級供應鏈關係圖生成。';
    }

    return response;
  }

  private static Boolean isEdgeBasedPrompt(List<Object> relationshipObjects) {
    for (Object relationshipObject : relationshipObjects) {
      Map<String, Object> relationship = asMap(relationshipObject);
      if (relationship == null) {
        continue;
      }
      if (
        relationship.containsKey('source_company_name') ||
        relationship.containsKey('source_company_domain') ||
        relationship.containsKey('target_company_name') ||
        relationship.containsKey('target_company_domain')
      ) {
        return true;
      }
    }
    return false;
  }

  private static Boolean isRootCompany(
    String domain,
    String nameKey,
    String rootDomain,
    String rootNameKey
  ) {
    return (!String.isBlank(rootDomain) && domain == rootDomain) ||
      (!String.isBlank(rootNameKey) && nameKey == rootNameKey);
  }

  private static NodeDto buildPromptRootNode(Account rootAccount) {
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
    rootNode.roleLabel = '供應鏈核心';
    rootNode.noteText = String.isBlank(rootAccount.Description)
      ? '供應鏈核心'
      : rootAccount.Description;
    return rootNode;
  }

  private static NodeDto buildPromptNode(
    String nodeId,
    String companyName,
    String companyDomain,
    AccountLookup accountLookup
  ) {
    NodeDto node = new NodeDto();
    node.id = nodeId;
    node.isRoot = false;
    node.signedLevel = 1;
    node.upstreamDepth = null;
    node.downstreamDepth = 1;
    node.relationshipDirection = 'DOWNSTREAM';
    node.label = companyName;
    node.roleLabel = '關聯節點';
    node.noteText = 'AI 生成的候選供應鏈關係。';

    Account matchedAccount = resolveAccountForCompany(
      companyDomain,
      normalizeName(companyName),
      accountLookup
    );
    node.accountId = matchedAccount == null ? null : matchedAccount.Id;
    node.accountType = matchedAccount == null ? null : matchedAccount.Type;
    return node;
  }

  private static NodeDto buildManualNode(String nodeId, Account accountRecord) {
    NodeDto node = new NodeDto();
    node.id = nodeId;
    node.accountId = accountRecord == null ? null : accountRecord.Id;
    node.label = accountRecord == null ? 'Unknown Account' : accountRecord.Name;
    node.isRoot = false;
    node.signedLevel = 1;
    node.upstreamDepth = null;
    node.downstreamDepth = 1;
    node.relationshipDirection = 'DOWNSTREAM';
    node.accountType = accountRecord == null ? null : accountRecord.Type;
    node.roleLabel = '關聯節點';
    node.noteText = '手動維護的供應鏈關係節點。';
    return node;
  }

  private static void updateManualNodeMetadata(
    NodeDto node,
    CM_Supply_Relationship__c relationshipRecord
  ) {
    if (node == null || node.isRoot || relationshipRecord == null) {
      return;
    }

    if (
      !String.isBlank(relationshipRecord.Role__c) &&
      (String.isBlank(node.roleLabel) || node.roleLabel == '關聯節點')
    ) {
      node.roleLabel = relationshipRecord.Role__c;
    }

    if (
      !String.isBlank(node.noteText) &&
      node.noteText != '手動維護的供應鏈關係節點。'
    ) {
      return;
    }

    String noteText = extractManualRelationshipNote(relationshipRecord);
    if (!String.isBlank(noteText)) {
      node.noteText = noteText;
    }
  }

  private static String extractManualRelationshipNote(
    CM_Supply_Relationship__c relationshipRecord
  ) {
    if (!String.isBlank(relationshipRecord.Evidence__c)) {
      return trimNoteText(relationshipRecord.Evidence__c);
    }
    if (!String.isBlank(relationshipRecord.Products__c)) {
      return trimNoteText('產品: ' + relationshipRecord.Products__c);
    }
    return null;
  }

  private static String trimNoteText(String rawText) {
    if (String.isBlank(rawText)) {
      return null;
    }
    String normalized = rawText.trim();
    if (normalized.length() <= 220) {
      return normalized;
    }
    return normalized.substring(0, 220) + '...';
  }

  private static void updatePromptNodeMetadata(
    NodeDto node,
    Map<String, Object> relationship
  ) {
    if (node == null || node.isRoot) {
      return;
    }

    String roleValue = stringValue(relationship.get('role'));
    if (
      !String.isBlank(roleValue) &&
      (String.isBlank(node.roleLabel) || node.roleLabel == '關聯節點')
    ) {
      node.roleLabel = roleValue;
    }

    String noteValue = buildNoteText(relationship);
    if (
      !String.isBlank(noteValue) &&
      (String.isBlank(node.noteText) ||
      node.noteText == 'AI 生成的候選供應鏈關係。')
    ) {
      node.noteText = noteValue;
    }
  }

  private static void ensureAdjacency(
    Map<String, List<String>> adjacencyByNode,
    String nodeId
  ) {
    if (!adjacencyByNode.containsKey(nodeId)) {
      adjacencyByNode.put(nodeId, new List<String>());
    }
  }

  private static String normalizeEdgeCategory(String edgeCategoryValue) {
    String normalized = String.isBlank(edgeCategoryValue)
      ? null
      : edgeCategoryValue.trim().toUpperCase();
    return SUPPORTED_EDGE_CATEGORIES.contains(normalized) ? normalized : null;
  }

  private static NormalizedEdgeOrientation normalizeEdgeOrientation(
    String rawEdgeCategory,
    String rawSourceId,
    String rawTargetId,
    String rootId
  ) {
    NormalizedEdgeOrientation orientation = new NormalizedEdgeOrientation();
    orientation.sourceId = rawSourceId;
    orientation.targetId = rawTargetId;
    orientation.edgeCategory = normalizeEdgeCategory(rawEdgeCategory);

    if (String.isBlank(orientation.edgeCategory)) {
      if (orientation.targetId == rootId) {
        orientation.edgeCategory = 'UPSTREAM';
      } else if (orientation.sourceId == rootId) {
        orientation.edgeCategory = 'DOWNSTREAM';
      } else {
        orientation.edgeCategory = 'INDIRECT_PATH';
      }
    }

    if (
      String.isBlank(rootId) ||
      String.isBlank(orientation.sourceId) ||
      String.isBlank(orientation.targetId) ||
      orientation.sourceId == orientation.targetId ||
      orientation.edgeCategory == 'COMPETITOR'
    ) {
      return orientation;
    }

    Boolean sourceIsRoot = orientation.sourceId == rootId;
    Boolean targetIsRoot = orientation.targetId == rootId;
    if (sourceIsRoot && !targetIsRoot) {
      orientation.edgeCategory = 'DOWNSTREAM';
      return orientation;
    }
    if (targetIsRoot && !sourceIsRoot) {
      orientation.edgeCategory = 'UPSTREAM';
      return orientation;
    }
    return orientation;
  }

  private static String defaultRelationTypeByCategory(String edgeCategory) {
    if (edgeCategory == 'UPSTREAM') {
      return 'Supplier';
    }
    if (edgeCategory == 'DOWNSTREAM') {
      return 'Customer';
    }
    if (edgeCategory == 'COMPETITOR') {
      return 'Direct Competitor';
    }
    return 'Other';
  }

  private static String inferRelationshipDirection(
    String edgeCategory,
    String sourceId,
    String targetId,
    String rootId
  ) {
    if (edgeCategory == 'COMPETITOR') {
      return 'COMPETITOR';
    }
    if (targetId == rootId || edgeCategory == 'UPSTREAM') {
      return 'UPSTREAM';
    }
    return 'DOWNSTREAM';
  }

  private static Integer resolveWeaklyConnectedSignedLevel(
    String nodeId,
    Integer weakDistance,
    Map<String, List<String>> outgoingByNode,
    Map<String, List<String>> incomingByNode,
    Set<String> connectedNodeIds
  ) {
    Integer depth = (weakDistance != null &&
      weakDistance > 0)
      ? weakDistance
      : 1;
    if (String.isBlank(nodeId)) {
      return depth;
    }

    Boolean hasConnectedOutgoing = false;
    List<String> outgoingTargets = outgoingByNode == null
      ? null
      : outgoingByNode.get(nodeId);
    if (outgoingTargets != null) {
      for (String targetId : outgoingTargets) {
        if (connectedNodeIds != null && !connectedNodeIds.contains(targetId)) {
          continue;
        }
        hasConnectedOutgoing = true;
        break;
      }
    }

    Boolean hasConnectedIncoming = false;
    List<String> incomingSources = incomingByNode == null
      ? null
      : incomingByNode.get(nodeId);
    if (incomingSources != null) {
      for (String sourceId : incomingSources) {
        if (connectedNodeIds != null && !connectedNodeIds.contains(sourceId)) {
          continue;
        }
        hasConnectedIncoming = true;
        break;
      }
    }

    if (hasConnectedOutgoing && !hasConnectedIncoming) {
      return -depth;
    }
    if (hasConnectedIncoming && !hasConnectedOutgoing) {
      return depth;
    }
    return depth;
  }

  private static NodeSelectionResult selectIncludedNodeIds(
    String rootId,
    List<String> orderedNodeIds,
    Map<String, Integer> signedLevelByNodeId,
    Integer nodeCap,
    Set<String> pinnedNodeIds
  ) {
    NodeSelectionResult result = new NodeSelectionResult();
    result.includedNodeIds = new Set<String>{ rootId };

    Integer directUpstreamCount = 0;
    Integer directDownstreamCount = 0;
    Boolean cappedByCount = false;
    Boolean cappedByTierLimit = false;
    Set<String> pinnedById = new Set<String>();
    if (pinnedNodeIds != null) {
      pinnedById.addAll(pinnedNodeIds);
    }
    pinnedById.remove(rootId);

    if (orderedNodeIds == null) {
      return result;
    }

    for (String nodeId : orderedNodeIds) {
      if (!pinnedById.contains(nodeId)) {
        continue;
      }
      if (result.includedNodeIds.size() >= nodeCap) {
        cappedByCount = true;
        break;
      }
      if (result.includedNodeIds.contains(nodeId)) {
        continue;
      }
      Integer signedLevel = signedLevelByNodeId == null
        ? null
        : signedLevelByNodeId.get(nodeId);
      if (signedLevel == -1) {
        directUpstreamCount++;
      } else if (signedLevel == 1) {
        directDownstreamCount++;
      }
      result.includedNodeIds.add(nodeId);
    }

    for (String nodeId : orderedNodeIds) {
      if (pinnedById.contains(nodeId)) {
        continue;
      }

      if (result.includedNodeIds.size() >= nodeCap) {
        cappedByCount = true;
        break;
      }

      Integer signedLevel = signedLevelByNodeId == null
        ? null
        : signedLevelByNodeId.get(nodeId);
      if (signedLevel == -1) {
        if (directUpstreamCount >= DIRECT_UPSTREAM_NODE_LIMIT) {
          cappedByTierLimit = true;
          continue;
        }
        directUpstreamCount++;
      } else if (signedLevel == 1) {
        if (directDownstreamCount >= DIRECT_DOWNSTREAM_NODE_LIMIT) {
          cappedByTierLimit = true;
          continue;
        }
        directDownstreamCount++;
      }

      result.includedNodeIds.add(nodeId);
    }

    result.truncated =
      cappedByCount ||
      cappedByTierLimit ||
      (orderedNodeIds.size() > Math.max(0, result.includedNodeIds.size() - 1));
    return result;
  }

  private static Set<String> resolvePinnedNodeIds(
    Account rootAccount,
    Map<String, NodeDto> nodeById,
    String rootId
  ) {
    Set<String> pinnedNameKeys = new Set<String>();

    if (
      rootAccount != null &&
      !String.isBlank(rootAccount.CM_Supply_Network_Prompt_JSON__c)
    ) {
      try {
        Map<String, Object> payload = parsePromptPayload(
          rootAccount.CM_Supply_Network_Prompt_JSON__c
        );
        Map<String, Object> focusCompany = asMap(
          payload.get('focus_company_analysis')
        );
        if (focusCompany != null) {
          String focusCompanyName = normalizeName(
            stringValue(focusCompany.get('focus_company_name'))
          );
          if (!String.isBlank(focusCompanyName)) {
            pinnedNameKeys.add(focusCompanyName);
          }
        }

        Map<String, Object> qualityPayload = asMap(payload.get('quality'));
        if (qualityPayload != null) {
          List<Object> mustIncludeTargets = asList(
            qualityPayload.get('must_include_targets')
          );
          if (mustIncludeTargets != null) {
            for (Object rawTarget : mustIncludeTargets) {
              String targetNameKey = normalizeName(stringValue(rawTarget));
              if (!String.isBlank(targetNameKey)) {
                pinnedNameKeys.add(targetNameKey);
              }
            }
          }
        }
      } catch (Exception ex) {
        // Invalid prompt snapshot should not block graph selection.
      }
    }

    Set<String> pinnedNodeIds = new Set<String>();
    if (nodeById == null || nodeById.isEmpty() || pinnedNameKeys.isEmpty()) {
      return pinnedNodeIds;
    }

    for (NodeDto node : nodeById.values()) {
      if (node == null || String.isBlank(node.id) || node.id == rootId) {
        continue;
      }
      String labelKey = normalizeName(node.label);
      if (!String.isBlank(labelKey) && pinnedNameKeys.contains(labelKey)) {
        pinnedNodeIds.add(node.id);
      }
    }
    return pinnedNodeIds;
  }

  private static PromptScopeFilter buildPromptScopeFilter(
    Account rootAccount,
    String promptScopeJsonOverride
  ) {
    if (rootAccount == null) {
      return null;
    }

    String promptJson = String.isBlank(promptScopeJsonOverride)
      ? rootAccount.CM_Supply_Network_Prompt_JSON__c
      : promptScopeJsonOverride;
    if (String.isBlank(promptJson)) {
      return null;
    }

    try {
      Map<String, Object> payload = parsePromptPayload(promptJson);
      List<Object> relationshipObjects = asList(payload.get('relationships'));
      if (relationshipObjects == null || relationshipObjects.isEmpty()) {
        return null;
      }

      AccountLookup accountLookup = buildAccountLookup(relationshipObjects);
      Boolean edgeBasedPrompt = isEdgeBasedPrompt(relationshipObjects);
      PromptScopeFilter filter = new PromptScopeFilter();

      for (Object relationshipObject : relationshipObjects) {
        Map<String, Object> relationship = asMap(relationshipObject);
        if (relationship == null) {
          continue;
        }

        PromptEdgeCandidate candidate = edgeBasedPrompt
          ? buildPromptEdgeCandidateFromEdges(
              relationship,
              rootAccount,
              accountLookup,
              null
            )
          : buildPromptEdgeCandidateFromLegacy(
              relationship,
              rootAccount,
              accountLookup,
              null
            );
        if (candidate == null) {
          continue;
        }

        String relationshipKey = buildPromptScopeRelationshipKey(
          String.valueOf(candidate.sourceAccountId),
          String.valueOf(candidate.targetAccountId),
          candidate.edgeCategory,
          candidate.relationType
        );
        if (!String.isBlank(relationshipKey)) {
          filter.relationshipKeys.add(relationshipKey);
        }
      }

      if (filter.relationshipKeys.isEmpty()) {
        return null;
      }
      return filter;
    } catch (Exception ex) {
      return null;
    }
  }

  private static Boolean isManualRelationshipInPromptScope(
    PromptScopeFilter promptScopeFilter,
    String sourceId,
    String targetId,
    String edgeCategory,
    String relationType
  ) {
    if (
      promptScopeFilter == null ||
      promptScopeFilter.relationshipKeys == null ||
      promptScopeFilter.relationshipKeys.isEmpty()
    ) {
      return true;
    }

    String relationshipKey = buildPromptScopeRelationshipKey(
      sourceId,
      targetId,
      edgeCategory,
      relationType
    );
    return promptScopeFilter.relationshipKeys.contains(relationshipKey);
  }

  private static String buildPromptScopeRelationshipKey(
    String sourceId,
    String targetId,
    String edgeCategory,
    String relationType
  ) {
    if (String.isBlank(sourceId) || String.isBlank(targetId)) {
      return null;
    }
    String normalizedEdgeCategory = normalizeEdgeCategory(edgeCategory);
    if (normalizedEdgeCategory == null) {
      normalizedEdgeCategory = 'INDIRECT_PATH';
    }
    String normalizedRelationType = normalizeScopeRelationType(
      relationType,
      normalizedEdgeCategory
    );

    return sourceId +
      '|' +
      targetId +
      '|' +
      normalizedEdgeCategory +
      '|' +
      normalizedRelationType;
  }

  private static String normalizeScopeRelationType(
    String relationType,
    String edgeCategory
  ) {
    String normalized = String.isBlank(relationType)
      ? null
      : relationType.trim();
    if (!String.isBlank(normalized)) {
      return normalized;
    }
    String fallback = defaultRelationTypeByCategory(edgeCategory);
    return String.isBlank(fallback) ? 'Related' : fallback;
  }

  private static void populateDebugPromptJson(
    GraphResponse response,
    String rawPromptJson
  ) {
    if (response == null) {
      return;
    }
    response.promptRawJson = normalizeStoredPromptJson(rawPromptJson);
  }

  private static String normalizeStoredPromptJson(String rawPromptJson) {
    if (String.isBlank(rawPromptJson)) {
      return null;
    }
    try {
      String sanitizedJson = sanitizePromptJson(rawPromptJson);
      Object payloadRaw = JSON.deserializeUntyped(sanitizedJson);
      return payloadRaw == null ? sanitizedJson : JSON.serialize(payloadRaw);
    } catch (Exception ex) {
      return rawPromptJson.trim();
    }
  }

  private static Account resolveAccountForRelationship(
    Map<String, Object> relationship,
    AccountLookup accountLookup
  ) {
    String domain = normalizeDomain(
      stringValue(relationship.get('company_domain'))
    );
    String nameKey = normalizeName(
      stringValue(relationship.get('company_name'))
    );
    return resolveAccountForCompany(domain, nameKey, accountLookup);
  }

  private static Account resolveAccountForCompany(
    String domain,
    String nameKey,
    AccountLookup accountLookup
  ) {
    if (!String.isBlank(domain) && accountLookup.byDomain.containsKey(domain)) {
      return accountLookup.byDomain.get(domain);
    }
    if (!String.isBlank(nameKey) && accountLookup.byName.containsKey(nameKey)) {
      return accountLookup.byName.get(nameKey);
    }
    return null;
  }

  private static AccountLookup buildAccountLookup(
    List<Object> relationshipObjects
  ) {
    Set<String> companyNames = new Set<String>();
    Set<String> companyDomains = new Set<String>();
    for (Object relationshipObject : relationshipObjects) {
      Map<String, Object> relationship = asMap(relationshipObject);
      if (relationship == null) {
        continue;
      }

      for (
        String keyName : new List<String>{
          'company_name',
          'source_company_name',
          'target_company_name'
        }
      ) {
        String companyName = stringValue(relationship.get(keyName));
        if (!String.isBlank(companyName)) {
          companyNames.add(companyName);
        }
      }
      for (
        String keyName : new List<String>{
          'company_domain',
          'source_company_domain',
          'target_company_domain'
        }
      ) {
        String companyDomain = normalizeDomain(
          stringValue(relationship.get(keyName))
        );
        if (!String.isBlank(companyDomain)) {
          companyDomains.add(companyDomain);
        }
      }
    }

    AccountLookup lookup = new AccountLookup();
    if (!companyNames.isEmpty()) {
      for (Account accountRecord : [
        SELECT Id, Name, Type, Website
        FROM Account
        WHERE Name IN :companyNames
        LIMIT 2000
      ]) {
        addAccountToLookup(lookup, accountRecord);
      }
    }

    if (!companyDomains.isEmpty()) {
      Set<String> websiteCandidates = new Set<String>();
      for (String companyDomain : companyDomains) {
        websiteCandidates.add(companyDomain);
        websiteCandidates.add('www.' + companyDomain);
        websiteCandidates.add('http://' + companyDomain);
        websiteCandidates.add('http://www.' + companyDomain);
        websiteCandidates.add('https://' + companyDomain);
        websiteCandidates.add('https://www.' + companyDomain);
        websiteCandidates.add('https://' + companyDomain + '/');
        websiteCandidates.add('https://www.' + companyDomain + '/');
      }

      for (Account accountRecord : [
        SELECT Id, Name, Type, Website
        FROM Account
        WHERE Website IN :websiteCandidates
        LIMIT 2000
      ]) {
        addAccountToLookup(lookup, accountRecord);
      }
    }

    return lookup;
  }

  private static void addAccountToLookup(
    AccountLookup lookup,
    Account accountRecord
  ) {
    String normalizedName = normalizeName(accountRecord.Name);
    if (
      !String.isBlank(normalizedName) &&
      !lookup.byName.containsKey(normalizedName)
    ) {
      lookup.byName.put(normalizedName, accountRecord);
    }

    String domain = normalizeDomain(accountRecord.Website);
    if (!String.isBlank(domain) && !lookup.byDomain.containsKey(domain)) {
      lookup.byDomain.put(domain, accountRecord);
    }
  }

  private static void ensurePlaceholderAccountsForPromptRelationships(
    List<Object> relationshipObjects,
    Account rootAccount,
    AccountLookup accountLookup
  ) {
    if (
      relationshipObjects == null ||
      relationshipObjects.isEmpty() ||
      rootAccount == null ||
      accountLookup == null
    ) {
      return;
    }

    String rootDomain = normalizeDomain(rootAccount.Website);
    String rootNameKey = normalizeName(rootAccount.Name);
    Map<String, PromptCompanySeed> missingByKey = new Map<String, PromptCompanySeed>();

    for (Object relationshipObject : relationshipObjects) {
      Map<String, Object> relationship = asMap(relationshipObject);
      if (relationship == null) {
        continue;
      }

      collectMissingPromptCompany(
        missingByKey,
        accountLookup,
        rootDomain,
        rootNameKey,
        stringValue(relationship.get('company_name')),
        normalizeDomain(stringValue(relationship.get('company_domain')))
      );
      collectMissingPromptCompany(
        missingByKey,
        accountLookup,
        rootDomain,
        rootNameKey,
        stringValue(relationship.get('source_company_name')),
        normalizeDomain(stringValue(relationship.get('source_company_domain')))
      );
      collectMissingPromptCompany(
        missingByKey,
        accountLookup,
        rootDomain,
        rootNameKey,
        stringValue(relationship.get('target_company_name')),
        normalizeDomain(stringValue(relationship.get('target_company_domain')))
      );
    }

    if (missingByKey.isEmpty()) {
      return;
    }

    List<Account> placeholders = new List<Account>();
    for (PromptCompanySeed seed : missingByKey.values()) {
      Account placeholder = new Account();
      placeholder.Name = truncateText(seed.displayName, 255);
      if (!String.isBlank(seed.domain)) {
        placeholder.Website = 'https://' + seed.domain;
      }
      placeholder.Description = 'Auto-created by CM Supply Network smart build.';
      placeholders.add(placeholder);
    }

    Database.SaveResult[] saveResults = Database.insert(placeholders, false);
    for (
      Integer indexValue = 0; indexValue < saveResults.size(); indexValue++
    ) {
      if (!saveResults[indexValue].isSuccess()) {
        continue;
      }
      addAccountToLookup(accountLookup, placeholders[indexValue]);
    }
  }

  private static void collectMissingPromptCompany(
    Map<String, PromptCompanySeed> missingByKey,
    AccountLookup accountLookup,
    String rootDomain,
    String rootNameKey,
    String rawCompanyName,
    String companyDomain
  ) {
    String companyName = String.isBlank(rawCompanyName)
      ? (String.isBlank(companyDomain) ? null : companyDomain)
      : rawCompanyName.trim();
    String companyNameKey = normalizeName(companyName);

    if (String.isBlank(companyDomain) && String.isBlank(companyNameKey)) {
      return;
    }
    if (isRootCompany(companyDomain, companyNameKey, rootDomain, rootNameKey)) {
      return;
    }
    if (
      !String.isBlank(companyDomain) &&
      accountLookup.byDomain.containsKey(companyDomain)
    ) {
      return;
    }
    if (
      !String.isBlank(companyNameKey) &&
      accountLookup.byName.containsKey(companyNameKey)
    ) {
      return;
    }

    String dedupeKey = String.isBlank(companyDomain)
      ? 'N|' + companyNameKey
      : 'D|' + companyDomain;
    if (missingByKey.containsKey(dedupeKey)) {
      return;
    }

    PromptCompanySeed seed = new PromptCompanySeed();
    seed.domain = companyDomain;
    seed.displayName = String.isBlank(companyName)
      ? 'Prompt Company'
      : companyName;
    missingByKey.put(dedupeKey, seed);
  }

  private static String generatePromptJson(Account rootAccount) {
    return generatePromptJson(rootAccount, null);
  }

  private static String generatePromptJson(
    Account rootAccount,
    String supplyScenario
  ) {
    if (Test.isRunningTest()) {
      if (!String.isBlank(testPromptFailureMessage)) {
        throw new AuraHandledException(testPromptFailureMessage);
      }
      if (!String.isBlank(testPromptJson)) {
        return testPromptJson;
      }
    }

    try {
      ConnectApi.EinsteinPromptTemplateGenerationsInput generationInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
      generationInput.inputParams = new Map<String, ConnectApi.WrappedValue>();

      ConnectApi.WrappedValue accountInput = new ConnectApi.WrappedValue();
      accountInput.value = new Map<String, String>{
        'id' => String.valueOf(rootAccount.Id)
      };
      generationInput.inputParams.put('Input:Account', accountInput);
      ConnectApi.WrappedValue scenarioInput = new ConnectApi.WrappedValue();
      scenarioInput.value = String.isBlank(supplyScenario)
        ? SUPPLY_SCENARIO_LEGACY_UNSCOPED
        : supplyScenario;
      generationInput.inputParams.put('Input:SupplyScenario', scenarioInput);
      ConnectApi.WrappedValue focusCompanyNameInput = new ConnectApi.WrappedValue();
      focusCompanyNameInput.value = resolvePromptFocusCompanyName(rootAccount);
      generationInput.inputParams.put(
        'Input:FocusCompanyName',
        focusCompanyNameInput
      );
      ConnectApi.WrappedValue focusCompanyDomainInput = new ConnectApi.WrappedValue();
      focusCompanyDomainInput.value = resolvePromptFocusCompanyDomain(
        rootAccount
      );
      generationInput.inputParams.put(
        'Input:FocusCompanyDomain',
        focusCompanyDomainInput
      );
      ConnectApi.WrappedValue scenarioCatalogInput = new ConnectApi.WrappedValue();
      scenarioCatalogInput.value = buildSupplyScenarioCatalogInput();
      generationInput.inputParams.put(
        'Input:SupplyScenarioCatalog',
        scenarioCatalogInput
      );
      generationInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
      generationInput.additionalConfig.applicationName = PROMPT_APPLICATION_NAME;
      generationInput.isPreview = false;

      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationOutput = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
        PROMPT_TEMPLATE_DEVELOPER_NAME,
        generationInput
      );

      if (
        generationOutput == null ||
        generationOutput.generations == null ||
        generationOutput.generations.isEmpty()
      ) {
        String generationErrorMessage = extractGenerationError(
          generationOutput
        );
        if (!String.isBlank(generationErrorMessage)) {
          throw new AuraHandledException(
            'Prompt template generation error: ' + generationErrorMessage
          );
        }
        throw new AuraHandledException(
          'Prompt template returned no generations.'
        );
      }

      String responseText = generationOutput.generations[0].text;
      if (String.isBlank(responseText)) {
        throw new AuraHandledException('Prompt template returned empty text.');
      }

      return responseText;
    } catch (ConnectApi.ConnectApiException ex) {
      throw new AuraHandledException(
        'Prompt template invocation failed: ' + ex.getMessage()
      );
    } catch (Exception ex) {
      throw new AuraHandledException(
        'Prompt template invocation failed: ' + ex.getMessage()
      );
    }
  }

  private static String resolvePromptFocusCompanyName(Account rootAccount) {
    SupplyNetworkRuntimeConfig runtimeConfig = getSupplyNetworkRuntimeConfig();
    if (!String.isBlank(runtimeConfig.focusCompanyName)) {
      return runtimeConfig.focusCompanyName;
    }
    return null;
  }

  private static String resolvePromptFocusCompanyDomain(Account rootAccount) {
    SupplyNetworkRuntimeConfig runtimeConfig = getSupplyNetworkRuntimeConfig();
    if (!String.isBlank(runtimeConfig.focusCompanyDomain)) {
      return runtimeConfig.focusCompanyDomain;
    }
    return null;
  }

  private static SupplyNetworkRuntimeConfig getSupplyNetworkRuntimeConfig() {
    if (testRuntimeConfig != null) {
      return testRuntimeConfig;
    }
    if (runtimeConfigCache == null) {
      runtimeConfigCache = buildSupplyNetworkRuntimeConfig();
    }
    return runtimeConfigCache;
  }

  private static SupplyNetworkRuntimeConfig buildSupplyNetworkRuntimeConfig() {
    SupplyNetworkRuntimeConfig runtimeConfig = new SupplyNetworkRuntimeConfig();
    runtimeConfig.focusCompanyName = null;
    runtimeConfig.focusCompanyDomain = null;
    runtimeConfig.scenarioDefinitions = new List<SupplyScenarioDefinition>();
    runtimeConfig.scenarioByCode = new Map<String, SupplyScenarioDefinition>();
    runtimeConfig.aiScenarioCodes = new Set<String>();

    Account activeDemoTarget = loadActiveDemoTargetAccount();
    if (activeDemoTarget != null) {
      if (!String.isBlank(activeDemoTarget.Name)) {
        runtimeConfig.focusCompanyName = activeDemoTarget.Name.trim();
      }
      String targetDomain = normalizeDomain(activeDemoTarget.Website);
      if (!String.isBlank(targetDomain)) {
        runtimeConfig.focusCompanyDomain = targetDomain;
      }
      runtimeConfig.scenarioDefinitions = parseSupplyScenarioCatalog(
        activeDemoTarget.CM_Supply_Scenario_Catalog__c
      );
    }

    if (runtimeConfig.scenarioDefinitions.isEmpty()) {
      runtimeConfig.scenarioDefinitions = buildDefaultSupplyScenarioDefinitions();
    }

    List<Map<String, Object>> scenarioCatalogPayload = new List<Map<String, Object>>();
    for (SupplyScenarioDefinition scenarioDefinition : runtimeConfig.scenarioDefinitions) {
      runtimeConfig.scenarioByCode.put(
        scenarioDefinition.normalizedCode,
        scenarioDefinition
      );
      if (scenarioDefinition.aiSupported) {
        runtimeConfig.aiScenarioCodes.add(scenarioDefinition.normalizedCode);
      }
      scenarioCatalogPayload.add(
        new Map<String, Object>{
          'code' => scenarioDefinition.code,
          'label' => scenarioDefinition.label,
          'ai_supported' => scenarioDefinition.aiSupported
        }
      );
    }
    runtimeConfig.scenarioCatalogJson = JSON.serialize(scenarioCatalogPayload);
    return runtimeConfig;
  }

  private static Account loadActiveDemoTargetAccount() {
    List<Account> activeTargets = [
      SELECT Id, Name, Website, CM_Supply_Scenario_Catalog__c
      FROM Account
      WHERE CM_Is_Demo_Target__c = true
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];
    return activeTargets.isEmpty() ? null : activeTargets[0];
  }

  private static List<SupplyScenarioDefinition> parseSupplyScenarioCatalog(
    String rawCatalog
  ) {
    List<SupplyScenarioDefinition> scenarioDefinitions = new List<SupplyScenarioDefinition>();
    if (String.isBlank(rawCatalog)) {
      return scenarioDefinitions;
    }

    Set<String> addedCodes = new Set<String>();
    String normalizedCatalog = rawCatalog.replace('\r', '\n');
    for (String rawLine : normalizedCatalog.split('\n')) {
      String trimmedLine = rawLine == null ? null : rawLine.trim();
      if (String.isBlank(trimmedLine)) {
        continue;
      }
      if (trimmedLine.startsWith('#') || trimmedLine.startsWith('//')) {
        continue;
      }

      List<String> segments = trimmedLine.contains('|')
        ? trimmedLine.split('\\|')
        : new List<String>{ trimmedLine };
      String rawScenarioToken = segments.isEmpty() ? null : segments[0];
      String normalizedScenarioToken = normalizeScenarioToken(rawScenarioToken);
      String scenarioCode = canonicalizeSupplyScenario(normalizedScenarioToken);
      if (String.isBlank(scenarioCode) || addedCodes.contains(scenarioCode)) {
        continue;
      }
      addedCodes.add(scenarioCode);

      String scenarioLabel = segments.size() > 1 ? normalizeText(segments[1]) : null;
      if (String.isBlank(scenarioLabel)) {
        if (
          !String.isBlank(rawScenarioToken) &&
          !String.isBlank(normalizedScenarioToken) &&
          normalizedScenarioToken != scenarioCode
        ) {
          scenarioLabel = rawScenarioToken.trim();
        } else {
          scenarioLabel = buildScenarioLabelFromCode(scenarioCode);
        }
      }
      Boolean aiSupported = parseAiSupportFlag(
        segments.size() > 2 ? segments[2] : null,
        scenarioCode
      );

      scenarioDefinitions.add(
        new SupplyScenarioDefinition(
          scenarioCode,
          scenarioLabel,
          aiSupported
        )
      );
    }
    return scenarioDefinitions;
  }

  private static Boolean parseAiSupportFlag(
    String rawAiFlag,
    String scenarioCode
  ) {
    String normalizedFlag = normalizeName(rawAiFlag);
    if (
      normalizedFlag == 'ai' ||
      normalizedFlag == 'true' ||
      normalizedFlag == 'yes' ||
      normalizedFlag == 'y' ||
      normalizedFlag == '1'
    ) {
      return true;
    }
    if (
      normalizedFlag == 'no_ai' ||
      normalizedFlag == 'false' ||
      normalizedFlag == 'no' ||
      normalizedFlag == 'n' ||
      normalizedFlag == '0' ||
      normalizedFlag == 'manual'
    ) {
      return false;
    }
    return scenarioCode != SUPPLY_SCENARIO_LEGACY_UNSCOPED;
  }

  private static List<SupplyScenarioDefinition> buildDefaultSupplyScenarioDefinitions() {
    return new List<SupplyScenarioDefinition>{
      new SupplyScenarioDefinition(
        SUPPLY_SCENARIO_FWA_5G,
        '5G FWA',
        true
      ),
      new SupplyScenarioDefinition(
        SUPPLY_SCENARIO_ENTERPRISE_WIFI_AP,
        'Enterprise Wi-Fi AP',
        true
      ),
      new SupplyScenarioDefinition(
        SUPPLY_SCENARIO_AUTOMOTIVE_TELEMATICS,
        'Automotive Telematics',
        true
      ),
      new SupplyScenarioDefinition(
        SUPPLY_SCENARIO_LEGACY_UNSCOPED,
        'Legacy / Unscoped',
        false
      )
    };
  }

  private static Map<String, String> buildSupplyScenarioAliasMap() {
    Map<String, String> aliasMap = new Map<String, String>();
    registerSupplyScenarioAliases(
      aliasMap,
      SUPPLY_SCENARIO_FWA_5G,
      new List<String>{
        SUPPLY_SCENARIO_FWA_5G,
        '5G_FWA',
        '5GFWA',
        'FWA5G',
        '5G_FIXED_WIRELESS_ACCESS',
        'FIXED_WIRELESS_ACCESS_5G'
      }
    );
    registerSupplyScenarioAliases(
      aliasMap,
      SUPPLY_SCENARIO_ENTERPRISE_WIFI_AP,
      new List<String>{
        SUPPLY_SCENARIO_ENTERPRISE_WIFI_AP,
        'ENTERPRISE_WIFI',
        'WIFI_AP',
        'WIFIAP',
        '企業級_WIFI_AP',
        '企業級_WIFI',
        '企業級無線_AP'
      }
    );
    registerSupplyScenarioAliases(
      aliasMap,
      SUPPLY_SCENARIO_AUTOMOTIVE_TELEMATICS,
      new List<String>{
        SUPPLY_SCENARIO_AUTOMOTIVE_TELEMATICS,
        'AUTOMOTIVE',
        'TELEMATICS',
        '車聯網模組',
        '車聯網',
        '車用模組'
      }
    );
    registerSupplyScenarioAliases(
      aliasMap,
      SUPPLY_SCENARIO_LEGACY_UNSCOPED,
      new List<String>{
        SUPPLY_SCENARIO_LEGACY_UNSCOPED,
        'LEGACY',
        'MIXED',
        'LEGACY_MIXED',
        'UNSCOPED'
      }
    );
    return aliasMap;
  }

  private static void registerSupplyScenarioAliases(
    Map<String, String> aliasMap,
    String canonicalScenario,
    List<String> rawAliases
  ) {
    String canonicalToken = normalizeScenarioToken(canonicalScenario);
    if (String.isBlank(canonicalToken)) {
      return;
    }

    aliasMap.put(canonicalToken, canonicalScenario);
    if (rawAliases == null || rawAliases.isEmpty()) {
      return;
    }

    for (String rawAlias : rawAliases) {
      String aliasToken = normalizeScenarioToken(rawAlias);
      if (String.isBlank(aliasToken)) {
        continue;
      }
      aliasMap.put(aliasToken, canonicalScenario);
    }
  }

  private static String buildScenarioLabelFromCode(String scenarioCode) {
    String normalizedCode = normalizeStoredSupplyScenario(scenarioCode);
    if (normalizedCode == SUPPLY_SCENARIO_FWA_5G) {
      return '5G FWA';
    }
    if (normalizedCode == SUPPLY_SCENARIO_ENTERPRISE_WIFI_AP) {
      return 'Enterprise Wi-Fi AP';
    }
    if (normalizedCode == SUPPLY_SCENARIO_AUTOMOTIVE_TELEMATICS) {
      return 'Automotive Telematics';
    }
    if (normalizedCode == SUPPLY_SCENARIO_LEGACY_UNSCOPED) {
      return 'Legacy / Unscoped';
    }
    if (String.isBlank(normalizedCode)) {
      return null;
    }
    return normalizedCode.replace('_', ' ');
  }

  private static String buildSupplyScenarioCatalogInput() {
    return getSupplyNetworkRuntimeConfig().scenarioCatalogJson;
  }

  private static String generateWncImpactJson(Account rootAccount) {
    return generateWncImpactJson(rootAccount, null);
  }

  private static String generateWncImpactJson(
    Account rootAccount,
    String supplyScenario
  ) {
    if (Test.isRunningTest()) {
      if (!String.isBlank(testWncImpactPromptFailureMessage)) {
        throw new AuraHandledException(testWncImpactPromptFailureMessage);
      }
      if (!String.isBlank(testWncImpactPromptJson)) {
        return testWncImpactPromptJson;
      }
    }

    try {
      ConnectApi.EinsteinPromptTemplateGenerationsInput generationInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
      generationInput.inputParams = new Map<String, ConnectApi.WrappedValue>();

      ConnectApi.WrappedValue accountInput = new ConnectApi.WrappedValue();
      accountInput.value = new Map<String, String>{
        'id' => String.valueOf(rootAccount.Id)
      };
      generationInput.inputParams.put('Input:Account', accountInput);
      ConnectApi.WrappedValue scenarioInput = new ConnectApi.WrappedValue();
      scenarioInput.value = String.isBlank(supplyScenario)
        ? SUPPLY_SCENARIO_LEGACY_UNSCOPED
        : supplyScenario;
      generationInput.inputParams.put('Input:SupplyScenario', scenarioInput);
      ConnectApi.WrappedValue focusCompanyNameInput = new ConnectApi.WrappedValue();
      focusCompanyNameInput.value = resolvePromptFocusCompanyName(rootAccount);
      generationInput.inputParams.put(
        'Input:FocusCompanyName',
        focusCompanyNameInput
      );
      ConnectApi.WrappedValue focusCompanyDomainInput = new ConnectApi.WrappedValue();
      focusCompanyDomainInput.value = resolvePromptFocusCompanyDomain(
        rootAccount
      );
      generationInput.inputParams.put(
        'Input:FocusCompanyDomain',
        focusCompanyDomainInput
      );
      generationInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
      generationInput.additionalConfig.applicationName = PROMPT_APPLICATION_NAME;
      generationInput.isPreview = false;

      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationOutput = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
        WNC_IMPACT_PROMPT_TEMPLATE_DEVELOPER_NAME,
        generationInput
      );

      if (
        generationOutput == null ||
        generationOutput.generations == null ||
        generationOutput.generations.isEmpty()
      ) {
        String generationErrorMessage = extractGenerationError(
          generationOutput
        );
        if (!String.isBlank(generationErrorMessage)) {
          throw new AuraHandledException(
            'Prompt template generation error: ' + generationErrorMessage
          );
        }
        throw new AuraHandledException(
          'Prompt template returned no generations.'
        );
      }

      String responseText = generationOutput.generations[0].text;
      if (String.isBlank(responseText)) {
        throw new AuraHandledException('Prompt template returned empty text.');
      }
      return responseText;
    } catch (ConnectApi.ConnectApiException ex) {
      throw new AuraHandledException(
        'Prompt template invocation failed: ' + ex.getMessage()
      );
    } catch (Exception ex) {
      throw new AuraHandledException(
        'Prompt template invocation failed: ' + ex.getMessage()
      );
    }
  }

  private static ImpactAnalysisResponse buildWncImpactAnalysisResponse(
    String rawImpactJson
  ) {
    Map<String, Object> payload = parsePromptPayload(rawImpactJson);
    ImpactAnalysisResponse response = new ImpactAnalysisResponse();
    response.promptTemplateName = WNC_IMPACT_PROMPT_TEMPLATE_DEVELOPER_NAME;
    response.generatedAt = Datetime.now();
    response.rawJson = JSON.serialize(payload);
    response.analysisVersion = stringValue(payload.get('analysis_version'));
    response.rootAccount = stringValue(payload.get('root_account'));
    response.focusCompany = stringValue(payload.get('focus_company'));
    Map<String, Object> analysisScenario = asMap(
      payload.get('analysis_scenario')
    );
    response.supplyScenario = normalizeSupplyScenario(
      analysisScenario == null
        ? null
        : stringValue(analysisScenario.get('code')),
      true
    );
    response.supplyScenarioLabel = getSupplyScenarioLabel(
      response.supplyScenario
    );

    String impactLevel = stringValue(payload.get('impact_level'));
    response.impactLevel = String.isBlank(impactLevel)
      ? 'UNKNOWN'
      : impactLevel.trim().toUpperCase();
    response.summaryForUi = stringValue(payload.get('summary_for_ui'));
    response.overallAssessment = stringValue(payload.get('overall_assessment'));
    response.keyRisks = buildImpactRiskItems(payload.get('key_risks'));
    response.positiveSignals = buildStringItems(
      payload.get('positive_signals')
    );
    response.recommendedActions = buildStringItems(
      payload.get('recommended_actions')
    );

    String summaryText = response.summaryForUi;
    if (String.isBlank(summaryText)) {
      summaryText = response.overallAssessment;
    }
    if (String.isBlank(summaryText)) {
      summaryText = buildFallbackImpactSummaryFromRisks(response.keyRisks);
    }
    response.summary = String.isBlank(summaryText)
      ? '分析已完成，但未回傳摘要內容。'
      : summaryText;
    return response;
  }

  private static String buildFallbackImpactSummaryFromRisks(
    List<ImpactRiskItem> keyRisks
  ) {
    if (keyRisks == null || keyRisks.isEmpty()) {
      return null;
    }
    List<String> summaryParts = new List<String>();
    Integer appendedCount = 0;
    for (ImpactRiskItem risk : keyRisks) {
      if (appendedCount >= 3) {
        break;
      }
      if (risk == null) {
        continue;
      }
      List<String> lineParts = new List<String>();
      if (!String.isBlank(risk.title)) {
        lineParts.add(risk.title);
      }
      if (!String.isBlank(risk.impact)) {
        lineParts.add(risk.impact);
      }
      if (!String.isBlank(risk.reason)) {
        lineParts.add(risk.reason);
      }
      if (lineParts.isEmpty()) {
        continue;
      }
      summaryParts.add(String.join(lineParts, ' - '));
      appendedCount++;
    }
    return summaryParts.isEmpty() ? null : String.join(summaryParts, '；');
  }

  private static List<ImpactRiskItem> buildImpactRiskItems(Object rawRisks) {
    List<ImpactRiskItem> items = new List<ImpactRiskItem>();
    List<Object> rawRiskList = asList(rawRisks);
    if (rawRiskList == null || rawRiskList.isEmpty()) {
      return items;
    }

    for (Object rawRisk : rawRiskList) {
      Map<String, Object> riskPayload = asMap(rawRisk);
      if (riskPayload == null) {
        continue;
      }

      ImpactRiskItem item = new ImpactRiskItem();
      item.title = stringValue(riskPayload.get('title'));
      item.impact = stringValue(riskPayload.get('impact'));
      item.reason = stringValue(riskPayload.get('reason'));

      if (
        String.isBlank(item.title) &&
        String.isBlank(item.impact) &&
        String.isBlank(item.reason)
      ) {
        continue;
      }
      items.add(item);
    }
    return items;
  }

  private static List<String> buildStringItems(Object rawValues) {
    List<String> items = new List<String>();
    List<Object> rawList = asList(rawValues);
    if (rawList == null || rawList.isEmpty()) {
      return items;
    }

    for (Object rawValue : rawList) {
      String textValue = stringValue(rawValue);
      if (String.isBlank(textValue)) {
        continue;
      }
      items.add(textValue);
    }
    return items;
  }

  private static String normalizeStoredSupplyScenario(String rawScenario) {
    return canonicalizeSupplyScenario(normalizeScenarioToken(rawScenario));
  }

  private static String canonicalizeSupplyScenario(String normalizedScenario) {
    if (String.isBlank(normalizedScenario)) {
      return null;
    }

    return SUPPLY_SCENARIO_ALIAS_TO_CANONICAL.containsKey(normalizedScenario)
      ? SUPPLY_SCENARIO_ALIAS_TO_CANONICAL.get(normalizedScenario)
      : normalizedScenario;
  }

  private static String normalizeScenarioToken(String rawScenario) {
    if (String.isBlank(rawScenario)) {
      return null;
    }

    String normalized = rawScenario.trim().toUpperCase();
    normalized = normalized.replace('-', '_');
    normalized = normalized.replace(' ', '_');
    normalized = normalized.replace('/', '_');
    while (normalized.contains('__')) {
      normalized = normalized.replace('__', '_');
    }
    if (normalized.startsWith('_')) {
      normalized = normalized.substring(1);
    }
    if (normalized.endsWith('_')) {
      normalized = normalized.substring(0, normalized.length() - 1);
    }
    return String.isBlank(normalized) ? null : normalized;
  }

  private static String normalizeSupplyScenario(
    String rawScenario,
    Boolean allowBlank
  ) {
    if (String.isBlank(rawScenario)) {
      if (allowBlank) {
        return null;
      }
      throw new AuraHandledException('supplyScenario is required.');
    }

    String normalized = normalizeStoredSupplyScenario(rawScenario);
    SupplyNetworkRuntimeConfig runtimeConfig = getSupplyNetworkRuntimeConfig();
    if (
      !String.isBlank(normalized) &&
      runtimeConfig.scenarioByCode.containsKey(normalized)
    ) {
      return normalized;
    }

    List<String> supportedCodes = new List<String>();
    for (SupplyScenarioDefinition scenarioDefinition : runtimeConfig.scenarioDefinitions) {
      supportedCodes.add(scenarioDefinition.code);
    }
    throw new AuraHandledException(
      'Unsupported supplyScenario. Valid values: ' +
      String.join(supportedCodes, ', ')
    );
  }

  private static String normalizeAiSupplyScenario(String rawScenario) {
    String normalized = normalizeSupplyScenario(rawScenario, false);
    SupplyNetworkRuntimeConfig runtimeConfig = getSupplyNetworkRuntimeConfig();
    if (runtimeConfig.aiScenarioCodes.contains(normalized)) {
      return normalized;
    }

    List<String> supportedAiLabels = new List<String>();
    for (SupplyScenarioDefinition scenarioDefinition : runtimeConfig.scenarioDefinitions) {
      if (scenarioDefinition.aiSupported) {
        supportedAiLabels.add(scenarioDefinition.label);
      }
    }
    if (supportedAiLabels.isEmpty()) {
      throw new AuraHandledException(
        '目前設定沒有可執行 AI 的場景，請先到 Demo Setup 設定 CM_Supply_Scenario_Catalog。'
      );
    }
    throw new AuraHandledException(
      '請選擇可執行 AI 的場景：' + String.join(supportedAiLabels, '、') + '。'
    );
  }

  private static Boolean matchesSupplyScenario(
    String relationshipScenario,
    String requestedScenario
  ) {
    String normalizedRequestedScenario = normalizeSupplyScenario(
      requestedScenario,
      true
    );
    if (String.isBlank(normalizedRequestedScenario)) {
      return true;
    }

    String normalizedRelationshipScenario = normalizeStoredSupplyScenario(
      relationshipScenario
    );

    if (normalizedRequestedScenario == SUPPLY_SCENARIO_LEGACY_UNSCOPED) {
      return String.isBlank(normalizedRelationshipScenario) ||
        normalizedRelationshipScenario == SUPPLY_SCENARIO_LEGACY_UNSCOPED;
    }
    return normalizedRelationshipScenario == normalizedRequestedScenario;
  }

  private static String getSupplyScenarioLabel(String supplyScenario) {
    String normalized = normalizeSupplyScenario(supplyScenario, true);
    if (String.isBlank(normalized)) {
      return 'All Scenarios';
    }
    SupplyScenarioDefinition scenarioDefinition = getSupplyNetworkRuntimeConfig().scenarioByCode.get(
      normalized
    );
    return scenarioDefinition == null || String.isBlank(scenarioDefinition.label)
      ? buildScenarioLabelFromCode(normalized)
      : scenarioDefinition.label;
  }

  private static String getSupplyScenarioLabelAllowUnknown(
    String supplyScenario
  ) {
    String normalized = normalizeStoredSupplyScenario(supplyScenario);
    if (String.isBlank(normalized)) {
      return 'All Scenarios';
    }
    SupplyScenarioDefinition scenarioDefinition = getSupplyNetworkRuntimeConfig().scenarioByCode.get(
      normalized
    );
    return scenarioDefinition == null || String.isBlank(scenarioDefinition.label)
      ? buildScenarioLabelFromCode(normalized)
      : scenarioDefinition.label;
  }

  private static String extractRelationshipSupplyScenario(
    CM_Supply_Relationship__c relationshipRecord
  ) {
    if (relationshipRecord == null) {
      return null;
    }
    String scenarioCode = normalizeStoredSupplyScenario(
      relationshipRecord.Supply_Scenario_Code__c
    );
    if (!String.isBlank(scenarioCode)) {
      return scenarioCode;
    }
    return normalizeStoredSupplyScenario(relationshipRecord.Supply_Scenario__c);
  }

  private static void applyRelationshipSupplyScenario(
    CM_Supply_Relationship__c relationshipRecord,
    String supplyScenario
  ) {
    String normalizedScenario = normalizeStoredSupplyScenario(supplyScenario);
    relationshipRecord.Supply_Scenario_Code__c = normalizedScenario;
    relationshipRecord.Supply_Scenario__c = toLegacyPicklistSupplyScenario(
      normalizedScenario
    );
  }

  private static String toLegacyPicklistSupplyScenario(String supplyScenario) {
    String normalizedScenario = normalizeStoredSupplyScenario(supplyScenario);
    return DEFAULT_SUPPORTED_SUPPLY_SCENARIOS.contains(normalizedScenario)
      ? normalizedScenario
      : null;
  }

  private static String buildManualCoverageNote(
    String supplyScenario,
    String baseNote
  ) {
    if (String.isBlank(baseNote)) {
      return null;
    }
    String normalizedSupplyScenario = normalizeSupplyScenario(
      supplyScenario,
      true
    );
    if (String.isBlank(normalizedSupplyScenario)) {
      return baseNote;
    }
    return baseNote +
      ' 場景：' +
      getSupplyScenarioLabel(normalizedSupplyScenario) +
      '。';
  }

  private static String resolveGraphPromptDebugJson(
    Account rootAccount,
    String supplyScenario
  ) {
    if (rootAccount == null) {
      return null;
    }
    if (String.isBlank(supplyScenario)) {
      return rootAccount.CM_Supply_Network_Prompt_JSON__c;
    }
    if (supplyScenario == SUPPLY_SCENARIO_LEGACY_UNSCOPED) {
      return rootAccount.CM_Supply_Network_Prompt_JSON__c;
    }
    if (
      promptJsonMatchesSupplyScenario(
        rootAccount.CM_Supply_Network_Prompt_JSON__c,
        supplyScenario
      )
    ) {
      return rootAccount.CM_Supply_Network_Prompt_JSON__c;
    }
    return buildScenarioPromptSnapshotJson(rootAccount, supplyScenario);
  }

  private static Boolean promptJsonMatchesSupplyScenario(
    String rawPromptJson,
    String supplyScenario
  ) {
    String normalizedSupplyScenario = normalizeSupplyScenario(
      supplyScenario,
      true
    );
    if (String.isBlank(normalizedSupplyScenario)) {
      return true;
    }
    if (String.isBlank(rawPromptJson)) {
      return false;
    }

    try {
      Map<String, Object> payload = parsePromptPayload(rawPromptJson);
      Map<String, Object> analysisScenario = asMap(
        payload.get('analysis_scenario')
      );
      if (analysisScenario == null) {
        return false;
      }
      String scenarioCode = normalizeSupplyScenario(
        stringValue(analysisScenario.get('code')),
        true
      );
      return scenarioCode == normalizedSupplyScenario;
    } catch (Exception ex) {
      return false;
    }
  }

  private static Account ensureScenarioPromptSnapshot(
    Id rootAccountId,
    String supplyScenario
  ) {
    Account rootAccount = loadRootAccount(rootAccountId);
    if (
      promptJsonMatchesSupplyScenario(
        rootAccount.CM_Supply_Network_Prompt_JSON__c,
        supplyScenario
      )
    ) {
      return rootAccount;
    }

    String scenarioSnapshotJson = buildScenarioPromptSnapshotJson(
      rootAccount,
      supplyScenario
    );
    if (String.isBlank(scenarioSnapshotJson)) {
      throw new AuraHandledException(
        '找不到所選場景的供應鏈資料。請先建立或維護該場景的關係。'
      );
    }

    persistPromptJsonOnAccount(rootAccountId, scenarioSnapshotJson);
    return loadRootAccount(rootAccountId);
  }

  private static String buildScenarioPromptSnapshotJson(
    Account rootAccount,
    String supplyScenario
  ) {
    if (rootAccount == null) {
      return null;
    }

    String normalizedSupplyScenario = normalizeAiSupplyScenario(supplyScenario);
    GraphResponse graphSnapshot = buildManualGraphResponse(
      rootAccount,
      ABSOLUTE_MAX_NODES,
      null,
      normalizedSupplyScenario
    );
    if (graphSnapshot == null || graphSnapshot.edges.isEmpty()) {
      return null;
    }

    Set<Id> includedAccountIds = new Set<Id>();
    for (NodeDto graphNode : graphSnapshot.nodes) {
      if (graphNode == null || graphNode.accountId == null) {
        continue;
      }
      includedAccountIds.add(graphNode.accountId);
    }
    if (includedAccountIds.isEmpty()) {
      return null;
    }

    Set<String> visibleEdgeKeys = new Set<String>();
    for (EdgeDto graphEdge : graphSnapshot.edges) {
      if (graphEdge == null) {
        continue;
      }
      visibleEdgeKeys.add(
        buildVisibleEdgeKey(
          graphEdge.sourceId,
          graphEdge.targetId,
          graphEdge.relationType,
          graphEdge.relationshipDirection
        )
      );
    }
    if (visibleEdgeKeys.isEmpty()) {
      return null;
    }

    List<Object> relationshipsPayload = new List<Object>();
    Integer upstreamCount = 0;
    Integer downstreamCount = 0;
    Integer competitorCount = 0;
    Boolean matchedWnc = false;
    Boolean hasDirectWnc = false;
    Set<String> involvedProducts = new Set<String>();
    String rootId = String.valueOf(rootAccount.Id);
    String rootDomain = normalizeDomain(rootAccount.Website);
    Set<String> includedVisibleEdgeKeys = new Set<String>();

    for (CM_Supply_Relationship__c relationshipRecord : [
      SELECT
        Source_Account__c,
        Source_Account__r.Name,
        Source_Account__r.Website,
        Target_Account__c,
        Target_Account__r.Name,
        Target_Account__r.Website,
        Edge_Category__c,
        Relation_Type__c,
        Role__c,
        Products__c,
        Evidence__c,
        Confidence__c,
        Source_Type__c,
        Supply_Scenario__c,
        Supply_Scenario_Code__c
      FROM CM_Supply_Relationship__c
      WHERE
        Is_Active__c = TRUE
        AND Source_Account__c != NULL
        AND Target_Account__c != NULL
        AND Source_Account__c IN :includedAccountIds
        AND Target_Account__c IN :includedAccountIds
      LIMIT :MANUAL_RELATIONSHIP_QUERY_LIMIT
    ]) {
      if (
        !matchesSupplyScenario(
          extractRelationshipSupplyScenario(relationshipRecord),
          normalizedSupplyScenario
        )
      ) {
        continue;
      }
      if (
        relationshipRecord.Confidence__c != null &&
        relationshipRecord.Confidence__c < MIN_CONFIDENCE
      ) {
        continue;
      }

      String sourceDomain = normalizeDomain(
        relationshipRecord.Source_Account__r == null
          ? null
          : relationshipRecord.Source_Account__r.Website
      );
      String targetDomain = normalizeDomain(
        relationshipRecord.Target_Account__r == null
          ? null
          : relationshipRecord.Target_Account__r.Website
      );
      String sourceName = relationshipRecord.Source_Account__r == null
        ? null
        : relationshipRecord.Source_Account__r.Name;
      String targetName = relationshipRecord.Target_Account__r == null
        ? null
        : relationshipRecord.Target_Account__r.Name;
      if (
        String.isBlank(sourceDomain) ||
        String.isBlank(targetDomain) ||
        String.isBlank(sourceName) ||
        String.isBlank(targetName)
      ) {
        continue;
      }

      String edgeCategory = normalizeEdgeCategory(
        relationshipRecord.Edge_Category__c
      );
      String relationType = String.isBlank(relationshipRecord.Relation_Type__c)
        ? defaultRelationTypeByCategory(edgeCategory)
        : relationshipRecord.Relation_Type__c;
      String direction = inferRelationshipDirection(
        edgeCategory,
        String.valueOf(relationshipRecord.Source_Account__c),
        String.valueOf(relationshipRecord.Target_Account__c),
        rootId
      );
      String visibleEdgeKey = buildVisibleEdgeKey(
        String.valueOf(relationshipRecord.Source_Account__c),
        String.valueOf(relationshipRecord.Target_Account__c),
        relationType,
        direction
      );
      if (!visibleEdgeKeys.contains(visibleEdgeKey)) {
        continue;
      }
      if (includedVisibleEdgeKeys.contains(visibleEdgeKey)) {
        continue;
      }
      includedVisibleEdgeKeys.add(visibleEdgeKey);

      if (edgeCategory == 'UPSTREAM') {
        upstreamCount++;
      } else if (
        edgeCategory == 'DOWNSTREAM' ||
        edgeCategory == 'INDIRECT_PATH'
      ) {
        downstreamCount++;
      } else if (edgeCategory == 'COMPETITOR') {
        competitorCount++;
      }

      Boolean sourceIsWnc = isFocusCompany(sourceDomain, sourceName);
      Boolean targetIsWnc = isFocusCompany(targetDomain, targetName);
      if (sourceIsWnc || targetIsWnc) {
        matchedWnc = true;
        if (
          String.valueOf(relationshipRecord.Source_Account__c) == rootId ||
          String.valueOf(relationshipRecord.Target_Account__c) == rootId
        ) {
          hasDirectWnc = true;
        }
      }

      List<String> productItems = splitPromptList(
        relationshipRecord.Products__c,
        '[,;\\n]+'
      );
      involvedProducts.addAll(productItems);

      Map<String, Object> edgePayload = new Map<String, Object>{
        'source_company_name' => sourceName,
        'source_company_domain' => sourceDomain,
        'target_company_name' => targetName,
        'target_company_domain' => targetDomain,
        'edge_category' => edgeCategory,
        'relation_type' => relationType,
        'role' => relationshipRecord.Role__c,
        'products_or_solutions' => productItems,
        'confidence' => relationshipRecord.Confidence__c == null
          ? 0.80
          : relationshipRecord.Confidence__c,
        'source_type' => normalizeSourceType(relationshipRecord.Source_Type__c),
        'evidence' => splitPromptList(
          relationshipRecord.Evidence__c,
          '\\r?\\n+'
        ),
        'is_focus_company_path' => sourceIsWnc || targetIsWnc
      };
      relationshipsPayload.add(edgePayload);
    }

    if (relationshipsPayload.isEmpty()) {
      return null;
    }

    SupplyNetworkRuntimeConfig runtimeConfig = getSupplyNetworkRuntimeConfig();
    String coverageNote = '由目前場景的 CM Supply Relationship 關係產生分析快照。';
    Map<String, Object> payload = new Map<String, Object>{
      'schema_version' => '2.1',
      'analysis_scenario' => new Map<String, Object>{
        'code' => normalizedSupplyScenario,
        'label' => getSupplyScenarioLabel(normalizedSupplyScenario)
      },
      'root_account' => new Map<String, Object>{
        'name' => rootAccount.Name,
        'website' => rootAccount.Website,
        'domain' => rootDomain,
        'core_positioning' => rootAccount.Description
      },
      'relationships' => relationshipsPayload,
      'focus_company_analysis' => new Map<String, Object>{
        'focus_company_name' => runtimeConfig.focusCompanyName,
        'focus_company_domain' => runtimeConfig.focusCompanyDomain,
        'matched_in_relationships' => matchedWnc,
        'has_direct_relationship' => hasDirectWnc,
        'relationship_category' => matchedWnc
          ? 'UPSTREAM_DOWNSTREAM'
          : 'NO_DIRECT_RELATION',
        'involved_products_or_technologies' => new List<String>(
          involvedProducts
        ),
        'detailed_analysis' => '此快照由目前場景的手動與智能建立關係整理而成。'
      },
      'unresolved_companies' => new List<Object>(),
      'summary' => new Map<String, Object>{
        'upstream_count' => upstreamCount,
        'downstream_count' => downstreamCount,
        'competitor_count' => competitorCount,
        'coverage_note' => buildManualCoverageNote(
          normalizedSupplyScenario,
          coverageNote
        )
      },
      'quality' => new Map<String, Object>{
        'min_confidence_applied' => MIN_CONFIDENCE,
        'dedupe_key' => 'source_target_relation_type_supply_scenario',
        'must_include_targets' => new List<String>{
          rootAccount.Name,
          runtimeConfig.focusCompanyName
        },
        'coverage_gaps' => new List<String>(),
        'must_include_check' => new List<Object>()
      }
    };
    return JSON.serialize(payload);
  }

  private static List<String> splitPromptList(String rawText, String pattern) {
    List<String> items = new List<String>();
    if (String.isBlank(rawText)) {
      return items;
    }

    for (String rawItem : rawText.split(pattern)) {
      if (String.isBlank(rawItem)) {
        continue;
      }
      items.add(rawItem.trim());
    }
    return items;
  }

  private static Boolean isFocusCompany(
    String companyDomain,
    String companyName
  ) {
    SupplyNetworkRuntimeConfig runtimeConfig = getSupplyNetworkRuntimeConfig();
    String normalizedDomain = normalizeDomain(companyDomain);
    String normalizedName = normalizeName(companyName);
    String focusAlias = normalizeName(
      resolveFocusCompanyAlias(runtimeConfig.focusCompanyName)
    );
    return normalizedDomain == normalizeDomain(runtimeConfig.focusCompanyDomain) ||
      normalizedName == normalizeName(runtimeConfig.focusCompanyName) ||
      (!String.isBlank(focusAlias) && normalizedName == focusAlias);
  }

  private static String resolveFocusCompanyAlias(String focusCompanyName) {
    if (String.isBlank(focusCompanyName)) {
      return null;
    }
    List<String> tokens = focusCompanyName.trim().split('\\s+');
    if (tokens.isEmpty()) {
      return null;
    }
    String alias = tokens[tokens.size() - 1];
    return String.isBlank(alias) ? null : alias;
  }

  private static void persistPromptJsonOnAccount(
    Id rootAccountId,
    String rawPromptJson
  ) {
    if (rootAccountId == null || String.isBlank(rawPromptJson)) {
      return;
    }

    String jsonToStore;
    try {
      String sanitizedJson = sanitizePromptJson(rawPromptJson);
      Object payloadRaw = JSON.deserializeUntyped(sanitizedJson);
      jsonToStore = payloadRaw == null
        ? sanitizedJson
        : JSON.serialize(payloadRaw);
    } catch (Exception ex) {
      jsonToStore = rawPromptJson.trim();
    }

    if (String.isBlank(jsonToStore)) {
      return;
    }

    if (jsonToStore.length() > ACCOUNT_PROMPT_JSON_MAX_LENGTH) {
      jsonToStore = jsonToStore.substring(0, ACCOUNT_PROMPT_JSON_MAX_LENGTH);
    }

    try {
      update new Account(
        Id = rootAccountId,
        CM_Supply_Network_Prompt_JSON__c = jsonToStore
      );
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.WARN,
        'Failed to persist CM prompt JSON snapshot: ' + ex.getMessage()
      );
    }
  }

  private static SmartBuildStats upsertPromptRelationships(
    List<Object> relationshipObjects,
    Account rootAccount,
    AccountLookup accountLookup,
    Boolean preserveExistingRelationships,
    String supplyScenario
  ) {
    SmartBuildStats stats = new SmartBuildStats();
    if (
      relationshipObjects == null ||
      relationshipObjects.isEmpty() ||
      rootAccount == null
    ) {
      return stats;
    }

    Boolean edgeBasedPrompt = isEdgeBasedPrompt(relationshipObjects);
    List<PromptEdgeCandidate> candidates = new List<PromptEdgeCandidate>();
    Set<Id> sourceIds = new Set<Id>();
    Set<Id> targetIds = new Set<Id>();
    Set<String> edgeCategories = new Set<String>();
    Set<String> relationTypes = new Set<String>();

    for (Object relationshipObject : relationshipObjects) {
      Map<String, Object> relationship = asMap(relationshipObject);
      stats.totalCandidateCount++;
      if (relationship == null) {
        stats.skippedCount++;
        continue;
      }

      PromptEdgeCandidate candidate = edgeBasedPrompt
        ? buildPromptEdgeCandidateFromEdges(
            relationship,
            rootAccount,
            accountLookup,
            supplyScenario
          )
        : buildPromptEdgeCandidateFromLegacy(
            relationship,
            rootAccount,
            accountLookup,
            supplyScenario
          );
      if (candidate == null) {
        stats.skippedCount++;
        continue;
      }

      candidates.add(candidate);
      sourceIds.add(candidate.sourceAccountId);
      targetIds.add(candidate.targetAccountId);
      edgeCategories.add(candidate.edgeCategory);
      relationTypes.add(candidate.relationType);
    }

    if (candidates.isEmpty()) {
      return stats;
    }

    Map<String, CM_Supply_Relationship__c> existingByKey = new Map<String, CM_Supply_Relationship__c>();
    for (CM_Supply_Relationship__c relationshipRecord : [
      SELECT
        Id,
        Source_Account__c,
        Target_Account__c,
        Edge_Category__c,
        Relation_Type__c,
        Role__c,
        Products__c,
        Supply_Scenario__c,
        Supply_Scenario_Code__c,
        Evidence__c,
        Confidence__c,
        Source_Type__c,
        Is_User_Curated__c,
        Is_Active__c
      FROM CM_Supply_Relationship__c
      WHERE
        Source_Account__c IN :sourceIds
        AND Target_Account__c IN :targetIds
        AND Edge_Category__c IN :edgeCategories
        AND Relation_Type__c IN :relationTypes
      LIMIT :MANUAL_RELATIONSHIP_QUERY_LIMIT
    ]) {
      existingByKey.put(
        buildPromptRelationshipKey(
          relationshipRecord.Source_Account__c,
          relationshipRecord.Target_Account__c,
          relationshipRecord.Edge_Category__c,
          relationshipRecord.Relation_Type__c,
          extractRelationshipSupplyScenario(relationshipRecord)
        ),
        relationshipRecord
      );
    }

    List<CM_Supply_Relationship__c> inserts = new List<CM_Supply_Relationship__c>();
    List<CM_Supply_Relationship__c> updates = new List<CM_Supply_Relationship__c>();
    Set<String> dedupeKeys = new Set<String>();

    for (PromptEdgeCandidate candidate : candidates) {
      String relationshipKey = buildPromptRelationshipKey(
        candidate.sourceAccountId,
        candidate.targetAccountId,
        candidate.edgeCategory,
        candidate.relationType,
        candidate.supplyScenario
      );
      if (dedupeKeys.contains(relationshipKey)) {
        stats.skippedCount++;
        continue;
      }
      dedupeKeys.add(relationshipKey);

      CM_Supply_Relationship__c existingRecord = existingByKey.get(
        relationshipKey
      );
      if (existingRecord == null) {
        CM_Supply_Relationship__c newRecord = new CM_Supply_Relationship__c(
          Source_Account__c = candidate.sourceAccountId,
          Target_Account__c = candidate.targetAccountId,
          Edge_Category__c = candidate.edgeCategory,
          Relation_Type__c = candidate.relationType,
          Role__c = candidate.role,
          Products__c = candidate.products,
          Evidence__c = candidate.evidence,
          Confidence__c = candidate.confidence,
          Source_Type__c = candidate.sourceType,
          Is_Active__c = true
        );
        applyRelationshipSupplyScenario(newRecord, candidate.supplyScenario);
        inserts.add(newRecord);
        stats.insertedCount++;
      } else {
        if (existingRecord.Is_User_Curated__c == true) {
          stats.skippedCount++;
          continue;
        }
        if (preserveExistingRelationships == true) {
          stats.skippedCount++;
          continue;
        }
        existingRecord.Role__c = candidate.role;
        existingRecord.Products__c = candidate.products;
        applyRelationshipSupplyScenario(existingRecord, candidate.supplyScenario);
        existingRecord.Evidence__c = candidate.evidence;
        existingRecord.Confidence__c = candidate.confidence;
        existingRecord.Source_Type__c = candidate.sourceType;
        existingRecord.Is_Active__c = true;
        updates.add(existingRecord);
        stats.updatedCount++;
      }
    }

    if (!inserts.isEmpty()) {
      insert inserts;
    }
    if (!updates.isEmpty()) {
      update updates;
    }

    return stats;
  }

  private static PromptEdgeCandidate buildPromptEdgeCandidateFromLegacy(
    Map<String, Object> relationship,
    Account rootAccount,
    AccountLookup accountLookup,
    String supplyScenario
  ) {
    Decimal confidence = toDecimal(relationship.get('confidence'));
    if (confidence == null || confidence < MIN_CONFIDENCE) {
      return null;
    }

    String direction = normalizeDirection(
      stringValue(relationship.get('direction'))
    );
    if (direction == null) {
      return null;
    }

    String companyDomain = normalizeDomain(
      stringValue(relationship.get('company_domain'))
    );
    if (String.isBlank(companyDomain)) {
      return null;
    }

    String companyName = stringValue(relationship.get('company_name'));
    if (String.isBlank(companyName)) {
      companyName = companyDomain;
    }

    String rootDomain = normalizeDomain(rootAccount.Website);
    String rootNameKey = normalizeName(rootAccount.Name);
    if (
      (!String.isBlank(rootDomain) && companyDomain == rootDomain) ||
      (!String.isBlank(rootNameKey) &&
      normalizeName(companyName) == rootNameKey)
    ) {
      return null;
    }

    Account companyAccount = resolveAccountForRelationship(
      relationship,
      accountLookup
    );
    if (companyAccount == null || companyAccount.Id == null) {
      return null;
    }

    PromptEdgeCandidate candidate = new PromptEdgeCandidate();
    String sourceAccountId = String.valueOf(
      direction == 'UPSTREAM' ? companyAccount.Id : rootAccount.Id
    );
    String targetAccountId = String.valueOf(
      direction == 'UPSTREAM' ? rootAccount.Id : companyAccount.Id
    );
    NormalizedEdgeOrientation orientation = normalizeEdgeOrientation(
      direction,
      sourceAccountId,
      targetAccountId,
      String.valueOf(rootAccount.Id)
    );
    candidate.sourceAccountId = (Id) orientation.sourceId;
    candidate.targetAccountId = (Id) orientation.targetId;
    candidate.edgeCategory = orientation.edgeCategory;
    candidate.relationType = truncateText(
      String.isBlank(stringValue(relationship.get('relation_type')))
        ? defaultRelationTypeByCategory(candidate.edgeCategory)
        : stringValue(relationship.get('relation_type')),
      80
    );
    candidate.role = truncateText(stringValue(relationship.get('role')), 255);
    candidate.products = normalizeLongText(
      extractPromptProductsText(relationship)
    );
    candidate.evidence = normalizeLongText(
      extractPromptEvidenceText(relationship)
    );
    candidate.sourceType = normalizeSourceType(
      stringValue(relationship.get('source_type'))
    );
    candidate.supplyScenario = supplyScenario;
    try {
      candidate.confidence = normalizeConfidence(confidence);
    } catch (Exception ex) {
      return null;
    }
    return candidate;
  }

  private static PromptEdgeCandidate buildPromptEdgeCandidateFromEdges(
    Map<String, Object> relationship,
    Account rootAccount,
    AccountLookup accountLookup,
    String supplyScenario
  ) {
    Decimal confidence = toDecimal(relationship.get('confidence'));
    if (confidence == null || confidence < MIN_CONFIDENCE) {
      return null;
    }

    String sourceDomain = normalizeDomain(
      stringValue(relationship.get('source_company_domain'))
    );
    String targetDomain = normalizeDomain(
      stringValue(relationship.get('target_company_domain'))
    );
    if (String.isBlank(sourceDomain) || String.isBlank(targetDomain)) {
      return null;
    }

    String sourceName = stringValue(relationship.get('source_company_name'));
    String targetName = stringValue(relationship.get('target_company_name'));
    if (String.isBlank(sourceName)) {
      sourceName = sourceDomain;
    }
    if (String.isBlank(targetName)) {
      targetName = targetDomain;
    }

    String rootDomain = normalizeDomain(rootAccount.Website);
    String rootNameKey = normalizeName(rootAccount.Name);
    Boolean sourceIsRoot = isRootCompany(
      sourceDomain,
      normalizeName(sourceName),
      rootDomain,
      rootNameKey
    );
    Boolean targetIsRoot = isRootCompany(
      targetDomain,
      normalizeName(targetName),
      rootDomain,
      rootNameKey
    );

    Account sourceAccount = sourceIsRoot
      ? rootAccount
      : resolveAccountForCompany(
          sourceDomain,
          normalizeName(sourceName),
          accountLookup
        );
    Account targetAccount = targetIsRoot
      ? rootAccount
      : resolveAccountForCompany(
          targetDomain,
          normalizeName(targetName),
          accountLookup
        );
    if (sourceAccount == null || targetAccount == null) {
      return null;
    }
    if (sourceAccount.Id == targetAccount.Id) {
      return null;
    }

    String edgeCategory = normalizeEdgeCategory(
      stringValue(relationship.get('edge_category'))
    );
    if (edgeCategory == null) {
      if (targetIsRoot) {
        edgeCategory = 'UPSTREAM';
      } else if (sourceIsRoot) {
        edgeCategory = 'DOWNSTREAM';
      } else {
        edgeCategory = 'INDIRECT_PATH';
      }
    }

    PromptEdgeCandidate candidate = new PromptEdgeCandidate();
    NormalizedEdgeOrientation orientation = normalizeEdgeOrientation(
      edgeCategory,
      String.valueOf(sourceAccount.Id),
      String.valueOf(targetAccount.Id),
      String.valueOf(rootAccount.Id)
    );
    candidate.sourceAccountId = (Id) orientation.sourceId;
    candidate.targetAccountId = (Id) orientation.targetId;
    candidate.edgeCategory = orientation.edgeCategory;
    candidate.relationType = truncateText(
      String.isBlank(stringValue(relationship.get('relation_type')))
        ? defaultRelationTypeByCategory(candidate.edgeCategory)
        : stringValue(relationship.get('relation_type')),
      80
    );
    candidate.role = truncateText(stringValue(relationship.get('role')), 255);
    candidate.products = normalizeLongText(
      extractPromptProductsText(relationship)
    );
    candidate.evidence = normalizeLongText(
      extractPromptEvidenceText(relationship)
    );
    candidate.sourceType = normalizeSourceType(
      stringValue(relationship.get('source_type'))
    );
    candidate.supplyScenario = supplyScenario;
    try {
      candidate.confidence = normalizeConfidence(confidence);
    } catch (Exception ex) {
      return null;
    }
    return candidate;
  }

  private static String extractPromptProductsText(
    Map<String, Object> relationship
  ) {
    for (
      String keyName : new List<String>{
        'products',
        'products_or_components',
        'products_or_solutions'
      }
    ) {
      String value = flattenTextList(relationship.get(keyName), ', ');
      if (!String.isBlank(value)) {
        return value;
      }
    }
    return null;
  }

  private static String extractPromptEvidenceText(
    Map<String, Object> relationship
  ) {
    return flattenTextList(relationship.get('evidence'), '\n');
  }

  private static String flattenTextList(Object rawValue, String separator) {
    if (rawValue == null) {
      return null;
    }
    List<Object> rawList = asList(rawValue);
    if (rawList != null) {
      List<String> values = new List<String>();
      for (Object rawItem : rawList) {
        String itemValue = stringValue(rawItem);
        if (!String.isBlank(itemValue)) {
          values.add(itemValue);
        }
      }
      return values.isEmpty() ? null : String.join(values, separator);
    }
    return stringValue(rawValue);
  }

  private static String truncateText(String rawValue, Integer maxLength) {
    if (String.isBlank(rawValue)) {
      return null;
    }
    String trimmed = rawValue.trim();
    if (maxLength == null || maxLength <= 0 || trimmed.length() <= maxLength) {
      return trimmed;
    }
    return trimmed.substring(0, maxLength);
  }

  private static String buildPromptRelationshipKey(
    Id sourceAccountId,
    Id targetAccountId,
    String edgeCategory,
    String relationType,
    String supplyScenario
  ) {
    return String.valueOf(sourceAccountId) +
      '|' +
      String.valueOf(targetAccountId) +
      '|' +
      String.valueOf(edgeCategory) +
      '|' +
      String.valueOf(relationType) +
      '|' +
      String.valueOf(normalizeStoredSupplyScenario(supplyScenario));
  }

  private static String buildVisibleEdgeKey(
    String sourceId,
    String targetId,
    String relationType,
    String relationshipDirection
  ) {
    return String.valueOf(sourceId) +
      '|' +
      String.valueOf(targetId) +
      '|' +
      String.valueOf(relationType) +
      '|' +
      String.valueOf(relationshipDirection);
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
      return (Map<String, Object>) payloadRaw;
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw new AuraHandledException(
        'Prompt output is not valid JSON: ' + ex.getMessage()
      );
    }
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
      new DemoNodeDefinition(
        'Quincy',
        'IC 設計原廠',
        '核心設計與平台供應節點。'
      ),
      new DemoNodeDefinition(
        'TSMC',
        '晶圓代工 (Foundry)',
        '提供先進製程晶圓代工服務。'
      ),
      new DemoNodeDefinition(
        'ASE',
        '封裝與測試 (OSAT)',
        '提供封裝與測試能力。'
      ),
      new DemoNodeDefinition(
        'Amkor',
        '封裝與測試 (OSAT)',
        '支援後段封裝與測試產能。'
      ),
      new DemoNodeDefinition(
        'WPG',
        'IC 通路代理商',
        '提供通路供貨與 FAE 支援。'
      ),
      new DemoNodeDefinition(
        'WT Microelectronics',
        'IC 通路代理商',
        '提供通路供貨與技術服務。'
      ),
      new DemoNodeDefinition(
        'WNC',
        '網通與車用設備 ODM/JDM',
        '負責系統整合與最終組裝。'
      ),
      new DemoNodeDefinition(
        'Verizon',
        '電信營運商',
        '5G FWA 家用路由器導入客戶。'
      ),
      new DemoNodeDefinition(
        'AT&T',
        '電信營運商',
        '5G FWA 家用路由器導入客戶。'
      ),
      new DemoNodeDefinition(
        'T-Mobile US',
        '電信營運商',
        '5G FWA 家用路由器導入客戶。'
      ),
      new DemoNodeDefinition('Ford', '車廠客戶', '車聯網模組導入客戶。'),
      new DemoNodeDefinition(
        'General Motors',
        '車廠客戶',
        '車聯網模組導入客戶。'
      )
    };
  }

  private static List<DemoEdgeDefinition> getDemoEdgeDefinitions() {
    return new List<DemoEdgeDefinition>{
      new DemoEdgeDefinition('TSMC', 'Quincy', 'Foundry', 'UPSTREAM'),
      new DemoEdgeDefinition('ASE', 'Quincy', 'OSAT', 'UPSTREAM'),
      new DemoEdgeDefinition('Amkor', 'Quincy', 'OSAT', 'UPSTREAM'),
      new DemoEdgeDefinition('Quincy', 'WPG', 'Distributor', 'DOWNSTREAM'),
      new DemoEdgeDefinition(
        'Quincy',
        'WT Microelectronics',
        'Distributor',
        'DOWNSTREAM'
      ),
      new DemoEdgeDefinition('WPG', 'WNC', 'Channel Partner', 'DOWNSTREAM'),
      new DemoEdgeDefinition(
        'WT Microelectronics',
        'WNC',
        'Channel Partner',
        'DOWNSTREAM'
      ),
      new DemoEdgeDefinition(
        'WNC',
        'Verizon',
        'Telecom Operator',
        'DOWNSTREAM'
      ),
      new DemoEdgeDefinition('WNC', 'AT&T', 'Telecom Operator', 'DOWNSTREAM'),
      new DemoEdgeDefinition(
        'WNC',
        'T-Mobile US',
        'Telecom Operator',
        'DOWNSTREAM'
      ),
      new DemoEdgeDefinition('WNC', 'Ford', 'Automaker', 'DOWNSTREAM'),
      new DemoEdgeDefinition('WNC', 'General Motors', 'Automaker', 'DOWNSTREAM')
    };
  }

  private static Map<String, Integer> computeShortestDistance(
    Map<String, List<String>> adjacencyByNode,
    String rootNameKey
  ) {
    Map<String, Integer> distanceByNode = new Map<String, Integer>();
    if (
      String.isBlank(rootNameKey) || !adjacencyByNode.containsKey(rootNameKey)
    ) {
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

  private static Map<String, Integer> computeWeaklyConnectedDistance(
    Map<String, List<String>> outgoingByNode,
    Map<String, List<String>> incomingByNode,
    String rootNodeId
  ) {
    Map<String, List<String>> undirectedByNode = new Map<String, List<String>>();
    mergeUndirectedAdjacency(undirectedByNode, outgoingByNode);
    mergeUndirectedAdjacency(undirectedByNode, incomingByNode);
    return computeShortestDistance(undirectedByNode, rootNodeId);
  }

  private static void mergeUndirectedAdjacency(
    Map<String, List<String>> undirectedByNode,
    Map<String, List<String>> directionalByNode
  ) {
    if (directionalByNode == null || directionalByNode.isEmpty()) {
      return;
    }

    for (String sourceNodeId : directionalByNode.keySet()) {
      if (String.isBlank(sourceNodeId)) {
        continue;
      }
      ensureAdjacency(undirectedByNode, sourceNodeId);
      List<String> targetNodeIds = directionalByNode.get(sourceNodeId);
      if (targetNodeIds == null) {
        continue;
      }

      for (String targetNodeId : targetNodeIds) {
        if (String.isBlank(targetNodeId)) {
          continue;
        }
        ensureAdjacency(undirectedByNode, targetNodeId);
        if (!undirectedByNode.get(sourceNodeId).contains(targetNodeId)) {
          undirectedByNode.get(sourceNodeId).add(targetNodeId);
        }
        if (!undirectedByNode.get(targetNodeId).contains(sourceNodeId)) {
          undirectedByNode.get(targetNodeId).add(sourceNodeId);
        }
      }
    }
  }

  private static Integer normalizeMaxNodes(Integer requestedMaxNodes) {
    Integer normalized = requestedMaxNodes == null
      ? DEFAULT_MAX_NODES
      : requestedMaxNodes;
    if (normalized <= 0) {
      normalized = DEFAULT_MAX_NODES;
    }
    return Math.min(normalized, ABSOLUTE_MAX_NODES);
  }

  private static String normalizeSmartBuildMode(String buildMode) {
    String normalized = String.isBlank(buildMode)
      ? SMART_BUILD_MODE_UPSERT
      : buildMode.trim().toUpperCase();
    return normalized == SMART_BUILD_MODE_FULL_REBUILD
      ? SMART_BUILD_MODE_FULL_REBUILD
      : SMART_BUILD_MODE_UPSERT;
  }

  private static Integer deactivateRootDirectRelationships(
    Id rootAccountId,
    String supplyScenario
  ) {
    if (rootAccountId == null) {
      return 0;
    }

    String normalizedSupplyScenario = normalizeSupplyScenario(
      supplyScenario,
      true
    );
    List<CM_Supply_Relationship__c> activeRows = [
      SELECT
        Id,
        Is_Active__c,
        Supply_Scenario__c,
        Supply_Scenario_Code__c,
        Is_User_Curated__c
      FROM CM_Supply_Relationship__c
      WHERE
        Is_Active__c = TRUE
        AND (Source_Account__c = :rootAccountId
        OR Target_Account__c = :rootAccountId)
      LIMIT :MANUAL_RELATIONSHIP_QUERY_LIMIT
    ];
    if (activeRows.isEmpty()) {
      return 0;
    }

    List<CM_Supply_Relationship__c> rowsToDeactivate = new List<CM_Supply_Relationship__c>();
    for (CM_Supply_Relationship__c row : activeRows) {
      if (
        !matchesSupplyScenario(
          extractRelationshipSupplyScenario(row),
          normalizedSupplyScenario
        )
      ) {
        continue;
      }
      if (row.Is_User_Curated__c == true) {
        continue;
      }
      row.Is_Active__c = false;
      rowsToDeactivate.add(row);
    }
    if (rowsToDeactivate.isEmpty()) {
      return 0;
    }
    update rowsToDeactivate;
    return rowsToDeactivate.size();
  }

  private static Account loadRootAccount(Id rootAccountId) {
    List<Account> rootAccounts = [
      SELECT
        Id,
        Name,
        Type,
        Website,
        Industry,
        Description,
        BillingCountry,
        CM_Supply_Network_Prompt_JSON__c
      FROM Account
      WHERE Id = :rootAccountId
      LIMIT 1
    ];
    if (rootAccounts.isEmpty()) {
      throw new AuraHandledException(
        'The requested account cannot be found or is not accessible.'
      );
    }
    return rootAccounts[0];
  }

  private static Account loadAccountById(Id accountId) {
    List<Account> accounts = [
      SELECT Id, Name, Type
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      throw new AuraHandledException(
        'The related account cannot be found or is not accessible.'
      );
    }
    return accounts[0];
  }

  private static Integer normalizeManualRelationshipLimit(
    Integer requestedLimit
  ) {
    Integer normalized = requestedLimit == null
      ? MANUAL_RELATIONSHIP_PANEL_DEFAULT_LIMIT
      : requestedLimit;
    if (normalized <= 0) {
      normalized = MANUAL_RELATIONSHIP_PANEL_DEFAULT_LIMIT;
    }
    return Math.min(normalized, MANUAL_RELATIONSHIP_QUERY_LIMIT);
  }

  private static ManualRelationshipRow buildManualRelationshipRowById(
    Id relationshipId,
    Id rootAccountId
  ) {
    List<CM_Supply_Relationship__c> relationships = [
      SELECT
        Id,
        Source_Account__c,
        Source_Account__r.Name,
        Target_Account__c,
        Target_Account__r.Name,
        Edge_Category__c,
        Relation_Type__c,
        Role__c,
        Products__c,
        Supply_Scenario__c,
        Supply_Scenario_Code__c,
        Evidence__c,
        Confidence__c,
        Source_Type__c,
        Is_User_Curated__c,
        Is_Active__c,
        LastModifiedDate
      FROM CM_Supply_Relationship__c
      WHERE Id = :relationshipId
      LIMIT 1
    ];
    if (relationships.isEmpty()) {
      throw new AuraHandledException('Unable to find saved relationship.');
    }
    return buildManualRelationshipRow(relationships[0], rootAccountId);
  }

  private static ManualRelationshipRow buildManualRelationshipRow(
    CM_Supply_Relationship__c relationshipRecord,
    Id rootAccountId
  ) {
    ManualRelationshipRow row = new ManualRelationshipRow();
    row.id = relationshipRecord.Id;
    row.sourceAccountId = relationshipRecord.Source_Account__c;
    row.sourceAccountName = relationshipRecord.Source_Account__r == null
      ? null
      : relationshipRecord.Source_Account__r.Name;
    row.targetAccountId = relationshipRecord.Target_Account__c;
    row.targetAccountName = relationshipRecord.Target_Account__r == null
      ? null
      : relationshipRecord.Target_Account__r.Name;
    row.edgeCategory = normalizeEdgeCategory(
      relationshipRecord.Edge_Category__c
    );
    row.relationType = relationshipRecord.Relation_Type__c;
    row.role = relationshipRecord.Role__c;
    row.products = relationshipRecord.Products__c;
    row.supplyScenario = extractRelationshipSupplyScenario(relationshipRecord);
    row.supplyScenarioLabel = getSupplyScenarioLabelAllowUnknown(
      row.supplyScenario
    );
    row.evidence = relationshipRecord.Evidence__c;
    row.confidence = relationshipRecord.Confidence__c;
    row.sourceType = normalizeSourceType(relationshipRecord.Source_Type__c);
    row.isUserCurated = relationshipRecord.Is_User_Curated__c;
    row.isActive = relationshipRecord.Is_Active__c;
    row.lastModifiedDate = relationshipRecord.LastModifiedDate;

    Boolean sourceIsRoot =
      relationshipRecord.Source_Account__c == rootAccountId;
    Boolean targetIsRoot =
      relationshipRecord.Target_Account__c == rootAccountId;
    Boolean isDirect = sourceIsRoot || targetIsRoot;
    row.pathType = isDirect ? 'DIRECT' : 'INDIRECT';
    row.pathTypeLabel = isDirect ? '直接' : '間接';
    if (sourceIsRoot && !targetIsRoot) {
      row.mode = row.edgeCategory == 'COMPETITOR' ? 'COMPETITOR' : 'DOWNSTREAM';
      row.relatedAccountId = relationshipRecord.Target_Account__c;
      row.relatedAccountName = relationshipRecord.Target_Account__r == null
        ? null
        : relationshipRecord.Target_Account__r.Name;
    } else if (targetIsRoot && !sourceIsRoot) {
      row.mode = 'UPSTREAM';
      row.relatedAccountId = relationshipRecord.Source_Account__c;
      row.relatedAccountName = relationshipRecord.Source_Account__r == null
        ? null
        : relationshipRecord.Source_Account__r.Name;
    } else {
      row.mode = row.edgeCategory == 'COMPETITOR' ? 'COMPETITOR' : 'DOWNSTREAM';
      row.relatedAccountId = null;
      String sourceName = relationshipRecord.Source_Account__r == null
        ? 'Unknown'
        : relationshipRecord.Source_Account__r.Name;
      String targetName = relationshipRecord.Target_Account__r == null
        ? 'Unknown'
        : relationshipRecord.Target_Account__r.Name;
      row.relatedAccountName = sourceName + ' -> ' + targetName;
    }
    return row;
  }

  private static String normalizeManualMode(String modeValue) {
    String normalized = String.isBlank(modeValue)
      ? null
      : modeValue.trim().toUpperCase();
    return SUPPORTED_MANUAL_MODES.contains(normalized) ? normalized : null;
  }

  private static String normalizeSourceType(String sourceTypeValue) {
    String normalized = String.isBlank(sourceTypeValue)
      ? null
      : sourceTypeValue.trim().toUpperCase();
    if (!SUPPORTED_SOURCE_TYPES.contains(normalized)) {
      return 'PUBLIC_INFO';
    }
    return normalized;
  }

  private static Decimal normalizeConfidence(Decimal confidenceValue) {
    Decimal normalized = confidenceValue == null
      ? Decimal.valueOf('0.80')
      : confidenceValue;
    if (normalized < 0 || normalized > 1) {
      throw new AuraHandledException('confidence must be between 0 and 1.');
    }
    return normalized.setScale(2);
  }

  private static String normalizeText(String rawValue) {
    if (String.isBlank(rawValue)) {
      return null;
    }
    return rawValue.trim();
  }

  private static String normalizeLongText(String rawValue) {
    if (String.isBlank(rawValue)) {
      return null;
    }
    return rawValue.trim();
  }

  private static void validateReadAccess(Boolean includePromptFields) {
    if (Test.isRunningTest()) {
      return;
    }

    if (!Schema.sObjectType.Account.isAccessible()) {
      throw new AuraHandledException('You do not have access to Account.');
    }

    assertFieldReadable(Account.Name, 'Account.Name');
    assertFieldReadable(Account.Type, 'Account.Type');

    if (!includePromptFields) {
      return;
    }

    assertFieldReadable(Account.Website, 'Account.Website');
    assertFieldReadable(Account.Industry, 'Account.Industry');
    assertFieldReadable(Account.Description, 'Account.Description');
    assertFieldReadable(Account.BillingCountry, 'Account.BillingCountry');
    assertFieldReadable(
      Account.CM_Supply_Network_Prompt_JSON__c,
      'Account.CM_Supply_Network_Prompt_JSON__c'
    );
  }

  private static void assertFieldReadable(
    Schema.SObjectField fieldToken,
    String fieldPath
  ) {
    if (!fieldToken.getDescribe().isAccessible()) {
      throw new AuraHandledException(
        'You do not have field access: ' + fieldPath
      );
    }
  }

  private static List<Object> asList(Object rawValue) {
    return rawValue instanceof List<Object> ? (List<Object>) rawValue : null;
  }

  private static Map<String, Object> asMap(Object rawValue) {
    return rawValue instanceof Map<String, Object>
      ? (Map<String, Object>) rawValue
      : null;
  }

  private static Decimal toDecimal(Object rawValue) {
    if (rawValue == null) {
      return null;
    }

    if (rawValue instanceof Decimal) {
      return (Decimal) rawValue;
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
    String normalized = String.isBlank(directionValue)
      ? null
      : directionValue.trim().toUpperCase();
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
    return String.isBlank(companyName)
      ? null
      : companyName.trim().toLowerCase();
  }

  private static String buildExternalNodeId(String seed) {
    String digest = EncodingUtil.convertToHex(
      Crypto.generateDigest('MD5', Blob.valueOf(seed))
    );
    return 'ext-' + digest.substring(0, 20);
  }

  private static String buildEdgeId(String seed, Integer indexValue) {
    String digest = EncodingUtil.convertToHex(
      Crypto.generateDigest('MD5', Blob.valueOf(seed + '|' + indexValue))
    );
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

    DemoEdgeDefinition(
      String sourceNameValue,
      String targetNameValue,
      String relationTypeValue,
      String directionValue
    ) {
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

  private class PromptNodeComparator implements System.Comparator<String> {
    private Map<String, Integer> signedLevelByNodeId;
    private Map<String, NodeDto> nodeById;

    PromptNodeComparator(
      Map<String, Integer> signedLevelByNodeIdValue,
      Map<String, NodeDto> nodeByIdValue
    ) {
      signedLevelByNodeId = signedLevelByNodeIdValue;
      nodeById = nodeByIdValue;
    }

    public Integer compare(String leftNodeId, String rightNodeId) {
      Integer leftLevel = signedLevelByNodeId.get(leftNodeId);
      Integer rightLevel = signedLevelByNodeId.get(rightNodeId);
      Integer leftAbs = leftLevel == null ? 99999 : Math.abs(leftLevel);
      Integer rightAbs = rightLevel == null ? 99999 : Math.abs(rightLevel);
      if (leftAbs != rightAbs) {
        return leftAbs < rightAbs ? -1 : 1;
      }

      if (leftLevel != rightLevel) {
        return leftLevel < rightLevel ? -1 : 1;
      }

      String leftLabel = nodeById.containsKey(leftNodeId)
        ? nodeById.get(leftNodeId).label
        : leftNodeId;
      String rightLabel = nodeById.containsKey(rightNodeId)
        ? nodeById.get(rightNodeId).label
        : rightNodeId;
      return leftLabel.toLowerCase().compareTo(rightLabel.toLowerCase());
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

  private static String extractGenerationError(
    ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationOutput
  ) {
    if (
      generationOutput == null ||
      generationOutput.generationErrors == null ||
      generationOutput.generationErrors.isEmpty()
    ) {
      return null;
    }

    Object firstError = generationOutput.generationErrors[0];
    if (firstError == null) {
      return null;
    }

    Map<String, Object> errorMap = (Map<String, Object>) JSON.deserializeUntyped(
      JSON.serialize(firstError)
    );
    String message = stringValue(errorMap.get('localizedErrorMessage'));
    if (String.isBlank(message)) {
      message = stringValue(errorMap.get('errorMessage'));
    }
    String messageCode = stringValue(errorMap.get('messageCode'));
    if (!String.isBlank(messageCode)) {
      message = String.isBlank(message)
        ? messageCode
        : (message + ' [' + messageCode + ']');
    }
    return message;
  }

  private class AccountLookup {
    Map<String, Account> byDomain = new Map<String, Account>();
    Map<String, Account> byName = new Map<String, Account>();
  }

  private class NormalizedEdgeOrientation {
    String sourceId;
    String targetId;
    String edgeCategory;
  }

  private class PromptEdgeCandidate {
    Id sourceAccountId;
    Id targetAccountId;
    String edgeCategory;
    String relationType;
    String role;
    String products;
    String evidence;
    Decimal confidence;
    String sourceType;
    String supplyScenario;
  }

  private class SmartBuildStats {
    Integer totalCandidateCount = 0;
    Integer insertedCount = 0;
    Integer updatedCount = 0;
    Integer skippedCount = 0;
  }

  private class PromptScopeFilter {
    Set<String> relationshipKeys = new Set<String>();
  }

  private class NodeSelectionResult {
    Set<String> includedNodeIds = new Set<String>();
    Boolean truncated = false;
  }

  private class SupplyScenarioDefinition {
    String code;
    String normalizedCode;
    String label;
    Boolean aiSupported;

    SupplyScenarioDefinition(
      String codeValue,
      String labelValue,
      Boolean aiSupportedValue
    ) {
      code = normalizeStoredSupplyScenario(codeValue);
      normalizedCode = code;
      String normalizedLabel = normalizeText(labelValue);
      label = String.isBlank(normalizedLabel)
        ? buildScenarioLabelFromCode(code)
        : normalizedLabel;
      aiSupported = aiSupportedValue == true;
    }
  }

  private class SupplyNetworkRuntimeConfig {
    String focusCompanyName;
    String focusCompanyDomain;
    List<SupplyScenarioDefinition> scenarioDefinitions;
    Map<String, SupplyScenarioDefinition> scenarioByCode;
    Set<String> aiScenarioCodes;
    String scenarioCatalogJson;
  }

  public class SupplyScenarioOption {
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean aiSupported;
  }

  public class SupplyNetworkRuntimeConfigResponse {
    @AuraEnabled
    public String focusCompanyName;
    @AuraEnabled
    public String focusCompanyDomain;
    @AuraEnabled
    public List<SupplyScenarioOption> supplyScenarios;
  }

  public class SmartBuildResponse {
    @AuraEnabled
    public String promptTemplateName;
    @AuraEnabled
    public String buildMode;
    @AuraEnabled
    public String supplyScenario;
    @AuraEnabled
    public String supplyScenarioLabel;
    @AuraEnabled
    public Datetime generatedAt;
    @AuraEnabled
    public Integer totalCandidateCount;
    @AuraEnabled
    public Integer insertedCount;
    @AuraEnabled
    public Integer updatedCount;
    @AuraEnabled
    public Integer skippedCount;
    @AuraEnabled
    public Integer deactivatedCount;
    @AuraEnabled
    public GraphResponse graph;
  }

  public class ManualRelationshipRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id sourceAccountId;
    @AuraEnabled
    public String sourceAccountName;
    @AuraEnabled
    public Id targetAccountId;
    @AuraEnabled
    public String targetAccountName;
    @AuraEnabled
    public Id relatedAccountId;
    @AuraEnabled
    public String relatedAccountName;
    @AuraEnabled
    public String mode;
    @AuraEnabled
    public String edgeCategory;
    @AuraEnabled
    public String relationType;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String products;
    @AuraEnabled
    public String supplyScenario;
    @AuraEnabled
    public String supplyScenarioLabel;
    @AuraEnabled
    public String evidence;
    @AuraEnabled
    public Decimal confidence;
    @AuraEnabled
    public String sourceType;
    @AuraEnabled
    public Boolean isUserCurated;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public Datetime lastModifiedDate;
    @AuraEnabled
    public String pathType;
    @AuraEnabled
    public String pathTypeLabel;
  }

  private class PromptCompanySeed {
    String displayName;
    String domain;
  }

  public class ImpactRiskItem {
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String impact;
    @AuraEnabled
    public String reason;
  }

  public class ImpactAnalysisResponse {
    @AuraEnabled
    public String analysisVersion;
    @AuraEnabled
    public String rootAccount;
    @AuraEnabled
    public String focusCompany;
    @AuraEnabled
    public String supplyScenario;
    @AuraEnabled
    public String supplyScenarioLabel;
    @AuraEnabled
    public String impactLevel;
    @AuraEnabled
    public String summary;
    @AuraEnabled
    public String summaryForUi;
    @AuraEnabled
    public String overallAssessment;
    @AuraEnabled
    public List<ImpactRiskItem> keyRisks;
    @AuraEnabled
    public List<String> positiveSignals;
    @AuraEnabled
    public List<String> recommendedActions;
    @AuraEnabled
    public String rawJson;
    @AuraEnabled
    public Datetime generatedAt;
    @AuraEnabled
    public String promptTemplateName;

    public ImpactAnalysisResponse() {
      keyRisks = new List<ImpactRiskItem>();
      positiveSignals = new List<String>();
      recommendedActions = new List<String>();
    }
  }

  public class GraphResponse {
    @AuraEnabled
    public String rootId;
    @AuraEnabled
    public Boolean truncated;
    @AuraEnabled
    public Integer nodeCount;
    @AuraEnabled
    public Integer edgeCount;
    @AuraEnabled
    public String supplyScenario;
    @AuraEnabled
    public String supplyScenarioLabel;
    @AuraEnabled
    public String promptTemplateName;
    @AuraEnabled
    public String dataSource;
    @AuraEnabled
    public Datetime generatedAt;
    @AuraEnabled
    public String promptRawJson;
    @AuraEnabled
    public String coverageNote;
    @AuraEnabled
    public List<NodeDto> nodes;
    @AuraEnabled
    public List<EdgeDto> edges;

    public GraphResponse() {
      truncated = false;
      nodeCount = 0;
      edgeCount = 0;
      nodes = new List<NodeDto>();
      edges = new List<EdgeDto>();
    }
  }

  public class NodeDto {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean isRoot;
    @AuraEnabled
    public Integer upstreamDepth;
    @AuraEnabled
    public Integer downstreamDepth;
    @AuraEnabled
    public Integer signedLevel;
    @AuraEnabled
    public String accountType;
    @AuraEnabled
    public String relationshipDirection;
    @AuraEnabled
    public String roleLabel;
    @AuraEnabled
    public String noteText;
  }

  public class EdgeDto {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String sourceId;
    @AuraEnabled
    public String targetId;
    @AuraEnabled
    public String relationType;
    @AuraEnabled
    public String edgeCategory;
    @AuraEnabled
    public String relationshipDirection;
    @AuraEnabled
    public String marketRiskNote;
  }
}