import { Link, useLocation } from 'react-router';

const tabs = [
	{ href: '/', name: 'Lists' },
	{ href: '/settings', name: 'Settings' },
];

export function TabBar() {
	const { pathname } = useLocation();
	const current = (href: string) => (href === '/' ? !pathname.startsWith('/settings') : pathname.startsWith(href));
	return (
		<nav className='tabs' aria-label='Tabs'>
			{tabs.map(tab => (
				<Link key={tab.href} to={tab.href} aria-current={current(tab.href) ? 'page' : undefined}>
					{tab.name}
				</Link>
			))}
		</nav>
	);
}
