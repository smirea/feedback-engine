import { feedback } from '@smirea/feedback-engine/react';
import { useState } from 'react';
import { CatalogRow } from '../components/CatalogRow.tsx';

const sections = ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms'];
const movements = ['Bench Press', 'Incline Press', 'Cable Fly', 'Push Up', 'Dip', 'Chest Press'];
const kinds = ['All', 'Barbell', 'Dumbbell', 'Machine'];
const featured = Array.from({ length: 12 }, (_, index) => `Plan ${index + 1}`);

export function CatalogScreen() {
	const [query, setQuery] = useState('');
	const [equipment, setEquipment] = useState('All');
	const shown = movements.filter(movement => movement.toLowerCase().includes(query.toLowerCase()));
	return (
		<main className='screen catalog' ref={feedback('CatalogScreen', () => ({ query, equipment }))}>
			<title>Catalog</title>
			<h1>Catalog</h1>
			<input
				className='field'
				type='search'
				value={query}
				onChange={event => setQuery(event.target.value)}
				aria-label='Search'
				placeholder='Search'
			/>
			<div className='picker' role='radiogroup' aria-label='Equipment'>
				{kinds.map(kind => (
					<button
						key={kind}
						type='button'
						className='button'
						role='radio'
						aria-checked={equipment === kind}
						onClick={() => setEquipment(kind)}
					>
						{kind}
					</button>
				))}
			</div>
			<div className='featured' ref={feedback('Featured')}>
				{featured.map(plan => (
					<span key={plan} className='plan'>
						{plan}
					</span>
				))}
			</div>
			{sections.map(section => (
				<section key={section} aria-label={section}>
					<header className='bar'>
						<h2>{section}</h2>
						<button type='button' className='more'>
							See {section.length * 7} More
						</button>
					</header>
					<ul className='card'>
						{shown.map(movement => (
							<CatalogRow
								key={movement}
								name={movement}
								detail={`${section} · ${equipment === 'All' ? 'Barbell' : equipment}`}
							/>
						))}
					</ul>
				</section>
			))}
		</main>
	);
}
