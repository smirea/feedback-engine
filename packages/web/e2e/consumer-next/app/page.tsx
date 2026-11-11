import App from './App';

/** A server component. React keeps no record of it in the page, so only the elements it draws are in a capture. */
export default function Page() {
	return (
		<>
			<App />
			<p>Served</p>
		</>
	);
}
