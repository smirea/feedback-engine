import { $ } from 'bun';

const example = 'examples/todo-ios';

switch (Bun.argv[2]) {
	case 'checks':
		await $`swift build`;
		break;
	case 'tests':
		await $`swift test`;
		break;
	case 'build':
		await $`xcodebuild build -project App.xcodeproj -scheme App -configuration Release -destination ${'generic/platform=iOS Simulator'} -derivedDataPath DerivedData/ci -clonedSourcePackagesDirPath DerivedData/SourcePackages CODE_SIGNING_ALLOWED=NO`.cwd(
			example,
		);
		break;
	default:
		throw new Error(`Unknown Swift task: ${Bun.argv[2]}`);
}
