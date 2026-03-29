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
const DEFAULT_GRAPH_LABELS = Object.freeze({
    edgeFallbackRelation: 'Related',
    laneLabels: {
        upstreamTier1: 'Tier 1 Upstream Suppliers',
        upstreamTier2: 'Tier 2 Upstream Suppliers',
        upstreamTier3: 'Multi-tier Upstream Suppliers',
        downstreamTier1: 'Tier 1 Downstream Customers',
        downstreamTier2: 'Tier 2 Downstream Customers',
        downstreamTier3: 'Multi-tier Downstream Customers',
        competitor: 'Competitors'
    },
    nodeInsights: {
        defaultRole: 'Related Role',
        defaultNote: 'AI-generated supply chain relationship.',
        rootRole: 'IC Design Company',
        rootNote: 'Key products: 5G Modem, Wi-Fi 7 SoC, Snapdragon platform',
        upstreamRole: 'Upstream manufacturing and OSAT partners',
        upstreamNote: 'Provides foundry, packaging, and test capabilities.',
        competitorRole: 'Competitor',
        competitorNote: 'Competes with the core node across key product lines and markets.',
        downstreamCustomerRole: 'End-customer adopter',
        downstreamCustomerNote: 'Deploys the solution into enterprise networking, automotive, or telecom scenarios.',
        downstreamChannelRole: 'Channel / ODM integrator',
        downstreamChannelNote: 'Handles fulfillment, FAE support, and full-system integration.',
        relatedNodeRole: 'Related Node',
        relatedNodeNote: 'This node is connected to the main supply chain.'
    }
});

function resolveGraphLabels(labels = {}) {
    return {
        edgeFallbackRelation:
            labels?.edgeFallbackRelation || DEFAULT_GRAPH_LABELS.edgeFallbackRelation,
        laneLabels: {
            ...DEFAULT_GRAPH_LABELS.laneLabels,
            ...(labels?.laneLabels || {})
        },
        nodeInsights: {
            ...DEFAULT_GRAPH_LABELS.nodeInsights,
            ...(labels?.nodeInsights || {})
        }
    };
}

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

export function buildFilteredElements(
    nodes,
    edges,
    filterValue,
    positionsByNode = {},
    focusContext = {},
    labels = {}
) {
    const activeFilter = normalizeFilter(filterValue);
    const focusMatcher = buildFocusMatcher(focusContext);
    const graphLabels = resolveGraphLabels(labels);
    const candidateNodeElements = (nodes || [])
        .filter((node) => shouldIncludeNode(node, activeFilter))
        .map((node) => {
            const nodeInsight = buildNodeInsight(node, graphLabels.nodeInsights);
            const isFocusCompany = isFocusCompanyNode(node, focusMatcher);
            return {
                data: {
                    id: node.id,
                    label: node.label,
                    accountId: node.accountId || null,
                    isFocusCompany,
                    companyDomain: node.companyDomain || '',
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
                classes: getNodeClasses(node, isFocusCompany)
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
                relationType: edge.relationType || graphLabels.edgeFallbackRelation,
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

export function buildStoryElements(
    nodes,
    edges,
    filterValue,
    positionsByNode = {},
    focusContext = {},
    labels = {}
) {
    const graphLabels = resolveGraphLabels(labels);
    const hasProvidedPositions = Object.keys(positionsByNode || {}).length > 0;
    const basePositions = hasProvidedPositions ? positionsByNode : computeNodePositions(nodes, 260, 200);
    const coreElements = buildFilteredElements(
        nodes,
        edges,
        filterValue,
        basePositions,
        focusContext,
        graphLabels
    );

    if (!coreElements.nodes.length) {
        return coreElements;
    }

    const laneElements = buildLaneElements(coreElements.nodes, graphLabels.laneLabels);

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

function getNodeClasses(node, isFocusCompany) {
    const classes = ['entity', 'interactive'];
    if (node.isRoot) {
        classes.push('root', 'role-design');
    } else if (node.signedLevel < 0) {
        classes.push('upstream', 'role-manufacturing');
    } else if (node.signedLevel > 0) {
        classes.push('downstream');
        if (isCompetitorNode(node)) {
            classes.push('competitor', 'role-competitor');
        } else {
            const depth = Number(node.downstreamDepth);
            if (Number.isFinite(depth) && depth >= 2) {
                classes.push('tier-2', 'role-customer');
            } else {
                classes.push('tier-1', 'role-channel');
            }
        }
    } else {
        classes.push('neutral');
    }

    if (isFocusCompany) {
        classes.push('wnc-focus', 'focus-company');
    }

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

function buildLaneElements(entityNodes, laneLabels = DEFAULT_GRAPH_LABELS.laneLabels) {
    const laneDefinitions = [
        {
            id: 'lane-upstream-tier1',
            label: laneLabels.upstreamTier1,
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
            label: laneLabels.upstreamTier2,
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
            label: laneLabels.upstreamTier3,
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
            label: laneLabels.downstreamTier1,
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
            label: laneLabels.downstreamTier2,
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
            label: laneLabels.downstreamTier3,
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
            label: laneLabels.competitor,
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

function buildNodeInsight(node, nodeInsightLabels = DEFAULT_GRAPH_LABELS.nodeInsights) {
    if (!isBlank(node?.roleLabel) || !isBlank(node?.noteText)) {
        return {
            roleLabel: node.roleLabel || nodeInsightLabels.defaultRole,
            noteText: node.noteText || nodeInsightLabels.defaultNote
        };
    }

    if (node.isRoot) {
        return {
            roleLabel: nodeInsightLabels.rootRole,
            noteText: nodeInsightLabels.rootNote
        };
    }

    if (node.signedLevel < 0) {
        return {
            roleLabel: nodeInsightLabels.upstreamRole,
            noteText: nodeInsightLabels.upstreamNote
        };
    }

    if (isCompetitorNode(node)) {
        return {
            roleLabel: nodeInsightLabels.competitorRole,
            noteText: nodeInsightLabels.competitorNote
        };
    }

    if (node.signedLevel > 0) {
        const depth = Number(node.downstreamDepth);
        if (Number.isFinite(depth) && depth >= 2) {
            return {
                roleLabel: nodeInsightLabels.downstreamCustomerRole,
                noteText: nodeInsightLabels.downstreamCustomerNote
            };
        }
        return {
            roleLabel: nodeInsightLabels.downstreamChannelRole,
            noteText: nodeInsightLabels.downstreamChannelNote
        };
    }

    return {
        roleLabel: nodeInsightLabels.relatedNodeRole,
        noteText: nodeInsightLabels.relatedNodeNote
    };
}

function isBlank(value) {
    return value === null || value === undefined || String(value).trim() === '';
}

function buildFocusMatcher(focusContext) {
    const exactNameCandidates = new Set();
    const exactCompactNameCandidates = new Set();
    const aliasNameCandidates = new Set();
    const aliasCompactNameCandidates = new Set();
    const domainCandidates = new Set();
    addExactNameCandidate(
        exactNameCandidates,
        exactCompactNameCandidates,
        focusContext?.focusCompanyName
    );
    addExactNameCandidate(
        exactNameCandidates,
        exactCompactNameCandidates,
        focusContext?.impactFocusCompanyName
    );
    addAliasCandidate(
        aliasNameCandidates,
        aliasCompactNameCandidates,
        focusContext?.focusCompanyAlias
    );
    addDomainCandidate(domainCandidates, focusContext?.focusCompanyDomain);

    return {
        exactNameCandidates,
        exactCompactNameCandidates,
        aliasNameCandidates,
        aliasCompactNameCandidates,
        domainCandidates,
        hasCandidates:
            exactNameCandidates.size > 0 ||
            exactCompactNameCandidates.size > 0 ||
            aliasNameCandidates.size > 0 ||
            aliasCompactNameCandidates.size > 0 ||
            domainCandidates.size > 0
    };
}

function addExactNameCandidate(nameCandidates, compactNameCandidates, rawName) {
    const normalized = normalizeNodeLabel(rawName);
    if (!normalized) {
        return;
    }
    nameCandidates.add(normalized);
    const compactNormalized = toCompactLabel(normalized);
    if (compactNormalized) {
        compactNameCandidates.add(compactNormalized);
    }
}

function addAliasCandidate(nameCandidates, compactNameCandidates, rawAlias) {
    const normalized = normalizeNodeLabel(rawAlias);
    if (!normalized) {
        return;
    }
    nameCandidates.add(normalized);
    const compactNormalized = toCompactLabel(normalized);
    if (compactNormalized) {
        compactNameCandidates.add(compactNormalized);
    }
}

function addDomainCandidate(domainCandidates, rawDomain) {
    const normalized = normalizeDomain(rawDomain);
    if (normalized) {
        domainCandidates.add(normalized);
    }
}

function isFocusCompanyNode(node, focusMatcher) {
    if (!node || !focusMatcher?.hasCandidates) {
        return false;
    }

    const nodeDomain = normalizeDomain(node.companyDomain);
    if (nodeDomain && focusMatcher.domainCandidates.has(nodeDomain)) {
        return true;
    }

    const normalizedLabel = normalizeNodeLabel(node?.label);
    const compactLabel = toCompactLabel(normalizedLabel);
    if (matchesExactNameCandidates(normalizedLabel, compactLabel, focusMatcher)) {
        return true;
    }
    if (matchesAliasCandidates(normalizedLabel, compactLabel, focusMatcher)) {
        return true;
    }

    const normalizedAccountType = normalizeNodeLabel(node?.accountType);
    const compactAccountType = toCompactLabel(normalizedAccountType);
    if (matchesExactNameCandidates(normalizedAccountType, compactAccountType, focusMatcher)) {
        return true;
    }
    return matchesAliasCandidates(
        normalizedAccountType,
        compactAccountType,
        focusMatcher
    );
}

function matchesExactNameCandidates(normalizedValue, compactValue, focusMatcher) {
    if (!normalizedValue && !compactValue) {
        return false;
    }

    if (
        normalizedValue &&
        focusMatcher.exactNameCandidates.has(normalizedValue)
    ) {
        return true;
    }

    return (
        !!compactValue &&
        focusMatcher.exactCompactNameCandidates.has(compactValue)
    );
}

function matchesAliasCandidates(normalizedValue, compactValue, focusMatcher) {
    if (!normalizedValue && !compactValue) {
        return false;
    }

    if (normalizedValue) {
        for (const aliasCandidate of focusMatcher.aliasNameCandidates) {
            if (normalizedValue === aliasCandidate) {
                return true;
            }
            if (
                aliasCandidate.length >= 2 &&
                normalizedValue.includes(aliasCandidate)
            ) {
                return true;
            }
        }
    }

    if (compactValue) {
        for (const compactAliasCandidate of focusMatcher.aliasCompactNameCandidates) {
            if (compactValue === compactAliasCandidate) {
                return true;
            }
            if (
                compactAliasCandidate.length >= 2 &&
                compactValue.includes(compactAliasCandidate)
            ) {
                return true;
            }
        }
    }

    return false;
}

function normalizeDomain(rawValue) {
    const normalized = String(rawValue || '')
        .trim()
        .toLowerCase()
        .replace(/^https?:\/\//, '')
        .replace(/^www\./, '');
    if (!normalized) {
        return '';
    }
    const slashIndex = normalized.indexOf('/');
    return slashIndex > -1 ? normalized.slice(0, slashIndex) : normalized;
}

function toCompactLabel(rawValue) {
    if (!rawValue) {
        return '';
    }
    return String(rawValue)
        .trim()
        .toLowerCase()
        .replace(/[\s/|,;:()（）\-_.]+/g, '');
}

function hasCjkCharacters(rawValue) {
    return /[\u3400-\u9FFF]/.test(String(rawValue || ''));
}

function normalizeNodeLabel(label) {
    return String(label || '')
        .trim()
        .toLowerCase();
}

function normalizeNodeId(value) {
    return String(value || '')
        .trim()
        .toLowerCase();
}

function isCompetitorNode(node) {
    return isCompetitorDirection(node?.relationshipDirection);
}

function isCompetitorDirection(direction) {
    return String(direction || '').toUpperCase() === COMPETITOR_DIRECTION;
}