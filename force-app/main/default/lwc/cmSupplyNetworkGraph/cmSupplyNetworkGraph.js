import { api, LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import cytoscapeResource from '@salesforce/resourceUrl/cytoscape';
import getGraph from '@salesforce/apex/CMSupplyNetworkGraphController.getGraph';
import {
    buildFilteredElements,
    buildStoryElements,
    computeNodePositions,
    DISPLAY_MODES,
    FILTER_VALUES
} from './cmSupplyNetworkGraphUtils';

const FILTER_OPTIONS = [
    { label: 'All', value: FILTER_VALUES.ALL },
    { label: 'Upstream', value: FILTER_VALUES.UPSTREAM },
    { label: 'Downstream', value: FILTER_VALUES.DOWNSTREAM }
];

const STORY_HORIZONTAL_SPACING = 280;
const STORY_VERTICAL_SPACING = 210;
const NETWORK_HORIZONTAL_SPACING = 250;
const NETWORK_VERTICAL_SPACING = 195;
const GRAPH_FIT_PADDING = 80;
const TOOLTIP_OFFSET_X = 18;
const TOOLTIP_OFFSET_Y = 16;
const NAVIGATION_GUARD_WINDOW_MS = 500;
const PAN_NAVIGATION_GUARD_WINDOW_MS = 120;
const CACHE_KEY_PREFIX = 'cmSupplyNetworkGraph';
const LOADING_STATUS_MESSAGE = '正在載入上下游關係圖...';

const CYTOSCAPE_STYLE = [
    {
        selector: 'node',
        style: {
            'background-color': '#6b7280',
            label: 'data(label)',
            color: '#e2e8f0',
            'font-size': 16,
            'font-weight': 600,
            'text-wrap': 'wrap',
            'text-max-width': 216,
            'text-valign': 'center',
            'text-halign': 'center',
            'background-opacity': 1,
            width: 232,
            height: 122,
            shape: 'round-rectangle',
            'border-width': 2,
            'border-color': '#475569',
            'text-outline-width': 0,
            'overlay-opacity': 0,
            'min-zoomed-font-size': 11
        }
    },
    {
        selector: 'node.entity',
        style: {
            'background-color': '#e2e8f0',
            color: '#111827',
            'font-size': 18
        }
    },
    {
        selector: 'node.root',
        style: {
            'background-color': '#fef3c7',
            'border-color': '#f59e0b',
            color: '#111827',
            width: 264,
            height: 136,
            'border-width': 2,
            'font-size': 22,
            'font-weight': 700
        }
    },
    {
        selector: 'node.role-manufacturing',
        style: {
            'background-color': '#e0f2fe',
            'border-color': '#38bdf8'
        }
    },
    {
        selector: 'node.role-channel',
        style: {
            'background-color': '#dcfce7',
            'border-color': '#22c55e'
        }
    },
    {
        selector: 'node.role-customer',
        style: {
            'background-color': '#f3e8ff',
            'border-color': '#c026d3'
        }
    },
    {
        selector: 'node.lane',
        style: {
            'background-color': '#4b5563',
            'background-opacity': 0.7,
            'border-color': '#94a3b8',
            'border-width': 1,
            width: 'data(width)',
            height: 'data(height)',
            color: '#e2e8f0',
            'font-size': 19,
            'font-weight': 700,
            'text-max-width': 320,
            'text-valign': 'top',
            'text-margin-y': -8,
            'z-index': -1,
            events: 'no'
        }
    },
    {
        selector: 'node.lane-upstream',
        style: {
            'background-color': '#5b6168',
            'background-opacity': 0.78
        }
    },
    {
        selector: 'node.lane-downstream',
        style: {
            'background-color': '#5f666d',
            'background-opacity': 0.8
        }
    },
    {
        selector: 'node.annotation',
        style: {
            width: 'data(width)',
            height: 'data(height)',
            'background-color': '#374151',
            'border-color': '#f59e0b',
            'border-width': 1.5,
            'border-style': 'dashed',
            color: '#f8fafc',
            'font-size': 15,
            'font-weight': 600,
            'text-max-width': 260,
            'text-wrap': 'wrap',
            'z-index': 3,
            events: 'no'
        }
    },
    {
        selector: 'edge',
        style: {
            width: 2,
            'curve-style': 'bezier',
            'target-arrow-shape': 'triangle',
            'arrow-scale': 0.9,
            'line-color': '#cbd5e1',
            'target-arrow-color': '#cbd5e1',
            'overlay-opacity': 0
        }
    },
    {
        selector: 'edge.flow-main',
        style: {
            width: 2.2
        }
    },
    {
        selector: 'edge.relation-supplier',
        style: {
            'line-color': '#7dd3fc',
            'target-arrow-color': '#7dd3fc'
        }
    },
    {
        selector: 'edge.relation-distributor',
        style: {
            'line-color': '#34d399',
            'target-arrow-color': '#34d399'
        }
    },
    {
        selector: 'edge.relation-competitor',
        style: {
            'line-color': '#fbbf24',
            'target-arrow-color': '#fbbf24',
            'line-style': 'dashed'
        }
    },
    {
        selector: 'edge.flow-support',
        style: {
            width: 1.6,
            'line-style': 'solid'
        }
    },
    {
        selector: 'edge.flow-note',
        style: {
            width: 1.4,
            'line-style': 'dashed',
            'line-color': '#e5e7eb',
            'target-arrow-color': '#e5e7eb',
            'target-arrow-shape': 'none',
            'curve-style': 'bezier'
        }
    },
    {
        selector: '.is-muted',
        style: {
            opacity: 0.16
        }
    },
    {
        selector: 'node.entity.is-focus',
        style: {
            'border-width': 3,
            'border-color': '#f8fafc',
            'shadow-blur': 14,
            'shadow-color': '#f8fafc',
            'shadow-opacity': 0.35,
            'shadow-offset-x': 0,
            'shadow-offset-y': 0
        }
    },
    {
        selector: 'edge.is-focus',
        style: {
            width: 2.8,
            opacity: 1
        }
    }
];

export default class CmSupplyNetworkGraph extends NavigationMixin(LightningElement) {
    @api recordId;
    @api maxNodes = 150;
    @api displayMode = DISPLAY_MODES.STORY;
    @track selectedFilter = FILTER_VALUES.ALL;

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
    resizeObserver;
    lastNavigationAt = 0;
    windowResizeHandler;
    windowScrollHandler;
    windowFocusHandler;
    visibilityChangeHandler;
    lastPanAt = 0;

    connectedCallback() {
        this.restoreCachedGraph();
        this.initializeViewportListeners();
        this.loadGraphData();
    }

    renderedCallback() {
        this.ensureContainerObserver();
        if (this.scriptLoadingPromise) {
            return;
        }
        this.scriptLoadingPromise = loadScript(this, cytoscapeResource)
            .then(() => {
                this.cytoscapeReady = true;
                this.renderGraph();
            })
            .catch((error) => {
                this.errorMessage = this.formatError(error);
            });
    }

    disconnectedCallback() {
        this.teardownViewportListeners();
        this.teardownContainerObserver();
        if (this.cy) {
            this.cy.destroy();
            this.cy = null;
        }
        this.hideNodeTooltip();
    }

    @api
    refreshGraph() {
        return this.loadGraphData();
    }

    handleRefreshClick() {
        this.loadGraphData();
    }

    async loadGraphData() {
        if (!this.recordId) {
            return;
        }

        const hasCachedGraph = this.hasData;
        this.isLoading = !hasCachedGraph;
        this.isRefreshingInBackground = hasCachedGraph;
        this.loadingStatusMessage = hasCachedGraph
            ? '顯示上次結果，背景更新中...'
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

            this.graphResponse = response || { nodes: [], edges: [], nodeCount: 0, edgeCount: 0, truncated: false };
            this.persistCachedGraph(this.graphResponse);
            this.generatedAtLabel = this.formatDateTime(this.graphResponse.generatedAt);
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
        this.selectedFilter = event.detail.value;
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

        const positionsByNode = computeNodePositions(
            nodes,
            this.isStoryMode ? STORY_HORIZONTAL_SPACING : NETWORK_HORIZONTAL_SPACING,
            this.isStoryMode ? STORY_VERTICAL_SPACING : NETWORK_VERTICAL_SPACING
        );
        const filteredElements = this.isStoryMode
            ? buildStoryElements(nodes, edges, this.selectedFilter, positionsByNode)
            : buildFilteredElements(nodes, edges, this.selectedFilter, positionsByNode);
        const elements = [...filteredElements.nodes, ...filteredElements.edges];

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
                name: 'preset'
            },
            wheelSensitivity: 0.15,
            pixelRatio: 1,
            panningEnabled: true,
            userPanningEnabled: true,
            zoomingEnabled: true,
            userZoomingEnabled: true,
            boxSelectionEnabled: false,
            autoungrabify: true
        });

        const navigateFromNode = (event) => {
            const tappedNode = event.target;
            if (tappedNode.data('isVirtual')) {
                return;
            }
            if (Date.now() - this.lastPanAt < PAN_NAVIGATION_GUARD_WINDOW_MS) {
                return;
            }
            this.navigateToAccount(tappedNode.data('accountId'));
        };
        this.cy.on('tap', 'node', navigateFromNode);
        this.cy.on('click', 'node', navigateFromNode);

        this.cy.on('mouseover', 'node.entity', (event) => {
            this.applyFocusState(event.target);
            this.showNodeTooltip(event);
        });

        this.cy.on('mousemove', 'node.entity', (event) => {
            this.moveNodeTooltip(event);
        });

        this.cy.on('mouseout', 'node.entity', () => {
            this.clearFocusState();
            this.hideNodeTooltip();
        });

        this.cy.on('tap', () => {
            this.hideNodeTooltip();
        });

        this.cy.on('pan', () => {
            this.lastPanAt = Date.now();
        });

        this.cy.on('pan zoom', () => {
            this.hideNodeTooltip();
        });

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
        if (!this.cy || !node || typeof node.data !== 'function') {
            return;
        }
        if (node.data('isVirtual')) {
            this.clearFocusState();
            return;
        }

        this.clearFocusState();

        const focusElements = node
            .closedNeighborhood()
            .union(node.predecessors())
            .union(node.successors());
        const mutedElements = this.cy.elements().difference(focusElements);

        mutedElements.addClass('is-muted');
        focusElements.addClass('is-focus');
    }

    clearFocusState() {
        if (!this.cy) {
            return;
        }
        this.cy.elements().removeClass('is-muted');
        this.cy.elements().removeClass('is-focus');
    }

    showNodeTooltip(event) {
        const targetNode = event?.target;
        if (!targetNode || targetNode.data('isVirtual')) {
            this.hideNodeTooltip();
            return;
        }

        const tooltipElement = this.template.querySelector('[data-id="node-tooltip"]');
        if (!tooltipElement) {
            return;
        }

        this.tooltipCurrentNodeId = targetNode.id();
        this.updateTooltipText(targetNode);
        tooltipElement.classList.add('is-visible');
        this.positionTooltip(event);
    }

    moveNodeTooltip(event) {
        if (!this.tooltipCurrentNodeId) {
            return;
        }
        this.positionTooltip(event);
    }

    hideNodeTooltip() {
        const tooltipElement = this.template.querySelector('[data-id="node-tooltip"]');
        if (tooltipElement) {
            tooltipElement.classList.remove('is-visible');
            tooltipElement.style.left = '-10000px';
            tooltipElement.style.top = '-10000px';
        }
        this.tooltipCurrentNodeId = undefined;
    }

    updateTooltipText(node) {
        const titleElement = this.template.querySelector('[data-id="tooltip-title"]');
        const roleElement = this.template.querySelector('[data-id="tooltip-role"]');
        const noteElement = this.template.querySelector('[data-id="tooltip-note"]');

        if (titleElement) {
            titleElement.textContent = node.data('label') || '';
        }
        if (roleElement) {
            roleElement.textContent = node.data('roleLabel') || '未分類';
        }
        if (noteElement) {
            noteElement.textContent = node.data('noteText') || '';
        }
    }

    positionTooltip(event) {
        const tooltipElement = this.template.querySelector('[data-id="node-tooltip"]');
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
            left = Math.max(12, originalEvent.clientX - tooltipRect.width - TOOLTIP_OFFSET_X);
        }
        if (top + tooltipRect.height > viewportHeight - 12) {
            top = Math.max(12, originalEvent.clientY - tooltipRect.height - TOOLTIP_OFFSET_Y);
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
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    formatError(error) {
        const errorBody = error?.body;
        if (Array.isArray(errorBody) && errorBody.length > 0) {
            return errorBody.map((item) => item.message).join(', ');
        }
        if (typeof errorBody?.message === 'string') {
            return errorBody.message;
        }
        if (typeof error?.message === 'string') {
            return error.message;
        }
        return '無法載入上下游關係圖。';
    }

    restoreCachedGraph() {
        if (!this.recordId) {
            return;
        }

        try {
            const rawCache = window.sessionStorage.getItem(this.graphCacheKey);
            if (!rawCache) {
                return;
            }

            const cachedPayload = JSON.parse(rawCache);
            if (!cachedPayload || !cachedPayload.graphResponse || !Array.isArray(cachedPayload.graphResponse.nodes)) {
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
            window.sessionStorage.setItem(this.graphCacheKey, JSON.stringify(cachePayload));
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
        return 150;
    }

    get hasData() {
        return (this.graphResponse?.nodes?.length || 0) > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && !this.hasData;
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

    get isStoryMode() {
        return this.normalizedDisplayMode === DISPLAY_MODES.STORY;
    }

    get normalizedDisplayMode() {
        return this.displayMode === DISPLAY_MODES.NETWORK ? DISPLAY_MODES.NETWORK : DISPLAY_MODES.STORY;
    }

    get isTruncated() {
        return this.graphResponse?.truncated === true;
    }

    get nodeCount() {
        return this.graphResponse?.nodeCount || 0;
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
        this.visibilityChangeHandler = () => {
            if (document.hidden) {
                return;
            }
            this.scheduleViewportSync();
        };

        window.addEventListener('resize', this.windowResizeHandler);
        window.addEventListener('scroll', this.windowScrollHandler, true);
        window.addEventListener('focus', this.windowFocusHandler);
        document.addEventListener('visibilitychange', this.visibilityChangeHandler);
    }

    teardownViewportListeners() {
        if (this.windowResizeHandler) {
            window.removeEventListener('resize', this.windowResizeHandler);
            this.windowResizeHandler = undefined;
        }
        if (this.windowFocusHandler) {
            window.removeEventListener('focus', this.windowFocusHandler);
            this.windowFocusHandler = undefined;
        }
        if (this.windowScrollHandler) {
            window.removeEventListener('scroll', this.windowScrollHandler, true);
            this.windowScrollHandler = undefined;
        }
        if (this.visibilityChangeHandler) {
            document.removeEventListener('visibilitychange', this.visibilityChangeHandler);
            this.visibilityChangeHandler = undefined;
        }
    }

    ensureContainerObserver() {
        if (this.resizeObserver || typeof window.ResizeObserver !== 'function') {
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

    syncViewport(shouldRefit = false) {
        if (!this.cy) {
            return;
        }

        try {
            this.cy.resize();
            if (shouldRefit) {
                this.cy.fit(undefined, GRAPH_FIT_PADDING);
            }
        } catch {
            // Best-effort refresh; ignore transient rendering failures.
        }
    }
}
