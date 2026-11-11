import { feedback } from '@smirea/feedback-engine/react';
import { useState } from 'react';
import type { Priority, TodoItem } from '../store.ts';

const priorities: Priority[] = ['none', 'low', 'medium', 'high'];

export function TodoDetailDialog({
	item,
	onSave,
	onDelete,
	onClose,
}: {
	item: TodoItem;
	onSave: (item: TodoItem) => void;
	onDelete: () => void;
	onClose: () => void;
}) {
	const [draft, setDraft] = useState({ ...item });
	// The draft is state, which React keeps out of the props a capture reads, so the tag reports it.
	const tag = feedback('TodoDetailDialog', () => ({ item: draft }));
	return (
		<dialog
			className='sheet'
			aria-labelledby='details'
			onClose={onClose}
			ref={dialog => {
				tag(dialog);
				if (dialog && !dialog.open) dialog.showModal();
			}}
		>
			<form
				onSubmit={event => {
					event.preventDefault();
					onSave(draft);
				}}
			>
				<h2 id='details'>Details</h2>
				<input
					className='field'
					value={draft.title}
					onChange={event => setDraft({ ...draft, title: event.target.value })}
					aria-label='Title'
					placeholder='Title'
				/>
				<textarea
					className='field'
					value={draft.notes}
					onChange={event => setDraft({ ...draft, notes: event.target.value })}
					aria-label='Notes'
					placeholder='Notes'
					rows={3}
				></textarea>
				<label className='line'>
					Due date
					<input
						type='checkbox'
						checked={draft.due !== undefined}
						onChange={event =>
							setDraft({ ...draft, due: event.target.checked ? new Date().toISOString().slice(0, 10) : undefined })
						}
					/>
				</label>
				{draft.due !== undefined && (
					<label className='line'>
						Due{' '}
						<input
							className='field date'
							type='date'
							value={draft.due}
							onChange={event => setDraft({ ...draft, due: event.target.value })}
						/>
					</label>
				)}
				<label className='line'>
					Priority
					<select
						className='field select'
						value={draft.priority}
						onChange={event => setDraft({ ...draft, priority: event.target.value as Priority })}
					>
						{priorities.map(priority => (
							<option key={priority} value={priority}>
								{priority}
							</option>
						))}
					</select>
				</label>
				<button type='button' className='button danger' onClick={onDelete}>
					Delete Todo
				</button>
				<div className='actions'>
					<button type='button' className='button' onClick={onClose}>
						Cancel
					</button>
					<button type='submit' className='button primary'>
						Save
					</button>
				</div>
			</form>
		</dialog>
	);
}
