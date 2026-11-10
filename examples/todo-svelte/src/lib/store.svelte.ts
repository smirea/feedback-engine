export type ListColor = 'blue' | 'green' | 'orange' | 'purple';

export type TodoItem = {
	id: string;
	title: string;
	isDone: boolean;
	due?: Date;
};

export type TodoList = {
	id: string;
	name: string;
	color: ListColor;
	items: TodoItem[];
};

const colors: ListColor[] = ['blue', 'green', 'orange', 'purple'];

export const remaining = (list: TodoList) => list.items.filter(item => !item.isDone).length;

const item = (title: string, isDone = false, due?: Date): TodoItem => ({ id: crypto.randomUUID(), title, isDone, due });

const list = (name: string, color: ListColor, items: TodoItem[]): TodoList => ({
	id: crypto.randomUUID(),
	name,
	color,
	items,
});

export class TodoStore {
	lists = $state<TodoList[]>([]);

	constructor(lists: TodoList[]) {
		this.lists = lists;
	}

	addList(name: string) {
		this.lists.push({ id: crypto.randomUUID(), name, color: colors[this.lists.length % colors.length]!, items: [] });
	}

	static sample() {
		const today = new Date();
		return new TodoStore([
			list('Groceries', 'green', [item('Oat milk', false, today), item('Sourdough'), item('Coffee beans', true)]),
			list('Work', 'blue', [
				item('Send the invoice', false, today),
				item('Review the pull request'),
				item('Book the flights'),
			]),
			list('Home', 'orange', [item('Water the plants', true), item('Fix the bike light')]),
			list('Reading', 'purple', []),
		]);
	}
}
