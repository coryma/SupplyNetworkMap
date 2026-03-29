import { buildFilteredElements, buildStoryElements, computeNodePositions, FILTER_VALUES } from '../cmSupplyNetworkGraphUtils';

describe('cmSupplyNetworkGraphUtils', () => {
    const sampleNodes = [
        { id: 'root', label: 'Quincy', isRoot: true, signedLevel: 0, upstreamDepth: 0, downstreamDepth: 0 },
        { id: 'up1', label: 'TSMC', isRoot: false, signedLevel: -1, upstreamDepth: 1 },
        { id: 'up2', label: 'ASE', isRoot: false, signedLevel: -1, upstreamDepth: 1 },
        { id: 'down1', label: 'WNC', isRoot: false, signedLevel: 1, downstreamDepth: 1, relationshipDirection: 'DOWNSTREAM' },
        {
            id: 'comp1',
            label: 'Amkor',
            isRoot: false,
            signedLevel: 2,
            downstreamDepth: 2,
            relationshipDirection: 'COMPETITOR'
        }
    ];

    const sampleEdges = [
        { id: 'e1', sourceId: 'up1', targetId: 'root', relationType: 'Supplier' },
        { id: 'e2', sourceId: 'root', targetId: 'down1', relationType: 'Distributor' },
        { id: 'e3', sourceId: 'root', targetId: 'comp1', relationType: 'Direct Competitor', relationshipDirection: 'COMPETITOR' }
    ];

    it('computes positions based on signed level', () => {
        const positions = computeNodePositions(sampleNodes, 200, 150);
        expect(positions.root.y).toBe(0);
        expect(positions.up1.y).toBe(-150);
        expect(positions.down1.y).toBe(150);
        expect(positions.up1.x).not.toBe(positions.up2.x);
        expect(positions.comp1.x).toBeGreaterThan(positions.root.x);
    });

    it('filters upstream nodes and edges', () => {
        const positions = computeNodePositions(sampleNodes);
        const filtered = buildFilteredElements(sampleNodes, sampleEdges, FILTER_VALUES.UPSTREAM, positions);
        const nodeIds = filtered.nodes.map((node) => node.data.id);

        expect(nodeIds).toContain('root');
        expect(nodeIds).toContain('up1');
        expect(nodeIds).not.toContain('up2');
        expect(nodeIds).not.toContain('down1');
        expect(filtered.edges).toHaveLength(1);
        expect(filtered.edges[0].data.id).toBe('e1');
    });

    it('filters downstream nodes and edges', () => {
        const positions = computeNodePositions(sampleNodes);
        const filtered = buildFilteredElements(sampleNodes, sampleEdges, FILTER_VALUES.DOWNSTREAM, positions);
        const nodeIds = filtered.nodes.map((node) => node.data.id);

        expect(nodeIds).toContain('root');
        expect(nodeIds).toContain('down1');
        expect(nodeIds).not.toContain('comp1');
        expect(nodeIds).not.toContain('up1');
        expect(filtered.edges).toHaveLength(1);
        expect(filtered.edges[0].data.id).toBe('e2');
    });

    it('returns all nodes for invalid filter value', () => {
        const positions = computeNodePositions(sampleNodes);
        const filtered = buildFilteredElements(sampleNodes, sampleEdges, 'invalid-filter', positions);

        expect(filtered.nodes).toHaveLength(4);
        expect(filtered.edges).toHaveLength(3);
    });

    it('always marks WNC nodes with dedicated class', () => {
        const positions = computeNodePositions(sampleNodes);
        const filtered = buildFilteredElements(sampleNodes, sampleEdges, FILTER_VALUES.ALL, positions);
        const wncNode = filtered.nodes.find((node) => node.data.id === 'down1');

        expect(wncNode).toBeDefined();
        expect(wncNode.classes.split(' ')).toContain('wnc-focus');
    });

    it('builds annotated lane elements for story mode', () => {
        const positions = computeNodePositions(sampleNodes, 260, 200);
        const storyElements = buildStoryElements(sampleNodes, sampleEdges, FILTER_VALUES.ALL, positions);
        const storyNodeIds = storyElements.nodes.map((node) => node.data.id);

        expect(storyNodeIds).toEqual(
            expect.arrayContaining(['lane-upstream-tier1', 'lane-downstream-tier1', 'lane-competitor'])
        );
        expect(storyNodeIds).not.toContain('lane-upstream-tier2');
        expect(storyNodeIds).not.toContain('lane-downstream-tier2');
        expect(storyNodeIds).not.toContain('annotation-products');
        expect(storyNodeIds).not.toContain('annotation-role');
    });

    it('limits story lane and annotations when filtering upstream', () => {
        const positions = computeNodePositions(sampleNodes, 260, 200);
        const storyElements = buildStoryElements(sampleNodes, sampleEdges, FILTER_VALUES.UPSTREAM, positions);
        const storyNodeIds = storyElements.nodes.map((node) => node.data.id);
        const rootNode = storyElements.nodes.find((node) => node.data.id === 'root');

        expect(storyNodeIds).toContain('lane-upstream-tier1');
        expect(storyNodeIds).not.toContain('lane-downstream-tier1');
        expect(storyNodeIds).not.toContain('lane-competitor');
        expect(storyNodeIds).not.toContain('annotation-products');
        expect(storyNodeIds).not.toContain('annotation-role');
        expect(rootNode.data.roleLabel).toBe('IC 設計原廠');
        expect(rootNode.data.noteText).toContain('5G Modem');
    });

    it('supports up to 7 virtual lanes when multi-tier data exists', () => {
        const multiTierNodes = [
            { id: 'root', label: 'Root', isRoot: true, signedLevel: 0, relationshipDirection: 'ROOT' },
            { id: 'u1', label: 'U1', isRoot: false, signedLevel: -1, relationshipDirection: 'UPSTREAM' },
            { id: 'u2', label: 'U2', isRoot: false, signedLevel: -2, relationshipDirection: 'UPSTREAM' },
            { id: 'u3', label: 'U3', isRoot: false, signedLevel: -3, relationshipDirection: 'UPSTREAM' },
            { id: 'd1', label: 'D1', isRoot: false, signedLevel: 1, relationshipDirection: 'DOWNSTREAM' },
            { id: 'd2', label: 'D2', isRoot: false, signedLevel: 2, relationshipDirection: 'DOWNSTREAM' },
            { id: 'd3', label: 'D3', isRoot: false, signedLevel: 3, relationshipDirection: 'DOWNSTREAM' },
            { id: 'c1', label: 'C1', isRoot: false, signedLevel: 2, relationshipDirection: 'COMPETITOR' }
        ];
        const multiTierEdges = [
            { id: 'u1-root', sourceId: 'u1', targetId: 'root', edgeCategory: 'UPSTREAM', relationType: 'Supplier' },
            { id: 'u2-u1', sourceId: 'u2', targetId: 'u1', edgeCategory: 'INDIRECT_PATH', relationType: 'Component Supply' },
            { id: 'u3-u2', sourceId: 'u3', targetId: 'u2', edgeCategory: 'INDIRECT_PATH', relationType: 'Component Supply' },
            { id: 'root-d1', sourceId: 'root', targetId: 'd1', edgeCategory: 'DOWNSTREAM', relationType: 'Customer' },
            { id: 'd1-d2', sourceId: 'd1', targetId: 'd2', edgeCategory: 'INDIRECT_PATH', relationType: 'Channel Partner' },
            { id: 'd2-d3', sourceId: 'd2', targetId: 'd3', edgeCategory: 'INDIRECT_PATH', relationType: 'Channel Partner' },
            {
                id: 'root-c1',
                sourceId: 'root',
                targetId: 'c1',
                edgeCategory: 'COMPETITOR',
                relationshipDirection: 'COMPETITOR',
                relationType: 'Direct Competitor'
            }
        ];
        const positions = computeNodePositions(multiTierNodes, 260, 200);
        const storyElements = buildStoryElements(multiTierNodes, multiTierEdges, FILTER_VALUES.ALL, positions);
        const virtualLaneIds = storyElements.nodes
            .filter((node) => node.data.isVirtual === true)
            .map((node) => node.data.id);

        expect(virtualLaneIds).toEqual(
            expect.arrayContaining([
                'lane-upstream-tier1',
                'lane-upstream-tier2',
                'lane-upstream-tier3',
                'lane-downstream-tier1',
                'lane-downstream-tier2',
                'lane-downstream-tier3',
                'lane-competitor'
            ])
        );
        expect(virtualLaneIds).toHaveLength(7);
    });

    it('keeps indirect-only connected nodes and renders indirect edges', () => {
        const nodes = [
            { id: 'root', label: 'Root', isRoot: true, signedLevel: 0, relationshipDirection: 'ROOT' },
            { id: 'mid', label: 'Mid', isRoot: false, signedLevel: 1, relationshipDirection: 'DOWNSTREAM' },
            { id: 'upIndirect', label: 'Up Indirect', isRoot: false, signedLevel: -2, relationshipDirection: 'UPSTREAM' }
        ];
        const edges = [
            {
                id: 'direct',
                sourceId: 'root',
                targetId: 'mid',
                relationType: 'Customer',
                edgeCategory: 'DOWNSTREAM'
            },
            {
                id: 'indirect',
                sourceId: 'upIndirect',
                targetId: 'mid',
                relationType: 'Component Supply',
                edgeCategory: 'INDIRECT_PATH'
            }
        ];

        const positions = computeNodePositions(nodes, 220, 180);
        const filtered = buildFilteredElements(nodes, edges, FILTER_VALUES.ALL, positions);
        const nodeIds = filtered.nodes.map((node) => node.data.id);
        const edgeIds = filtered.edges.map((edge) => edge.data.id);

        expect(nodeIds).toEqual(expect.arrayContaining(['root', 'mid', 'upIndirect']));
        expect(edgeIds).toEqual(['direct', 'indirect']);
    });
});
