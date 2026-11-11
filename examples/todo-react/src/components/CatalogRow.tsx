import { feedback } from '@smirea/feedback-engine/react';

export function CatalogRow({ name, detail }: { name: string; detail: string }) {
	const initials = name
		.split(' ')
		.slice(0, 2)
		.map(word => word[0])
		.join('');
	return (
		<li className='catalog-row'>
			<span className='initials' aria-hidden='true' ref={feedback('Initials', () => ({ name }))}>
				{initials}
			</span>
			<span className='text'>
				<strong>{name}</strong>
				<span className='muted'>{detail}</span>
			</span>
		</li>
	);
}
