<script>
	import { feedback } from '@smirea/feedback-engine/svelte';

	let count = $state(3);
</script>

<main {@attach feedback()}>
	<h1>Consumer</h1>
	<button onclick={() => (count += 1)}>Count {count}</button>
</main>
