import { buildFilteredElements, buildStoryElements, computeNodePositions, FILTER_VALUES } from '../cmSupplyNetworkGraphUtils';

describe('cmSupplyNetworkGraphUtils', () => {
    const sampleNodes = [
        { id: 'root', label: 'Quincy', isRoot: true, signedLevel: 0, upstreamDepth: 0, downstreamDepth: 0 },
        { id: 'up1', label: 'TSMC', isRoot: false, signedLevel: -1, upstreamDepth: 1 },
        { id: 'up2', label: 'ASE', isRoot: false, signedLevel: -1, upstreamDepth: 1 },
        { id: 'down1', label: 'WNC', isRoot: false, signedLevel: 1, downstreamDepth: 1 }
    ];

    const sampleEdges = [
        { id: 'e1', sourceId: 'up1', targetId: 'root', relationType: 'Supplier' },
        { id: 'e2', sourceId: 'root', targetId: 'down1', relationType: 'Distributor' }
    ];

    it('computes positions based on signed level', () => {
        const positions = computeNodePositions(sampleNodes, 200, 150);
        expect(positions.root.y).toBe(0);
        expect(positions.up1.y).toBe(-150);
        expect(positions.down1.y).toBe(150);
        expect(positions.up1.x).not.toBe(positions.up2.x);
    });

    it('filters upstream nodes and edges', () => {
        const positions = computeNodePositions(sampleNodes);
        const filtered = buildFilteredElements(sampleNodes, sampleEdges, FILTER_VALUES.UPSTREAM, positions);
        const nodeIds = filtered.nodes.map((node) => node.data.id);

        expect(nodeIds).toContain('root');
        expect(nodeIds).toContain('up1');
        expect(nodeIds).toContain('up2');
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
        expect(nodeIds).not.toContain('up1');
        expect(filtered.edges).toHaveLength(1);
        expect(filtered.edges[0].data.id).toBe('e2');
    });

    it('returns all nodes for invalid filter value', () => {
        const positions = computeNodePositions(sampleNodes);
        const filtered = buildFilteredElements(sampleNodes, sampleEdges, 'invalid-filter', positions);

        expect(filtered.nodes).toHaveLength(4);
        expect(filtered.edges).toHaveLength(2);
    });

    it('builds annotated lane elements for story mode', () => {
        const positions = computeNodePositions(sampleNodes, 260, 200);
        const storyElements = buildStoryElements(sampleNodes, sampleEdges, FILTER_VALUES.ALL, positions);
        const storyNodeIds = storyElements.nodes.map((node) => node.data.id);

        expect(storyNodeIds).toEqual(expect.arrayContaining(['lane-upstream', 'lane-downstream']));
        expect(storyNodeIds).not.toContain('annotation-products');
        expect(storyNodeIds).not.toContain('annotation-role');
    });

    it('limits story lane and annotations when filtering upstream', () => {
        const positions = computeNodePositions(sampleNodes, 260, 200);
        const storyElements = buildStoryElements(sampleNodes, sampleEdges, FILTER_VALUES.UPSTREAM, positions);
        const storyNodeIds = storyElements.nodes.map((node) => node.data.id);
        const rootNode = storyElements.nodes.find((node) => node.data.id === 'root');

        expect(storyNodeIds).toContain('lane-upstream');
        expect(storyNodeIds).not.toContain('lane-downstream');
        expect(storyNodeIds).not.toContain('annotation-products');
        expect(storyNodeIds).not.toContain('annotation-role');
        expect(rootNode.data.roleLabel).toBe('IC 設計原廠');
        expect(rootNode.data.noteText).toContain('5G Modem');
    });
});
