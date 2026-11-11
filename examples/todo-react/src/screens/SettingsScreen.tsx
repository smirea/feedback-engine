import { feedback } from '@smirea/feedback-engine/react';
import { Link } from 'react-router';
import { useStore, type SortOrder } from '../store.ts';

const orders: SortOrder[] = ['manual', 'due date', 'priority'];

export function SettingsScreen() {
	const store = useStore();
	return (
		<main
			className='screen settings'
			ref={feedback('SettingsScreen', () => ({ showCompleted: store.showCompleted, sortOrder: store.sortOrder }))}
		>
			<title>Settings</title>
			<h1>Settings</h1>

			<section aria-labelledby='display'>
				<h2 id='display'>Display</h2>
				<div className='card'>
					<label className='line'>
						Show completed{' '}
						<input
							type='checkbox'
							role='switch'
							checked={store.showCompleted}
							onChange={event => store.change(() => (store.showCompleted = event.target.checked))}
						/>
					</label>
					<label className='line'>
						Sort by
						<select
							className='field'
							value={store.sortOrder}
							onChange={event => store.change(() => (store.sortOrder = event.target.value as SortOrder))}
						>
							{orders.map(order => (
								<option key={order} value={order}>
									{order}
								</option>
							))}
						</select>
					</label>
				</div>
			</section>

			<section aria-labelledby='feedback'>
				<h2 id='feedback'>Feedback</h2>
				<div className='card'>
					<div className='line'>
						<button type='button' className='button' onClick={() => globalThis.__feedbackEngine?.countdown()}>
							Send Feedback
						</button>
					</div>
					<p className='line muted'>
						Starts in 5 seconds, so open the screen you mean. With a mouse, Alt+Meta+click anything.
					</p>
				</div>
			</section>

			<section aria-labelledby='examples'>
				<h2 id='examples'>Examples</h2>
				<div className='card'>
					<Link className='line' to='/timeline'>
						Timeline
					</Link>
					<Link className='line' to='/catalog'>
						Exercise Catalog
					</Link>
					<Link className='line' to='/media'>
						Media
					</Link>
				</div>
			</section>

			<section aria-labelledby='about'>
				<h2 id='about'>About</h2>
				<div className='card'>
					<p className='line'>
						Version <span className='muted'>1.0</span>
					</p>
				</div>
			</section>
		</main>
	);
}
