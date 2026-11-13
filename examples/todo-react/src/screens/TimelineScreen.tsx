import { feedback } from '@stefan.inc/feedback-engine/react';

const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const sessions = ['Warm-up', 'Squat', 'Bench press', 'Row', 'Overhead press', 'Deadlift', 'Pull-up', 'Core', 'Stretch'];

export function TimelineScreen() {
	return (
		<main className='screen timeline'>
			<title>Timeline</title>
			<h1>Timeline</h1>
			{days.map(day => (
				<section key={day} className='day card'>
					<header className='pinned' ref={feedback('DayHeader', () => ({ day, count: sessions.length }))}>
						<strong>{day}</strong>
						<span className='muted'>{sessions.length} sessions</span>
					</header>
					{sessions.map((session, index) => (
						<div
							key={session}
							className='session'
							ref={feedback('TimelineRow', () => ({ title: `${day} ${session}`, minutes: 20 + index * 5 }))}
						>
							<strong>
								{day} {session}
							</strong>
							<span className='muted'>{20 + index * 5} min</span>
						</div>
					))}
				</section>
			))}
		</main>
	);
}
