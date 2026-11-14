import { expect, test } from 'bun:test';
import fixture from '../../../../spec/fixtures/capture.json';
import { Annotations, hitTest, place, report, similar, taskTitle, type Capture, type Node } from './index.ts';

test('the shared fixture gives the same answers as on iOS', () => {
	const nodes = fixture.nodes as Node[];
	const capture: Capture = { ...fixture, nodes, date: new Date(fixture.captured) };
	const annotations = new Annotations();
	for (const step of fixture.annotate) {
		if (step.submit !== undefined) annotations.submit(step.submit, step.on!);
		else if (step.reserve) annotations.reserve();
		else annotations.reference(nodes[step.reference!]!);
	}
	const { expected } = fixture;

	expect(fixture.hitTests.map(([x, y]) => hitTest(capture, { x: x!, y: y! }))).toEqual(expected.hitTests);
	expect(fixture.similar.map(id => similar(capture, id))).toEqual(expected.similar);
	expect(nodes.map(node => annotations.colorIndex(node.id))).toEqual(expected.colorIndexes);
	expect(annotations.segments(fixture.segments).map(segment => [segment.text, segment.reference?.number ?? 0])).toEqual(
		expected.segments,
	);
	expect(JSON.parse(JSON.stringify(report(capture, annotations)))).toEqual(expected.report);
	expect(
		fixture.cards.map(cards =>
			place(cards.targets, cards.heights, cards.screen, cards.environmentHeight, cards.viewport, cards.references),
		),
	).toEqual(expected.cards);
	const name = taskTitle(capture, annotations.items);
	expect({
		placeholder: name.placeholder,
		prompt: name.prompt,
		summarized: name.summarized(fixture.summary),
	}).toEqual(expected.taskTitle);
});
