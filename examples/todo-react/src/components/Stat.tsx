export function Stat({ value, label }: { value: number; label: string }) {
	return (
		<div className='stat'>
			<span className='value'>{value}</span>
			<span className='label'>{label}</span>
		</div>
	);
}
