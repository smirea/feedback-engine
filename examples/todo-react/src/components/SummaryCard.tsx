import { remaining, type TodoList } from '../store.ts';
import { Stat } from './Stat.tsx';

export function SummaryCard({ lists }: { lists: TodoList[] }) {
	const today = new Date().toISOString().slice(0, 10);
	const open = lists.reduce((sum, list) => sum + remaining(list), 0);
	const dueToday = lists.flatMap(list => list.items).filter(item => !item.isDone && item.due === today).length;
	return (
		<section className='summary card' aria-label='Summary'>
			<Stat value={open} label='Open' />
			<Stat value={dueToday} label='Due today' />
			<Stat value={lists.length} label='Lists' />
		</section>
	);
}
