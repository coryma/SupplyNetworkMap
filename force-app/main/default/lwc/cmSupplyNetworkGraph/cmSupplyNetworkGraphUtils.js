export const FILTER_VALUES = Object.freeze({
    ALL: 'all',
    UPSTREAM: 'upstream',
    DOWNSTREAM: 'downstream'
});

export const DISPLAY_MODES = Object.freeze({
    NETWORK: 'network',
    STORY: 'story'
});

const DEFAULT_POSITION = { x: 0, y: 0 };
const COMPETITOR_DIRECTION = 'COMPETITOR';

export function computeNodePositions(nodes, horizontalSpacing = 220, verticalSpacing = 180) {
    const positions = {};
    const levelToNodes = new Map();
    const sourceNodes = Array.isArray(nodes) ? nodes : [];
    const standardNodes = sourceNodes.filter((node) => !isCompetitorNode(node));
    const competitorNodes = sourceNodes.filter((node) => isCompetitorNode(node));

    standardNodes.forEach((node) => {
        const level = Number.isFinite(node.signedLevel) ? node.signedLevel : 0;
        if (!levelToNodes.has(level)) {
            levelToNodes.set(level, []);
        }
        levelToNodes.get(level).push(node);
    });

    [...levelToNodes.keys()]
        .sort((a, b) => a - b)
        .forEach((level) => {
            const levelNodes = [...levelToNodes.get(level)].sort((leftNode, rightNode) =>
                String(leftNode.label || '').localeCompare(String(rightNode.label || ''))
            );
            const xStart = -((levelNodes.length - 1) * horizontalSpacing) / 2;

            levelNodes.forEach((node, index) => {
                positions[node.id] = {
                    x: xStart + index * horizontalSpacing,
                    y: level * verticalSpacing
                };
            });
        });

    if (competitorNodes.length) {
        const rootNode =
            standardNodes.find((node) => node.isRoot) ||
            standardNodes.find((node) => Number(node.signedLevel) === 0) ||
            sourceNodes[0];
        const rootPosition = rootNode && positions[rootNode.id] ? positions[rootNode.id] : DEFAULT_POSITION;
        const competitorX = rootPosition.x + Math.max(horizontalSpacing * 2.2, 430);
        const competitorVerticalSpacing = Math.max(Math.round(verticalSpacing * 0.95), 150);
        const sortedCompetitors = [...competitorNodes].sort((leftNode, rightNode) =>
            String(leftNode.label || '').localeCompare(String(rightNode.label || ''))
        );
        const yStart = rootPosition.y - ((sortedCompetitors.length - 1) * competitorVerticalSpacing) / 2;

        sortedCompetitors.forEach((node, index) => {
            positions[node.id] = {
                x: competitorX,
                y: yStart + index * competitorVerticalSpacing
            };
        });
    }

    return positions;
}

export function buildFilteredElements(nodes, edges, filterValue, positionsByNode = {}) {
    const activeFilter = normalizeFilter(filterValue);
    const candidateNodeElements = (nodes || [])
        .filter((node) => shouldIncludeNode(node, activeFilter))
        .map((node) => {
            const nodeInsight = buildNodeInsight(node);
            return {
                data: {
                    id: node.id,
                    label: node.label,
                    accountId: node.accountId || null,
                    signedLevel: node.signedLevel,
                    isRoot: node.isRoot,
                    accountType: node.accountType || '',
                    upstreamDepth: node.upstreamDepth,
                    downstreamDepth: node.downstreamDepth,
                    relationshipDirection: node.relationshipDirection || '',
                    roleLabel: nodeInsight.roleLabel,
                    noteText: nodeInsight.noteText,
                    isVirtual: false
                },
                position: positionsByNode[node.id] || DEFAULT_POSITION,
                classes: getNodeClasses(node)
            };
        });
    const allowedNodeIds = new Set(
        candidateNodeElements.map((nodeElement) => nodeElement.data.id)
    );

    const sourceEdges = edges || [];
    const edgeElements = sourceEdges
        .filter((edge) =>
            allowedNodeIds.has(edge.sourceId) &&
            allowedNodeIds.has(edge.targetId)
        )
        .map((edge, index) => ({
            data: {
                id: edge.id || `${edge.sourceId}-${edge.targetId}-${index}`,
                source: edge.sourceId,
                target: edge.targetId,
                relationType: edge.relationType || 'Related',
                edgeCategory: edge.edgeCategory || '',
                relationshipDirection: edge.relationshipDirection || '',
                marketRiskNote: edge.marketRiskNote || '',
                isVirtual: false
            },
            classes: getEdgeClasses(edge)
        }));

    // Keep nodes that are connected by any relationship.
    const connectedNodeIds = new Set();
    sourceEdges
        .filter((edge) => allowedNodeIds.has(edge.sourceId) && allowedNodeIds.has(edge.targetId))
        .forEach((edge) => {
            connectedNodeIds.add(edge.sourceId);
            connectedNodeIds.add(edge.targetId);
        });

    edgeElements.forEach((edgeElement) => {
        connectedNodeIds.add(edgeElement.data.source);
        connectedNodeIds.add(edgeElement.data.target);
    });
    const nodeElements = candidateNodeElements.filter(
        (nodeElement) =>
            nodeElement.data.isRoot === true || connectedNodeIds.has(nodeElement.data.id)
    );

    return {
        nodes: nodeElements,
        edges: edgeElements
    };
}

export function buildStoryElements(nodes, edges, filterValue, positionsByNode = {}) {
    const hasProvidedPositions = Object.keys(positionsByNode || {}).length > 0;
    const basePositions = hasProvidedPositions ? positionsByNode : computeNodePositions(nodes, 260, 200);
    const coreElements = buildFilteredElements(nodes, edges, filterValue, basePositions);

    if (!coreElements.nodes.length) {
        return coreElements;
    }

    const laneElements = buildLaneElements(coreElements.nodes);

    return {
        nodes: [...laneElements, ...coreElements.nodes],
        edges: [...coreElements.edges]
    };
}

function normalizeFilter(filterValue) {
    if (filterValue === FILTER_VALUES.UPSTREAM || filterValue === FILTER_VALUES.DOWNSTREAM) {
        return filterValue;
    }
    return FILTER_VALUES.ALL;
}

function shouldIncludeNode(node, filterValue) {
    if (filterValue === FILTER_VALUES.ALL) {
        return true;
    }
    if (filterValue === FILTER_VALUES.UPSTREAM) {
        return node.isRoot || node.signedLevel <= 0;
    }
    return node.isRoot || (node.signedLevel >= 0 && !isCompetitorNode(node));
}

function getNodeClasses(node) {
    const classes = ['entity', 'interactive'];
    if (node.isRoot) {
        classes.push('root', 'role-design');
        return classes.join(' ');
    }
    if (node.signedLevel < 0) {
        classes.push('upstream', 'role-manufacturing');
        return classes.join(' ');
    }
    if (node.signedLevel > 0) {
        classes.push('downstream');
        if (isCompetitorNode(node)) {
            classes.push('competitor', 'role-competitor');
            return classes.join(' ');
        }

        const depth = Number(node.downstreamDepth);
        if (Number.isFinite(depth) && depth >= 2) {
            classes.push('tier-2', 'role-customer');
        } else {
            classes.push('tier-1', 'role-channel');
        }
        return classes.join(' ');
    }
    classes.push('neutral');
    return classes.join(' ');
}

function getEdgeClasses(edge) {
    const classes = ['flow', 'flow-main', 'relation-default'];
    const relationType = edge?.relationType;
    const edgeCategory = String(edge?.edgeCategory || '').toUpperCase();
    const relationshipDirection = String(edge?.relationshipDirection || '').toUpperCase();
    const normalized = String(relationType || '').toLowerCase();
    if (edgeCategory === 'UPSTREAM' || relationshipDirection === 'UPSTREAM') {
        classes.push('relation-supplier', 'flow-support');
        return classes.join(' ');
    }
    if (
        normalized.includes('supplier') ||
        normalized.includes('foundry') ||
        normalized.includes('osat') ||
        normalized.includes('manufacturer')
    ) {
        classes.push('relation-supplier', 'flow-support');
        return classes.join(' ');
    }
    if (
        edgeCategory === COMPETITOR_DIRECTION ||
        relationshipDirection === COMPETITOR_DIRECTION ||
        normalized.includes('competitor')
    ) {
        classes.push('relation-competitor', 'flow-note');
        return classes.join(' ');
    }
    if (
        normalized.includes('distributor') ||
        normalized.includes('customer') ||
        normalized.includes('odm') ||
        normalized.includes('oem') ||
        normalized.includes('channel') ||
        normalized.includes('telecom') ||
        normalized.includes('operator') ||
        normalized.includes('automaker') ||
        normalized.includes('brand') ||
        normalized.includes('enterprise')
    ) {
        classes.push('relation-distributor');
        return classes.join(' ');
    }
    return classes.join(' ');
}

function buildLaneElements(entityNodes) {
    const laneDefinitions = [
        {
            id: 'lane-upstream-tier1',
            label: '上游一階供應',
            nodeFilter: (node) =>
                getSignedLevel(node) === -1 && !isCompetitorDirection(node?.data?.relationshipDirection),
            laneClass: 'lane-upstream lane-upstream-tier1',
            minWidth: 420,
            minHeight: 200,
            horizontalPadding: 260,
            verticalPadding: 170
        },
        {
            id: 'lane-upstream-tier2',
            label: '上游二階供應',
            nodeFilter: (node) =>
                getSignedLevel(node) === -2 && !isCompetitorDirection(node?.data?.relationshipDirection),
            laneClass: 'lane-upstream lane-upstream-tier2',
            minWidth: 420,
            minHeight: 200,
            horizontalPadding: 260,
            verticalPadding: 170
        },
        {
            id: 'lane-upstream-tier3',
            label: '上游多階供應',
            nodeFilter: (node) =>
                getSignedLevel(node) <= -3 && !isCompetitorDirection(node?.data?.relationshipDirection),
            laneClass: 'lane-upstream lane-upstream-tier3',
            minWidth: 420,
            minHeight: 200,
            horizontalPadding: 260,
            verticalPadding: 170
        },
        {
            id: 'lane-downstream-tier1',
            label: '下游一階客戶',
            nodeFilter: (node) =>
                getSignedLevel(node) === 1 && !isCompetitorDirection(node?.data?.relationshipDirection),
            laneClass: 'lane-downstream lane-downstream-tier1',
            minWidth: 420,
            minHeight: 200,
            horizontalPadding: 260,
            verticalPadding: 170
        },
        {
            id: 'lane-downstream-tier2',
            label: '下游二階客戶',
            nodeFilter: (node) =>
                getSignedLevel(node) === 2 && !isCompetitorDirection(node?.data?.relationshipDirection),
            laneClass: 'lane-downstream lane-downstream-tier2',
            minWidth: 420,
            minHeight: 200,
            horizontalPadding: 260,
            verticalPadding: 170
        },
        {
            id: 'lane-downstream-tier3',
            label: '下游多階客戶',
            nodeFilter: (node) =>
                getSignedLevel(node) >= 3 && !isCompetitorDirection(node?.data?.relationshipDirection),
            laneClass: 'lane-downstream lane-downstream-tier3',
            minWidth: 420,
            minHeight: 200,
            horizontalPadding: 260,
            verticalPadding: 170
        },
        {
            id: 'lane-competitor',
            label: '同業競爭',
            nodeFilter: (node) => isCompetitorDirection(node?.data?.relationshipDirection),
            laneClass: 'lane-competitor',
            minWidth: 440,
            minHeight: 220,
            horizontalPadding: 280,
            verticalPadding: 170
        }
    ];

    return laneDefinitions
        .map((laneConfig) => {
            const laneNodes = entityNodes.filter(laneConfig.nodeFilter);
            if (!laneNodes.length) {
                return null;
            }

            const bounds = computeBounds(laneNodes);
            return {
                data: {
                    id: laneConfig.id,
                    label: laneConfig.label,
                    width: Math.max(bounds.width + laneConfig.horizontalPadding, laneConfig.minWidth),
                    height: Math.max(bounds.height + laneConfig.verticalPadding, laneConfig.minHeight),
                    isVirtual: true
                },
                position: {
                    x: bounds.centerX,
                    y: bounds.centerY
                },
                classes: `lane ${laneConfig.laneClass}`
            };
        })
        .filter((element) => element !== null);
}

function getSignedLevel(node) {
    const signedLevel = Number(node?.data?.signedLevel);
    return Number.isFinite(signedLevel) ? signedLevel : 0;
}

function computeBounds(nodes) {
    const initialBounds = {
        minX: Number.POSITIVE_INFINITY,
        maxX: Number.NEGATIVE_INFINITY,
        minY: Number.POSITIVE_INFINITY,
        maxY: Number.NEGATIVE_INFINITY
    };

    const bounds = nodes.reduce((accumulator, node) => {
        const position = node.position || DEFAULT_POSITION;
        return {
            minX: Math.min(accumulator.minX, position.x),
            maxX: Math.max(accumulator.maxX, position.x),
            minY: Math.min(accumulator.minY, position.y),
            maxY: Math.max(accumulator.maxY, position.y)
        };
    }, initialBounds);

    return {
        centerX: (bounds.minX + bounds.maxX) / 2,
        centerY: (bounds.minY + bounds.maxY) / 2,
        width: bounds.maxX - bounds.minX,
        height: bounds.maxY - bounds.minY
    };
}

function buildNodeInsight(node) {
    if (!isBlank(node?.roleLabel) || !isBlank(node?.noteText)) {
        return {
            roleLabel: node.roleLabel || '關聯角色',
            noteText: node.noteText || 'AI 產生的供應鏈關係。'
        };
    }

    if (node.isRoot) {
        return {
            roleLabel: 'IC 設計原廠',
            noteText: '關鍵產品: 5G Modem、Wi-Fi 7 SoC、Snapdragon 平台'
        };
    }

    if (node.signedLevel < 0) {
        return {
            roleLabel: '上游製造與封測夥伴',
            noteText: '提供晶圓代工、封裝與測試能力。'
        };
    }

    if (isCompetitorNode(node)) {
        return {
            roleLabel: '同業競爭者',
            noteText: '與核心節點在關鍵產品線與市場上形成競爭。'
        };
    }

    if (node.signedLevel > 0) {
        const depth = Number(node.downstreamDepth);
        if (Number.isFinite(depth) && depth >= 2) {
            return {
                roleLabel: '終端採用客戶',
                noteText: '將方案導入企業網通、車聯網或電信場景。'
            };
        }
        return {
            roleLabel: '通路/ODM 系統整合',
            noteText: '負責供貨、FAE 支援與產品整機整合。'
        };
    }

    return {
        roleLabel: '關聯節點',
        noteText: '此節點與主供應鏈存在關聯。'
    };
}

function isBlank(value) {
    return value === null || value === undefined || String(value).trim() === '';
}

function isCompetitorNode(node) {
    return isCompetitorDirection(node?.relationshipDirection);
}

function isCompetitorDirection(direction) {
    return String(direction || '').toUpperCase() === COMPETITOR_DIRECTION;
}
