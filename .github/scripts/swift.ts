import { $ } from 'bun';

switch (Bun.argv[2]) {
	case 'package':
		// `swift test` compiles the package for macOS before it runs the tests, so it is the compile check too.
		await $`swift test`;
		break;
	case 'app':
		// `swift test` targets macOS and skips every `#if canImport(UIKit)` file. The example app links the package, so its build compiles them.
		await $`xcodebuild build -project App.xcodeproj -scheme App -derivedDataPath DerivedData/ci -clonedSourcePackagesDirPath DerivedData/SourcePackages CODE_SIGNING_ALLOWED=NO -configuration Release -destination ${'generic/platform=iOS Simulator'}`.cwd(
			'examples/todo-ios',
		);
		break;
	default:
		throw new Error(`Unknown Swift task: ${Bun.argv[2]}`);
}
