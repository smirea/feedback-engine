import { feedback } from '@smirea/feedback-engine/react';
import { remaining, type TodoList } from '../store.ts';

export function ListRow({ list }: { list: TodoList }) {
	return (
		<span
			className='list-row'
			// The tag carries the component's own name, so its data replaces the whole `list` prop in a capture.
			ref={feedback('ListRow', () => ({ name: list.name, remaining: remaining(list), total: list.items.length }))}
		>
			<span className='dot' data-color={list.color} aria-hidden='true'></span>
			<span className='name'>{list.name}</span>
			<span className='count'>{remaining(list)}</span>
		</span>
	);
}
