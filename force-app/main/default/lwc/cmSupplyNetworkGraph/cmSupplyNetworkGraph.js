import { api, LightningElement, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { loadScript } from "lightning/platformResourceLoader";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import cytoscapeResource from "@salesforce/resourceUrl/cytoscape";
import getGraph from "@salesforce/apex/CMSupplyNetworkGraphController.getGraph";
import getManualRelationships from "@salesforce/apex/CMSupplyNetworkGraphController.getManualRelationships";
import createManualRelationship from "@salesforce/apex/CMSupplyNetworkGraphController.createManualRelationship";
import deactivateManualRelationship from "@salesforce/apex/CMSupplyNetworkGraphController.deactivateManualRelationship";
import activateManualRelationship from "@salesforce/apex/CMSupplyNetworkGraphController.activateManualRelationship";
import analyzeWncImpact from "@salesforce/apex/CMSupplyNetworkGraphController.analyzeWncImpact";
import smartBuildRelationships from "@salesforce/apex/CMSupplyNetworkGraphController.smartBuildRelationships";
import {
  buildFilteredElements,
  buildStoryElements,
  computeNodePositions,
  DISPLAY_MODES,
  FILTER_VALUES
} from "./cmSupplyNetworkGraphUtils";

const FILTER_OPTIONS = [
  { label: "All", value: FILTER_VALUES.ALL },
  { label: "Upstream", value: FILTER_VALUES.UPSTREAM },
  { label: "Downstream", value: FILTER_VALUES.DOWNSTREAM }
];

const STORY_HORIZONTAL_SPACING = 280;
const STORY_VERTICAL_SPACING = 210;
const NETWORK_HORIZONTAL_SPACING = 250;
const NETWORK_VERTICAL_SPACING = 195;
const GRAPH_FIT_PADDING = 64;
const TOOLTIP_OFFSET_X = 18;
const TOOLTIP_OFFSET_Y = 16;
const LANE_NODE_PADDING_X = 16;
const LANE_NODE_PADDING_TOP = 52;
const LANE_NODE_PADDING_BOTTOM = 18;
const LANE_NODE_GAP_X = 24;
const LANE_NODE_GAP_Y = 20;
const LANE_RESIZE_HANDLE_SIZE = 16;
const LANE_RESIZE_HANDLE_INSET = 8;
const NAVIGATION_GUARD_WINDOW_MS = 500;
const PAN_NAVIGATION_GUARD_WINDOW_MS = 120;
const DRAG_NAVIGATION_GUARD_WINDOW_MS = 280;
const CACHE_KEY_PREFIX = "cmSupplyNetworkGraph";
const LOADING_STATUS_MESSAGE = "正在載入上下游關係圖...";
const BACKGROUND_REFRESHING_STATUS_MESSAGE = "顯示上次結果，背景更新中...";
const WNC_IMPACT_LOADING_STATUS_MESSAGE =
  "正在分析供應鏈對 WNC 的影響（約需 10~45 秒），完成後會自動更新。";
const SMART_BUILD_LOADING_STATUS_MESSAGE =
  "正在智能建立供應鏈關係（約需 15~60 秒），完成後會自動更新。";
const COMPETITOR_DIRECTION = "COMPETITOR";
const PREFERENCE_STORAGE_KEY_PREFIX = `${CACHE_KEY_PREFIX}:preferences:v2`;
const WNC_IMPACT_CACHE_TTL_MS = 1000 * 60 * 60 * 24;
const MANUAL_RELATIONSHIP_LIMIT = 200;
const RELATIONSHIP_MODE_OPTIONS = [
  { label: "新增上游 (Supplier -> Root)", value: "UPSTREAM" },
  { label: "新增下游 (Root -> Customer)", value: "DOWNSTREAM" },
  { label: "新增競爭 (Root -> Competitor)", value: "COMPETITOR" }
];
const SOURCE_TYPE_OPTIONS = [
  { label: "PUBLIC_INFO", value: "PUBLIC_INFO" },
  { label: "INFERRED", value: "INFERRED" }
];
const RELATIONSHIP_MODE_LABELS = Object.freeze({
  UPSTREAM: "上游",
  DOWNSTREAM: "下游",
  COMPETITOR: "競爭"
});
const DEFAULT_RELATION_TYPE_BY_MODE = Object.freeze({
  UPSTREAM: "Supplier",
  DOWNSTREAM: "Customer",
  COMPETITOR: "Direct Competitor"
});
const EMPTY_RELATIONSHIP_FORM = Object.freeze({
  mode: "UPSTREAM",
  relatedAccountId: null,
  relationType: "Supplier",
  role: "",
  products: "",
  evidence: "",
  confidence: 0.8,
  sourceType: "PUBLIC_INFO"
});

const CYTOSCAPE_STYLE = [
  {
    selector: "node",
    style: {
      "background-color": "#6b7280",
      label: "data(label)",
      color: "#e2e8f0",
      "font-size": 16,
      "font-weight": 600,
      "text-wrap": "wrap",
      "text-max-width": 216,
      "text-valign": "center",
      "text-halign": "center",
      "background-opacity": 1,
      width: 232,
      height: 122,
      shape: "round-rectangle",
      "border-width": 2,
      "border-color": "#475569",
      "text-outline-width": 0,
      "overlay-opacity": 0,
      "min-zoomed-font-size": 8
    }
  },
  {
    selector: "node.entity",
    style: {
      "background-color": "#e2e8f0",
      color: "#111827",
      "font-size": 18
    }
  },
  {
    selector: "node.root",
    style: {
      "background-color": "#fef3c7",
      "border-color": "#f59e0b",
      color: "#111827",
      width: 264,
      height: 136,
      "border-width": 2,
      "font-size": 22,
      "font-weight": 700
    }
  },
  {
    selector: "node.role-manufacturing",
    style: {
      "background-color": "#e0f2fe",
      "border-color": "#38bdf8"
    }
  },
  {
    selector: "node.role-channel",
    style: {
      "background-color": "#dcfce7",
      "border-color": "#22c55e"
    }
  },
  {
    selector: "node.role-customer",
    style: {
      "background-color": "#f3e8ff",
      "border-color": "#c026d3"
    }
  },
  {
    selector: "node.role-competitor",
    style: {
      "background-color": "#fee2e2",
      "border-color": "#ef4444"
    }
  },
  {
    selector: "node.lane",
    style: {
      "background-color": "#4b5563",
      "background-opacity": 0.7,
      "border-color": "#94a3b8",
      "border-width": 1,
      width: "data(width)",
      height: "data(height)",
      color: "#e2e8f0",
      "font-size": 24,
      "font-weight": 700,
      "text-max-width": 320,
      "text-valign": "top",
      "text-margin-y": -12,
      "z-index": -1,
      events: "yes",
      "min-zoomed-font-size": 14
    }
  },
  {
    selector: "node.lane-upstream",
    style: {
      "background-color": "#5b6168",
      "background-opacity": 0.78
    }
  },
  {
    selector: "node.lane-downstream",
    style: {
      "background-color": "#5f666d",
      "background-opacity": 0.8,
      "text-margin-y": 12
    }
  },
  {
    selector: "node.lane-competitor",
    style: {
      "background-color": "#624b4b",
      "background-opacity": 0.76,
      "text-margin-y": -8
    }
  },
  {
    selector: "node.lane-resize-handle",
    style: {
      width: LANE_RESIZE_HANDLE_SIZE,
      height: LANE_RESIZE_HANDLE_SIZE,
      shape: "ellipse",
      "background-color": "#60a5fa",
      "border-color": "#bfdbfe",
      "border-width": 1,
      "background-opacity": 0.45,
      "overlay-opacity": 0,
      "z-index": 12,
      label: ""
    }
  },
  {
    selector: "node.annotation",
    style: {
      width: "data(width)",
      height: "data(height)",
      "background-color": "#374151",
      "border-color": "#f59e0b",
      "border-width": 1.5,
      "border-style": "dashed",
      color: "#f8fafc",
      "font-size": 15,
      "font-weight": 600,
      "text-max-width": 260,
      "text-wrap": "wrap",
      "z-index": 3,
      events: "no"
    }
  },
  {
    selector: "edge",
    style: {
      width: 2,
      "curve-style": "bezier",
      "target-arrow-shape": "triangle",
      "arrow-scale": 0.9,
      "line-color": "#cbd5e1",
      "target-arrow-color": "#cbd5e1",
      "overlay-opacity": 0
    }
  },
  {
    selector: "edge.flow-main",
    style: {
      width: 2.2
    }
  },
  {
    selector: "edge.relation-supplier",
    style: {
      "line-color": "#7dd3fc",
      "target-arrow-color": "#7dd3fc"
    }
  },
  {
    selector: "edge.relation-distributor",
    style: {
      "line-color": "#34d399",
      "target-arrow-color": "#34d399"
    }
  },
  {
    selector: "edge.relation-competitor",
    style: {
      "line-color": "#fca5a5",
      "target-arrow-color": "#fca5a5",
      "target-arrow-shape": "none",
      "line-style": "dashed"
    }
  },
  {
    selector: "edge.flow-support",
    style: {
      width: 1.6,
      "line-style": "solid"
    }
  },
  {
    selector: "edge.flow-note",
    style: {
      width: 1.4,
      "line-style": "dashed",
      "line-color": "#e5e7eb",
      "target-arrow-color": "#e5e7eb",
      "target-arrow-shape": "none",
      "curve-style": "bezier"
    }
  },
  {
    selector: ".is-muted",
    style: {
      opacity: 0.16
    }
  },
  {
    selector: "node.entity.is-focus",
    style: {
      "border-width": 3,
      "border-color": "#f8fafc",
      "shadow-blur": 14,
      "shadow-color": "#f8fafc",
      "shadow-opacity": 0.35,
      "shadow-offset-x": 0,
      "shadow-offset-y": 0
    }
  },
  {
    selector: "node.edge-endpoint",
    style: {
      opacity: 1,
      "border-width": 3,
      "border-color": "#f8fafc",
      "shadow-blur": 16,
      "shadow-color": "#f8fafc",
      "shadow-opacity": 0.4,
      "shadow-offset-x": 0,
      "shadow-offset-y": 0
    }
  },
  {
    selector: "edge.is-focus",
    style: {
      width: 2.8,
      opacity: 1
    }
  }
];

export default class CmSupplyNetworkGraph extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  @api maxNodes = 15;
  @api displayMode = DISPLAY_MODES.STORY;
  @api autoPromptEnabled = false;
  @track selectedFilter = FILTER_VALUES.ALL;
  @track relationshipForm = { ...EMPTY_RELATIONSHIP_FORM };
  @track manualRelationships = [];

  graphResponse;
  isLoading = false;
  errorMessage;
  cytoscapeReady = false;
  isRefreshingInBackground = false;
  loadingStatusMessage = LOADING_STATUS_MESSAGE;
  generatedAtLabel;

  cy;
  scriptLoadingPromise;
  requestSequence = 0;
  tooltipCurrentNodeId;
  tooltipCurrentEdgeId;
  resizeObserver;
  lastNavigationAt = 0;
  lastNodeDragAt = 0;
  windowResizeHandler;
  windowScrollHandler;
  windowFocusHandler;
  windowKeydownHandler;
  fullscreenChangeHandler;
  visibilityChangeHandler;
  lastPanAt = 0;
  manualPositionsByNodeId = {};
  isManualLoading = false;
  isSavingRelationship = false;
  isDeactivatingRelationship = false;
  isAnalyzingWncImpact = false;
  isSmartBuilding = false;
  wncImpactSummary;
  wncImpactOverallAssessment;
  wncImpactRootAccount;
  wncImpactFocusCompany;
  wncImpactLevel;
  wncImpactKeyRisks = [];
  wncImpactPositiveSignals = [];
  wncImpactRecommendedActions = [];
  wncImpactGeneratedAtLabel;
  isWncImpactFromCache = false;
  manualManagerExpanded = false;
  wncImpactExpanded = false;
  isGraphFullscreen = false;
  isUsingNativeFullscreen = false;
  pendingViewportRefit = false;

  connectedCallback() {
    this.restoreUserPreferences();
    this.restoreCachedGraph();
    this.restoreCachedWncImpact();
    this.initializeViewportListeners();
    this.loadGraphData();
    if (this.manualManagerExpanded) {
      this.loadManualRelationships();
    }
  }

  renderedCallback() {
    this.ensureContainerObserver();
    if (!this.scriptLoadingPromise) {
      this.scriptLoadingPromise = loadScript(this, cytoscapeResource)
        .then(() => {
          this.cytoscapeReady = true;
          this.renderGraph();
        })
        .catch((error) => {
          this.errorMessage = this.formatError(error);
        });
    }

    if (this.pendingViewportRefit && this.cy) {
      this.pendingViewportRefit = false;
      this.scheduleViewportSync({ refit: true });
    }
  }

  disconnectedCallback() {
    this.exitNativeFullscreenIfNeeded();
    this.teardownViewportListeners();
    this.teardownContainerObserver();
    if (this.cy) {
      this.cy.destroy();
      this.cy = null;
    }
    this.setBodyScrollLock(false);
    this.hideNodeTooltip();
  }

  @api
  refreshGraph() {
    return this.loadGraphData();
  }

  handleRefreshClick() {
    this.relayoutCurrentGraph();
  }

  relayoutCurrentGraph() {
    if (!this.hasData) {
      return;
    }

    this.manualPositionsByNodeId = {};
    this.hideNodeTooltip();
    this.renderGraph();
    this.requestViewportRefit();
  }

  handleZoomIn() {
    this.adjustGraphZoom(1.18);
  }

  handleZoomOut() {
    this.adjustGraphZoom(1 / 1.18);
  }

  handleFitGraph() {
    this.scheduleViewportSync({ refit: true });
  }

  handleToggleManualManager() {
    this.manualManagerExpanded = !this.manualManagerExpanded;
    this.persistUserPreferences();
    if (
      this.manualManagerExpanded &&
      !this.isManualLoading &&
      this.manualRelationships.length === 0
    ) {
      this.loadManualRelationships();
    }
  }

  handleOpenManualManager() {
    const shouldLoadRelationships =
      !this.manualManagerExpanded &&
      !this.isManualLoading &&
      this.manualRelationships.length === 0;

    if (!this.manualManagerExpanded) {
      this.manualManagerExpanded = true;
      this.persistUserPreferences();
    }

    if (shouldLoadRelationships) {
      this.loadManualRelationships();
    }

    window.setTimeout(() => {
      const manualPanelElement = this.template.querySelector(".manual-panel");
      if (manualPanelElement) {
        manualPanelElement.scrollIntoView({
          behavior: "smooth",
          block: "start"
        });
      }
    }, 0);
  }

  handleToggleWncImpactExpanded() {
    this.wncImpactExpanded = !this.wncImpactExpanded;
    this.persistUserPreferences();
  }

  async handleToggleGraphFullscreen() {
    const graphShell = this.getGraphShellElement();
    if (!graphShell) {
      return;
    }

    const nativeFullscreenElement = this.getCurrentNativeFullscreenElement();
    const isCurrentlyNativeFullscreen = nativeFullscreenElement === graphShell;

    if (isCurrentlyNativeFullscreen) {
      await this.exitNativeFullscreen();
      return;
    }

    const enteredNativeFullscreen =
      await this.enterNativeFullscreen(graphShell);
    if (enteredNativeFullscreen) {
      this.isUsingNativeFullscreen = true;
      this.isGraphFullscreen = true;
      this.setBodyScrollLock(true);
      this.hideNodeTooltip();
      this.requestViewportRefit();
      return;
    }

    this.isUsingNativeFullscreen = false;
    this.isGraphFullscreen = !this.isGraphFullscreen;
    this.setBodyScrollLock(this.isGraphFullscreen);
    this.hideNodeTooltip();
    this.requestViewportRefit();
  }

  async handleAnalyzeWncImpact() {
    if (!this.recordId) {
      return;
    }

    this.isAnalyzingWncImpact = true;
    try {
      const response = await analyzeWncImpact({ rootAccountId: this.recordId });
      const summary =
        response?.summary ||
        response?.summaryForUi ||
        response?.overallAssessment;
      if (!summary) {
        throw new Error("分析已完成，但沒有可顯示的摘要。");
      }

      const impactPayload = {
        summary,
        overallAssessment: response?.overallAssessment || null,
        rootAccount: response?.rootAccount || null,
        focusCompany: response?.focusCompany || null,
        impactLevel: response?.impactLevel || "UNKNOWN",
        keyRisks: response?.keyRisks,
        positiveSignals: response?.positiveSignals,
        recommendedActions: response?.recommendedActions,
        generatedAt: response?.generatedAt || Date.now()
      };
      this.applyWncImpactPayload(impactPayload, false);
      this.persistCachedWncImpact(impactPayload);
      this.showToast("分析完成", "已完成供應鏈對 WNC 的影響分析。", "success");
    } catch (error) {
      this.showToast("分析失敗", this.formatError(error), "error");
    } finally {
      this.isAnalyzingWncImpact = false;
    }
  }

  async handleSmartBuild() {
    if (!this.recordId) {
      return;
    }

    this.isSmartBuilding = true;
    try {
      const response = await smartBuildRelationships({
        rootAccountId: this.recordId,
        maxNodes: this.effectiveMaxNodes
      });

      const graphResponse = response?.graph;
      if (graphResponse) {
        this.graphResponse = graphResponse;
        this.persistCachedGraph(graphResponse);
        this.generatedAtLabel = this.formatDateTime(graphResponse.generatedAt);
        this.errorMessage = undefined;
        this.renderGraph();
      } else {
        await this.loadGraphData();
      }

      await this.loadManualRelationships();

      const insertedCount = Number(response?.insertedCount || 0);
      const updatedCount = Number(response?.updatedCount || 0);
      const skippedCount = Number(response?.skippedCount || 0);
      this.showToast(
        "智能建立完成",
        `已建立 ${insertedCount} 筆，更新 ${updatedCount} 筆，略過 ${skippedCount} 筆。`,
        "success"
      );
    } catch (error) {
      this.showToast("智能建立失敗", this.formatError(error), "error");
    } finally {
      this.isSmartBuilding = false;
    }
  }

  normalizeImpactRiskItems(rawItems) {
    if (!Array.isArray(rawItems)) {
      return [];
    }
    return rawItems
      .map((rawItem) => {
        if (!rawItem || typeof rawItem !== "object") {
          return null;
        }
        const title =
          typeof rawItem.title === "string" ? rawItem.title.trim() : "";
        const impact =
          typeof rawItem.impact === "string" ? rawItem.impact.trim() : "";
        const reason =
          typeof rawItem.reason === "string" ? rawItem.reason.trim() : "";
        if (!title && !impact && !reason) {
          return null;
        }
        return { title, impact, reason };
      })
      .filter((item) => item !== null);
  }

  normalizeImpactTextItems(rawItems) {
    if (!Array.isArray(rawItems)) {
      return [];
    }
    return rawItems
      .map((rawItem) => (typeof rawItem === "string" ? rawItem.trim() : ""))
      .filter((item) => item.length > 0);
  }

  applyWncImpactPayload(rawPayload, fromCache) {
    if (!rawPayload || typeof rawPayload !== "object") {
      return;
    }

    this.wncImpactSummary = rawPayload.summary || null;
    this.wncImpactOverallAssessment = rawPayload.overallAssessment || null;
    this.wncImpactRootAccount = rawPayload.rootAccount || null;
    this.wncImpactFocusCompany = rawPayload.focusCompany || null;
    this.wncImpactLevel = rawPayload.impactLevel || "UNKNOWN";
    this.wncImpactKeyRisks = this.normalizeImpactRiskItems(rawPayload.keyRisks);
    this.wncImpactPositiveSignals = this.normalizeImpactTextItems(
      rawPayload.positiveSignals
    );
    this.wncImpactRecommendedActions = this.normalizeImpactTextItems(
      rawPayload.recommendedActions
    );
    this.wncImpactGeneratedAtLabel = this.formatDateTime(
      rawPayload.generatedAt
    );
    this.isWncImpactFromCache = fromCache === true;
  }

  async loadManualRelationships() {
    if (!this.recordId) {
      return;
    }

    this.isManualLoading = true;
    try {
      const rows = await getManualRelationships({
        rootAccountId: this.recordId,
        limitRows: MANUAL_RELATIONSHIP_LIMIT,
        maxNodes: this.effectiveMaxNodes
      });
      this.manualRelationships = (rows || []).map((row) =>
        this.decorateManualRelationship(row)
      );
    } catch (error) {
      this.showToast("關係清單載入失敗", this.formatError(error), "error");
    } finally {
      this.isManualLoading = false;
    }
  }

  decorateManualRelationship(row) {
    const normalizedMode = this.normalizeMode(row?.mode);
    return {
      ...row,
      mode: normalizedMode,
      modeLabel: RELATIONSHIP_MODE_LABELS[normalizedMode] || normalizedMode,
      sourceTypeLabel: row?.sourceType || "PUBLIC_INFO",
      statusLabel: row?.isActive ? "Active" : "Inactive",
      badgeClass: row?.isActive
        ? "status-badge is-active"
        : "status-badge is-inactive",
      updatedLabel: this.formatDateTime(row?.lastModifiedDate),
      relatedAccountName: row?.relatedAccountName || "(Unknown Account)",
      pathTypeLabel: row?.pathTypeLabel || (row?.pathType === "INDIRECT" ? "間接" : "直接")
    };
  }

  getManualRelationshipById(relationshipId) {
    return (
      this.manualRelationships.find((row) => row.id === relationshipId) || null
    );
  }

  updateManualRelationshipLocalStatus(relationshipId, isActive) {
    const nowIso = new Date().toISOString();
    this.manualRelationships = this.manualRelationships.map((row) => {
      if (row.id !== relationshipId) {
        return row;
      }
      return this.decorateManualRelationship({
        ...row,
        isActive,
        lastModifiedDate: nowIso
      });
    });
  }

  handleRelationshipModeChange(event) {
    const selectedMode = this.normalizeMode(event.detail?.value);
    const defaultRelationType = DEFAULT_RELATION_TYPE_BY_MODE[selectedMode];
    const nextRelationType =
      this.relationshipForm.relationType || defaultRelationType;
    this.relationshipForm = {
      ...this.relationshipForm,
      mode: selectedMode,
      relationType: nextRelationType
    };
  }

  handleRelatedAccountChange(event) {
    this.relationshipForm = {
      ...this.relationshipForm,
      relatedAccountId: event?.detail?.recordId || null
    };
  }

  handleRelationshipFieldChange(event) {
    const fieldName = event.target?.dataset?.field;
    if (!fieldName) {
      return;
    }

    let value = event?.detail?.value;
    if (fieldName === "confidence") {
      value =
        value === "" || value === null || value === undefined
          ? null
          : Number(value);
    }
    this.relationshipForm = {
      ...this.relationshipForm,
      [fieldName]: value
    };
  }

  handleResetRelationshipForm() {
    this.relationshipForm = {
      ...EMPTY_RELATIONSHIP_FORM
    };
  }

  async handleCreateRelationship() {
    if (!this.recordId) {
      return;
    }
    if (!this.relationshipForm.relatedAccountId) {
      this.showToast(
        "請選擇 Account",
        "建立關係前請先選擇對象 Account。",
        "error"
      );
      return;
    }
    if (this.relationshipForm.relatedAccountId === this.recordId) {
      this.showToast("資料錯誤", "無法建立自己到自己的關係。", "error");
      return;
    }

    this.isSavingRelationship = true;
    try {
      await createManualRelationship({
        rootAccountId: this.recordId,
        relatedAccountId: this.relationshipForm.relatedAccountId,
        mode: this.relationshipForm.mode,
        relationType: this.relationshipForm.relationType,
        role: this.relationshipForm.role,
        products: this.relationshipForm.products,
        evidence: this.relationshipForm.evidence,
        confidence: this.relationshipForm.confidence,
        sourceType: this.relationshipForm.sourceType
      });

      this.showToast("建立成功", "已建立手動供應鏈關係。", "success");
      this.handleResetRelationshipForm();
      await Promise.all([
        this.loadGraphData(),
        this.loadManualRelationships()
      ]);
    } catch (error) {
      this.showToast("建立失敗", this.formatError(error), "error");
    } finally {
      this.isSavingRelationship = false;
    }
  }

  async handleDeactivateRelationship(event) {
    const relationshipId = event.currentTarget?.dataset?.relationshipId;
    if (!relationshipId || !this.recordId) {
      return;
    }

    const targetRow = this.getManualRelationshipById(relationshipId);
    if (!targetRow) {
      return;
    }
    const originalStatus = targetRow.isActive;

    this.isDeactivatingRelationship = true;
    this.updateManualRelationshipLocalStatus(relationshipId, false);
    try {
      await deactivateManualRelationship({
        relationshipId,
        rootAccountId: this.recordId
      });

      this.showToast("已停用", "關係已停用，不會再顯示在圖上。", "success");
      this.loadGraphData();
      this.loadManualRelationships();
    } catch (error) {
      this.updateManualRelationshipLocalStatus(relationshipId, originalStatus);
      this.showToast("停用失敗", this.formatError(error), "error");
    } finally {
      this.isDeactivatingRelationship = false;
    }
  }

  async handleActivateRelationship(event) {
    const relationshipId = event.currentTarget?.dataset?.relationshipId;
    if (!relationshipId || !this.recordId) {
      return;
    }

    const targetRow = this.getManualRelationshipById(relationshipId);
    if (!targetRow) {
      return;
    }
    const originalStatus = targetRow.isActive;

    this.isDeactivatingRelationship = true;
    this.updateManualRelationshipLocalStatus(relationshipId, true);
    try {
      await activateManualRelationship({
        relationshipId,
        rootAccountId: this.recordId
      });

      this.showToast("已啟用", "關係已重新啟用並回到圖上。", "success");
      this.loadGraphData();
      this.loadManualRelationships();
    } catch (error) {
      this.updateManualRelationshipLocalStatus(relationshipId, originalStatus);
      this.showToast("啟用失敗", this.formatError(error), "error");
    } finally {
      this.isDeactivatingRelationship = false;
    }
  }

  handleManualRelatedAccountClick(event) {
    const accountId = event.currentTarget?.dataset?.accountId;
    if (!accountId) {
      return;
    }
    this.navigateToAccount(accountId);
  }

  async loadGraphData() {
    if (!this.recordId) {
      return;
    }
    const hasCachedGraph = this.hasData;

    this.isLoading = !hasCachedGraph;
    this.isRefreshingInBackground = hasCachedGraph;
    this.loadingStatusMessage = hasCachedGraph
      ? BACKGROUND_REFRESHING_STATUS_MESSAGE
      : LOADING_STATUS_MESSAGE;
    this.errorMessage = undefined;
    const requestId = ++this.requestSequence;

    try {
      const response = await getGraph({
        rootAccountId: this.recordId,
        maxNodes: this.effectiveMaxNodes
      });

      if (requestId !== this.requestSequence) {
        return;
      }

      this.graphResponse = response || {
        nodes: [],
        edges: [],
        nodeCount: 0,
        edgeCount: 0,
        truncated: false
      };
      this.persistCachedGraph(this.graphResponse);
      this.generatedAtLabel = this.formatDateTime(
        this.graphResponse.generatedAt
      );
      this.isRefreshingInBackground = false;
      this.renderGraph();
    } catch (error) {
      if (requestId !== this.requestSequence) {
        return;
      }
      this.errorMessage = this.formatError(error);

      if (!hasCachedGraph) {
        this.graphResponse = undefined;
        this.clearGraph();
      } else {
        this.errorMessage = `更新失敗，顯示上次結果。${this.errorMessage}`;
      }
    } finally {
      if (requestId === this.requestSequence) {
        this.isLoading = false;
        this.isRefreshingInBackground = false;
      }
    }
  }

  handleFilterChange(event) {
    this.selectedFilter = this.normalizeFilterValue(event.detail.value);
    this.persistUserPreferences();
    this.renderGraph();
  }

  renderGraph() {
    if (!this.cytoscapeReady) {
      return;
    }

    const container = this.template.querySelector('[data-id="graph"]');
    if (!container) {
      return;
    }

    const nodes = this.graphResponse?.nodes || [];
    const edges = this.graphResponse?.edges || [];

    if (!nodes.length) {
      this.clearGraph();
      return;
    }

    const computedPositionsByNode = computeNodePositions(
      nodes,
      this.isStoryMode ? STORY_HORIZONTAL_SPACING : NETWORK_HORIZONTAL_SPACING,
      this.isStoryMode ? STORY_VERTICAL_SPACING : NETWORK_VERTICAL_SPACING
    );
    const positionsByNode = this.mergeManualPositions(
      nodes,
      computedPositionsByNode
    );
    const filteredElements = this.isStoryMode
      ? buildStoryElements(nodes, edges, this.selectedFilter, positionsByNode)
      : buildFilteredElements(
          nodes,
          edges,
          this.selectedFilter,
          positionsByNode
        );
    const laneResizeHandleElements = this.buildLaneResizeHandleElements(
      filteredElements.nodes
    );
    const elements = [
      ...filteredElements.nodes,
      ...laneResizeHandleElements,
      ...filteredElements.edges
    ];

    if (!elements.length) {
      this.clearGraph();
      return;
    }

    if (this.cy) {
      this.cy.destroy();
    }

    this.cy = window.cytoscape({
      container,
      elements,
      style: CYTOSCAPE_STYLE,
      layout: {
        name: "preset"
      },
      wheelSensitivity: 0.15,
      pixelRatio: 1,
      panningEnabled: true,
      userPanningEnabled: true,
      zoomingEnabled: true,
      userZoomingEnabled: true,
      boxSelectionEnabled: false,
      autoungrabify: false
    });

    const navigateFromNode = (event) => {
      const tappedNode = event.target;
      if (tappedNode.data("isVirtual")) {
        return;
      }
      if (Date.now() - this.lastPanAt < PAN_NAVIGATION_GUARD_WINDOW_MS) {
        return;
      }
      if (Date.now() - this.lastNodeDragAt < DRAG_NAVIGATION_GUARD_WINDOW_MS) {
        return;
      }
      this.navigateToAccount(tappedNode.data("accountId"));
    };
    this.cy.on("tap", "node", navigateFromNode);
    this.cy.on("click", "node", navigateFromNode);

    this.cy.on("grab", "node.entity", (event) => {
      const grabbedNode = event.target;
      grabbedNode.scratch("dragStartPosition", { ...grabbedNode.position() });
      this.hideNodeTooltip();
    });

    this.cy.on("drag", "node.entity", (event) => {
      const draggedNode = event.target;
      this.clampEntityNodeToLane(draggedNode);
      this.hideNodeTooltip();
    });

    this.cy.on("free", "node.entity", (event) => {
      const draggedNode = event.target;
      const startPosition = draggedNode.scratch("dragStartPosition");
      draggedNode.removeScratch("dragStartPosition");
      this.clampEntityNodeToLane(draggedNode);
      if (!startPosition) {
        return;
      }

      const deltaX = draggedNode.position("x") - startPosition.x;
      const deltaY = draggedNode.position("y") - startPosition.y;
      if (Math.abs(deltaX) < 2 && Math.abs(deltaY) < 2) {
        return;
      }

      this.lastNodeDragAt = Date.now();
      this.captureNodePosition(draggedNode);
    });

    this.cy.on("grab", "node.lane", (event) => {
      const laneNode = event.target;
      const laneMembers = this.getLaneMembers(laneNode.id());
      if (!laneMembers.length) {
        return;
      }

      laneNode.scratch("dragState", {
        laneStartPosition: { ...laneNode.position() },
        memberStartPositions: laneMembers.map((memberNode) => ({
          id: memberNode.id(),
          position: { ...memberNode.position() }
        }))
      });
      this.hideNodeTooltip();
    });

    this.cy.on("drag", "node.lane", (event) => {
      const laneNode = event.target;
      const dragState = laneNode.scratch("dragState");
      if (!dragState || !Array.isArray(dragState.memberStartPositions)) {
        return;
      }

      const deltaX = laneNode.position("x") - dragState.laneStartPosition.x;
      const deltaY = laneNode.position("y") - dragState.laneStartPosition.y;
      dragState.memberStartPositions.forEach((memberState) => {
        const memberNode = this.cy.getElementById(memberState.id);
        if (!memberNode || memberNode.empty()) {
          return;
        }
        memberNode.position({
          x: memberState.position.x + deltaX,
          y: memberState.position.y + deltaY
        });
      });
      this.syncLaneResizeHandle(laneNode);
    });

    this.cy.on("free", "node.lane", (event) => {
      const laneNode = event.target;
      const dragState = laneNode.scratch("dragState");
      laneNode.removeScratch("dragState");
      if (!dragState || !dragState.laneStartPosition) {
        return;
      }

      const deltaX = laneNode.position("x") - dragState.laneStartPosition.x;
      const deltaY = laneNode.position("y") - dragState.laneStartPosition.y;
      if (Math.abs(deltaX) < 2 && Math.abs(deltaY) < 2) {
        return;
      }

      this.lastNodeDragAt = Date.now();
      this.getLaneMembers(laneNode.id()).forEach((memberNode) => {
        this.captureNodePosition(memberNode);
      });
      this.syncLaneResizeHandle(laneNode);
    });

    this.cy.on("grab", "node.lane-resize-handle", (event) => {
      const handleNode = event.target;
      const laneId = handleNode.data("laneId");
      if (!laneId) {
        return;
      }

      const laneNode = this.cy.getElementById(laneId);
      if (!laneNode || laneNode.empty()) {
        return;
      }

      const laneWidth = Number(laneNode.data("width"));
      const laneHeight = Number(laneNode.data("height"));
      if (!Number.isFinite(laneWidth) || !Number.isFinite(laneHeight)) {
        return;
      }

      handleNode.scratch("resizeState", {
        laneId,
        startHandleX: handleNode.position("x"),
        startHandleY: handleNode.position("y"),
        laneLeft: laneNode.position("x") - laneWidth / 2,
        laneTop: laneNode.position("y") - laneHeight / 2,
        startLaneWidth: laneWidth,
        startLaneHeight: laneHeight,
        moved: false
      });
      this.hideNodeTooltip();
    });

    this.cy.on("drag", "node.lane-resize-handle", (event) => {
      const moved = this.resizeLaneFromHandle(event.target);
      if (moved) {
        this.hideNodeTooltip();
      }
    });

    this.cy.on("free", "node.lane-resize-handle", (event) => {
      const handleNode = event.target;
      const resizeState = handleNode.scratch("resizeState");
      const moved = this.resizeLaneFromHandle(handleNode);
      handleNode.removeScratch("resizeState");
      if (!resizeState || !resizeState.laneId) {
        return;
      }

      const laneNode = this.cy.getElementById(resizeState.laneId);
      if (laneNode && !laneNode.empty()) {
        this.syncLaneResizeHandle(laneNode);
      }
      if (!moved) {
        return;
      }

      this.lastNodeDragAt = Date.now();
      if (laneNode && !laneNode.empty()) {
        this.getLaneMembers(laneNode.id()).forEach((memberNode) => {
          this.captureNodePosition(memberNode);
        });
      }
    });

    this.cy.on("mouseover", "node.entity", (event) => {
      this.applyFocusState(event.target);
      this.showNodeTooltip(event);
    });

    this.cy.on("mousemove", "node.entity", (event) => {
      this.moveTooltip(event);
    });

    this.cy.on("mouseout", "node.entity", () => {
      this.clearFocusState();
      this.hideNodeTooltip();
    });

    this.cy.on("mouseover", "edge", (event) => {
      const hoveredEdge = event.target;
      if (!hoveredEdge || hoveredEdge.data("isVirtual")) {
        return;
      }
      this.applyEdgeFocusState(hoveredEdge);
      this.showEdgeTooltip(event);
    });

    this.cy.on("mousemove", "edge", (event) => {
      this.moveTooltip(event);
    });

    this.cy.on("mouseout", "edge", () => {
      this.clearFocusState();
      this.hideNodeTooltip();
    });

    this.cy.on("tap", () => {
      this.hideNodeTooltip();
    });

    this.cy.on("pan", () => {
      this.lastPanAt = Date.now();
    });

    this.cy.on("pan zoom", () => {
      this.hideNodeTooltip();
    });

    this.cy.nodes("node.entity").forEach((entityNode) => {
      this.clampEntityNodeToLane(entityNode);
    });
    this.syncAllLaneResizeHandles();

    this.scheduleViewportSync({ refit: true });
  }

  clearGraph() {
    if (this.cy) {
      this.cy.destroy();
      this.cy = null;
    }
    this.hideNodeTooltip();
  }

  applyFocusState(node) {
    if (!this.cy || !node || typeof node.data !== "function") {
      return;
    }
    if (node.data("isVirtual")) {
      this.clearFocusState();
      return;
    }

    this.clearFocusState();

    const focusElements = node
      .closedNeighborhood()
      .union(node.predecessors())
      .union(node.successors());
    const mutedElements = this.cy.elements().difference(focusElements);

    mutedElements.addClass("is-muted");
    focusElements.addClass("is-focus");
  }

  applyEdgeFocusState(edge) {
    if (!this.cy || !edge || typeof edge.data !== "function") {
      return;
    }
    if (edge.data("isVirtual")) {
      this.clearFocusState();
      return;
    }

    this.clearFocusState();

    const sourceNode = edge.source();
    const targetNode = edge.target();
    let focusElements = edge.collection();
    if (sourceNode && !sourceNode.empty()) {
      focusElements = focusElements.union(sourceNode);
    }
    if (targetNode && !targetNode.empty()) {
      focusElements = focusElements.union(targetNode);
    }
    const mutedElements = this.cy.elements().difference(focusElements);

    mutedElements.addClass("is-muted");
    focusElements.addClass("is-focus");
    if (sourceNode && !sourceNode.empty()) {
      sourceNode.removeClass("is-muted");
      sourceNode.addClass("edge-endpoint");
    }
    if (targetNode && !targetNode.empty()) {
      targetNode.removeClass("is-muted");
      targetNode.addClass("edge-endpoint");
    }
  }

  clearFocusState() {
    if (!this.cy) {
      return;
    }
    this.cy.elements().removeClass("is-muted");
    this.cy.elements().removeClass("is-focus");
    this.cy.elements().removeClass("edge-endpoint");
  }

  showNodeTooltip(event) {
    const targetNode = event?.target;
    if (!targetNode || targetNode.data("isVirtual")) {
      this.hideNodeTooltip();
      return;
    }

    const tooltipElement = this.template.querySelector(
      '[data-id="node-tooltip"]'
    );
    if (!tooltipElement) {
      return;
    }

    this.tooltipCurrentNodeId = targetNode.id();
    this.tooltipCurrentEdgeId = undefined;
    this.updateTooltipText({
      title: targetNode.data("label") || "",
      metaLabel: "Role",
      metaValue: targetNode.data("roleLabel") || "未分類",
      note: targetNode.data("noteText") || ""
    });
    tooltipElement.classList.add("is-visible");
    this.positionTooltip(event);
  }

  showEdgeTooltip(event) {
    const targetEdge = event?.target;
    if (!targetEdge || targetEdge.data("isVirtual")) {
      this.hideNodeTooltip();
      return;
    }

    const tooltipElement = this.template.querySelector(
      '[data-id="node-tooltip"]'
    );
    if (!tooltipElement) {
      return;
    }

    const sourceNode = targetEdge.source();
    const targetNode = targetEdge.target();
    const sourceLabel =
      sourceNode?.data("label") || targetEdge.data("source") || "Source";
    const targetLabel =
      targetNode?.data("label") || targetEdge.data("target") || "Target";
    const relationType = targetEdge.data("relationType") || "Related";
    const edgeCategory = targetEdge.data("edgeCategory") || "";
    const marketRiskNote = targetEdge.data("marketRiskNote") || "";
    const direction = this.getEdgeDirectionLabel(
      targetEdge.data("relationshipDirection"),
      relationType,
      edgeCategory
    );
    const noteSegments = [`方向：${direction}`];
    if (marketRiskNote) {
      noteSegments.push(`市場風險：${marketRiskNote}`);
    }

    this.tooltipCurrentNodeId = undefined;
    this.tooltipCurrentEdgeId = targetEdge.id();
    this.updateTooltipText({
      title: `${sourceLabel} -> ${targetLabel}`,
      metaLabel: "Relation",
      metaValue: relationType,
      note: noteSegments.join(" | ")
    });
    tooltipElement.classList.add("is-visible");
    this.positionTooltip(event);
  }

  moveTooltip(event) {
    if (!this.tooltipCurrentNodeId && !this.tooltipCurrentEdgeId) {
      return;
    }
    this.positionTooltip(event);
  }

  hideNodeTooltip() {
    const tooltipElement = this.template.querySelector(
      '[data-id="node-tooltip"]'
    );
    if (tooltipElement) {
      tooltipElement.classList.remove("is-visible");
      tooltipElement.style.left = "-10000px";
      tooltipElement.style.top = "-10000px";
    }
    this.tooltipCurrentNodeId = undefined;
    this.tooltipCurrentEdgeId = undefined;
  }

  updateTooltipText(tooltipPayload) {
    const titleElement = this.template.querySelector(
      '[data-id="tooltip-title"]'
    );
    const metaLabelElement = this.template.querySelector(
      '[data-id="tooltip-meta-label"]'
    );
    const roleElement = this.template.querySelector('[data-id="tooltip-role"]');
    const noteElement = this.template.querySelector('[data-id="tooltip-note"]');

    if (titleElement) {
      titleElement.textContent = tooltipPayload?.title || "";
    }
    if (metaLabelElement) {
      metaLabelElement.textContent = tooltipPayload?.metaLabel || "Role";
    }
    if (roleElement) {
      roleElement.textContent = tooltipPayload?.metaValue || "";
    }
    if (noteElement) {
      noteElement.textContent = tooltipPayload?.note || "";
    }
  }

  getEdgeDirectionLabel(direction, relationType, edgeCategory) {
    const normalizedCategory = String(edgeCategory || "").toUpperCase();
    if (normalizedCategory === "INDIRECT_PATH") {
      return "間接供應鏈路徑";
    }
    if (normalizedCategory === "UPSTREAM") {
      return "上游供應";
    }
    if (normalizedCategory === "DOWNSTREAM") {
      return "下游客戶";
    }
    if (normalizedCategory === "COMPETITOR") {
      return "同業競爭";
    }

    const normalizedDirection = String(direction || "").toUpperCase();
    if (normalizedDirection === "UPSTREAM") {
      return "上游供應";
    }
    if (normalizedDirection === "DOWNSTREAM") {
      return "下游客戶";
    }
    if (normalizedDirection === "COMPETITOR") {
      return "同業競爭";
    }
    if (normalizedDirection === "INDIRECT_PATH") {
      return "間接供應鏈路徑";
    }

    const normalizedRelationType = String(relationType || "").toLowerCase();
    if (normalizedRelationType.includes("competitor")) {
      return "同業競爭";
    }
    if (
      normalizedRelationType.includes("supplier") ||
      normalizedRelationType.includes("foundry") ||
      normalizedRelationType.includes("manufacturer") ||
      normalizedRelationType.includes("osat")
    ) {
      return "上游供應";
    }
    if (
      normalizedRelationType.includes("customer") ||
      normalizedRelationType.includes("odm") ||
      normalizedRelationType.includes("oem") ||
      normalizedRelationType.includes("channel")
    ) {
      return "下游客戶";
    }
    return "關聯";
  }

  positionTooltip(event) {
    const tooltipElement = this.template.querySelector(
      '[data-id="node-tooltip"]'
    );
    if (!tooltipElement) {
      return;
    }

    const originalEvent = event?.originalEvent;
    if (
      !originalEvent ||
      !Number.isFinite(originalEvent.clientX) ||
      !Number.isFinite(originalEvent.clientY)
    ) {
      return;
    }

    const tooltipRect = tooltipElement.getBoundingClientRect();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;

    let left = originalEvent.clientX + TOOLTIP_OFFSET_X;
    let top = originalEvent.clientY + TOOLTIP_OFFSET_Y;

    if (left + tooltipRect.width > viewportWidth - 12) {
      left = Math.max(
        12,
        originalEvent.clientX - tooltipRect.width - TOOLTIP_OFFSET_X
      );
    }
    if (top + tooltipRect.height > viewportHeight - 12) {
      top = Math.max(
        12,
        originalEvent.clientY - tooltipRect.height - TOOLTIP_OFFSET_Y
      );
    }

    tooltipElement.style.left = `${Math.round(left)}px`;
    tooltipElement.style.top = `${Math.round(top)}px`;
  }

  navigateToAccount(accountId) {
    if (!accountId) {
      return;
    }
    const now = Date.now();
    if (now - this.lastNavigationAt < NAVIGATION_GUARD_WINDOW_MS) {
      return;
    }
    this.lastNavigationAt = now;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: accountId,
        objectApiName: "Account",
        actionName: "view"
      }
    });
  }

  formatError(error) {
    const errorBody = error?.body;
    if (Array.isArray(errorBody) && errorBody.length > 0) {
      return errorBody.map((item) => item.message).join(", ");
    }
    if (typeof errorBody?.message === "string") {
      return errorBody.message;
    }
    if (typeof error?.message === "string") {
      return error.message;
    }
    return "無法載入上下游關係圖。";
  }

  restoreCachedGraph(options = {}) {
    if (!this.recordId) {
      return;
    }
    const clearWhenMissing = options?.clearWhenMissing === true;

    try {
      const rawCache = window.sessionStorage.getItem(this.graphCacheKey);
      if (!rawCache) {
        if (clearWhenMissing) {
          this.graphResponse = undefined;
          this.generatedAtLabel = undefined;
        }
        return;
      }

      const cachedPayload = JSON.parse(rawCache);
      if (
        !cachedPayload ||
        !cachedPayload.graphResponse ||
        !Array.isArray(cachedPayload.graphResponse.nodes)
      ) {
        if (clearWhenMissing) {
          this.graphResponse = undefined;
          this.generatedAtLabel = undefined;
        }
        return;
      }

      this.graphResponse = cachedPayload.graphResponse;
      this.generatedAtLabel = this.formatDateTime(cachedPayload.savedAt);
    } catch {
      // Cache read failure should never block graph rendering.
    }
  }

  persistCachedGraph(graphResponse) {
    if (!this.recordId || !graphResponse) {
      return;
    }

    try {
      const cachePayload = {
        savedAt: Date.now(),
        graphResponse
      };
      window.sessionStorage.setItem(
        this.graphCacheKey,
        JSON.stringify(cachePayload)
      );
    } catch {
      // Cache write failure is non-blocking.
    }
  }

  restoreCachedWncImpact() {
    if (!this.recordId) {
      return;
    }

    try {
      const rawCache = window.localStorage.getItem(this.wncImpactCacheKey);
      if (!rawCache) {
        return;
      }

      const cachedPayload = JSON.parse(rawCache);
      if (!cachedPayload || typeof cachedPayload !== "object") {
        return;
      }

      const savedAt = Number(cachedPayload.savedAt);
      if (
        !Number.isFinite(savedAt) ||
        Date.now() - savedAt > WNC_IMPACT_CACHE_TTL_MS
      ) {
        window.localStorage.removeItem(this.wncImpactCacheKey);
        return;
      }

      this.applyWncImpactPayload(cachedPayload.payload, true);
    } catch {
      // Cache read failure should not block component rendering.
    }
  }

  persistCachedWncImpact(payload) {
    if (!this.recordId || !payload) {
      return;
    }

    try {
      window.localStorage.setItem(
        this.wncImpactCacheKey,
        JSON.stringify({
          savedAt: Date.now(),
          payload
        })
      );
    } catch {
      // Cache write failure is non-blocking.
    }
  }

  formatDateTime(rawValue) {
    if (!rawValue) {
      return undefined;
    }

    const dateValue = new Date(rawValue);
    if (Number.isNaN(dateValue.getTime())) {
      return undefined;
    }
    return dateValue.toLocaleString();
  }

  get effectiveMaxNodes() {
    const configuredValue = Number(this.maxNodes);
    if (Number.isFinite(configuredValue) && configuredValue > 0) {
      return configuredValue;
    }
    return 15;
  }

  get hasData() {
    return (this.graphResponse?.nodes?.length || 0) > 0;
  }

  get showEmptyState() {
    return !this.isLoading && !this.errorMessage && !this.hasData;
  }

  get isBusy() {
    return this.isLoading || this.isRefreshingInBackground || this.isSmartBuilding;
  }

  get filterOptions() {
    return FILTER_OPTIONS;
  }

  get coverageNote() {
    return this.graphResponse?.coverageNote;
  }

  get graphCacheKey() {
    return `${CACHE_KEY_PREFIX}:${this.recordId}:${this.normalizedDisplayMode}`;
  }

  get wncImpactCacheKey() {
    return `${CACHE_KEY_PREFIX}:${this.recordId}:wncImpact:v1`;
  }

  get isStoryMode() {
    return this.normalizedDisplayMode === DISPLAY_MODES.STORY;
  }

  get normalizedDisplayMode() {
    return this.displayMode === DISPLAY_MODES.NETWORK
      ? DISPLAY_MODES.NETWORK
      : DISPLAY_MODES.STORY;
  }

  get isTruncated() {
    return this.graphResponse?.truncated === true;
  }

  get nodeCount() {
    return this.graphResponse?.nodeCount || 0;
  }

  get refreshGraphButtonTooltip() {
    return "重新整理目前關係圖版面並置中。";
  }

  get analyzeWncImpactButtonTooltip() {
    if (this.showWncImpactAnalysis || this.isWncImpactFromCache) {
      return "目前顯示上次分析結果。按供應鏈分析可重新分析。";
    }
    return "執行供應鏈對 WNC 的影響分析。";
  }

  get showManualRelationshipManager() {
    return this.manualManagerExpanded;
  }

  get manualManagerActionLabel() {
    return this.manualManagerExpanded ? "Hide Manager" : "Show Manager";
  }

  get graphFullscreenActionLabel() {
    return this.isGraphFullscreen ? "Exit Fullscreen" : "Fullscreen";
  }

  get graphShellClass() {
    return this.isGraphFullscreen ? "graph-shell is-fullscreen" : "graph-shell";
  }

  get showGraphStatusOverlay() {
    return this.graphStatusMessages.length > 0;
  }

  get graphStatusMessages() {
    const statusRows = [];
    if (this.showLoadingStatusMessage || this.showBackgroundStatusMessage) {
      statusRows.push({
        key: "graph-status",
        className: "graph-status-banner is-loading",
        text: this.loadingStatusMessage,
        isLoading: true
      });
    }
    if (this.isAnalyzingWncImpact) {
      statusRows.push({
        key: "impact-status",
        className: "graph-status-banner is-loading",
        text: this.wncImpactStatusMessage,
        isLoading: true
      });
    }
    if (this.isSmartBuilding) {
      statusRows.push({
        key: "smart-build-status",
        className: "graph-status-banner is-loading",
        text: this.smartBuildStatusMessage,
        isLoading: true
      });
    }
    return statusRows;
  }

  get showGraphSpinner() {
    return this.isLoading && !this.hasData;
  }

  get relationshipModeOptions() {
    return RELATIONSHIP_MODE_OPTIONS;
  }

  get sourceTypeOptions() {
    return SOURCE_TYPE_OPTIONS;
  }

  get relationshipFormMode() {
    return this.relationshipForm.mode;
  }

  get relationshipFormRelatedAccountId() {
    return this.relationshipForm.relatedAccountId;
  }

  get relationshipFormRelationType() {
    return this.relationshipForm.relationType;
  }

  get relationshipFormRole() {
    return this.relationshipForm.role;
  }

  get relationshipFormProducts() {
    return this.relationshipForm.products;
  }

  get relationshipFormEvidence() {
    return this.relationshipForm.evidence;
  }

  get relationshipFormSourceType() {
    return this.relationshipForm.sourceType;
  }

  get manualRelationshipsEmpty() {
    return !this.isManualLoading && this.manualRelationships.length === 0;
  }

  get disableRelationshipCreate() {
    return (
      this.isSavingRelationship ||
      this.isLoading ||
      this.isRefreshingInBackground ||
      !this.relationshipForm.relatedAccountId
    );
  }

  get disableRelationshipActions() {
    return (
      this.isSavingRelationship ||
      this.isDeactivatingRelationship ||
      this.isLoading ||
      this.isRefreshingInBackground
    );
  }

  get disableImpactAnalysisAction() {
    return (
      this.isAnalyzingWncImpact ||
      this.isSmartBuilding ||
      this.isLoading ||
      this.isRefreshingInBackground ||
      !this.recordId
    );
  }

  get disableSmartBuildAction() {
    return (
      this.isSmartBuilding ||
      this.isLoading ||
      this.isRefreshingInBackground ||
      !this.recordId
    );
  }

  get showBackgroundStatusMessage() {
    return this.isRefreshingInBackground;
  }

  get showLoadingStatusMessage() {
    return this.isLoading;
  }

  get wncImpactStatusMessage() {
    return WNC_IMPACT_LOADING_STATUS_MESSAGE;
  }

  get smartBuildStatusMessage() {
    return SMART_BUILD_LOADING_STATUS_MESSAGE;
  }

  get wncImpactToggleLabel() {
    return this.wncImpactExpanded ? "收合分析" : "展開分析";
  }

  get showWncImpactAnalysis() {
    return (
      !this.isAnalyzingWncImpact &&
      (this.hasWncImpactSummary ||
        this.hasWncImpactOverallAssessment ||
        this.hasWncImpactRisks ||
        this.hasWncImpactPositiveSignals ||
        this.hasWncImpactRecommendedActions)
    );
  }

  get showWncImpactCachedHint() {
    return this.showWncImpactAnalysis && this.isWncImpactFromCache;
  }

  get wncImpactLevelLabel() {
    return this.wncImpactLevel ? this.wncImpactLevel.toUpperCase() : "UNKNOWN";
  }

  get hasWncImpactSummary() {
    return !!this.wncImpactSummary;
  }

  get wncImpactSummaryPreview() {
    if (!this.hasWncImpactSummary) {
      return "";
    }
    if (this.wncImpactExpanded) {
      return this.wncImpactSummary;
    }
    return this.truncateText(this.wncImpactSummary, 220);
  }

  get showWncImpactSummaryFull() {
    return false;
  }

  get showExpandedWncImpactDetails() {
    return this.wncImpactExpanded;
  }

  get hasWncImpactOverallAssessment() {
    return !!this.wncImpactOverallAssessment;
  }

  get hasWncImpactRisks() {
    return this.wncImpactKeyRisks.length > 0;
  }

  get hasWncImpactPositiveSignals() {
    return this.wncImpactPositiveSignals.length > 0;
  }

  get hasWncImpactRecommendedActions() {
    return this.wncImpactRecommendedActions.length > 0;
  }

  get hasWncImpactContext() {
    return !!this.wncImpactRootAccount || !!this.wncImpactFocusCompany;
  }

  get wncImpactContextLabel() {
    const rootName = this.wncImpactRootAccount;
    const focusName = this.wncImpactFocusCompany;
    if (rootName && focusName) {
      return `${rootName} -> ${focusName}`;
    }
    return rootName || focusName || "";
  }

  get wncImpactRiskRows() {
    return this.wncImpactKeyRisks.map((risk, index) => ({
      key: `risk-${index}`,
      title: risk.title,
      impact: risk.impact,
      reason: risk.reason
    }));
  }

  get wncImpactPositiveSignalRows() {
    return this.wncImpactPositiveSignals.map((text, index) => ({
      key: `signal-${index}`,
      text
    }));
  }

  get wncImpactRecommendedActionRows() {
    return this.wncImpactRecommendedActions.map((text, index) => ({
      key: `action-${index}`,
      text
    }));
  }

  initializeViewportListeners() {
    if (this.windowResizeHandler) {
      return;
    }

    this.windowResizeHandler = () => {
      this.scheduleViewportSync();
    };
    this.windowScrollHandler = () => {
      this.scheduleViewportSync();
    };
    this.windowFocusHandler = () => {
      this.scheduleViewportSync();
    };
    this.windowKeydownHandler = (event) => {
      if (
        !this.isGraphFullscreen ||
        this.isUsingNativeFullscreen ||
        event?.key !== "Escape"
      ) {
        return;
      }
      event.preventDefault();
      this.handleToggleGraphFullscreen();
    };
    this.fullscreenChangeHandler = () => {
      const graphShell = this.getGraphShellElement();
      const nativeFullscreenElement = this.getCurrentNativeFullscreenElement();
      const isGraphInNativeFullscreen =
        !!graphShell && nativeFullscreenElement === graphShell;

      if (!this.isUsingNativeFullscreen && !isGraphInNativeFullscreen) {
        return;
      }

      this.isGraphFullscreen = isGraphInNativeFullscreen;
      if (!isGraphInNativeFullscreen) {
        this.isUsingNativeFullscreen = false;
        this.setBodyScrollLock(false);
      }
      this.hideNodeTooltip();
      this.requestViewportRefit();
    };
    this.visibilityChangeHandler = () => {
      if (document.hidden) {
        return;
      }
      this.scheduleViewportSync();
    };

    window.addEventListener("resize", this.windowResizeHandler);
    window.addEventListener("scroll", this.windowScrollHandler, true);
    window.addEventListener("focus", this.windowFocusHandler);
    window.addEventListener("keydown", this.windowKeydownHandler);
    document.addEventListener("fullscreenchange", this.fullscreenChangeHandler);
    document.addEventListener(
      "webkitfullscreenchange",
      this.fullscreenChangeHandler
    );
    document.addEventListener("visibilitychange", this.visibilityChangeHandler);
  }

  teardownViewportListeners() {
    if (this.windowResizeHandler) {
      window.removeEventListener("resize", this.windowResizeHandler);
      this.windowResizeHandler = undefined;
    }
    if (this.windowFocusHandler) {
      window.removeEventListener("focus", this.windowFocusHandler);
      this.windowFocusHandler = undefined;
    }
    if (this.windowKeydownHandler) {
      window.removeEventListener("keydown", this.windowKeydownHandler);
      this.windowKeydownHandler = undefined;
    }
    if (this.fullscreenChangeHandler) {
      document.removeEventListener(
        "fullscreenchange",
        this.fullscreenChangeHandler
      );
      document.removeEventListener(
        "webkitfullscreenchange",
        this.fullscreenChangeHandler
      );
      this.fullscreenChangeHandler = undefined;
    }
    if (this.windowScrollHandler) {
      window.removeEventListener("scroll", this.windowScrollHandler, true);
      this.windowScrollHandler = undefined;
    }
    if (this.visibilityChangeHandler) {
      document.removeEventListener(
        "visibilitychange",
        this.visibilityChangeHandler
      );
      this.visibilityChangeHandler = undefined;
    }
  }

  ensureContainerObserver() {
    if (this.resizeObserver || typeof window.ResizeObserver !== "function") {
      return;
    }

    const container = this.template.querySelector('[data-id="graph"]');
    if (!container) {
      return;
    }

    this.resizeObserver = new window.ResizeObserver(() => {
      this.scheduleViewportSync();
    });
    this.resizeObserver.observe(container);
  }

  teardownContainerObserver() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = undefined;
    }
  }

  scheduleViewportSync(options = {}) {
    if (!this.cy) {
      return;
    }

    const shouldRefit = options.refit === true;
    this.syncViewport(shouldRefit);
  }

  requestViewportRefit() {
    this.pendingViewportRefit = true;
    this.scheduleViewportSync({ refit: true });
  }

  adjustGraphZoom(multiplier) {
    if (!this.cy || !Number.isFinite(multiplier) || multiplier <= 0) {
      return;
    }

    const currentZoom = this.cy.zoom();
    const minZoom = Number.isFinite(this.cy.minZoom())
      ? this.cy.minZoom()
      : 0.1;
    const maxZoom = Number.isFinite(this.cy.maxZoom()) ? this.cy.maxZoom() : 4;
    const nextZoom = Math.min(
      maxZoom,
      Math.max(minZoom, currentZoom * multiplier)
    );

    const graphContainer = this.template.querySelector('[data-id="graph"]');
    const renderedPosition = graphContainer
      ? {
          x: graphContainer.clientWidth / 2,
          y: graphContainer.clientHeight / 2
        }
      : undefined;

    this.cy.zoom({
      level: nextZoom,
      renderedPosition
    });
  }

  syncViewport(shouldRefit = false) {
    if (!this.cy) {
      return;
    }

    try {
      this.cy.resize();
      if (shouldRefit) {
        const nonVirtualElements = this.cy.elements('[isVirtual = false]');
        if (nonVirtualElements && nonVirtualElements.length > 0) {
          this.cy.fit(nonVirtualElements, GRAPH_FIT_PADDING);
        } else {
          this.cy.fit(undefined, GRAPH_FIT_PADDING);
        }
      }
    } catch {
      // Best-effort refresh; ignore transient rendering failures.
    }
  }

  buildLaneResizeHandleElements(nodes) {
    if (!Array.isArray(nodes) || !nodes.length) {
      return [];
    }

    return nodes
      .filter((nodeElement) => {
        const laneId = nodeElement?.data?.id;
        const classNames = String(nodeElement?.classes || "");
        return (
          typeof laneId === "string" &&
          laneId.startsWith("lane-") &&
          classNames.split(/\s+/).includes("lane")
        );
      })
      .map((laneElement) => {
        const laneId = laneElement?.data?.id;
        const laneWidth = Number(laneElement?.data?.width);
        const laneHeight = Number(laneElement?.data?.height);
        const laneCenterX = Number(laneElement?.position?.x);
        const laneCenterY = Number(laneElement?.position?.y);
        if (
          !laneId ||
          !Number.isFinite(laneWidth) ||
          !Number.isFinite(laneHeight) ||
          !Number.isFinite(laneCenterX) ||
          !Number.isFinite(laneCenterY)
        ) {
          return null;
        }

        return {
          data: {
            id: this.getLaneResizeHandleId(laneId),
            laneId,
            isVirtual: true
          },
          position: {
            x: laneCenterX + laneWidth / 2 - LANE_RESIZE_HANDLE_INSET,
            y: laneCenterY + laneHeight / 2 - LANE_RESIZE_HANDLE_INSET
          },
          classes: "lane-resize-handle"
        };
      })
      .filter((element) => element !== null);
  }

  getLaneResizeHandleId(laneId) {
    if (!laneId) {
      return null;
    }
    return `lane-resize-handle-${laneId}`;
  }

  syncAllLaneResizeHandles() {
    if (!this.cy) {
      return;
    }
    this.cy.nodes("node.lane").forEach((laneNode) => {
      this.syncLaneResizeHandle(laneNode);
    });
  }

  syncLaneResizeHandle(laneNode) {
    if (!this.cy || !laneNode || laneNode.empty()) {
      return;
    }

    const handleId = this.getLaneResizeHandleId(laneNode.id());
    if (!handleId) {
      return;
    }

    const handleNode = this.cy.getElementById(handleId);
    if (!handleNode || handleNode.empty()) {
      return;
    }

    const laneWidth = Number(laneNode.data("width"));
    const laneHeight = Number(laneNode.data("height"));
    if (!Number.isFinite(laneWidth) || !Number.isFinite(laneHeight)) {
      return;
    }

    handleNode.position({
      x: laneNode.position("x") + laneWidth / 2 - LANE_RESIZE_HANDLE_INSET,
      y: laneNode.position("y") + laneHeight / 2 - LANE_RESIZE_HANDLE_INSET
    });
  }

  resizeLaneFromHandle(handleNode) {
    if (!this.cy || !handleNode || handleNode.empty()) {
      return false;
    }

    const resizeState = handleNode.scratch("resizeState");
    if (!resizeState || !resizeState.laneId) {
      return false;
    }

    const laneNode = this.cy.getElementById(resizeState.laneId);
    if (!laneNode || laneNode.empty()) {
      return false;
    }

    const deltaX = handleNode.position("x") - resizeState.startHandleX;
    const deltaY = handleNode.position("y") - resizeState.startHandleY;
    const requestedWidth = resizeState.startLaneWidth + deltaX;
    const requestedHeight = resizeState.startLaneHeight + deltaY;

    const layoutResult = this.reflowLaneMembers(
      laneNode,
      resizeState.laneLeft,
      resizeState.laneTop,
      requestedWidth,
      requestedHeight
    );
    if (!layoutResult) {
      return false;
    }

    const hasMoved =
      Math.abs(layoutResult.width - resizeState.startLaneWidth) > 0.5 ||
      Math.abs(layoutResult.height - resizeState.startLaneHeight) > 0.5;
    resizeState.moved = resizeState.moved || hasMoved;
    return resizeState.moved === true;
  }

  reflowLaneMembers(laneNode, laneLeft, laneTop, requestedWidth, requestedHeight) {
    if (!laneNode || laneNode.empty()) {
      return null;
    }

    const members = this.getLaneMembers(laneNode.id());
    if (!members.length) {
      return null;
    }

    const currentWidth = Number(laneNode.data("width"));
    const currentHeight = Number(laneNode.data("height"));
    if (!Number.isFinite(currentWidth) || !Number.isFinite(currentHeight)) {
      return null;
    }

    const anchorLeft = Number.isFinite(laneLeft)
      ? laneLeft
      : laneNode.position("x") - currentWidth / 2;
    const anchorTop = Number.isFinite(laneTop)
      ? laneTop
      : laneNode.position("y") - currentHeight / 2;

    const orderedMembers = [...members].sort((nodeA, nodeB) => {
      const deltaY = nodeA.position("y") - nodeB.position("y");
      if (Math.abs(deltaY) > 2) {
        return deltaY;
      }
      return nodeA.position("x") - nodeB.position("x");
    });

    const maxNodeWidth = orderedMembers.reduce(
      (maxWidth, memberNode) => Math.max(maxWidth, Number(memberNode.width()) || 0),
      0
    );
    const maxNodeHeight = orderedMembers.reduce(
      (maxHeight, memberNode) =>
        Math.max(maxHeight, Number(memberNode.height()) || 0),
      0
    );
    if (maxNodeWidth <= 0 || maxNodeHeight <= 0) {
      return null;
    }

    const minimumWidth = LANE_NODE_PADDING_X * 2 + maxNodeWidth;
    const targetWidth = Number.isFinite(requestedWidth)
      ? requestedWidth
      : currentWidth;
    const appliedWidth = Math.max(minimumWidth, targetWidth);
    const usableWidth = Math.max(1, appliedWidth - LANE_NODE_PADDING_X * 2);
    const columns = Math.max(
      1,
      Math.floor((usableWidth + LANE_NODE_GAP_X) / (maxNodeWidth + LANE_NODE_GAP_X))
    );
    const rows = Math.max(1, Math.ceil(orderedMembers.length / columns));

    const minimumHeight =
      LANE_NODE_PADDING_TOP +
      LANE_NODE_PADDING_BOTTOM +
      rows * maxNodeHeight +
      Math.max(0, rows - 1) * LANE_NODE_GAP_Y;
    const targetHeight = Number.isFinite(requestedHeight)
      ? requestedHeight
      : currentHeight;
    const appliedHeight = Math.max(minimumHeight, targetHeight);

    laneNode.data({
      width: appliedWidth,
      height: appliedHeight
    });
    laneNode.position({
      x: anchorLeft + appliedWidth / 2,
      y: anchorTop + appliedHeight / 2
    });

    const firstColumnCenterX = anchorLeft + LANE_NODE_PADDING_X + maxNodeWidth / 2;
    const firstRowCenterY = anchorTop + LANE_NODE_PADDING_TOP + maxNodeHeight / 2;
    orderedMembers.forEach((memberNode, index) => {
      const rowIndex = Math.floor(index / columns);
      const columnIndex = index % columns;
      memberNode.position({
        x: firstColumnCenterX + columnIndex * (maxNodeWidth + LANE_NODE_GAP_X),
        y: firstRowCenterY + rowIndex * (maxNodeHeight + LANE_NODE_GAP_Y)
      });
      this.clampEntityNodeToLane(memberNode);
    });

    return {
      width: appliedWidth,
      height: appliedHeight
    };
  }

  mergeManualPositions(nodes, basePositions) {
    const mergedPositions = { ...basePositions };
    if (!nodes || !Array.isArray(nodes)) {
      return mergedPositions;
    }

    nodes.forEach((node) => {
      const manualPosition = this.manualPositionsByNodeId[node.id];
      if (!manualPosition) {
        return;
      }
      mergedPositions[node.id] = {
        x: manualPosition.x,
        y: manualPosition.y
      };
    });
    return mergedPositions;
  }

  captureNodePosition(node) {
    if (!node || typeof node.id !== "function" || node.data("isVirtual")) {
      return;
    }

    const nodePosition = node.position();
    this.manualPositionsByNodeId = {
      ...this.manualPositionsByNodeId,
      [node.id()]: {
        x: nodePosition.x,
        y: nodePosition.y
      }
    };
  }

  getLaneMembers(laneId) {
    if (!this.cy) {
      return [];
    }

    return this.cy
      .nodes("node.entity")
      .filter((candidateNode) => this.belongsToLane(candidateNode, laneId))
      .toArray();
  }

  getLaneIdForEntityNode(node) {
    if (!node) {
      return null;
    }

    const direction = String(
      node.data("relationshipDirection") || ""
    ).toUpperCase();
    const signedLevel = Number(node.data("signedLevel"));

    if (direction === COMPETITOR_DIRECTION) {
      return "lane-competitor";
    }
    if (!Number.isFinite(signedLevel)) {
      return null;
    }

    if (signedLevel < 0) {
      if (signedLevel === -1) {
        return "lane-upstream-tier1";
      }
      if (signedLevel === -2) {
        return "lane-upstream-tier2";
      }
      return "lane-upstream-tier3";
    }

    if (signedLevel > 0) {
      if (signedLevel === 1) {
        return "lane-downstream-tier1";
      }
      if (signedLevel === 2) {
        return "lane-downstream-tier2";
      }
      return "lane-downstream-tier3";
    }

    return null;
  }

  clampEntityNodeToLane(node) {
    if (!this.cy || !node || node.data("isVirtual")) {
      return;
    }

    const laneId = this.getLaneIdForEntityNode(node);
    if (!laneId) {
      return;
    }

    const laneNode = this.cy.getElementById(laneId);
    if (!laneNode || laneNode.empty()) {
      return;
    }

    const laneWidth = Number(laneNode.data("width"));
    const laneHeight = Number(laneNode.data("height"));
    if (!Number.isFinite(laneWidth) || !Number.isFinite(laneHeight)) {
      return;
    }

    const laneCenterX = laneNode.position("x");
    const laneCenterY = laneNode.position("y");
    const nodeHalfWidth = node.width() / 2;
    const nodeHalfHeight = node.height() / 2;

    let minX =
      laneCenterX - laneWidth / 2 + LANE_NODE_PADDING_X + nodeHalfWidth;
    let maxX =
      laneCenterX + laneWidth / 2 - LANE_NODE_PADDING_X - nodeHalfWidth;
    let minY =
      laneCenterY - laneHeight / 2 + LANE_NODE_PADDING_TOP + nodeHalfHeight;
    let maxY =
      laneCenterY + laneHeight / 2 - LANE_NODE_PADDING_BOTTOM - nodeHalfHeight;

    if (minX > maxX) {
      minX = laneCenterX;
      maxX = laneCenterX;
    }
    if (minY > maxY) {
      minY = laneCenterY;
      maxY = laneCenterY;
    }

    const currentX = node.position("x");
    const currentY = node.position("y");
    const clampedX = Math.min(maxX, Math.max(minX, currentX));
    const clampedY = Math.min(maxY, Math.max(minY, currentY));

    if (
      Math.abs(clampedX - currentX) > 0.25 ||
      Math.abs(clampedY - currentY) > 0.25
    ) {
      node.position({
        x: clampedX,
        y: clampedY
      });
    }
  }

  belongsToLane(node, laneId) {
    if (!node) {
      return false;
    }

    const direction = String(
      node.data("relationshipDirection") || ""
    ).toUpperCase();
    const signedLevel = Number(node.data("signedLevel"));
    if (laneId === "lane-competitor") {
      return direction === COMPETITOR_DIRECTION;
    }
    if (!Number.isFinite(signedLevel) || direction === COMPETITOR_DIRECTION) {
      return false;
    }

    if (laneId === "lane-upstream" || laneId === "lane-upstream-tier1") {
      return signedLevel === -1;
    }
    if (laneId === "lane-upstream-tier2") {
      return signedLevel === -2;
    }
    if (laneId === "lane-upstream-tier3") {
      return signedLevel <= -3;
    }

    if (laneId === "lane-downstream" || laneId === "lane-downstream-tier1") {
      return signedLevel === 1;
    }
    if (laneId === "lane-downstream-tier2") {
      return signedLevel === 2;
    }
    if (laneId === "lane-downstream-tier3") {
      return signedLevel >= 3;
    }
    return false;
  }

  restoreUserPreferences() {
    try {
      const rawPreferences = window.localStorage.getItem(
        this.preferenceStorageKey
      );
      if (!rawPreferences) {
        return;
      }

      const preferences = JSON.parse(rawPreferences);
      if (!preferences || typeof preferences !== "object") {
        return;
      }

      if (Object.prototype.hasOwnProperty.call(preferences, "selectedFilter")) {
        this.selectedFilter = this.normalizeFilterValue(
          preferences.selectedFilter
        );
      }
      if (
        Object.prototype.hasOwnProperty.call(
          preferences,
          "manualManagerExpanded"
        )
      ) {
        this.manualManagerExpanded = this.coerceBoolean(
          preferences.manualManagerExpanded
        );
      }
      if (
        Object.prototype.hasOwnProperty.call(preferences, "wncImpactExpanded")
      ) {
        this.wncImpactExpanded = this.coerceBoolean(
          preferences.wncImpactExpanded
        );
      }
    } catch {
      // Preference read failure should not block graph.
    }
  }

  persistUserPreferences() {
    try {
      const preferences = {
        selectedFilter: this.normalizeFilterValue(this.selectedFilter),
        manualManagerExpanded: this.manualManagerExpanded === true,
        wncImpactExpanded: this.wncImpactExpanded === true
      };
      window.localStorage.setItem(
        this.preferenceStorageKey,
        JSON.stringify(preferences)
      );
    } catch {
      // Preference write failure is non-blocking.
    }
  }

  get preferenceStorageKey() {
    const scope = this.recordId || "global";
    return `${PREFERENCE_STORAGE_KEY_PREFIX}:${scope}`;
  }

  get disableRelationshipFormInputs() {
    return this.disableRelationshipActions;
  }

  normalizeFilterValue(rawValue) {
    const isKnownFilter = FILTER_OPTIONS.some(
      (option) => option.value === rawValue
    );
    return isKnownFilter ? rawValue : FILTER_VALUES.ALL;
  }

  normalizeMode(rawValue) {
    if (
      rawValue === "UPSTREAM" ||
      rawValue === "DOWNSTREAM" ||
      rawValue === "COMPETITOR"
    ) {
      return rawValue;
    }
    return "UPSTREAM";
  }

  truncateText(text, maxLength) {
    if (typeof text !== "string") {
      return "";
    }
    const normalizedText = text.trim();
    if (normalizedText.length <= maxLength) {
      return normalizedText;
    }
    return `${normalizedText.slice(0, maxLength).trimEnd()}…`;
  }

  setBodyScrollLock(isLocked) {
    if (typeof document === "undefined" || !document.body) {
      return;
    }
    document.body.style.overflow = isLocked ? "hidden" : "";
  }

  getGraphShellElement() {
    return this.template.querySelector(".graph-shell");
  }

  getCurrentNativeFullscreenElement() {
    if (typeof document === "undefined") {
      return null;
    }
    return (
      document.fullscreenElement || document.webkitFullscreenElement || null
    );
  }

  async enterNativeFullscreen(graphShell) {
    if (!graphShell) {
      return false;
    }
    try {
      if (typeof graphShell.requestFullscreen === "function") {
        await graphShell.requestFullscreen();
        return true;
      }
      if (typeof graphShell.webkitRequestFullscreen === "function") {
        graphShell.webkitRequestFullscreen();
        return true;
      }
    } catch {
      // Native fullscreen may be blocked by browser policy; fallback to CSS mode.
    }
    return false;
  }

  async exitNativeFullscreen() {
    try {
      if (typeof document.exitFullscreen === "function") {
        await document.exitFullscreen();
        return true;
      }
      if (typeof document.webkitExitFullscreen === "function") {
        document.webkitExitFullscreen();
        return true;
      }
    } catch {
      // Ignore native exit failure; fallback state is handled by CSS mode.
    }
    return false;
  }

  exitNativeFullscreenIfNeeded() {
    const graphShell = this.getGraphShellElement();
    const nativeFullscreenElement = this.getCurrentNativeFullscreenElement();
    if (graphShell && nativeFullscreenElement === graphShell) {
      this.exitNativeFullscreen();
    }
    this.isUsingNativeFullscreen = false;
  }

  showToast(title, message, variant = "info") {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    );
  }

  coerceBoolean(rawValue) {
    if (
      rawValue === true ||
      rawValue === "true" ||
      rawValue === 1 ||
      rawValue === "1"
    ) {
      return true;
    }
    return false;
  }
}
