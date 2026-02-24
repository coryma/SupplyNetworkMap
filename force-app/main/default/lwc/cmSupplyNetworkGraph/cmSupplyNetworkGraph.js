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
const NETWORK_HORIZONTAL_SPACING = 220;
const NETWORK_VERTICAL_SPACING = 180;
const GRAPH_FIT_PADDING = 80;
const TOOLTIP_OFFSET_X = 18;
const TOOLTIP_OFFSET_Y = 16;
const CACHE_KEY_PREFIX = 'cmSupplyNetworkGraph';
const LOADING_STATUS_MESSAGE = '正在載入上下游關係圖...';

const CYTOSCAPE_STYLE = [
    {
        selector: 'node',
        style: {
            'background-color': '#ffffff',
            label: 'data(label)',
            color: '#032d60',
            'font-size': 13,
            'font-weight': 600,
            'text-wrap': 'wrap',
            'text-max-width': 180,
            'text-valign': 'center',
            'text-halign': 'center',
            'background-opacity': 1,
            width: 190,
            height: 96,
            shape: 'round-rectangle',
            'border-width': 2,
            'border-color': '#d8dde6',
            'text-outline-width': 0,
            'overlay-opacity': 0
        }
    },
    {
        selector: 'node.entity',
        style: {
            'background-color': '#ffffff',
            color: '#032d60',
            'font-size': 15
        }
    },
    {
        selector: 'node.root',
        style: {
            'background-color': '#eaf5fe',
            'border-color': '#0176d3',
            color: '#032d60',
            width: 220,
            height: 110,
            'border-width': 2,
            'font-size': 17,
            'font-weight': 700
        }
    },
    {
        selector: 'node.role-manufacturing',
        style: {
            'background-color': '#f4f7fb',
            'border-color': '#8da2bc'
        }
    },
    {
        selector: 'node.role-channel',
        style: {
            'background-color': '#edf7f2',
            'border-color': '#2e844a'
        }
    },
    {
        selector: 'node.role-customer',
        style: {
            'background-color': '#fef6f0',
            'border-color': '#dd7a01'
        }
    },
    {
        selector: 'node.lane',
        style: {
            'background-color': '#f8f9fb',
            'background-opacity': 0.95,
            'border-color': '#d8dde6',
            'border-width': 1,
            width: 'data(width)',
            height: 'data(height)',
            color: '#3e3e3c',
            'font-size': 16,
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
            'background-color': '#f4f7fb',
            'background-opacity': 0.95
        }
    },
    {
        selector: 'node.lane-downstream',
        style: {
            'background-color': '#f9f6fb',
            'background-opacity': 0.95
        }
    },
    {
        selector: 'node.annotation',
        style: {
            width: 'data(width)',
            height: 'data(height)',
            'background-color': '#ffffff',
            'border-color': '#8e9db4',
            'border-width': 1.5,
            'border-style': 'dashed',
            color: '#032d60',
            'font-size': 12,
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
            'line-color': '#b0bccd',
            'target-arrow-color': '#b0bccd',
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
            'line-color': '#0176d3',
            'target-arrow-color': '#0176d3'
        }
    },
    {
        selector: 'edge.relation-distributor',
        style: {
            'line-color': '#2e844a',
            'target-arrow-color': '#2e844a'
        }
    },
    {
        selector: 'edge.relation-competitor',
        style: {
            'line-color': '#ba0517',
            'target-arrow-color': '#ba0517',
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
            'line-color': '#8e9db4',
            'target-arrow-color': '#8e9db4',
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
            'border-color': '#0176d3',
            'shadow-blur': 14,
            'shadow-color': '#0176d3',
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

    connectedCallback() {
        this.restoreCachedGraph();
        this.loadGraphData();
    }

    renderedCallback() {
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
            wheelSensitivity: 0.15
        });

        this.cy.on('tap', 'node', (event) => {
            const tappedNode = event.target;
            if (tappedNode.data('isVirtual')) {
                return;
            }
            this.navigateToAccount(tappedNode.data('accountId'));
        });

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

        this.cy.on('pan zoom', () => {
            this.hideNodeTooltip();
        });

        this.cy.fit(undefined, GRAPH_FIT_PADDING);
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
}
