import { Route, Routes } from 'react-router';
import { TabBar } from './components/TabBar.tsx';
import { CatalogScreen } from './screens/CatalogScreen.tsx';
import { ListDetailScreen } from './screens/ListDetailScreen.tsx';
import { ListsScreen } from './screens/ListsScreen.tsx';
import { MediaScreen } from './screens/MediaScreen.tsx';
import { SettingsScreen } from './screens/SettingsScreen.tsx';
import { TimelineScreen } from './screens/TimelineScreen.tsx';

export function App() {
	return (
		<>
			<Routes>
				<Route path='/' element={<ListsScreen />} />
				<Route path='/lists/:id' element={<ListDetailScreen />} />
				<Route path='/settings' element={<SettingsScreen />} />
				<Route path='/timeline' element={<TimelineScreen />} />
				<Route path='/catalog' element={<CatalogScreen />} />
				<Route path='/media' element={<MediaScreen />} />
			</Routes>
			<TabBar />
		</>
	);
}
