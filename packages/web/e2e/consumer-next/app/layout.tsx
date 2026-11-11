import type { ReactNode } from 'react';
import { Feedback } from './Feedback';

export const metadata = { title: 'Consumer' };

export default function Layout({ children }: { children: ReactNode }) {
	return (
		<html lang='en'>
			<body>
				{children}
				<Feedback />
			</body>
		</html>
	);
}
