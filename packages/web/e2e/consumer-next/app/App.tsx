'use client';

import { feedback } from '@smirea/feedback-engine/react';
import { Component, forwardRef, memo, useEffect, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';

const Card = memo(function Card({ title, icon, children }: { title: string; icon: ReactNode; children: ReactNode }) {
	return (
		<section aria-label={title}>
			{icon}
			{children}
		</section>
	);
});

const Field = forwardRef<HTMLInputElement, { label: string }>(({ label }, ref) => (
	<input ref={ref} aria-label={label} />
));

const Pair = ({ first, second }: { first: string; second: string }) => (
	<>
		<p>{first}</p>
		<p>{second}</p>
	</>
);

class Legend extends Component<{ note: string }> {
	override render() {
		return <small>{this.props.note}</small>;
	}
}

function Icon() {
	return <i aria-hidden='true'></i>;
}

function Toast({ message }: { message: string }) {
	// The server has no document to draw into.
	const [body, setBody] = useState<HTMLElement>();
	useEffect(() => setBody(document.body), []);
	return body ? createPortal(<output>{message}</output>, body) : null;
}

/** Passes its children through, as a provider does. It draws nothing of its own. */
function Theme({ children }: { children: ReactNode }) {
	return children;
}

export default function App() {
	const [count, setCount] = useState(3);
	return (
		<Theme>
			<main ref={feedback('App', () => ({ count }))}>
				<h1>Consumer</h1>
				<Card title='Counter' icon={<Icon />}>
					<button onClick={() => setCount(count + 1)}>Count {count}</button>
				</Card>
				<Field label='Name' />
				<Pair first='One' second='Two' />
				<Legend note='Legend' />
				<div ref={feedback('Footer')}>Footer</div>
				<Toast message='Saved' />
			</main>
		</Theme>
	);
}
