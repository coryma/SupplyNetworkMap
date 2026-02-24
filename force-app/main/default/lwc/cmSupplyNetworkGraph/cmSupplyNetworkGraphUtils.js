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

export function computeNodePositions(nodes, horizontalSpacing = 220, verticalSpacing = 180) {
    const positions = {};
    const levelToNodes = new Map();

    nodes.forEach((node) => {
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

    return positions;
}

export function buildFilteredElements(nodes, edges, filterValue, positionsByNode = {}) {
    const activeFilter = normalizeFilter(filterValue);
    const allowedNodeIds = new Set();

    const nodeElements = (nodes || [])
        .filter((node) => shouldIncludeNode(node, activeFilter))
        .map((node) => {
            allowedNodeIds.add(node.id);
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

    const edgeElements = (edges || [])
        .filter((edge) => allowedNodeIds.has(edge.sourceId) && allowedNodeIds.has(edge.targetId))
        .map((edge, index) => ({
            data: {
                id: edge.id || `${edge.sourceId}-${edge.targetId}-${index}`,
                source: edge.sourceId,
                target: edge.targetId,
                relationType: edge.relationType || 'Related',
                relationshipDirection: edge.relationshipDirection || '',
                isVirtual: false
            },
            classes: getEdgeClasses(edge)
        }));

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
    return node.isRoot || node.signedLevel >= 0;
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
        if (String(node.relationshipDirection || '').toUpperCase() === 'COMPETITOR') {
            classes.push('tier-2', 'role-customer');
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
    const relationshipDirection = String(edge?.relationshipDirection || '').toUpperCase();
    const normalized = String(relationType || '').toLowerCase();
    if (relationshipDirection === 'UPSTREAM') {
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
    if (relationshipDirection === 'COMPETITOR' || normalized.includes('competitor')) {
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
            id: 'lane-upstream',
            label: '上游製造與封測',
            nodeFilter: (node) => Number(node.data.signedLevel) < 0,
            laneClass: 'lane-upstream'
        },
        {
            id: 'lane-downstream',
            label: '下游整合與終端客戶',
            nodeFilter: (node) => Number(node.data.signedLevel) > 0,
            laneClass: 'lane-downstream'
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
                    width: Math.max(bounds.width + 340, 560),
                    height: Math.max(bounds.height + 220, 260),
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
