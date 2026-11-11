import { feedback } from '@smirea/feedback-engine/react';
import { useRef, useState, type FormEvent } from 'react';
import { Link } from 'react-router';
import { ListRow } from '../components/ListRow.tsx';
import { SummaryCard } from '../components/SummaryCard.tsx';
import { useStore } from '../store.ts';

export function ListsScreen() {
	const store = useStore();
	const dialog = useRef<HTMLDialogElement>(null);
	const [newListName, setNewListName] = useState('');

	function addList(event: FormEvent) {
		event.preventDefault();
		const name = newListName.trim();
		if (name) store.addList(name);
		setNewListName('');
		dialog.current?.close();
	}

	return (
		<>
			<title>Lists</title>
			<main
				className='screen lists'
				ref={feedback('ListsScreen', () => ({ isAddingList: dialog.current?.open ?? false, newListName }))}
			>
				<header className='bar'>
					<h1>Lists</h1>
					<button type='button' className='button' onClick={() => dialog.current?.showModal()}>
						New List
					</button>
				</header>

				<SummaryCard lists={store.lists} />

				<section aria-labelledby='my-lists'>
					<h2 id='my-lists'>My Lists</h2>
					<ul className='card'>
						{store.lists.map(list => (
							<li key={list.id}>
								<Link to={`/lists/${list.id}`}>
									<ListRow list={list} />
								</Link>
							</li>
						))}
					</ul>
				</section>
			</main>

			<dialog className='sheet' ref={dialog} aria-labelledby='new-list'>
				<form onSubmit={addList}>
					<h2 id='new-list'>New List</h2>
					<input
						className='field'
						value={newListName}
						onChange={event => setNewListName(event.target.value)}
						aria-label='Name'
						placeholder='Name'
					/>
					<div className='actions'>
						<button type='button' className='button' onClick={() => dialog.current?.close()}>
							Cancel
						</button>
						<button type='submit' className='button primary'>
							Add
						</button>
					</div>
				</form>
			</dialog>
		</>
	);
}
