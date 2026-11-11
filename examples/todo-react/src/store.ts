import { useSyncExternalStore } from 'react';

export type ListColor = 'blue' | 'green' | 'orange' | 'purple';
export type Priority = 'none' | 'low' | 'medium' | 'high';
export type SortOrder = 'manual' | 'due date' | 'priority';

export type TodoItem = {
	id: string;
	title: string;
	notes: string;
	isDone: boolean;
	due?: string;
	priority: Priority;
};

export type TodoList = {
	id: string;
	name: string;
	color: ListColor;
	items: TodoItem[];
};

const colors: ListColor[] = ['blue', 'green', 'orange', 'purple'];
const day = 86_400_000;

export const remaining = (list: TodoList) => list.items.filter(item => !item.isDone).length;

const dateIn = (days: number) => new Date(Date.now() + days * day).toISOString().slice(0, 10);

const item = (title: string, fields: Partial<TodoItem> = {}): TodoItem => ({
	id: crypto.randomUUID(),
	title,
	notes: '',
	isDone: false,
	priority: 'none',
	...fields,
});

/** The app's state, changed in place. `change` tells React, which then draws every screen that reads it again. */
export class TodoStore {
	lists: TodoList[];
	showCompleted = true;
	sortOrder: SortOrder = 'manual';
	#version = 0;
	#listeners = new Set<() => void>();

	constructor(lists: TodoList[]) {
		this.lists = lists;
	}

	subscribe = (listener: () => void) => {
		this.#listeners.add(listener);
		return () => this.#listeners.delete(listener);
	};

	version = () => this.#version;

	change(edit: () => void) {
		edit();
		this.#version += 1;
		for (const listener of this.#listeners) listener();
	}

	list(id: string) {
		return this.lists.find(list => list.id === id);
	}

	add(title: string, listId: string) {
		this.change(() => this.list(listId)?.items.push(item(title)));
	}

	update(changed: TodoItem, listId: string) {
		const list = this.list(listId);
		const index = list?.items.findIndex(existing => existing.id === changed.id) ?? -1;
		if (list && index !== -1) this.change(() => (list.items[index] = changed));
	}

	delete(itemId: string, listId: string) {
		const list = this.list(listId);
		if (list) this.change(() => (list.items = list.items.filter(existing => existing.id !== itemId)));
	}

	addList(name: string) {
		const id = name.toLowerCase().replace(/[^a-z0-9]+/g, '-') || crypto.randomUUID();
		this.change(() =>
			this.lists.push({
				id: this.list(id) ? crypto.randomUUID() : id,
				name,
				color: colors[this.lists.length % colors.length]!,
				items: [],
			}),
		);
	}

	static sample() {
		const groceries = [
			'Eggs',
			'Spinach',
			'Greek yogurt',
			'Lemons',
			'Rice',
			'Black beans',
			'Tortillas',
			'Avocados',
			'Cheddar',
			'Tomatoes',
			'Garlic',
			'Pasta',
			'Parmesan',
			'Apples',
		];
		return new TodoStore([
			{
				id: 'groceries',
				name: 'Groceries',
				color: 'green',
				items: [
					item('Oat milk', { priority: 'high' }),
					item('Sourdough bread', { isDone: true }),
					item('Bananas', { notes: 'Not too ripe', due: dateIn(1) }),
					item('Coffee beans', { due: dateIn(2), priority: 'medium' }),
					item('Olive oil', { isDone: true }),
					...groceries.map(title => item(title)),
				],
			},
			{
				id: 'work',
				name: 'Work',
				color: 'blue',
				items: [
					item('Review Q4 roadmap', { due: dateIn(0), priority: 'high' }),
					item('Reply to design feedback', { notes: 'Mention the spacing issue' }),
					item('Book flights for offsite', { due: dateIn(5), priority: 'low' }),
				],
			},
			{
				id: 'home',
				name: 'Home',
				color: 'orange',
				items: [item('Fix leaky faucet', { priority: 'medium' }), item('Water plants', { isDone: true })],
			},
		]);
	}
}

export const store = TodoStore.sample();

/** The store, for a component that draws from it. */
export function useStore() {
	useSyncExternalStore(store.subscribe, store.version);
	return store;
}
