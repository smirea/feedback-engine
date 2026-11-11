import type { TodoItem } from '../store.ts';

export function TodoRow({ item, onToggle, onEdit }: { item: TodoItem; onToggle: () => void; onEdit: () => void }) {
	return (
		<li className='todo'>
			<button
				type='button'
				className={item.isDone ? 'check done' : 'check'}
				aria-label={item.isDone ? 'Mark not done' : 'Mark done'}
				onClick={onToggle}
			></button>
			<button type='button' className='body' onClick={onEdit}>
				<span className={item.isDone ? 'title done' : 'title'}>{item.title}</span>
				{item.notes && <span className='muted'>{item.notes}</span>}
			</button>
			{item.due && <span className='muted'>{item.due.slice(5)}</span>}
			{item.priority !== 'none' && (
				<span className='flag' data-priority={item.priority} role='img' aria-label={`${item.priority} priority`}></span>
			)}
		</li>
	);
}
