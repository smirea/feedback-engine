import { feedback } from '@smirea/feedback-engine/react';
import { useState, type FormEvent } from 'react';
import { useParams } from 'react-router';
import { TodoDetailDialog } from '../components/TodoDetailDialog.tsx';
import { TodoRow } from '../components/TodoRow.tsx';
import { remaining, useStore, type SortOrder, type TodoItem } from '../store.ts';

type Filter = 'All' | 'Open' | 'Done';
const filters: Filter[] = ['All', 'Open', 'Done'];
const ranks = { high: 0, medium: 1, low: 2, none: 3 };
const orders: SortOrder[] = ['manual', 'due date', 'priority'];

export function ListDetailScreen() {
	const store = useStore();
	const list = store.list(useParams().id ?? '');
	const [filter, setFilter] = useState<Filter>('All');
	const [editing, setEditing] = useState<TodoItem>();
	const [newTitle, setNewTitle] = useState('');

	if (!list) {
		return (
			<main className='screen'>
				<h1>No such list</h1>
			</main>
		);
	}

	const shown = list.items.filter(item =>
		filter === 'All' ? store.showCompleted || !item.isDone : filter === 'Done' ? item.isDone : !item.isDone,
	);
	const visible =
		store.sortOrder === 'due date'
			? shown.toSorted((a, b) => (a.due ?? '9').localeCompare(b.due ?? '9'))
			: store.sortOrder === 'priority'
				? shown.toSorted((a, b) => ranks[a.priority] - ranks[b.priority])
				: shown;
	const done = list.items.length - remaining(list);

	function add(event: FormEvent) {
		event.preventDefault();
		if (list && newTitle.trim()) store.add(newTitle.trim(), list.id);
		setNewTitle('');
	}

	return (
		<>
			<title>{list.name}</title>
			<main className='screen detail' ref={feedback('ListDetailScreen', () => ({ listID: list.id, filter, editing }))}>
				<header className='bar'>
					<h1>{list.name}</h1>
					<span className='tools'>
						<button type='button' className='button' popoverTarget='sort-menu'>
							Sort
						</button>
						<button
							type='button'
							className='button'
							onClick={() => store.change(() => list.items.forEach(item => (item.isDone = true)))}
						>
							Mark All Done
						</button>
					</span>
				</header>

				<section className='progress card' ref={feedback('ProgressHeader', () => ({ done, total: list.items.length }))}>
					<strong className='percent'>{list.items.length ? Math.round((done / list.items.length) * 100) : 0}%</strong>
					<span className='counts'>
						<strong>
							{done} of {list.items.length} done
						</strong>
						<br />
						<span className='muted'>{remaining(list) === 0 ? 'All clear' : `${remaining(list)} to go`}</span>
					</span>
				</section>

				<label className='filter'>
					<span className='muted'>Filter</span>
					<select className='field' value={filter} onChange={event => setFilter(event.target.value as Filter)}>
						{filters.map(name => (
							<option key={name}>{name}</option>
						))}
					</select>
				</label>

				<ul className='card'>
					{visible.map(item => (
						<TodoRow
							key={item.id}
							item={item}
							onToggle={() => store.change(() => (item.isDone = !item.isDone))}
							onEdit={() => setEditing(item)}
						/>
					))}
				</ul>

				<form className='add card' onSubmit={add} ref={feedback('AddTodoBar', () => ({ title: newTitle }))}>
					<input
						className='field'
						value={newTitle}
						onChange={event => setNewTitle(event.target.value)}
						aria-label='New todo'
						placeholder='New todo'
					/>
					<button type='submit' className='button primary' disabled={!newTitle.trim()}>
						Add
					</button>
				</form>
			</main>

			<div
				id='sort-menu'
				className='menu'
				popover='auto'
				role='menu'
				aria-label='Sort'
				ref={feedback('SortMenu', () => ({ sortOrder: store.sortOrder }))}
			>
				{orders.map(order => (
					<button
						key={order}
						type='button'
						role='menuitemradio'
						aria-checked={store.sortOrder === order}
						onClick={() => store.change(() => (store.sortOrder = order))}
					>
						{order}
					</button>
				))}
			</div>

			{editing && (
				<TodoDetailDialog
					item={editing}
					onClose={() => setEditing(undefined)}
					onSave={changed => {
						store.update(changed, list.id);
						setEditing(undefined);
					}}
					onDelete={() => {
						store.delete(editing.id, list.id);
						setEditing(undefined);
					}}
				/>
			)}
		</>
	);
}
